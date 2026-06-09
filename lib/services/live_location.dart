import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import 'access_land_service.dart';
import 'location_service.dart';
import 'trip_recorder.dart';

/// Single source of truth for the device's live position and the land-access
/// classification at that position. A [ChangeNotifier] singleton so the Map and
/// Now tabs both reflect movement (and boundary crossings) without each opening
/// its own GPS stream — geolocator supports only one position stream at a time.
///
/// While a trip is recording, [TripRecorder] owns the (foreground-service) GPS
/// stream; this service drops its own and mirrors the recorder's fixes instead,
/// so there is never more than one active stream.
class LiveLocation extends ChangeNotifier with WidgetsBindingObserver {
  LiveLocation._();
  static final LiveLocation instance = LiveLocation._();

  final LocationService _location = const LocationService();
  StreamSubscription<LatLng>? _sub;

  LatLng? _current;
  String? _accessStatus;
  String? _reason; // user-facing reason when there's no fix
  bool _locating = true;
  bool _started = false;
  bool _needed = true; // a location-showing tab (Map/Now) is visible

  /// Latest position, or null before the first fix.
  LatLng? get current => _current;

  /// Land-access classification at [current] (e.g. "Open Access (CRoW)"), or
  /// null before the first reading / when no access data is bundled.
  String? get accessStatus => _accessStatus;

  /// Why there's no fix (permission/services), for a calm status message.
  String? get reason => _reason;

  /// True only until the first location attempt resolves.
  bool get locating => _locating;

  /// Begin tracking. Idempotent — the first screen that needs location calls it;
  /// later callers are no-ops.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    TripRecorder.instance.addListener(_onRecorderChange);

    final result = await _location.getCurrentLatLng();
    _locating = false;
    if (result.latLng != null) {
      _setCurrent(result.latLng!);
    } else {
      _reason = result.reason;
      notifyListeners();
    }
    _syncSubscription();
  }

  /// Tell the service whether any visible screen needs location right now (the
  /// Map or Now tab). When nothing needs it, the GPS stream is released to save
  /// battery; returning to a location screen re-acquires immediately. Recording
  /// is unaffected — the recorder owns its own stream regardless of tab.
  void setNeeded(bool needed) {
    if (needed == _needed) return;
    _needed = needed;
    if (!_started) return;
    if (needed) {
      _refreshNow(); // snap to the current position, then resume the stream
    } else {
      _syncSubscription(); // releases the stream
    }
  }

  /// Run the live stream exactly when it's wanted: started, needed by a visible
  /// screen, and not while the recorder owns GPS.
  void _syncSubscription() {
    final shouldRun =
        _started && _needed && !TripRecorder.instance.isRecording;
    if (shouldRun && _sub == null) {
      _sub = _location.liveLatLng().listen(
        _setCurrent,
        onError: (Object _) {}, // keep last fix; getCurrentLatLng owns reasons
      );
    } else if (!shouldRun && _sub != null) {
      _sub!.cancel();
      _sub = null;
    }
  }

  void _onRecorderChange() {
    // Mirror the recorder's fixes while it owns GPS, then let _syncSubscription
    // drop our stream during recording and resume it afterwards.
    if (TripRecorder.instance.isRecording) {
      final fix = TripRecorder.instance.lastFix;
      if (fix != null) _setCurrent(fix);
    }
    _syncSubscription();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-acquire on resume so a drive with the app backgrounded doesn't leave us
    // at the old position. The recorder keeps location alive while recording.
    if (state == AppLifecycleState.resumed &&
        _started &&
        _needed &&
        !TripRecorder.instance.isRecording) {
      _refreshNow();
    }
  }

  Future<void> _refreshNow() async {
    final result = await _location.getCurrentLatLng();
    if (result.latLng != null) _setCurrent(result.latLng!);
    _syncSubscription();
  }

  void _setCurrent(LatLng fix) {
    if (fix == _current) return; // no movement — skip redundant work
    _current = fix;
    _locating = false;
    _reason = null;
    notifyListeners();
    _refreshAccess(fix);
  }

  /// Reclassify access for [at] (cheap offline point-in-polygon). Guards against
  /// a stale async result overwriting a newer fix.
  Future<void> _refreshAccess(LatLng at) async {
    final status = await AccessLandService.instance.statusAt(at);
    if (_current != at) return;
    if (status != _accessStatus) {
      _accessStatus = status;
      notifyListeners();
    }
  }
}
