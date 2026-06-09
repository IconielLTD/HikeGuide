import 'package:geomag/geomag.dart';

/// Magnetic declination from the World Magnetic Model (WMM2025), computed
/// entirely on-device — no network, no key. Declination is the angle between
/// grid/true north and magnetic north, which a compass user must allow for.
class Geomagnetic {
  Geomagnetic._();

  static final GeoMag _geoMag = GeoMag();

  /// Declination in degrees: positive = east of true north, negative = west.
  static double declinationDegrees(double lat, double lng, {DateTime? date}) {
    return _geoMag.calculate(lat, lng, 0, date ?? DateTime.now()).dec;
  }

  /// Human-readable, e.g. "0.6° E", "1.2° W", or "0.0°".
  static String format(double degrees) {
    final rounded = double.parse(degrees.abs().toStringAsFixed(1));
    if (rounded == 0.0) return '0.0°';
    return '${rounded.toStringAsFixed(1)}° ${degrees >= 0 ? 'E' : 'W'}';
  }

  /// Convenience: formatted declination straight from a location.
  static String formatForLatLng(double lat, double lng, {DateTime? date}) {
    return format(declinationDegrees(lat, lng, date: date));
  }
}
