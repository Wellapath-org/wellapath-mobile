/// Small, purposeful motion helpers.
///
/// Two rules the whole app obeys:
///
///  * **Reduced motion is honoured.** [motionEnabled] reads the platform's
///    "reduce motion" accessibility setting. When it is on, animated widgets
///    render their final state immediately — no fades, no slides, no float.
///  * **Motion never gates content.** Entrances animate opacity and offset
///    only; the widget is laid out, hit-testable and readable by assistive
///    technology from the first frame, so a tap can never be swallowed by a
///    transition and navigation is never delayed.
///
/// Everything here uses Flutter's built-in animation primitives. No animation
/// package is added — the brief asks for delight, not a dependency.
library;

import 'dart:async';

import 'package:flutter/material.dart';

/// False when the user has asked the platform to reduce motion.
bool motionEnabled(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context);

/// Fades and lifts [child] into place once, after [delay].
///
/// Used to let home cards and onboarding lines arrive one after another
/// instead of all at once. With reduced motion the child is simply shown.
class EntranceFade extends StatefulWidget {
  const EntranceFade({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.offset = 12,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Vertical travel in logical pixels. Kept small: a long slide reads as
  /// sluggish on the low-end devices this app targets.
  final double offset;

  @override
  State<EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<EntranceFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  bool _started = false;

  /// Held so it can be cancelled: a pending start that fires after dispose
  /// would outlive the widget (and trips the test binding's timer check).
  Timer? _startTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!motionEnabled(context)) {
      _controller.value = 1;
      return;
    }
    _startTimer = Timer(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - _curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// A tap target that dips very slightly while pressed.
///
/// The feedback is the point: on a budget Android device an InkWell ripple
/// can be the only sign a tap registered, and it is easy to miss. Scale is
/// capped at 2% so nothing appears to jump.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bool animate = motionEnabled(context);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: AnimatedScale(
          scale: animate && _down ? 0.98 : 1,
          duration: const Duration(milliseconds: 90),
          child: widget.child,
        ),
      ),
    );
  }
}
