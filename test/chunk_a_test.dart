// Chunk A pure-logic tests: OS grid reference conversion + declination
// formatting. Both are pure Dart (proj4dart / geomag) — no plugins or network.

import 'package:flutter_test/flutter_test.dart';
import 'package:hike_guide/services/geomagnetic.dart';
import 'package:hike_guide/services/grid_reference.dart';

void main() {
  group('GridReference', () {
    test('Sherwood Forest lands in the SK square with valid format', () {
      final ref = GridReference.fromLatLng(53.2058, -1.0721);
      expect(ref, isNotNull);
      expect(ref, matches(RegExp(r'^[A-Z]{2} \d{3} \d{3}$')));
      expect(ref!.startsWith('SK'), isTrue);
    });

    test('a point outside Great Britain returns null', () {
      // Paris — outside the British National Grid.
      expect(GridReference.fromLatLng(48.8566, 2.3522), isNull);
    });
  });

  group('Geomagnetic', () {
    test('formats declination with E/W and zero', () {
      expect(Geomagnetic.format(0.6), '0.6° E');
      expect(Geomagnetic.format(-1.24), '1.2° W');
      expect(Geomagnetic.format(0.04), '0.0°');
    });

    test('UK declination is small and finite', () {
      final dec = Geomagnetic.declinationDegrees(53.2058, -1.0721,
          date: DateTime(2026, 6, 4));
      expect(dec.isFinite, isTrue);
      expect(dec.abs(), lessThan(5)); // UK is within a few degrees of zero
    });
  });
}
