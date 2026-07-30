import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home/home_screen.dart';

/// Single-screen onboarding.
///
/// Was a 4-page `PageView` walking through assess / understand / choose. With
/// the home screen now offering the three services directly, that walkthrough
/// described a flow the user can simply see, so it stood between them and the
/// app for no benefit. Reduced to one screen, and skippable.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Persisted flag — once true, the splash skips straight to [HomeScreen].
  static const String onboardingSeenKey = 'onboarding_seen';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const Color _primary = Color(0xFF6B4EFF);

  /// Both "Skip" and "Get started" mark onboarding seen. Skipping is a
  /// deliberate choice, not an interruption — re-showing this screen on the
  /// next launch would ignore it.
  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen.onboardingSeenKey, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B6B7B),
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Welcome to wellapath',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'A '),
                    TextSpan(
                      text: 'Clinical Support',
                      style: TextStyle(color: _primary),
                    ),
                    TextSpan(text: ' System For You'),
                  ],
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'WellaPath helps you assess symptoms, find clinics, and '
                'access emergency care — even offline.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.55,
                  color: Colors.black54,
                ),
              ),
              Expanded(
                child: Center(
                  child: Image.asset(
                    'assets/images/onboarding_welcome.png',
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _finish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Get started',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
