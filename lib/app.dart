import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/telemetry/contract/telemetry_event.dart';
import 'core/telemetry/telemetry.dart';
import 'features/splash/splash_screen.dart';

class WellaPathApp extends StatefulWidget {
  const WellaPathApp({super.key});

  /// SharedPreferences key recording that the app has been launched once.
  ///
  /// A boolean, not an identifier: it says "this install has run before" and
  /// nothing about who is running it. Deliberately separate from
  /// `onboarding_seen`, which the user can reach a different way.
  static const String launchedBeforeKey = 'wp_launched_before';

  @override
  State<WellaPathApp> createState() => _WellaPathAppState();
}

/// Owns the app lifecycle observer that drives `app_open` and background
/// flushes.
///
/// This is the only structural change telemetry makes to the app shell:
/// `WellaPathApp` becomes stateful so it can observe lifecycle transitions.
/// The widget tree it builds is unchanged.
class _WellaPathAppState extends State<WellaPathApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fire-and-forget: nothing in the app waits on this, and a failure to
    // read preferences must not delay the first frame.
    _captureColdOpen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _captureColdOpen() async {
    bool? isFirstLaunch;
    try {
      final prefs = await SharedPreferences.getInstance();
      isFirstLaunch = !(prefs.getBool(WellaPathApp.launchedBeforeKey) ?? false);
      if (isFirstLaunch) {
        await prefs.setBool(WellaPathApp.launchedBeforeKey, true);
      }
    } catch (_) {
      // `is_first_launch` is optional in the contract. If preferences are
      // unreadable, omit it rather than guessing — a wrong `true` on every
      // launch would corrupt the install-funnel numbers this event exists for.
      isFirstLaunch = null;
    }
    Telemetry.capture(
      AppOpenEvent(launchType: LaunchType.cold, isFirstLaunch: isFirstLaunch),
    );
  }

  /// True once the app has actually been backgrounded.
  ///
  /// Guards against double-counting the launch: a `resumed` callback that
  /// arrives before anything was ever paused is a startup artefact, not a warm
  /// open, and the cold event has already been sent from `initState`.
  bool _hasBeenBackgrounded = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_hasBeenBackgrounded) return;
        // A resume is a warm open. `is_first_launch` is omitted — it is only
        // meaningful for a cold start.
        Telemetry.capture(const AppOpenEvent(launchType: LaunchType.warm));
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _hasBeenBackgrounded = true;
        // Backgrounding is the contract's recommended flush point and is off
        // every clinical path by definition.
        Telemetry.instance.onAppBackgrounded();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WellaPath',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
