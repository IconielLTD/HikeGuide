import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'geo/geometry.dart';

/// Result of one woodland + water detection round-trip.
///
/// [ok] distinguishes "queried successfully, nothing here" (e.g. open ground,
/// no water nearby) from "every endpoint failed" — the detector degrades
/// differently in each case.
class WoodlandWater {
  final bool ok;
  final bool inWoodland;
  final String? woodlandType; // null unless inside a wood/forest polygon
  final double? waterDistanceMetres; // null if no water within search radius
  final String? waterDirection; // 8-point compass, null if no water
  final String? waterKind; // e.g. "stream", "river", "lake"

  const WoodlandWater({
    required this.ok,
    this.inWoodland = false,
    this.woodlandType,
    this.waterDistanceMetres,
    this.waterDirection,
    this.waterKind,
  });

  /// All endpoints failed — caller should keep its last-known/default context.
  const WoodlandWater.failed() : this(ok: false);
}

/// Best-effort woodland + nearest-water detection via the public Overpass API.
///
/// Phase 0 proved the service is FLAKY (typical 7–9 s, frequent 504/429), so
/// this is never a hard dependency: a short per-request timeout, a fallback
/// endpoint list, one retry over the list, and a clean [WoodlandWater.failed]
/// on total failure. Callers cache the result (see EnvironmentDetector) so we
/// query Overpass rarely.
///
/// Woodland uses the approach the spike validated: fetch wood/forest polygons in
/// a small BBOX around the point (not `around:`, which measures distance to the
/// boundary and misses a point deep inside a large wood) and run our own
/// ray-cast point-in-polygon. Water uses `around:` + haversine to the nearest
/// geometry node.
class OverpassService {
  OverpassService._();
  static final OverpassService instance = OverpassService._();

