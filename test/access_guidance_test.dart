import 'package:flutter_test/flutter_test.dart';

import 'package:hike_guide/models/access_guidance.dart';
import 'package:hike_guide/services/access_land_service.dart';

void main() {
  group('accessCategoryForStatus', () {
    test('maps the real AccessLandService status strings', () {
      expect(accessCategoryForStatus('Open Access (CRoW)'),
          AccessCategory.crowOpenAccess);
      expect(accessCategoryForStatus('Forestry England'),
          AccessCategory.forestryEngland);
      expect(accessCategoryForStatus('No mapped open-access right'),
          AccessCategory.noMappedRight);
      expect(accessCategoryForStatus('Access status unknown'),
          AccessCategory.unknown);
    });

    test('the statusAt default sentinels classify to their categories', () {
      // Ties AccessLandService's per-nation fallbacks to the right guidance.
      expect(accessCategoryForStatus(kScotlandOpenAccessStatus),
          AccessCategory.scotlandOpenAccess);
      expect(accessCategoryForStatus(kNoMappedRightStatus),
          AccessCategory.noMappedRight);
    });

    test('Scotland open-access is matched before the CRoW "open access" branch',
        () {
      // kScotlandOpenAccessStatus contains "open access"; the right-to-roam /
      // Scotland check must win so it is not mis-classified as England CRoW.
      expect(accessCategoryForStatus(kScotlandOpenAccessStatus),
          isNot(AccessCategory.crowOpenAccess));
      expect(accessCategoryForStatus('Right to roam (Scotland)'),
          AccessCategory.scotlandOpenAccess);
    });

    test('Scotland restriction-zone labels classify correctly', () {
      expect(accessCategoryForStatus('Military (MOD) — no public access'),
          AccessCategory.militaryNoAccess);
      expect(accessCategoryForStatus('MOD danger area'),
          AccessCategory.militaryNoAccess);
      expect(accessCategoryForStatus('Camping management zone (byelaws)'),
          AccessCategory.campingByelawZone);
    });

    test('null / blank fall back to unknown', () {
      expect(accessCategoryForStatus(null), AccessCategory.unknown);
      expect(accessCategoryForStatus('   '), AccessCategory.unknown);
    });

    test('is case-insensitive and tolerant of wording', () {
      expect(accessCategoryForStatus('crow open access land'),
          AccessCategory.crowOpenAccess);
      expect(accessCategoryForStatus('Managed by FORESTRY England'),
          AccessCategory.forestryEngland);
    });
  });

  group('guidanceForCategory', () {
    test('every category has a title, summary and both lists populated', () {
      for (final c in AccessCategory.values) {
        final g = guidanceForCategory(c);
        expect(g.title, isNotEmpty, reason: '$c title');
        expect(g.summary, isNotEmpty, reason: '$c summary');
        expect(g.youCan, isNotEmpty, reason: '$c youCan');
        expect(g.takeCare, isNotEmpty, reason: '$c takeCare');
      }
    });

    test('CRoW guidance covers roaming off-path; limited covers staying on path',
        () {
      final crow = guidanceForCategory(AccessCategory.crowOpenAccess);
      expect(crow.youCan.join(' ').toLowerCase(), contains('roam'));

      final limited = guidanceForCategory(AccessCategory.noMappedRight);
      expect(limited.takeCare.join(' ').toLowerCase(), contains('right of way'));
    });

    test('Scotland open-access covers roaming, camping, and the key warnings', () {
      final scot = guidanceForCategory(AccessCategory.scotlandOpenAccess);
      final youCan = scot.youCan.join(' ').toLowerCase();
      expect(youCan, contains('roam'));
      expect(youCan, contains('camp'));
      final takeCare = scot.takeCare.join(' ').toLowerCase();
      // The general Scotland notice (auto-shown on entering Scotland) must cover
      // what to avoid + the live-firing warning, since MOD land isn't mapped.
      expect(takeCare, contains('crop'));
      expect(takeCare, contains('fenced'));
      expect(takeCare, contains('construction'));
      expect(takeCare, contains('red flag'));
      expect(takeCare, contains('firing'));
    });

    test('military guidance warns against entry; camping zone mentions a permit',
        () {
      final military = guidanceForCategory(AccessCategory.militaryNoAccess);
      expect(military.takeCare.join(' ').toLowerCase(), contains('ordnance'));

      final camping = guidanceForCategory(AccessCategory.campingByelawZone);
      expect(camping.takeCare.join(' ').toLowerCase(), contains('permit'));
    });

    test('guidanceForStatus routes through the classifier', () {
      expect(guidanceForStatus('Forestry England').title,
          guidanceForCategory(AccessCategory.forestryEngland).title);
    });
  });
}
