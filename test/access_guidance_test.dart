import 'package:flutter_test/flutter_test.dart';

import 'package:hike_guide/models/access_guidance.dart';

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

    test('guidanceForStatus routes through the classifier', () {
      expect(guidanceForStatus('Forestry England').title,
          guidanceForCategory(AccessCategory.forestryEngland).title);
    });
  });
}
