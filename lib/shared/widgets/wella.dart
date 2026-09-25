/// Wella — WellaPath's guide character.
///
/// Drawn entirely in code from the brand mark's two chevrons, so the app gains
/// an original character instead of borrowing a generic medical illustration.
/// Because it is geometry rather than an image file there is **no third-party
/// asset and no licence to clear**, it scales to any size without artwork
/// exports, and it costs a few kilobytes of Dart instead of a set of PNGs.
///
/// The face is deliberately minimal — two eyes, a soft smile, a raised hand.
/// A clinical-decision-support app should feel calm and friendly, not cute to
/// the point of being unserious.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/motion.dart';

/// What Wella is doing.
enum WellaMood {
  /// Neutral, gently breathing.
  calm,

  /// Hand raised, waving. Used for the welcome.
  waving,

  /// Eyes closed in a smile, small sparkle. Used when onboarding completes.
  celebrating,
}

class Wella extends StatefulWidget {
  const Wella({
    super.key,
    this.size = 140,
    this.mood = WellaMood.calm,
    this.semanticLabel = 'Wella, the WellaPath guide',
  });

  final double size;
  final WellaMood mood;
  final String semanticLabel;

  @override
  State<Wella> createState() => _WellaState();
}

class _WellaState extends State<Wella> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  bool _configured = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) return;
    _configured = true;
    if (motionEnabled(context)) {
      _controller.repeat();
    } else {
      // Reduced motion: hold a still, friendly pose rather than freezing at
      // an arbitrary phase.
      _controller.value = 0.25;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _WellaPainter(phase: _controller.value, mood: widget.mood),
          ),
        ),
      ),
    );
  }
}

class _WellaPainter extends CustomPainter {
  _WellaPainter({required this.phase, required this.mood});

  /// 0..1, one full breathe/wave cycle.
  final double phase;
  final WellaMood mood;

  static const Color _purple = Color(0xFF6B4EFF);
  static const Color _purpleDeep = Color(0xFF4A32C9);
  static const Color _ink = Color(0xFF1A1A2E);

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide;
    final Offset centre = Offset(size.width / 2, size.height / 2);

    // One slow sine drives the breathe; the body rises a little over 2% of
    // its height, which reads as alive without being distracting.
    final double breathe = math.sin(phase * 2 * math.pi);
    final Offset bodyCentre = centre.translate(0, breathe * s * 0.018);

    canvas.save();
    canvas.translate(bodyCentre.dx, bodyCentre.dy);

    _paintHalo(canvas, s);
    _paintBody(canvas, s);
    _paintChevronSheen(canvas, s);
    _paintFace(canvas, s, breathe);
    _paintHand(canvas, s, breathe);
    if (mood == WellaMood.celebrating) _paintSparkles(canvas, s);

