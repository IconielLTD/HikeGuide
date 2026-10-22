import 'package:latlong2/latlong.dart';

import '../models/environment_context.dart';
import 'access_land_service.dart';
import 'cache_repository.dart';
import 'overpass_service.dart';
import 'region_lookup.dart';

/// Builds a real [EnvironmentContext] from a GPS fix, replacing the Phase-1
/// mock. Composes:
///   - season/month from the clock,
///   - region offline (RegionLookup, prompt flavour only),
///   - woodland + nearest water from Overpass (best-effort; degrades on failure),
///   - access status from bundled CRoW/Forestry GeoJSON (null → "unknown").
///
/// Result is cached per ~500 m cell (env_cache) so Overpass — flaky, 7–9 s, and
/// possibly a metered keyed server — is queried rarely: at most once per cell
/// per [_maxAge] (the land doesn't change, so the Now tab's Refresh reuses it
/// too). On total Overpass failure, returns a degraded context (woodland
/// [unknownWoodland]) so the LLM screens still function, and remembers that
/// failure for [_failureBackoff] so an outage isn't re-queried on every open.
class EnvironmentDetector {
  EnvironmentDetector._();
  static final EnvironmentDetector instance = EnvironmentDetector._();

  static const Duration _maxAge = Duration(days: 7);
  static const Duration _failureBackoff = Duration(minutes: 30);

  /// woodlandType of a degraded context (every Overpass endpoint failed).
  static const String unknownWoodland = 'unknown';

  Future<EnvironmentContext> detect(LatLng at, {DateTime? now}) async {
    final cellKey = CacheRepository.gridKey(at.latitude, at.longitude);
    final repo = CacheRepository.instance;
    final cached = await repo.getCachedEnv(cellKey, maxAge: _maxAge);
    if (cached != null) {
      // A confident detection is good for [_maxAge]; a remembered failure only
      // for [_failureBackoff], after which Overpass is tried again.
      if (cached.woodlandType != unknownWoodland) return cached;
      final recentFailure =
          await repo.getCachedEnv(cellKey, maxAge: _failureBackoff);
      if (recentFailure != null) return recentFailure;
    }

    final when = now ?? DateTime.now();
    final region = RegionLookup.forLatLng(at.latitude, at.longitude);
    final access = await AccessLandService.instance.statusAt(at);
    final ww = await OverpassService.instance.detect(at);

    final env = EnvironmentContext(
      lat: at.latitude,
      lng: at.longitude,
      woodlandType: !ww.ok
          ? unknownWoodland
          : (ww.inWoodland ? (ww.woodlandType ?? 'woodland') : 'open ground'),
      accessStatus: access ?? 'Access status unknown',
      region: region,
      season: seasonForMonth(when.month),
      month: when.month,
      waterDistanceMetres: ww.waterDistanceMetres ?? -1,
      waterDirection: ww.waterDirection ?? '',
      waterKind: ww.waterKind ?? '',
    );

    // Cache either way: a confident detection is reused for [_maxAge], a
    // degraded one only for [_failureBackoff] (see the read above).
    await repo.putCachedEnv(cellKey, env);
    return env;
  }

  static String seasonForMonth(int month) {
    switch (month) {
      case 12:
      case 1:
      case 2:
        return 'winter';
      case 3:
      case 4:
      case 5:
        return 'spring';
      case 6:
      case 7:
      case 8:
        return 'summer';
      default:
        return 'autumn';
    }
  }
}
