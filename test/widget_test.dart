// Phase 1 smoke test. We test the theme directly rather than pumping the full
// app, because MapScreen reads GPS via the geolocator plugin (unavailable in a
// plain widget test) and runs a repeating pulse animation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hike_guide/theme/app_theme.dart';

void main() {
  test('HikeGuide theme is a dark olive theme', () {
    final ThemeData theme = buildHikeGuideTheme();
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF1A1F14));
    expect(theme.colorScheme.primary, const Color(0xFFC8962A));
  });
}
