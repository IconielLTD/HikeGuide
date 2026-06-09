// Phase 2 pure-logic tests (no plugins/network): context_hash behaviour and
// tolerant model parsing. CacheRepository.contextHash is a static pure function
// and does not open the database, so this stays a plain unit test.

import 'package:flutter_test/flutter_test.dart';
import 'package:hike_guide/models/environment_context.dart';
import 'package:hike_guide/models/guide.dart';
import 'package:hike_guide/models/opportunity.dart';
import 'package:hike_guide/models/skill_category.dart';
import 'package:hike_guide/services/cache_repository.dart';

EnvironmentContext _withMock({
  double? lat,
  double? lng,
  int? month,
  String? woodland,
  double? water,
  String? waterDir,
}) {
  const m = EnvironmentContext.mock;
  return EnvironmentContext(
    lat: lat ?? m.lat,
    lng: lng ?? m.lng,
    woodlandType: woodland ?? m.woodlandType,
    accessStatus: m.accessStatus,
    region: m.region,
    season: m.season,
    month: month ?? m.month,
    waterDistanceMetres: water ?? m.waterDistanceMetres,
    waterDirection: waterDir ?? m.waterDirection,
  );
}

void main() {
  group('contextHash', () {
    test('is deterministic for identical inputs', () {
      expect(
        CacheRepository.contextHash(EnvironmentContext.mock),
        CacheRepository.contextHash(EnvironmentContext.mock),
      );
    });

    test('changes with month and woodland type', () {
      final base = CacheRepository.contextHash(EnvironmentContext.mock);
      expect(base, isNot(CacheRepository.contextHash(_withMock(month: 7))));
      expect(base, isNot(CacheRepository.contextHash(_withMock(woodland: 'pine plantation'))));
    });

    test('ignores sub-grid GPS jitter and exact water distance/direction', () {
      // Small move (~100m) stays in the same ~500m cell; water distance/direction
      // are intentionally excluded from the hash.
      final base = CacheRepository.contextHash(EnvironmentContext.mock);
      final jittered = CacheRepository.contextHash(
        _withMock(lat: 53.2068, lng: -1.0711, water: 9999, waterDir: 'N'),
      );
      expect(base, jittered);
    });
  });

  group('model parsing is tolerant', () {
    test('Opportunity fills sensible defaults for missing fields', () {
      final o = Opportunity.fromJson({
        'title': 'Find north by shadow stick',
        'skill_category': 'navigation',
      });
      expect(o.category, SkillCategory.navigation);
      expect(o.fireWarning, isFalse);
      expect(o.description, isEmpty);
    });

    test('unknown skill_category degrades to unknown, never throws', () {
      final o = Opportunity.fromJson({'title': 'x', 'skill_category': 'wizardry'});
      expect(o.category, SkillCategory.unknown);
    });

    test('wildlife tracking is a first-class category', () {
      final o = Opportunity.fromJson(
          {'title': 'Read deer tracks by the stream', 'skill_category': 'tracking'});
      expect(o.category, SkillCategory.tracking);
      expect(SkillCategory.tracking.label, 'Tracking');
    });

    test('Guide tolerates string steps and null legal_note', () {
      final g = Guide.fromJson({
        'title': 'Lay a small fire',
        'steps': ['Gather tinder', 'Build a platform'],
        'fire_warning': true,
        'legal_note': null,
      }, category: SkillCategory.fire);
      expect(g.steps.length, 2);
      expect(g.steps.first.text, 'Gather tinder');
      expect(g.fireWarning, isTrue);
      expect(g.legalNote, isNull);
      expect(g.category, SkillCategory.fire);
    });
  });
}
