import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/region_pack.dart';
import 'geo/geometry.dart';
import 'region_pack_service.dart';

/// Version stamp for the bundled access-land assets AND the environment
/// detection logic. BUMP THIS whenever a bundled pack is rebuilt
/// (spike/build_pack.mjs) OR the detection rules change (e.g. which water
/// counts, how distance is measured) — the next launch then drops stale cached
/// detections (see CacheRepository.reconcileAccessDataVersion) so the new logic
/// re-runs per cell. A hand-set constant on purpose: the check costs one tiny
/// DB read at startup and never loads the pack GeoJSON just to verify a version.
const String kAccessDataVersion = 'gb-regions-2026-06-16';

/// Status returned by [AccessLandService.statusAt] when the point is in Scotland
/// but inside no mapped restriction parcel. Scotland's access model is
/// open-by-default (right of responsible access under the Land Reform (Scotland)
/// Act 2003), so the absence of a parcel means "you may roam here" — the inverse
/// of England/Wales, where it means "no mapped right". Classified by
/// accessCategoryForStatus (models/access_guidance.dart) into scotlandOpenAccess.
const String kScotlandOpenAccessStatus = 'Open access — right to roam';

/// Status returned for England/Wales when the point is inside no open-access
/// parcel — access is limited to public rights of way.
const String kNoMappedRightStatus = 'No mapped open-access right';

/// Background-isolate entry point (compute): parse one pack's GeoJSON into
/// parcels. Top-level so it can be sent to another isolate.
List<AccessParcel> _parsePackRaw(String raw) =>
    AccessLandService.parseFeatureCollection(raw);

/// One access-land parcel: an outer/holed polygon plus which dataset it came
/// from (so the Map can colour-code and the context can name the regime).
class AccessParcel {
  final GeoPolygon polygon;
  final String source; // human label, e.g. "Open Access (CRoW)"

  const AccessParcel({required this.polygon, required this.source});

  List<LatLng> get outline =>
      polygon.rings.first.map((c) => LatLng(c[1], c[0])).toList();

  List<List<LatLng>> get holes => polygon.rings.length <= 1
      ? const []
      : polygon.rings
          .skip(1)
          .map((r) => r.map((c) => LatLng(c[1], c[0])).toList())
          .toList();
}

/// Answers two access-land questions with bbox-prefiltered ray-cast
/// point-in-polygon, using whichever region pack covers the point:
///   - statusAt(point)  → access label for the EnvironmentContext
///   - parcelsInView()  → polygons to draw on the Map for a viewport
///
/// Data comes from [RegionPackService] (a bundled or downloaded pack), parsed
/// once per pack and cached. If no pack covers the point — or it isn't
/// downloaded yet — every method degrades cleanly (statusAt → null = "unknown",
/// parcelsInView → empty) so the rest of the app keeps working.
class AccessLandService {
  AccessLandService._();
  static final AccessLandService instance = AccessLandService._();

  @visibleForTesting
  RegionPackService packs = RegionPackService.instance;

  /// Parsed parcels keyed by "<packId>-<version>"; concurrent callers await the
  /// single in-flight parse.
  final Map<String, Future<List<AccessParcel>>> _loads = {};

  Future<List<AccessParcel>> _parcelsForPack(RegionPack pack) async {
    final key = '${pack.id}-${pack.version}';
    final existing = _loads[key];
    if (existing != null) return existing;
    // Don't cache a "not downloaded yet" miss: once the pack is fetched a later
    // call must re-read it, or the Map/Now stay empty until an app restart.
    if (!await packs.isAvailable(pack)) return const [];
    return _loads[key] ??= _loadPack(pack);
  }

  Future<List<AccessParcel>> _loadPack(RegionPack pack) async {
    final raw = await packs.rawGeoJson(pack);
    if (raw == null) return const []; // not downloaded yet / missing asset
    // The heavy jsonDecode + polygon build is offloaded to a background isolate
    // so it never janks the Map's first frames.
    List<AccessParcel> parcels;
    try {
      parcels = await compute(_parsePackRaw, raw);
    } catch (_) {
      parcels = _parsePackRaw(raw); // fallback on the main isolate
    }
    debugPrint('AccessLandService: loaded ${parcels.length} parcels for ${pack.id}');
    return parcels;
  }

  /// Access label for [at], or null if we have no data to judge from
  /// ("unknown"). When data IS loaded but the point falls outside every parcel,
  /// returns the nation's default: Scotland → open-access (right to roam),
  /// England/Wales → no mapped right. (See [kScotlandOpenAccessStatus].)
  Future<String?> statusAt(LatLng at) async {
    final pack = await packs.packFor(at);
    if (pack == null) return null;
    final parcels = await _parcelsForPack(pack);
    if (parcels.isEmpty) return null;
    for (final p in parcels) {
      if (p.polygon.contains(at.longitude, at.latitude)) return p.source;
    }
    return pack.nation == 'Scotland'
        ? kScotlandOpenAccessStatus
        : kNoMappedRightStatus;
  }

  /// Parcels whose bbox overlaps [view] — for drawing the Map overlay. Resolves
  /// the pack covering the viewport centre.
  Future<List<AccessParcel>> parcelsInView(GeoBBox view) async {
    final centre = LatLng(
      (view.minLat + view.maxLat) / 2,
      (view.minLng + view.maxLng) / 2,
    );
    final pack = await packs.packFor(centre);
    if (pack == null) return const [];
    final parcels = await _parcelsForPack(pack);
    return parcels.where((p) => p.polygon.bbox.overlaps(view)).toList();
  }

  /// True when the app has any access data to offer (the manifest lists at
  /// least one pack). Used to show the Map legend; does not require a location,
  /// so the overlay isn't gated on a pack having been parsed yet.
  Future<bool> get hasData async => (await packs.allPacks()).isNotEmpty;

  // --- parsing (static + testable) ----------------------------------------

  /// Parse a GeoJSON FeatureCollection of Polygon/MultiPolygon into parcels.
  /// Coordinates are GeoJSON order [lng, lat]. Each feature's access label comes
  /// from its `properties.source`; [defaultSource] is the fallback when a
  /// feature doesn't carry one (e.g. older single-dataset files). Tolerant of
  /// stray feature types.
  @visibleForTesting
  static List<AccessParcel> parseFeatureCollection(String raw,
      [String? defaultSource]) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    final features = decoded['features'];
    if (features is! List) return const [];

    final parcels = <AccessParcel>[];
    for (final f in features) {
      if (f is! Map) continue;
      final props = (f['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
      final source =
          (props['source'] as String?) ?? defaultSource ?? 'Access land';
      final geom = f['geometry'];
      if (geom is! Map) continue;
      final type = geom['type'];
      final coords = geom['coordinates'];
      if (type == 'Polygon' && coords is List) {
        final rings = _rings(coords);
        if (rings.isNotEmpty) {
          parcels.add(AccessParcel(polygon: GeoPolygon(rings), source: source));
        }
      } else if (type == 'MultiPolygon' && coords is List) {
        for (final poly in coords) {
          if (poly is List) {
            final rings = _rings(poly);
            if (rings.isNotEmpty) {
              parcels
                  .add(AccessParcel(polygon: GeoPolygon(rings), source: source));
            }
          }
        }
      }
    }
    return parcels;
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