  static const List<String> _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];
  static const Duration _timeout = Duration(seconds: 12);

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: _timeout,
    receiveTimeout: _timeout,
    sendTimeout: _timeout,
    headers: const {
      'User-Agent': 'HikeGuide/1.0 (bushcraft field companion; hobby use)',
    },
  ));

  Future<WoodlandWater> detect(LatLng at, {double waterRadiusM = 1500}) async {
    final json = await _post(_buildQuery(at, waterRadiusM));
    if (json == null) return const WoodlandWater.failed();
    return parse(at, json);
  }

  /// Woodland (bbox) + water (around:) in a SINGLE request — two `out` blocks,
  /// concatenated in `elements`, distinguished by tags at parse time.
  String _buildQuery(LatLng at, double waterRadiusM) {
    const double d = 0.012; // ~1.3 km half-box; guarantees the enclosing wood
    final south = at.latitude - d;
    final north = at.latitude + d;
    final west = at.longitude - d;
    final east = at.longitude + d;
    final bbox = '$south,$west,$north,$east';
    final r = waterRadiusM.round();
    final lat = at.latitude;
    final lng = at.longitude;
    return '[out:json][timeout:25];'
        '('
        'way[natural=wood]($bbox);'
        'way[landuse=forest]($bbox);'
        'relation[natural=wood]($bbox);'
        'relation[landuse=forest]($bbox);'
        ');'
        'out geom;'
        // Water: running water (streams/rivers/canals/ditches) + still water
        // (lakes/ponds/reservoirs) + springs. `out geom` returns full geometry
        // so we can measure to the nearest edge, not just a mapped vertex.
        '('
        'way(around:$r,$lat,$lng)[waterway];'
        'way(around:$r,$lat,$lng)[natural=water];'
        'relation(around:$r,$lat,$lng)[natural=water];'
        'way(around:$r,$lat,$lng)[landuse=reservoir];'
        'relation(around:$r,$lat,$lng)[landuse=reservoir];'
        'node(around:$r,$lat,$lng)[natural=spring];'
        ');'
        'out geom;';
  }

  Future<Map<String, dynamic>?> _post(String query) async {
    // Two passes over the endpoint list = one retry, rotating on 429/504/timeout.
    for (int attempt = 0; attempt < 2; attempt++) {
      for (final url in _endpoints) {
        try {
          final res = await _dio.post<dynamic>(
            url,
            data: {'data': query},
            options: Options(
              contentType: Headers.formUrlEncodedContentType,
              responseType: ResponseType.plain,
            ),
          );
          if (res.statusCode == 200 && res.data != null) {
            final decoded = jsonDecode(res.data.toString());
            if (decoded is Map<String, dynamic>) return decoded;
          }
        } on DioException catch (e) {
          debugPrint('Overpass $url failed: ${e.type.name}');
        } catch (e) {
          debugPrint('Overpass $url parse error: $e');
        }
      }
    }
    return null;
  }

  // --- parsing (static + testable, no network) ----------------------------

  /// Turn an Overpass `out geom` response into a [WoodlandWater] for [at].
  @visibleForTesting
  static WoodlandWater parse(LatLng at, Map<String, dynamic> json) {
    final elements = (json['elements'] as List?) ?? const [];

    final woods = <GeoPolygon>[];
    double? bestDist;
    LatLng? bestPoint;
    String? bestKind;

    for (final el in elements) {
      if (el is! Map) continue;
      final tags = (el['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
      final isWood = tags['natural'] == 'wood' || tags['landuse'] == 'forest';

      if (isWood) {
        for (final ring in _ringsOf(el)) {
          if (ring.length >= 4) woods.add(GeoPolygon([ring], tags: tags));
        }
        continue;
      }
      // Only report substantial, reliably-mapped water — lakes, ponds,
      // reservoirs, rivers, canals. Small streams/ditches and spring points are
      // patchy in OSM (hence the UI says "large body of water"), so they never
      // become the reported nearest.
      if (!_isLargeBody(tags)) continue;

      final kind = _waterKind(tags);
      void consider(double dist, LatLng point) {
        if (bestDist == null || dist < bestDist!) {
          bestDist = dist;
          bestPoint = point;
          bestKind = kind;
        }
      }

      // Point features (springs) carry their own lat/lon directly.
      if (el['type'] == 'node' && el['lat'] is num && el['lon'] is num) {
        final node = LatLng(
            (el['lat'] as num).toDouble(), (el['lon'] as num).toDouble());
        consider(haversineMetres(at, node), node);
        continue;
      }

      // Lines/areas: measure to the nearest point on each edge.
      for (final way in _waysOf(el)) {
        if (way.length == 1) {
          consider(haversineMetres(at, way.first), way.first);
          continue;
        }
        for (var i = 0; i + 1 < way.length; i++) {
          final seg = pointToSegment(at, way[i], way[i + 1]);
          consider(seg.metres, seg.closest);
        }
      }
    }

    GeoPolygon? hit;
    for (final poly in woods) {
      if (poly.contains(at.longitude, at.latitude)) {
        hit = poly;
        break;
      }
    }

    final nearestWater = bestPoint;
    return WoodlandWater(
      ok: true,
      inWoodland: hit != null,
      woodlandType: hit == null ? null : woodlandTypeFromTags(hit.tags),
      waterDistanceMetres: bestDist,
      waterDirection: nearestWater == null ? null : bearing8(at, nearestWater),
      waterKind: bestKind,
    );
  }

  /// leaf_type → human woodland type, with sensible fallbacks (often untagged).
  @visibleForTesting
  static String woodlandTypeFromTags(Map<String, dynamic> tags) {
    switch (tags['leaf_type']) {
      case 'broadleaved':
        return 'broadleaf deciduous';
      case 'needleleaved':
        return 'coniferous';
      case 'mixed':
        return 'mixed woodland';
    }
    if (tags['landuse'] == 'forest') return 'forest';
    return 'woodland';
  }

  /// A notable standing/large body: lake, pond, reservoir, river or canal.
  /// Deliberately excludes minor waterways (stream, ditch, drain…) and spring
  /// points, which OSM maps inconsistently.
  static bool _isLargeBody(Map<String, dynamic> tags) {
    if (tags['natural'] == 'water') return true;
    if (tags['landuse'] == 'reservoir') return true;
    final w = tags['waterway'];
    return w == 'river' || w == 'canal' || w == 'riverbank';
  }

  static String? _waterKind(Map<String, dynamic> tags) {
    final waterway = tags['waterway'];
    if (waterway == 'riverbank') return 'river';
    if (waterway is String && waterway.isNotEmpty) return waterway;
    if (tags['landuse'] == 'reservoir') return 'reservoir';
    if (tags['natural'] == 'water') {
      final water = tags['water'];
      // Untagged open water is almost always a lake at this scale.
      return (water is String && water.isNotEmpty) ? water : 'lake';
    }
    return null;
  }

  static Iterable<List<List<double>>> _ringsOf(Map el) sync* {
    final type = el['type'];
    if (type == 'way' && el['geometry'] is List) {
      yield _ring(el['geometry'] as List);
    } else if (type == 'relation' && el['members'] is List) {
      for (final m in (el['members'] as List)) {
        if (m is Map && m['type'] == 'way' && m['geometry'] is List) {
          final role = m['role'];
          if (role == 'outer' || role == null || role == '') {
            yield _ring(m['geometry'] as List);
          }
        }
      }
    }
  }

  static List<List<double>> _ring(List geom) => [
        for (final n in geom)
          if (n is Map && n['lon'] is num && n['lat'] is num)
            [(n['lon'] as num).toDouble(), (n['lat'] as num).toDouble()],
      ];

  /// Ordered node sequences for a water feature: one per way, one per relation
  /// member way, so callers can walk the edges (not just loose vertices).
  static Iterable<List<LatLng>> _waysOf(Map el) sync* {
    final type = el['type'];
    if (type == 'way' && el['geometry'] is List) {
      yield _latLngs(el['geometry'] as List);
    } else if (type == 'relation' && el['members'] is List) {
      for (final m in (el['members'] as List)) {
        if (m is Map && m['geometry'] is List) {
          yield _latLngs(m['geometry'] as List);
        }
      }
    }
  }

  static List<LatLng> _latLngs(List geom) => [
        for (final n in geom)
          if (n is Map && n['lat'] is num && n['lon'] is num)
            LatLng((n['lat'] as num).toDouble(), (n['lon'] as num).toDouble()),
      ];
}
