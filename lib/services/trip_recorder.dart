import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import 'cache_repository.dart';
import 'geo/geometry.dart';

/// Records a GPS trip into the trips / route_points tables.
///
/// On Android it runs the location stream as a FOREGROUND SERVICE (persistent
/// notification) so tracking continues with the screen off or the app
/// backgrounded. Battery-conscious: a [_distanceFilterMetres] filter means the
/// OS only wakes us when the user has actually moved, so a still walker idling
/// by a fire isn't logging a point per second.
///
/// Singleton [ChangeNotifier] so the Now tab (controls) and Map tab (live
/// polyline) both reflect live state.
class TripRecorder extends ChangeNotifier {
  TripRecorder._();
  static final TripRecorder instance = TripRecorder._();

  /// Only log/accumulate once the user has moved this far since the last point.
  static const int _distanceFilterMetres = 8;

  /// A point counts as "doubling back" when it passes within this distance of
  /// an earlier part of the same track…
  static const double _retraceRadiusMetres = 18;

  /// …ignoring the most recent [_retraceSkip] points, which are always nearby
  /// (so an ordinary forward walk never flags itself).
  static const int _retraceSkip = 4;

  int? _tripId;
  DateTime? _startedAt;
  double _distanceMetres = 0;
  final List<LatLng> _points = [];
  final List<bool> _retraced = [];
  LatLng? _last;
  StreamSubscription<Position>? _sub;
  String? _lastError;

  // Step count for the trip. Null until the pedometer delivers a first reading
  // (and stays null when the permission is refused or there's no step sensor —
  // the stat is simply hidden then). [_stepBaseline] is the device's cumulative
  // count at the moment tracking began; trip steps are the delta from it.
  StreamSubscription<StepCount>? _stepSub;
  int? _stepBaseline;
  int? _steps;

  bool get isRecording => _tripId != null;
  int? get tripId => _tripId;
  DateTime? get startedAt => _startedAt;
  double get distanceMetres => _distanceMetres;
  int get pointCount => _points.length;
  List<LatLng> get points => List.unmodifiable(_points);

  /// Per-point retrace flags aligned with [points]: `retraced[i]` is true when
  /// point i passes back over track already laid down. Lets the live map draw
  /// doubled-back stretches lighter.
  List<bool> get retraced => List.unmodifiable(_retraced);

  /// The most recent GPS fix while recording (the live marker follows this so
  /// the Map tab doesn't need a second location stream of its own).
  LatLng? get lastFix => _last;

  /// Steps taken so far this trip, or null when unavailable (permission refused
  /// or no step-counter sensor) — callers hide the stat in that case.
  int? get steps => _steps;
  String? get lastError => _lastError;

  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  /// Finalize any trip left open by an app kill: compute its distance from the
  /// stored points and stamp ended_at so it can't linger as a zombie "active"
  /// trip. Cheap (usually no rows); call once at startup.
  Future<void> finalizeOrphans() async {
    final repo = CacheRepository.instance;
    for (final row in await repo.activeTrips()) {
      final id = row['id'] as int;
      final pts = await repo.routePoints(id);
      final dist = pathDistanceMetres([for (final p in pts) p.latLng]);
      final endedAt = pts.isNotEmpty
          ? pts.last.recordedAt
          : DateTime.fromMillisecondsSinceEpoch(row['started_at'] as int);
      await repo.finishTrip(id, endedAt: endedAt, distanceMetres: dist);
    }
  }

  /// Begin recording. Returns false (and sets [lastError]) if location is off or
  /// permission is refused.
  Future<bool> start({String? name}) async {
    if (isRecording) return true;
    _lastError = null;
    if (!await _ensurePermission()) {
      _lastError = 'Location must be on and permitted to record a trip.';
      notifyListeners();
      return false;
    }
    final now = DateTime.now();
    _tripId = await CacheRepository.instance.insertTrip(name: name, startedAt: now);
    _startedAt = now;
    _distanceMetres = 0;
    _points.clear();
    _retraced.clear();
    _last = null;
    _stepBaseline = null;
    _steps = null;
    _sub = Geolocator.getPositionStream(locationSettings: _locationSettings())
        .listen(_onPosition, onError: (Object e) {
      _lastError = 'Lost the location signal.';
      notifyListeners();
    });
    _startStepCounter(); // best-effort; recording proceeds either way
    notifyListeners();
    return true;
  }

