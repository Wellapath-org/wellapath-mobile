import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/widgets/first_launch_offline_screen.dart';
import '../boot/boot_controller.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.bootController, this.minimumSplash});

  /// Injectable for tests. Production passes nothing and gets the real one.
  final BootController? bootController;

  /// Overridable for tests so the suite does not sit through the real
  /// minimum-display delay.
  final Duration? minimumSplash;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const Color _primary = Color(0xFF6B4EFF);

  /// Minimum time the splash stays up, so a fast boot does not flash past.
  static const Duration defaultMinimumSplash = Duration(seconds: 2);

  /// How long to wait before admitting the first attempt did not land.
  ///
  /// Below this the status line would flicker on every fast launch, which is
  /// noise. Above it the user is watching a static logo with no explanation.
  static const Duration _statusRevealDelay = Duration(seconds: 3);

  /// Set on dispose. Read by the boot loop through [_isCancelled] so a retry
  /// in flight stops instead of continuing against a dead widget.
  bool _disposed = false;

  /// Guards against two boot sequences running at once. `_restartBoot` pushes
  /// a fresh SplashScreen, and without this the old screen's loop could still
  /// be retrying while the new one starts — two `/config` races, two possible
  /// navigations.
  bool _bootStarted = false;

  /// Held so it can be cancelled on dispose. An uncancelled timer would call
  /// setState on a defunct State when the screen is left quickly.
  Timer? _statusRevealTimer;

  int _attempt = 0;
  int _maxAttempts = 0;
  bool _showStatus = false;

  @override
  void initState() {
    super.initState();
    _bootAndRoute();
    // Reveal the status line only if boot is still running by then.
    _statusRevealTimer = Timer(_statusRevealDelay, () {
      if (!_disposed && mounted) setState(() => _showStatus = true);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _statusRevealTimer?.cancel();
    super.dispose();
  }

  bool _isCancelled() => _disposed;

  void _onAttempt(int attempt, int maxAttempts) {
    if (_disposed || !mounted) return;
    setState(() {
      _attempt = attempt;
      _maxAttempts = maxAttempts;
    });
  }

  Future<void> _bootAndRoute() async {
    if (_bootStarted) return;
    _bootStarted = true;

    // Run the boot sequence and the minimum splash display together, so the
    // splash is always visible for at least _minimumSplash regardless of how
    // fast boot completes.
    final results = await Future.wait<Object?>([
      (widget.bootController ?? BootController()).boot(
        onAttempt: _onAttempt,
        isCancelled: _isCancelled,
      ),
      Future<void>.delayed(widget.minimumSplash ?? defaultMinimumSplash),
    ]);
    final bootResult = results[0] as BootResult;

    if (_disposed || !mounted) return;

    // A failed boot only happens when /config exhausted its bounded retry
    // policy AND no cached config exists — i.e. this is genuinely the user's
    // first launch with no usable network. Anything else (a fresh config,
    // or a cached one from a previous successful boot) proceeds normally;
    // the app supports offline mode and the assessment flow reads cached
    // config directly.
    if (bootResult.status == BootStatus.failed) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          // The retry must navigate from the offline route's own context.
          // Capturing this State's context instead threw "This widget has
          // been unmounted" the moment the button was pressed: pushReplacement
          // disposes the splash, so by the time anyone could tap Try again the
          // context it closed over was already defunct. The button was dead on
          // the one screen whose entire purpose is recovery.
          builder: (offlineContext) => FirstLaunchOfflineScreen(
            message:
                'WellaPath needs a brief internet connection the first '
                'time. Please check your connection and try again.',
            onRetry: () => _restartBootFrom(offlineContext),
          ),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final seenOnboarding =
        prefs.getBool(OnboardingScreen.onboardingSeenKey) ?? false;

    if (_disposed || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            seenOnboarding ? const HomeScreen() : const OnboardingScreen(),
      ),
    );
  }

  /// The manual path: a fresh SplashScreen replaces the offline screen,
  /// starting a clean boot. [routeContext] belongs to the route doing the
  /// replacing, which is still mounted when the button is pressed.
  static void _restartBootFrom(BuildContext routeContext) {
    Navigator.of(routeContext).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const SplashScreen()),
    );
  }

  /// Honest, specific, and only shown once the wait is real.
  String get _statusLabel {
    if (_attempt <= 1) return 'Connecting…';
    if (_maxAttempts > 0 && _attempt >= _maxAttempts) {
      return 'Last attempt…';
    }
    return 'Still connecting — attempt $_attempt of $_maxAttempts';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/brand_logo.png', width: 180),
            const SizedBox(height: 40),
            // Reserved space so revealing the status does not shift the logo.
            SizedBox(
              height: 60,
              child: AnimatedOpacity(
                opacity: _showStatus ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: Column(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white70,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _statusLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
