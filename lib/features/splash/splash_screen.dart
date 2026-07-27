import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/widgets/first_launch_offline_screen.dart';
import '../boot/boot_controller.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const Color _primary = Color(0xFF6B4EFF);

  @override
  void initState() {
    super.initState();
    _bootAndRoute();
  }

  Future<void> _bootAndRoute() async {
    // Run the boot sequence and a minimum 2-second splash display together,
    // so the splash is always visible for at least 2s regardless of boot speed.
    final results = await Future.wait<Object?>([
      BootController().boot(),
      Future<void>.delayed(const Duration(seconds: 2)),
    ]);
    final bootResult = results[0] as BootResult;

    if (!mounted) return;

    // A failed boot only happens when /config exhausted all its retries
    // AND no cached config exists — i.e. this is genuinely the user's
    // first launch with no usable network. Anything else (a fresh config,
    // or a cached one from a previous successful boot) proceeds normally;
    // the app supports offline mode and the assessment flow reads cached
    // config directly.
    if (bootResult.status == BootStatus.failed) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => FirstLaunchOfflineScreen(
            message:
                'WellaPath needs a brief internet connection the first '
                'time. Please check your connection and try again.',
            onRetry: _restartBoot,
          ),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final seenOnboarding =
        prefs.getBool(OnboardingScreen.onboardingSeenKey) ?? false;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            seenOnboarding ? const HomeScreen() : const OnboardingScreen(),
      ),
    );
  }

  void _restartBoot() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const SplashScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _primary,
      body: Center(
        child: Image.asset('assets/images/brand_logo.png', width: 180),
      ),
    );
  }
}
