/// WellaPath design tokens — colour, spacing, radius and type.
///
/// ### Where these come from
///
/// Nothing here is invented. The colours were read out of what the app
/// already ships:
///
///  * `#6B4EFF` is the purple every existing screen already uses (25
///    occurrences across assessment, results, locator and splash). It is the
///    app's established primary and is used as-is.
///  * `#6F17FF` is the exact purple of the logo mark
///    (`assets/images/logo_icon.png`, sampled). It is **recorded** as
///    [brandMark] but deliberately not adopted as the UI primary: switching
///    would repaint clinical screens this work must not touch. The
///    difference between the mark and the UI purple is a real inconsistency
///    for design to reconcile deliberately, not something to fix silently
///    here.
///  * The supporting colours the app already uses — `#DC2626`, `#22C55E`,
///    `#F59E0B`, `#E5E7EB` — are Tailwind red-600 / green-500 / amber-500 /
///    gray-200. Where a token needed a step the app had not used yet (a
///    surface tint, or a darker shade to reach contrast), the value is taken
///    from the **same family** rather than mixed by hand.
///
/// ### Contrast
///
/// Every normal-text pairing below is ≥ 4.5:1 (WCAG 2.2 AA), measured, not
/// estimated:
///
/// | Pair | Ratio |
/// | --- | --- |
/// | [ink] on [surface] | 17.06:1 |
/// | [ink] on [surfaceMuted] | 15.73:1 |
/// | [inkSoft] on [surface] | 7.15:1 |
/// | [inkSoft] on [surfaceMuted] | 6.59:1 |
/// | [primary] on [surface] | 5.05:1 |
/// | white on [primary] | 5.05:1 |
/// | [emergencyText] on [emergencySurface] | 5.91:1 |
/// | [emergencyText] on [surface] | 6.47:1 |
/// | white on [emergency] | 4.83:1 |
/// | [successText] / [warningText] on [surface] | 5.02:1 |
/// | [disabledText] on [surface] | 4.83:1 |
///
/// `test/theme/brand_tokens_test.dart` recomputes these, so a colour cannot
/// be nudged without the build noticing.
///
/// ### House style
///
/// Flat, confident surfaces. No gradients, no glow, no glassmorphism, no
/// card around every paragraph. Elevation is restrained: a border or a tint
/// carries the separation, and shadow is reserved for things that genuinely
/// float (sheets, the bottom bar).
library;

import 'package:flutter/material.dart';

abstract final class Brand {
  // ── Colour ────────────────────────────────────────────────────────────

  /// The app's established primary purple.
  static const Color primary = Color(0xFF6B4EFF);

  /// A pressed/darker step of [primary], for interaction states only.
  static const Color primaryPressed = Color(0xFF5A3FE0);

  /// Very light violet for selected chips and quiet tinted surfaces.
  static const Color primarySurface = Color(0xFFF1EEFF);

  /// The logo mark's exact purple. Recorded for design reconciliation; not
  /// used as the UI primary. See the library comment.
  static const Color brandMark = Color(0xFF6F17FF);

  /// Emergency. [emergency] fills icons and solid shapes; [emergencyText] is
  /// the darker step used for words, because the fill colour does not reach
  /// 4.5:1 on the tinted surface.
  static const Color emergency = Color(0xFFDC2626);
  static const Color emergencyText = Color(0xFFB91C1C);
  static const Color emergencySurface = Color(0xFFFEF2F2);

  /// Status. The bright step marks state (dots, icons); the dark step is for
  /// text on a light surface.
  static const Color success = Color(0xFF22C55E);
  static const Color successText = Color(0xFF15803D);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningText = Color(0xFFB45309);

  /// Text.
  static const Color ink = Color(0xFF1A1A2E);
  static const Color inkSoft = Color(0xFF55566D);

  /// Surfaces. The page is white; [surfaceMuted] separates a block without
  /// needing a border or a shadow.
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF6F5FA);
  static const Color border = Color(0xFFE5E7EB);

  /// Disabled controls. Both are legible — a disabled control must still be
  /// readable, it just must not look pressable.
  static const Color disabledSurface = Color(0xFFF3F4F6);
  static const Color disabledText = Color(0xFF6B7280);

  // ── Spacing ───────────────────────────────────────────────────────────
  // A 4pt scale. Anything not on it is a mistake, not a nuance.

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;

  /// Screen side gutter.
  static const double gutter = space5;

  // ── Radius ────────────────────────────────────────────────────────────
  // Two values only. Controls are tighter than the surfaces they sit on.

  static const double radiusControl = 12;
  static const double radiusSurface = 16;

  // ── Touch ─────────────────────────────────────────────────────────────

  /// Minimum interactive size, per WCAG 2.2 and Android guidance.
  static const double minTapTarget = 48;

  // ── Type ──────────────────────────────────────────────────────────────
  // One scale, used everywhere. Sizes are unscaled: Flutter applies the
  // user's text-size setting on top, and every layout here is built to grow
  // with it rather than clip.

  static const TextStyle display = TextStyle(
    fontSize: 26,
    height: 1.25,
    fontWeight: FontWeight.w800,
    color: ink,
  );
  static const TextStyle title = TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: ink,
  );
  static const TextStyle cardTitle = TextStyle(
    fontSize: 16.5,
    height: 1.35,
    fontWeight: FontWeight.w700,
    color: ink,
  );
  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.5,
    color: inkSoft,
  );
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: ink,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    height: 1.45,
    color: inkSoft,
  );
  static const TextStyle label = TextStyle(
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: inkSoft,
  );
}
