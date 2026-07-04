import 'package:flutter/material.dart';
import '../../core/engine/models/engine_output.dart';

class ResultsScreen extends StatelessWidget {
  final EngineOutput engineOutput;

  const ResultsScreen({super.key, required this.engineOutput});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(child: Text('Results Screen — Coming in E4.4')),
      ),
    );
  }
}
