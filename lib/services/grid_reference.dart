import 'dart:math';

import 'package:proj4dart/proj4dart.dart' as proj4;

/// Converts a WGS84 GPS position to an Ordnance Survey grid reference
/// (e.g. "SK 123 678"). Pure offline maths — no OS plan or key required.
///
/// Uses the standard 7-parameter Helmert transform to OSGB36 (~5 m accuracy),
/// which is well within a 6-figure (100 m) grid reference.
class GridReference {
  GridReference._();

  static final proj4.Projection _osgb = proj4.Projection.get('EPSG:27700') ??
      proj4.Projection.add(
        'EPSG:27700',
        '+proj=tmerc +lat_0=49 +lon_0=-2 +k=0.9996012717 +x_0=400000 '
        '+y_0=-100000 +ellps=airy '
        '+towgs84=446.448,-125.157,542.06,0.15,0.247,0.842,-20.489 '
        '+units=m +no_defs',
      );

  /// OS grid reference for [lat]/[lng], or null if outside the British National
  /// Grid (i.e. not in Great Britain).
  static String? fromLatLng(double lat, double lng, {int figures = 6}) {
    final p = proj4.Projection.WGS84
        .transform(_osgb, proj4.Point(x: lng, y: lat));
    return _format(p.x, p.y, figures);
  }

  static String? _format(double easting, double northing, int figures) {
    if (easting.isNaN || northing.isNaN) return null;
    final int e100k = (easting / 100000).floor();
    final int n100k = (northing / 100000).floor();
    if (e100k < 0 || e100k > 6 || n100k < 0 || n100k > 12) return null;

    int l1 = (19 - n100k) - (19 - n100k) % 5 + ((e100k + 10) / 5).floor();
    int l2 = ((19 - n100k) * 5) % 25 + e100k % 5;
    // Compensate for the omitted letter 'I'.
    if (l1 > 7) l1 += 1;
    if (l2 > 7) l2 += 1;
    final letters = String.fromCharCode(65 + l1) + String.fromCharCode(65 + l2);

    final int digits = figures ~/ 2;
    final int divisor = pow(10, 5 - digits).toInt();
    final e = ((easting % 100000) ~/ divisor).toString().padLeft(digits, '0');
    final n = ((northing % 100000) ~/ divisor).toString().padLeft(digits, '0');
    return '$letters $e $n';
  }
}
