import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:hike_guide/models/environment_context.dart';
import 'package:hike_guide/services/access_land_service.dart';
import 'package:hike_guide/services/environment_detector.dart';
import 'package:hike_guide/services/geo/geometry.dart';
import 'package:hike_guide/services/overpass_service.dart';
import 'package:hike_guide/services/region_lookup.dart';

void main() {
  group('geometry — point in polygon', () {
    final square = GeoPolygon([
      [
        [0, 0],
        [10, 0],
        [10, 10],
        [0, 10],
        [0, 0],
      ]
    ]);

    test('inside vs outside', () {
      expect(square.contains(5, 5), isTrue);
      expect(square.contains(15, 5), isFalse); // bbox-rejected
      expect(square.contains(-1, 5), isFalse);
    });

    test('holes subtract (even-odd across rings)', () {
      final withHole = GeoPolygon([
        [
          [0, 0],
          [10, 0],
          [10, 10],
          [0, 10],
          [0, 0],
        ],
        [
          [3, 3],
          [7, 3],
          [7, 7],
          [3, 7],
          [3, 3],
        ],
      ]);
      expect(withHole.contains(1, 1), isTrue); // in outer, not in hole
      expect(withHole.contains(5, 5), isFalse); // inside the hole
    });
  });

  group('geometry — distance & bearing', () {
    test('haversine ~111 km per degree of latitude', () {
      final d = haversineMetres(const LatLng(0, 0), const LatLng(1, 0));
      expect(d, greaterThan(111000));
      expect(d, lessThan(111400));
    });

    test('8-point bearings', () {
      expect(bearing8(const LatLng(0, 0), const LatLng(1, 0)), 'N');
      expect(bearing8(const LatLng(0, 0), const LatLng(0, 1)), 'E');
      expect(bearing8(const LatLng(1, 1), const LatLng(0, 0)), 'SW');
    });

    test('pointToSegment measures to the nearest edge, clamped to the ends', () {
      const a = LatLng(0, 0);
      const b = LatLng(0, 0.002); // ~222 m east-west segment at the equator
      // 100 m north of the middle → ~100 m, closest near the midpoint.
      final mid = pointToSegment(const LatLng(0.0009, 0.001), a, b);
      expect(mid.metres, closeTo(100, 5));
      expect(mid.closest.longitude, closeTo(0.001, 1e-4));
      // Past end B → clamps to B (~111 m beyond it).
      final past = pointToSegment(const LatLng(0, 0.003), a, b);
      expect(past.metres, closeTo(111, 5));
      expect(past.closest.longitude, closeTo(0.002, 1e-4));
    });
  });

  group('Overpass parse', () {
    test('point inside a wood polygon + nearest water', () {
      const at = LatLng(53.2058, -1.0721);
      final json = {
        'elements': [
          {
            'type': 'way',
            'tags': {
              'natural': 'wood',
              'leaf_type': 'broadleaved',
              'name': 'Test Wood',
            },
            'geometry': [
              {'lat': 53.20, 'lon': -1.08},
              {'lat': 53.21, 'lon': -1.08},
              {'lat': 53.21, 'lon': -1.06},
              {'lat': 53.20, 'lon': -1.06},
              {'lat': 53.20, 'lon': -1.08},
            ],
          },
          {
            'type': 'way',
            'tags': {'natural': 'water', 'water': 'lake'},
            'geometry': [
              {'lat': 53.2030, 'lon': -1.0690},
              {'lat': 53.2025, 'lon': -1.0685},
            ],
          },
        ],
      };
      final ww = OverpassService.parse(at, json);
      expect(ww.ok, isTrue);
      expect(ww.inWoodland, isTrue);
      expect(ww.woodlandType, 'broadleaf deciduous');
      expect(ww.waterDistanceMetres, isNotNull);
      expect(ww.waterDistanceMetres! > 0, isTrue);
      expect(ww.waterKind, 'lake');
      expect(
        const ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'],
        contains(ww.waterDirection),
      );
    });

    test('leaf_type mapping fallbacks', () {
      expect(OverpassService.woodlandTypeFromTags({'leaf_type': 'needleleaved'}),
          'coniferous');
      expect(OverpassService.woodlandTypeFromTags({'leaf_type': 'mixed'}),
          'mixed woodland');
      expect(OverpassService.woodlandTypeFromTags({'natural': 'wood'}),
          'woodland');
      expect(OverpassService.woodlandTypeFromTags({'landuse': 'forest'}),
          'forest');
    });

    test('prefers the nearest large body by edge distance, ignoring streams',
        () {
      const at = LatLng(53.2000, -1.0700);
      final json = {
        'elements': [
          // Far lake (~1 km NW), closed-way polygon.
          {
            'type': 'way',
            'tags': {'natural': 'water', 'water': 'lake'},
            'geometry': [
              {'lat': 53.2090, 'lon': -1.0850},
              {'lat': 53.2095, 'lon': -1.0840},
              {'lat': 53.2088, 'lon': -1.0835},
              {'lat': 53.2090, 'lon': -1.0850},
            ],
          },
          // Very near stream (~10 m) — must be IGNORED (not a large body).
          {
            'type': 'way',
            'tags': {'waterway': 'stream'},
            'geometry': [
              {'lat': 53.20009, 'lon': -1.0701},
              {'lat': 53.20008, 'lon': -1.0699},
            ],
          },
          // Near lake (~70 m), 2-node way — the expected winner.
          {
            'type': 'way',
            'tags': {'natural': 'water', 'water': 'lake'},
            'geometry': [
              {'lat': 53.2006, 'lon': -1.0703},
              {'lat': 53.2004, 'lon': -1.0698},
            ],
          },
        ],
      };
      final ww = OverpassService.parse(at, json);
      expect(ww.waterKind, 'lake'); // not the closer stream
      expect(ww.waterDistanceMetres, isNotNull);
      expect(ww.waterDistanceMetres!, lessThan(150)); // the near lake, not the far one
    });

    test('reservoirs and rivers count; streams and springs are ignored', () {
      const at = LatLng(53.2000, -1.0700);

      final reservoir = OverpassService.parse(at, {
        'elements': [
          {
            'type': 'way',
            'tags': {'landuse': 'reservoir'},
            'geometry': [
              {'lat': 53.2010, 'lon': -1.0710},
              {'lat': 53.2012, 'lon': -1.0700},
              {'lat': 53.2008, 'lon': -1.0695},
              {'lat': 53.2010, 'lon': -1.0710},
            ],
          },
        ],
      });
      expect(reservoir.waterKind, 'reservoir');
      expect(reservoir.waterDistanceMetres, isNotNull);

      final river = OverpassService.parse(at, {
        'elements': [
          {
            'type': 'way',
            'tags': {'waterway': 'river'},
            'geometry': [
              {'lat': 53.2005, 'lon': -1.0705},
              {'lat': 53.2003, 'lon': -1.0699},
            ],
          },
        ],
      });
      expect(river.waterKind, 'river');
      expect(river.waterDistanceMetres, isNotNull);

      // A lone spring or stream is not a "large body" → no water reported.
      final spring = OverpassService.parse(at, {
        'elements': [
          {
            'type': 'node',
            'tags': {'natural': 'spring'},
            'lat': 53.2003,
            'lon': -1.0702,
          },
        ],
      });
      expect(spring.waterKind, isNull);
      expect(spring.waterDistanceMetres, isNull);
    });

    test('open ground when not inside any wood polygon', () {
      const at = LatLng(54.0, -2.0); // far from the polygon below
      final json = {
        'elements': [
          {
            'type': 'way',
            'tags': {'natural': 'wood'},
            'geometry': [
              {'lat': 53.20, 'lon': -1.08},
              {'lat': 53.21, 'lon': -1.08},
              {'lat': 53.21, 'lon': -1.06},
              {'lat': 53.20, 'lon': -1.08},
            ],
          },
        ],
      };
      final ww = OverpassService.parse(at, json);
      expect(ww.ok, isTrue);
      expect(ww.inWoodland, isFalse);
      expect(ww.woodlandType, isNull);
    });
  });

  group('access GeoJSON parse', () {
    const fc = '{"type":"FeatureCollection","features":['
        '{"type":"Feature","properties":{},"geometry":{"type":"Polygon",'
        '"coordinates":[[[-1.10,53.20],[-1.05,53.20],[-1.05,53.22],'
        '[-1.10,53.22],[-1.10,53.20]]]}}]}';

    test('parses polygons and answers containment', () {
      final parcels = AccessLandService.parseFeatureCollection(
          fc, 'Open Access (CRoW)');
      expect(parcels, hasLength(1));
      expect(parcels.first.source, 'Open Access (CRoW)');
      expect(parcels.first.polygon.contains(-1.07, 53.21), isTrue);
      expect(parcels.first.polygon.contains(-2.00, 53.21), isFalse);
      expect(parcels.first.outline, isNotEmpty);
    });
  });

  group('EnvironmentContext.waterSummary', () {
    EnvironmentContext ctx({required double dist, String kind = ''}) =>
        EnvironmentContext(
          lat: 0,
          lng: 0,
          woodlandType: 'woodland',
          accessStatus: 'unknown',
          region: 'England',
          season: 'summer',
          month: 6,
          waterDistanceMetres: dist,
          waterDirection: 'SE',
          waterKind: kind,
        );

    test('appends the water kind when known', () {
      expect(ctx(dist: 60, kind: 'lake').waterSummary, '60 m SE · lake');
      expect(ctx(dist: 60).waterSummary, '60 m SE');
      expect(ctx(dist: -1, kind: 'lake').waterSummary, 'None within range');
    });

    test('reads distance in km past 1 km', () {
      expect(ctx(dist: 1500, kind: 'reservoir').waterSummary,
          '1.5 km SE · reservoir');
      expect(ctx(dist: 999).waterSummary, '999 m SE');
    });
  });

  group('region & season', () {
    test('region by nearest centroid', () {
      expect(RegionLookup.forLatLng(53.2058, -1.0721), 'East Midlands');
      expect(RegionLookup.forLatLng(51.5, -0.1), 'London');
    });

    test('season by month', () {
      expect(EnvironmentDetector.seasonForMonth(1), 'winter');
      expect(EnvironmentDetector.seasonForMonth(4), 'spring');
      expect(EnvironmentDetector.seasonForMonth(7), 'summer');
      expect(EnvironmentDetector.seasonForMonth(10), 'autumn');
    });
  });
}
