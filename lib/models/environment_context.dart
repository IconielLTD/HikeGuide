/// The environment the user is standing in — the input to every LLM call and the
/// basis for the cache key (context_hash).
///
/// PHASE 3: real detection (Overpass woodland + nearest water, GeoJSON
/// point-in-polygon access) builds this via EnvironmentDetector; [mock] remains
/// only as a fallback when there is no GPS fix. The field set here is the
/// stable-input set the brief defines for context_hash: rounded GPS grid cell +
/// woodland_type + access_status + month.
///
/// [waterDistanceMetres] is negative when no surface water was found within the
/// search radius (see [hasWater]).
class EnvironmentContext {
  final double lat;
  final double lng;
  final String woodlandType; // e.g. "mixed deciduous"
  final String accessStatus; // e.g. "Open Access (CRoW)"
  final String region; // e.g. "East Midlands"
  final String season; // e.g. "summer"
  final int month; // 1-12
  final double waterDistanceMetres;
  final String waterDirection; // 8-point compass, e.g. "SE"
  final String waterKind; // e.g. "stream", "river", "lake"; "" if unknown

  const EnvironmentContext({
    required this.lat,
    required this.lng,
    required this.woodlandType,
    required this.accessStatus,
    required this.region,
    required this.season,
    required this.month,
    required this.waterDistanceMetres,
    required this.waterDirection,
    this.waterKind = '',
  });

  /// Phase 1 stand-in context (Sherwood Forest, East Midlands, early summer).
  /// Replaced by real detection in Phase 3.
  static const EnvironmentContext mock = EnvironmentContext(
    lat: 53.2058,
    lng: -1.0721,
    woodlandType: 'mixed deciduous',
    accessStatus: 'Open Access (CRoW)',
    region: 'East Midlands',
    season: 'summer',
    month: 6,
    waterDistanceMetres: 220,
    waterDirection: 'SE',
    waterKind: 'stream',
  );

  /// False when detection found no surface water within range (distance < 0).
  bool get hasWater => waterDistanceMetres >= 0;

  String get waterSummary {
    if (!hasWater) return 'None within range';
    // Large bodies are often well over a kilometre off, so read in km past 1000 m.
    final d = waterDistanceMetres;
    final dist = d >= 1000
        ? '${(d / 1000).toStringAsFixed(1)} km'
        : '${d.round()} m';
    final base = '$dist $waterDirection';
    return waterKind.isEmpty ? base : '$base · $waterKind';
  }

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'woodlandType': woodlandType,
        'accessStatus': accessStatus,
        'region': region,
        'season': season,
        'month': month,
        'waterDistanceMetres': waterDistanceMetres,
        'waterDirection': waterDirection,
        'waterKind': waterKind,
      };

  factory EnvironmentContext.fromJson(Map<String, dynamic> json) =>
      EnvironmentContext(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        woodlandType: json['woodlandType'] as String? ?? 'unknown',
        accessStatus: json['accessStatus'] as String? ?? 'Access status unknown',
        region: json['region'] as String? ?? 'England',
        season: json['season'] as String? ?? 'unknown',
        month: (json['month'] as num?)?.toInt() ?? 1,
        waterDistanceMetres:
            (json['waterDistanceMetres'] as num?)?.toDouble() ?? -1,
        waterDirection: json['waterDirection'] as String? ?? '',
        waterKind: json['waterKind'] as String? ?? '',
      );
}
