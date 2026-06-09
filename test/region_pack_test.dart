import 'package:flutter_test/flutter_test.dart';

import 'package:hike_guide/models/region_pack.dart';
import 'package:hike_guide/services/access_land_service.dart';
import 'package:hike_guide/services/pack_resolver.dart';

void main() {
  group('RegionPack / PackManifest', () {
    test('parses a bundled pack from manifest JSON', () {
      final manifest = PackManifest.fromJson(const {
        'schema': 1,
        'packs': [
          {
            'id': 'east-midlands',
            'nation': 'England',
            'label': 'East Midlands',
            'version': '2026-06-09',
            'asset': 'assets/packs/east-midlands.geojson',
            'sizeBytes': 3916745,
          },
        ],
      });
      expect(manifest.schema, 1);
      expect(manifest.packs, hasLength(1));
      final pack = manifest.byId('east-midlands')!;
      expect(pack.nation, 'England');
      expect(pack.label, 'East Midlands');
      expect(pack.isBundled, isTrue); // has an asset
      expect(pack.url, isNull);
    });

    test('a remote pack (url, no asset) is not bundled', () {
      final pack = RegionPack.fromJson(const {
        'id': 'scotland',
        'nation': 'Scotland',
        'version': '1',
        'url': 'https://example.com/scotland.geojson',
        'sha256': 'abc123',
      });
      expect(pack.isBundled, isFalse);
      expect(pack.label, 'scotland'); // falls back to id
      expect(pack.sha256, 'abc123');
    });

    test('byId returns null for an unknown pack', () {
      const manifest = PackManifest(schema: 1, packs: []);
      expect(manifest.byId('nope'), isNull);
    });
  });

  group('PackResolver coverage index', () {
    // A square coverage area roughly over the East Midlands.
    const coverage = '{"type":"FeatureCollection","features":['
        '{"type":"Feature","properties":{"packId":"east-midlands",'
        '"nation":"England","label":"East Midlands"},'
        '"geometry":{"type":"Polygon","coordinates":'
        '[[[-1.5,52.5],[-0.5,52.5],[-0.5,53.3],[-1.5,53.3],[-1.5,52.5]]]}}]}';

    test('a point inside resolves to the pack + nation', () {
      final resolver = PackResolver(PackResolver.parseCoverage(coverage));
      final area = resolver.areaAt(53.0, -1.0); // lat, lng
      expect(area, isNotNull);
      expect(area!.packId, 'east-midlands');
      expect(area.nation, 'England');
    });

    test('a point outside is uncovered (null)', () {
      final resolver = PackResolver(PackResolver.parseCoverage(coverage));
      expect(resolver.areaAt(56.8, -4.2), isNull); // Scotland, no pack
    });
  });

  group('AccessLandService.parseFeatureCollection', () {
    test('reads per-feature properties.source, with a fallback', () {
      const fc = '{"type":"FeatureCollection","features":['
          '{"type":"Feature","properties":{"source":"Forestry England"},'
          '"geometry":{"type":"Polygon","coordinates":'
          '[[[-1.1,53.2],[-1.05,53.2],[-1.05,53.22],[-1.1,53.22],[-1.1,53.2]]]}},'
          '{"type":"Feature","properties":{},'
          '"geometry":{"type":"Polygon","coordinates":'
          '[[[-1.2,53.2],[-1.15,53.2],[-1.15,53.22],[-1.2,53.22],[-1.2,53.2]]]}}]}';
      final parcels =
          AccessLandService.parseFeatureCollection(fc, 'Open Access (CRoW)');
      expect(parcels, hasLength(2));
      expect(parcels[0].source, 'Forestry England'); // from properties.source
      expect(parcels[1].source, 'Open Access (CRoW)'); // fell back to default
    });
  });
}
