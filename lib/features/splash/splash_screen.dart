import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    await Future.wait<void>([
      BootController().boot().then((_) {}),
      Future<void>.delayed(const Duration(seconds: 2)),
    ]);

    // Routing depends on whether onboarding has been seen, not boot status —
    // the app supports offline mode and the assessment flow reads cached config.
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
