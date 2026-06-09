import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Pure-Dart geometry shared by woodland detection (Overpass polygons) and
/// access-land detection (bundled CRoW/Forestry GeoJSON). Coordinates follow
/// the GeoJSON axis order [lng, lat]. No Flutter dependency, so it is unit
/// testable on its own.

/// A lng/lat bounding box used as a cheap prefilter before the ray-cast.
class GeoBBox {
  final double minLng;
  final double minLat;
  final double maxLng;
  final double maxLat;

  const GeoBBox(this.minLng, this.minLat, this.maxLng, this.maxLat);

  bool contains(double lng, double lat) =>
      lng >= minLng && lng <= maxLng && lat >= minLat && lat <= maxLat;

  bool overlaps(GeoBBox other) =>
      minLng <= other.maxLng &&
      maxLng >= other.minLng &&
      minLat <= other.maxLat &&
      maxLat >= other.minLat;

  /// A square box of half-size [deltaDeg] around a point.
  static GeoBBox around(double lng, double lat, double deltaDeg) =>
      GeoBBox(lng - deltaDeg, lat - deltaDeg, lng + deltaDeg, lat + deltaDeg);

  static GeoBBox fromRing(List<List<double>> ring) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final pt in ring) {
      final x = pt[0], y = pt[1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    return GeoBBox(minX, minY, maxX, maxY);
  }
}

/// A polygon as parsed from GeoJSON / Overpass: ring 0 is the outer boundary,
/// any further rings are holes. Carries a precomputed outer bbox so callers can
/// reject far-away polygons in O(1) before the ray-cast.
class GeoPolygon {
  /// [ring][point][lng, lat].
  final List<List<List<double>>> rings;
  final GeoBBox bbox;
  final Map<String, dynamic> tags;

  GeoPolygon(this.rings, {this.tags = const {}})
      : bbox = rings.isEmpty
            ? const GeoBBox(0, 0, 0, 0)
            : GeoBBox.fromRing(rings.first);

  /// Even-odd ray-cast across every ring, so holes subtract naturally: a point
  /// inside the outer ring but also inside a hole flips twice and reads false.
  bool contains(double lng, double lat) {
    if (!bbox.contains(lng, lat)) return false;
    bool inside = false;
    for (final ring in rings) {
      for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        final xi = ring[i][0], yi = ring[i][1];
        final xj = ring[j][0], yj = ring[j][1];
        if ((yi > lat) != (yj > lat) &&
            lng < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
          inside = !inside;
        }
      }
    }
    return inside;
  }
}

const double _earthRadiusM = 6371000.0;

double _deg2rad(double d) => d * math.pi / 180.0;

/// Great-circle distance in metres.
double haversineMetres(LatLng a, LatLng b) {
  final dLat = _deg2rad(b.latitude - a.latitude);
  final dLng = _deg2rad(b.longitude - a.longitude);
  final lat1 = _deg2rad(a.latitude);
  final lat2 = _deg2rad(b.latitude);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Shortest distance in metres from [p] to the line segment [a]–[b], plus the
/// closest point on that segment. Uses a local equirectangular projection
/// centred on [p] (metres east/north), which is accurate over the short
/// distances we measure water against and far cheaper than per-vertex haversine.
///
/// Measuring to the segment — not just the endpoints — matters because OSM lakes
/// and streams are noded sparsely: the nearest *vertex* of a feature can be far
/// even when its nearest *edge* runs right past you.
({double metres, LatLng closest}) pointToSegment(LatLng p, LatLng a, LatLng b) {
  final cosLat = math.cos(_deg2rad(p.latitude));
  double east(double lng) => _deg2rad(lng - p.longitude) * cosLat * _earthRadiusM;
  double north(double lat) => _deg2rad(lat - p.latitude) * _earthRadiusM;

  final ax = east(a.longitude), ay = north(a.latitude);
  final bx = east(b.longitude), by = north(b.latitude);
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  // Project the origin (p) onto AB, clamped to the segment.
  double t = len2 == 0 ? 0 : -(ax * dx + ay * dy) / len2;
  if (t < 0) {
    t = 0;
  } else if (t > 1) {
    t = 1;
  }
  final cx = ax + t * dx, cy = ay + t * dy;
  final metres = math.sqrt(cx * cx + cy * cy);

  final closeLat = p.latitude + (cy / _earthRadiusM) * 180 / math.pi;
  final closeLng =
      p.longitude + (cx / (_earthRadiusM * cosLat)) * 180 / math.pi;
  return (metres: metres, closest: LatLng(closeLat, closeLng));
}

const List<String> _compass8 = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

/// 8-point compass bearing from [from] to [to] (e.g. "SE").
String bearing8(LatLng from, LatLng to) {
  final lat1 = _deg2rad(from.latitude);
  final lat2 = _deg2rad(to.latitude);
  final dLng = _deg2rad(to.longitude - from.longitude);
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  final brng = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  final idx = (((brng + 22.5) ~/ 45) % 8).toInt();
  return _compass8[idx];
}