    canvas.restore();
  }

  /// Soft violet glow so Wella sits on white without a hard edge.
  void _paintHalo(Canvas canvas, double s) {
    final Paint halo = Paint()
      ..shader = RadialGradient(
        colors: [_purple.withValues(alpha: 0.16), _purple.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: s * 0.5));
    canvas.drawCircle(Offset.zero, s * 0.5, halo);
  }

  /// The body: the brand mark's chevron, rounded into a friendly shape.
  ///
  /// A wide rounded wedge — flat-ish shoulders, a soft point at the bottom —
  /// which keeps the logo's downward "check" gesture while reading as a
  /// character rather than an icon.
  void _paintBody(Canvas canvas, double s) {
    final double w = s * 0.46;
    final double h = s * 0.50;

    // Shoulders are rounded and the point is softened into a chin, so the
    // silhouette reads as a character rather than a triangle.
    final Path body = Path()
      ..moveTo(-w, -h * 0.58)
      ..quadraticBezierTo(-w, -h * 0.98, -w * 0.58, -h * 0.98)
      ..lineTo(w * 0.58, -h * 0.98)
      ..quadraticBezierTo(w, -h * 0.98, w, -h * 0.58)
      ..lineTo(w * 0.42, h * 0.40)
      ..quadraticBezierTo(w * 0.30, h * 0.86, 0, h * 0.92)
      ..quadraticBezierTo(-w * 0.30, h * 0.86, -w * 0.42, h * 0.40)
      ..close();

    final Paint fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_purple, _purpleDeep],
      ).createShader(Rect.fromLTRB(-w, -h, w, h));

    canvas.drawShadow(body.shift(const Offset(0, 3)), _purpleDeep, 6, false);
    canvas.drawPath(body, fill);
  }

  /// The second, smaller chevron of the mark, as a lighter sheen on the body.
  void _paintChevronSheen(Canvas canvas, double s) {
    final double w = s * 0.46;
    final double h = s * 0.50;
    final Path sheen = Path()
      ..moveTo(w * 0.10, -h * 0.80)
      ..lineTo(w * 0.72, -h * 0.80)
      ..lineTo(w * 0.24, h * 0.10)
      ..lineTo(-w * 0.10, -h * 0.18)
      ..close();
    canvas.drawPath(
      sheen,
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );
  }

  void _paintFace(Canvas canvas, double s, double breathe) {
    final double eyeY = -s * 0.13;
    final double eyeDx = s * 0.115;
    final double eyeR = s * 0.052;

    final Paint white = Paint()..color = Colors.white;
    final Paint pupil = Paint()..color = _ink;

    if (mood == WellaMood.celebrating) {
      // Happy closed eyes: two upward arcs.
      final Paint stroke = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.026
        ..strokeCap = StrokeCap.round;
      for (final double dx in [-eyeDx, eyeDx]) {
        final Rect r = Rect.fromCenter(
          center: Offset(dx, eyeY),
          width: eyeR * 2.2,
          height: eyeR * 1.8,
        );
        canvas.drawArc(r, math.pi, math.pi, false, stroke);
      }
    } else {
      // A slow blink near the end of each cycle.
      final bool blinking = phase > 0.92;
      for (final double dx in [-eyeDx, eyeDx]) {
        if (blinking) {
          canvas.drawLine(
            Offset(dx - eyeR * 0.8, eyeY),
            Offset(dx + eyeR * 0.8, eyeY),
            Paint()
              ..color = Colors.white
              ..strokeWidth = s * 0.024
              ..strokeCap = StrokeCap.round,
          );
        } else {
          canvas.drawCircle(Offset(dx, eyeY), eyeR, white);
          // Pupils drift a hair with the breathe, so the gaze feels alive.
          canvas.drawCircle(
            Offset(dx + breathe * s * 0.006, eyeY + s * 0.006),
            eyeR * 0.52,
            pupil,
          );
        }
      }
    }

    // Smile.
    final Rect mouth = Rect.fromCenter(
      center: Offset(0, s * 0.02),
      width: s * 0.17,
      height: s * 0.11,
    );
    canvas.drawArc(
      mouth,
      math.pi * 0.12,
      math.pi * 0.76,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.026
        ..strokeCap = StrokeCap.round,
    );
  }

  /// A raised hand, clear of the body so it reads as a wave rather than an
  /// ear: a short arm from the shoulder, then a rounded mitten that swings
  /// from the wrist.
  void _paintHand(Canvas canvas, double s, double breathe) {
    final bool waving =
        mood == WellaMood.waving || mood == WellaMood.celebrating;
    final double swing = waving
        ? math.sin(phase * 4 * math.pi) * 0.30
        : 0.05 * breathe;

    final Paint limb = Paint()
      ..color = _purple
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round;

    canvas.save();
    // Pivot at the shoulder, just outside the body edge.
    canvas.translate(s * 0.26, -s * 0.20);
    canvas.rotate(swing);

    // Arm.
    canvas.drawLine(Offset.zero, Offset(s * 0.13, -s * 0.10), limb);

    // Mitten: palm plus a thumb, filled and lightly outlined so it stays
    // legible against the body at small sizes.
    final Offset palm = Offset(s * 0.16, -s * 0.13);
    canvas.drawCircle(palm, s * 0.055, Paint()..color = _purple);
    canvas.drawCircle(
      palm.translate(-s * 0.045, s * 0.018),
      s * 0.026,
      Paint()..color = _purple,
    );
    canvas.drawCircle(
      palm,
      s * 0.055,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.010,
    );
    canvas.restore();
  }

  void _paintSparkles(Canvas canvas, double s) {
    final Paint spark = Paint()..color = const Color(0xFFFFC857);
    for (final (double dx, double dy, double scale) in [
      (-s * 0.34, -s * 0.30, 1.0),
      (s * 0.36, -s * 0.22, 0.72),
      (s * 0.20, s * 0.34, 0.56),
    ]) {
      final double r =
          s * 0.035 * scale * (0.7 + 0.3 * math.sin(phase * 2 * math.pi));
      final Path star = Path()
        ..moveTo(dx, dy - r)
        ..quadraticBezierTo(dx, dy, dx + r, dy)
        ..quadraticBezierTo(dx, dy, dx, dy + r)
        ..quadraticBezierTo(dx, dy, dx - r, dy)
        ..quadraticBezierTo(dx, dy, dx, dy - r)
        ..close();
      canvas.drawPath(star, spark);
    }
  }

  @override
  bool shouldRepaint(_WellaPainter old) =>
      old.phase != phase || old.mood != mood;
}
