import 'package:flutter/material.dart';

/// Shown whenever a first-launch (no cached data available) network
/// operation exhausts all its retries — used both when the assessment's
/// artifact download fails outright (loading_screen.dart) and when the
/// boot-time `/config` fetch fails outright with no cached config to fall
/// back on (splash_screen.dart).
class FirstLaunchOfflineScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const FirstLaunchOfflineScreen({
    super.key,
    required this.message,
    required this.onRetry,
  });

  static const Color _primary = Color(0xFF6B4EFF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 64, color: _primary),
                const SizedBox(height: 20),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Try again',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
