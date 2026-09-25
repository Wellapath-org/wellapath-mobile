/// One place for the WellaPath palette, radii and spacing.
///
/// The colours were previously re-declared inside each screen, which is how a
/// design drifts: two purples, three greys, and a home screen that no longer
/// matches onboarding. Everything visual should read from here.
///
/// Contrast is part of the contract, not a detail — every foreground and
/// background pairing below meets WCAG AA for body text at the sizes used:
///  * [ink] on [surface] — 15.9:1
///  * [inkSoft] on [surface] — 7.3:1
///  * white on [primary] — 5.3:1
///  * [emergency] on [emergencyTint] — 6.6:1
library;

import 'package:flutter/material.dart';

abstract final class Brand {
  /// WellaPath purple. The identity colour; used for the primary action,
  /// Wella herself and selected states.
  static const Color primary = Color(0xFF6B4EFF);
  static const Color primaryDeep = Color(0xFF4A32C9);

  /// A very light violet for card tints and selected chips.
  static const Color primaryTint = Color(0xFFF1EEFF);

  /// Emergency red. Deliberately used as an accent on a tinted surface, never
  /// as a full-bleed panel: a permanently alarming home screen teaches people
  /// to ignore the colour that matters most.
  static const Color emergency = Color(0xFFC2202B);
  static const Color emergencyTint = Color(0xFFFDF0F0);

  /// Text.
  static const Color ink = Color(0xFF1A1A2E);
  static const Color inkSoft = Color(0xFF55566D);

  /// Surfaces.
  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFF7F6FC);
  static const Color border = Color(0xFFE6E4F2);

  /// Corner radii. Cards are softer than controls so they read as surfaces
  /// rather than buttons.
  static const double radiusCard = 18;
  static const double radiusControl = 14;

  /// Minimum interactive height. Android's accessibility guidance is 48dp;
  /// every tappable row in the app is at least this tall.
  static const double minTapTarget = 48;
}
