import 'package:flutter/material.dart';
import 'features/splash/splash_screen.dart';

class WellaPathApp extends StatelessWidget {
  const WellaPathApp({super.key});

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
