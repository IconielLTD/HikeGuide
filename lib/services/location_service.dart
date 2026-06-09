import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Result of a one-shot location read. On failure [latLng] is null and [reason]
/// holds a short, user-facing explanation (the Map tab degrades to a default
/// centre rather than erroring).
class LocationResult {
  final LatLng? latLng;
  final String? reason;
  const LocationResult({this.latLng, this.reason});

  bool get hasFix => latLng != null;
}

/// Phase 1: a single getCurrentPosition for the Map tab's GPS marker.
/// Continuous trip recording (foreground service) arrives in Phase 4.
class LocationService {
  const LocationService();

  Future<LocationResult> getCurrentLatLng() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(reason: 'Location services are off');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LocationResult(reason: 'Location permission not granted');
      }

      // geolocator 14.x: configure via LocationSettings (not desiredAccuracy:).
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationResult(latLng: LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      return const LocationResult(reason: 'Could not get a location fix');
    }
  }

  /// Continuous stream of location fixes for the Map tab's live position marker.
  /// Foreground-only (no notification): trip recording uses its own
  /// foreground-service stream in [TripRecorder]. Emits a new fix each time the
  /// device moves [distanceFilterMetres], so standing still costs nothing.
  ///
  /// Assumes location is already enabled/permitted (the Map tab calls
  /// [getCurrentLatLng] first, which owns the user-facing reason); stream
  /// errors surface to the listener's onError.
  Stream<LatLng> liveLatLng({int distanceFilterMetres = 5}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMetres,
      ),
    ).map((p) => LatLng(p.latitude, p.longitude));
  }
}
