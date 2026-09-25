/// The design tokens are a contract, so the contrast figures in their
/// documentation are recomputed here rather than trusted.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/shared/theme/brand.dart';

double _channel(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrast(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('normal text meets WCAG AA (4.5:1)', () {
    const List<(Color, Color, String)> pairs = [
      (Brand.ink, Brand.surface, 'ink on page'),
      (Brand.ink, Brand.surfaceMuted, 'ink on muted surface'),
      (Brand.inkSoft, Brand.surface, 'secondary text on page'),
      (Brand.inkSoft, Brand.surfaceMuted, 'secondary text on muted surface'),
      (Brand.primary, Brand.surface, 'primary on page'),
      (Colors.white, Brand.primary, 'white on primary'),
      (Brand.emergencyText, Brand.emergencySurface, 'emergency text'),
      (Brand.emergencyText, Brand.surface, 'emergency text on page'),
      (Colors.white, Brand.emergency, 'white on emergency fill'),
      (Brand.successText, Brand.surface, 'success text'),
      (Brand.warningText, Brand.surface, 'warning text'),
      (Brand.disabledText, Brand.surface, 'disabled text'),
    ];

    for (final (Color fg, Color bg, String label) in pairs) {
      test(label, () {
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5));
      });
    }
  });

  test('the brand purple is the one the app already ships', () {
    expect(Brand.primary, const Color(0xFF6B4EFF));
  });

  test('the logo mark colour is recorded, not silently adopted', () {
    expect(Brand.brandMark, const Color(0xFF6F17FF));
    expect(Brand.brandMark, isNot(Brand.primary));
  });

  test('spacing is a 4pt scale', () {
    for (final double v in [
      Brand.space1,
      Brand.space2,
      Brand.space3,
      Brand.space4,
      Brand.space5,
      Brand.space6,
      Brand.space8,
    ]) {
      expect(v % 4, 0, reason: '$v is off the 4pt scale');
    }
  });

  test('there are exactly two corner radii', () {
    expect({Brand.radiusControl, Brand.radiusSurface}, hasLength(2));
  });

  test('the minimum tap target meets platform guidance', () {
    expect(Brand.minTapTarget, greaterThanOrEqualTo(48));
  });
}