  /// Best-effort step tracking: requests the activity-recognition permission and
  /// subscribes to the pedometer. The step counter is cumulative since boot, so
  /// we hold the first reading as a baseline and report the delta. Any failure
  /// (denied permission, no sensor) leaves [steps] null and is otherwise silent.
  Future<void> _startStepCounter() async {
    try {
      final status = await Permission.activityRecognition.request();
      if (!status.isGranted) return;
      _stepSub = Pedometer.stepCountStream.listen(
        (event) {
          _stepBaseline ??= event.steps;
          _steps = stepsSinceBaseline(_stepBaseline!, event.steps);
          notifyListeners();
        },
        onError: (Object _) {}, // no step sensor — stat stays hidden
      );
    } catch (_) {
      // Pedometer/permission plugin unavailable — ignore, steps stay null.
    }
  }

  Future<void> _onPosition(Position p) async {
    final pt = LatLng(p.latitude, p.longitude);
    if (_last != null) _distanceMetres += haversineMetres(_last!, pt);
    // Flag against the track laid down so far, before this point joins it.
    _retraced.add(_isRetrace(_points, pt));
    _last = pt;
    _points.add(pt);
    final id = _tripId;
    if (id != null) {
      await CacheRepository.instance
          .insertRoutePoint(id, pt.latitude, pt.longitude, DateTime.now());
    }
    notifyListeners();
  }

  /// Stop recording, finalize the trip row, and return its id.
  Future<int?> stop() async {
    final id = _tripId;
    await _sub?.cancel();
    _sub = null;
    await _stepSub?.cancel();
    _stepSub = null;
    if (id != null) {
      await CacheRepository.instance.finishTrip(id,
          endedAt: DateTime.now(), distanceMetres: _distanceMetres);
    }
    _tripId = null;
    _startedAt = null;
    _last = null;
    _stepBaseline = null;
    _steps = null;
    notifyListeners();
    return id;
  }

  LocationSettings _locationSettings() {
    const accuracy = LocationAccuracy.high;
    if (defaultTargetPlatform == TargetPlatform.android) {
      // The foreground service keeps location alive in the background under the
      // "while in use" grant — no scary "all the time" permission needed.
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: _distanceFilterMetres,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'HikeGuide — recording trip',
          notificationText: 'Tracking your route. Tap to return.',
          enableWakeLock: true,
          setOngoing: true,
          notificationIcon:
              AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        ),
      );
    }
    return const LocationSettings(
        accuracy: accuracy, distanceFilter: _distanceFilterMetres);
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  // --- pure helpers (testable, no GPS) ------------------------------------

  /// True if [pt] lands within [_retraceRadiusMetres] of a point already in
  /// [prior], ignoring the last [_retraceSkip] points (always adjacent).
  static bool _isRetrace(List<LatLng> prior, LatLng pt) {
    final cutoff = prior.length - _retraceSkip;
    for (var i = 0; i < cutoff; i++) {
      if (haversineMetres(prior[i], pt) <= _retraceRadiusMetres) return true;
    }
    return false;
  }

  /// Per-point retrace flags for a whole track — the batch equivalent of the
  /// incremental flagging done while recording. flags[i] is true when point i
  /// doubles back over earlier track.
  static List<bool> retraceFlags(List<LatLng> pts) {
    final flags = List<bool>.filled(pts.length, false);
    for (var i = 0; i < pts.length; i++) {
      final cutoff = i - _retraceSkip;
      for (var j = 0; j < cutoff; j++) {
        if (haversineMetres(pts[j], pts[i]) <= _retraceRadiusMetres) {
          flags[i] = true;
          break;
        }
      }
    }
    return flags;
  }

  /// Trip steps from a cumulative-since-boot counter. Guards a mid-trip reboot
  /// (counter resets below the baseline) by flooring at zero rather than
  /// reporting a negative count.
  static int stepsSinceBaseline(int baseline, int current) {
    final diff = current - baseline;
    return diff < 0 ? 0 : diff;
  }

  static double pathDistanceMetres(List<LatLng> pts) {
    double d = 0;
    for (var i = 1; i < pts.length; i++) {
      d += haversineMetres(pts[i - 1], pts[i]);
    }
    return d;
  }

  static String formatDistance(double metres) =>
      metres < 1000 ? '${metres.round()} m' : '${(metres / 1000).toStringAsFixed(2)} km';

  static String formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}
