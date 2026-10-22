import 'package:flutter_test/flutter_test.dart';
import 'package:hike_guide/services/overpass_server_store.dart';

void main() {
  group('OverpassServerStore.normalise', () {
    test('completes a base address with a trailing slash', () {
      expect(OverpassServerStore.normalise('https://api.overpass.ch/v1/abc123/'),
          'https://api.overpass.ch/v1/abc123/interpreter');
    });

    test('completes a base address without a trailing slash', () {
      expect(OverpassServerStore.normalise('https://overpass.nextgis.com/abc123/api'),
          'https://overpass.nextgis.com/abc123/api/interpreter');
    });

    test('leaves a full interpreter address unchanged', () {
      const full = 'https://api.overpass.ch/v1/abc123/interpreter';
      expect(OverpassServerStore.normalise(full), full);
      expect(OverpassServerStore.normalise(' $full '), full);
    });
  });
}
