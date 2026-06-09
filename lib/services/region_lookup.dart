/// Offline, coarse English-region lookup by nearest centroid. Used only as
/// prompt flavour ("region: East Midlands") — NOT part of the cache key — so an
/// approximate nearest-centroid match over the nine English regions (plus a
/// Wales/Scotland fallback) is plenty. No network, no data file.
class RegionLookup {
  RegionLookup._();

  static const List<({String name, double lat, double lng})> _regions = [
    (name: 'North East England', lat: 54.9, lng: -1.7),
    (name: 'North West England', lat: 53.8, lng: -2.7),
    (name: 'Yorkshire and the Humber', lat: 53.9, lng: -1.3),
    (name: 'East Midlands', lat: 52.9, lng: -0.9),
    (name: 'West Midlands', lat: 52.5, lng: -2.0),
    (name: 'East of England', lat: 52.2, lng: 0.5),
    (name: 'London', lat: 51.5, lng: -0.1),
    (name: 'South East England', lat: 51.3, lng: -0.6),
    (name: 'South West England', lat: 50.8, lng: -3.6),
    (name: 'Wales', lat: 52.3, lng: -3.8),
    (name: 'Scotland', lat: 56.8, lng: -4.2),
  ];

  static String forLatLng(double lat, double lng) {
    String best = 'England';
    double bestSq = double.infinity;
    for (final r in _regions) {
      final dLat = lat - r.lat;
      final dLng = lng - r.lng;
      final sq = dLat * dLat + dLng * dLng;
      if (sq < bestSq) {
        bestSq = sq;
        best = r.name;
      }
    }
    return best;
  }
}
