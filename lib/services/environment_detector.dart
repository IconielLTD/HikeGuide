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
/// Result is cached per ~500 m cell (env_cache) so Overpass — flaky, 7–9 s — is
/// queried rarely: at most once per cell per [_maxAge], or on an explicit
/// refresh. On total Overpass failure with no cache, returns a degraded context
/// (woodland "unknown") so the LLM screens still function.
class EnvironmentDetector {
  EnvironmentDetector._();
  static final EnvironmentDetector instance = EnvironmentDetector._();

  static const Duration _maxAge = Duration(days: 7);

  Future<EnvironmentContext> detect(
    LatLng at, {
    bool forceRefresh = false,
    DateTime? now,
  }) async {
    final cellKey = CacheRepository.gridKey(at.latitude, at.longitude);
    if (!forceRefresh) {
      final cached =
          await CacheRepository.instance.getCachedEnv(cellKey, maxAge: _maxAge);
      if (cached != null) return cached;
    }

    final when = now ?? DateTime.now();
    final region = RegionLookup.forLatLng(at.latitude, at.longitude);
    final access = await AccessLandService.instance.statusAt(at);
    final ww = await OverpassService.instance.detect(at);

    final env = EnvironmentContext(
      lat: at.latitude,
      lng: at.longitude,
      woodlandType: !ww.ok
          ? 'unknown'
          : (ww.inWoodland ? (ww.woodlandType ?? 'woodland') : 'open ground'),
      accessStatus: access ?? 'Access status unknown',
      region: region,
      season: seasonForMonth(when.month),
      month: when.month,
      waterDistanceMetres: ww.waterDistanceMetres ?? -1,
      waterDirection: ww.waterDirection ?? '',
      waterKind: ww.waterKind ?? '',
    );

    // Only cache a confident detection — never cache a degraded "unknown" from a
    // failed Overpass round-trip, so the next open retries.
    if (ww.ok) {
      await CacheRepository.instance.putCachedEnv(cellKey, env);
    }
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
