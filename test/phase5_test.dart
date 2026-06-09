import 'package:flutter_test/flutter_test.dart';

import 'package:hike_guide/models/trip.dart';

void main() {
  group('Trip.fromRow', () {
    test('parses fields and computes duration', () {
      final start = DateTime(2026, 6, 5, 14, 30);
      final end = DateTime(2026, 6, 5, 15, 12);
      final trip = Trip.fromRow({
        'id': 7,
        'name': 'Sherwood loop',
        'started_at': start.millisecondsSinceEpoch,
        'ended_at': end.millisecondsSinceEpoch,
        'distance_metres': 2540.0,
      });
      expect(trip.id, 7);
      expect(trip.title, 'Sherwood loop');
      expect(trip.distanceMetres, 2540.0);
      expect(trip.duration, const Duration(minutes: 42));
      expect(trip.dateLabel, contains('5 Jun 2026, 14:30'));
    });

    test('untitled fallback and null duration when unfinished', () {
      final trip = Trip.fromRow({
        'id': 1,
        'name': null,
        'started_at': DateTime(2026, 1, 2, 9, 5).millisecondsSinceEpoch,
        'ended_at': null,
        'distance_metres': null,
      });
      expect(trip.hasName, isFalse);
      expect(trip.title, 'Untitled trip');
      expect(trip.duration, isNull);
      expect(trip.dateLabel, contains('2 Jan 2026, 09:05'));
    });
  });
}
