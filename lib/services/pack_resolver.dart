import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'geo/geometry.dart';

/// One coverage area from the bundled `coverage.geojson` index: the polygon a
/// GPS fix must fall inside for a given pack (and nation) to apply.
@immutable
class CoverageArea {
  final String packId;
  final String nation;
  final String label;
  final GeoPolygon polygon;

  const CoverageArea({
    required this.packId,
    required this.nation,
    required this.label,
    required this.polygon,
  });
}

/// Offline "which region pack covers this point". Parses the small bundled
/// `coverage.geojson` index into polygons; a GPS fix → pack via point-in-polygon.
/// Tiny enough to ship in the APK, so the nation/legal regime is known even
/// before any pack data is downloaded.
class PackResolver {
  PackResolver(this._areas);

  final List<CoverageArea> _areas;

  List<CoverageArea> get areas => List.unmodifiable(_areas);

  /// The first coverage area containing [lat]/[lng], or null if uncovered.
  CoverageArea? areaAt(double lat, double lng) {
    for (final a in _areas) {
      if (a.polygon.contains(lng, lat)) return a;
    }
    return null;
  }

  /// Parse `coverage.geojson` into coverage areas. Static + pure (no I/O) so the
  /// service can call it on a loaded string and tests can exercise it directly.
  static List<CoverageArea> parseCoverage(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    final features = decoded['features'];
    if (features is! List) return const [];

    final out = <CoverageArea>[];
    for (final f in features) {
      if (f is! Map) continue;
      final props = (f['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
      final geom = f['geometry'];
      if (geom is! Map || geom['type'] != 'Polygon') continue;
      final coords = geom['coordinates'];
      if (coords is! List) continue;
      final rings = _rings(coords);
      if (rings.isEmpty) continue;
      out.add(CoverageArea(
        packId: props['packId'] as String? ?? '',
        nation: props['nation'] as String? ?? 'England',
        label: props['label'] as String? ?? '',
        polygon: GeoPolygon(rings),
      ));
    }
    return out;
  }

  static List<List<List<double>>> _rings(List polygon) {
    final rings = <List<List<double>>>[];
    for (final ring in polygon) {
      if (ring is! List) continue;
      final pts = <List<double>>[];
      for (final c in ring) {
        if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
          pts.add([(c[0] as num).toDouble(), (c[1] as num).toDouble()]);
        }
      }
      if (pts.length >= 4) rings.add(pts);
    }
    return rings;
  }
}
