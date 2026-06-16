import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:hike_guide/services/trip_recorder.dart';

void main() {
  group('TripRecorder.pathDistanceMetres', () {
    test('sums consecutive legs', () {
      final pts = [
        const LatLng(0, 0),
        const LatLng(0, 0.001),
        const LatLng(0, 0.002),
      ];
      final d = TripRecorder.pathDistanceMetres(pts);
      expect(d, greaterThan(210)); // ~111 m per 0.001° lng, two legs
      expect(d, lessThan(235));
    });

    test('zero for fewer than two points', () {
      expect(TripRecorder.pathDistanceMetres(const []), 0);
      expect(TripRecorder.pathDistanceMetres(const [LatLng(1, 1)]), 0);
    });
  });

  group('TripRecorder.formatDistance', () {
    test('metres below 1 km, km above', () {
      expect(TripRecorder.formatDistance(0), '0 m');
      expect(TripRecorder.formatDistance(999), '999 m');
      expect(TripRecorder.formatDistance(1000), '1.00 km');
      expect(TripRecorder.formatDistance(2540), '2.54 km');
    });
  });

  group('TripRecorder.formatDuration', () {
    test('mm:ss under an hour, h:mm:ss over', () {
      expect(TripRecorder.formatDuration(const Duration(seconds: 5)), '00:05');
      expect(
          TripRecorder.formatDuration(const Duration(minutes: 3, seconds: 7)),
          '03:07');
      expect(
          TripRecorder.formatDuration(
              const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });
  });

  group('TripRecorder.stepsSinceBaseline', () {
    test('delta from the boot-cumulative counter', () {
      expect(TripRecorder.stepsSinceBaseline(1000, 1000), 0);
      expect(TripRecorder.stepsSinceBaseline(1000, 1250), 250);
    });

    test('floors at zero across a mid-trip reboot (counter resets)', () {
      expect(TripRecorder.stepsSinceBaseline(5000, 40), 0);
    });
  });

  group('TripRecorder.acceptFix', () {
    final t0 = DateTime(2026, 6, 16, 17, 0, 0);
    const here = LatLng(53.20, -1.07);

    test('keeps the first good fix (no prior point)', () {
      expect(
        TripRecorder.acceptFix(
            accuracyMetres: 8, candidate: here, candidateAt: t0),
        isTrue,
      );
    });

    test('rejects a low-accuracy (coarse network) fix', () {
      // The "jumped to the town centre" bug: a fix reporting a huge error radius.
      expect(
        TripRecorder.acceptFix(
            accuracyMetres: 1500, candidate: here, candidateAt: t0),
        isFalse,
      );
    });

    test('rejects an impossible teleport between close-in-time fixes', () {
      // ~1.6 km away (0.02° lng ≈ 1.3 km at 53°N, plus lat) just 5 s later.
      const far = LatLng(53.21, -1.04);
      expect(
        TripRecorder.acceptFix(
          accuracyMetres: 8,
          candidate: far,
          candidateAt: t0.add(const Duration(seconds: 5)),
          lastAccepted: here,
          lastAt: t0,
        ),
        isFalse,
      );
    });

    test('keeps a far point reached after a long gap (real, just backgrounded)',
        () {
      // Same ~1.6 km jump, but 20 minutes later → ~1.3 m/s, plausibly walked.
      const far = LatLng(53.21, -1.04);
      expect(
        TripRecorder.acceptFix(
          accuracyMetres: 8,
          candidate: far,
          candidateAt: t0.add(const Duration(minutes: 20)),
          lastAccepted: here,
          lastAt: t0,
        ),
        isTrue,
      );
    });

    test('keeps a normal walking step', () {
      const next = LatLng(53.2001, -1.07); // ~11 m
      expect(
        TripRecorder.acceptFix(
          accuracyMetres: 12,
          candidate: next,
          candidateAt: t0.add(const Duration(seconds: 5)),
          lastAccepted: here,
          lastAt: t0,
        ),
        isTrue,
      );
    });
  });

  group('TripRecorder.retraceFlags', () {
    test('a straight walk never flags itself', () {
      // ~11 m spacing (0.0001° lng at the equator), all forward.
      final pts = [for (var i = 0; i < 12; i++) LatLng(0, i * 0.0001)];
      expect(TripRecorder.retraceFlags(pts).any((f) => f), isFalse);
    });

    test('out-and-back flags the return leg, not the outbound leg', () {
      final out = [for (var i = 0; i <= 8; i++) LatLng(0, i * 0.0001)];
      final back = [for (var i = 7; i >= 0; i--) LatLng(0, i * 0.0001)];
      final flags = TripRecorder.retraceFlags([...out, ...back]);

      // Nothing on the way out doubles back.
      expect(flags.sublist(0, out.length).any((f) => f), isFalse);
      // The deep return (back near the start) retraces earlier track.
      expect(flags.last, isTrue);
      // And at least some of the return leg is flagged.
      expect(flags.sublist(out.length).where((f) => f).length, greaterThan(1));
    });

    test('flags align 1:1 with points and empty in == empty out', () {
      expect(TripRecorder.retraceFlags(const []), isEmpty);
      final pts = [const LatLng(1, 1), const LatLng(1, 1.0001)];
      expect(TripRecorder.retraceFlags(pts).length, pts.length);
    });
  });
}
