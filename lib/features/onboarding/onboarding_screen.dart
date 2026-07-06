import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home/home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Persisted flag — once true, the splash skips straight to [HomeScreen].
  static const String onboardingSeenKey = 'onboarding_seen';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const Color _primary = Color(0xFF6B4EFF);
  static const int _pageCount = 4;

  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

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
    final bool onPurpleBg = _currentPage != 0;
    return Scaffold(
      backgroundColor: onPurpleBg ? _primary : Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _currentPage = i),
              children: [
                _buildWelcomePage(),
                _buildIllustrationPage(
                  image: 'assets/images/onboarding_check.png',
                  title: 'Check your symptoms',
                  subtitle:
                      'Take a few moment to complete your symptoms assessment.',
                ),
                _buildIllustrationPage(
                  image: 'assets/images/onboarding_understand.png',
                  title: 'Understand your symptoms',
                  subtitle:
                      'We show your urgency level and explain what may be behind '
                      'your symptoms, so you know exactly what to do next.',
                ),
                _buildIllustrationPage(
                  image: 'assets/images/onboarding_choose.png',
                  title: 'You choose what to do next',
                  subtitle:
                      'We provide you multiple options on the next action to take.',
                ),
              ],
            ),
            Positioned(top: 16, left: 0, right: 0, child: _buildDots()),
          ],
        ),
      ),
    );
  }

  Widget _buildDots() {
    final bool onPurpleBg = _currentPage != 0;
    final Color active = onPurpleBg ? Colors.white : _primary;
    final Color inactive = onPurpleBg
        ? Colors.white38
        : const Color(0xFFD9D9D9);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(_pageCount, (i) {
        final bool isActive = i == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: isActive ? 22 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? active : inactive,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildWelcomePage() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            'A quick and reliable guidance support system for your health '
            'concerns.',
            style: TextStyle(fontSize: 15, height: 1.5, color: Colors.black54),
          ),
          const SizedBox(height: 24),
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
          _buildContinueButton(onPurpleBg: false),
        ],
      ),
    );
  }

  Widget _buildIllustrationPage({
    required String image,
    required String title,
    required String subtitle,
  }) {
    return Container(
      color: _primary,
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      child: Column(
        children: [
          Expanded(child: Center(child: Image.asset(image))),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 32),
          _buildContinueButton(onPurpleBg: true),
        ],
      ),
    );
  }

  Widget _buildContinueButton({required bool onPurpleBg}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _next,
        style: ElevatedButton.styleFrom(
          backgroundColor: onPurpleBg ? Colors.white : _primary,
          foregroundColor: onPurpleBg ? _primary : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'Continue',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
