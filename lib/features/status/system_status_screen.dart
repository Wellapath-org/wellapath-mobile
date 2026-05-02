import 'package:flutter/material.dart';
import '../boot/boot_controller.dart';

class SystemStatusScreen extends StatelessWidget {
  final BootResult result;

  const SystemStatusScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WellaPath')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusChip(),
            if (result.config?['version'] != null) ...[
              const SizedBox(height: 16),
              Text('Config version: ${result.config!['version']}'),
            ],
            if (result.errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                result.errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip() {
    switch (result.status) {
      case BootStatus.success:
        return const Chip(
          label: Text('Online'),
          backgroundColor: Colors.green,
          labelStyle: TextStyle(color: Colors.white),
        );
      case BootStatus.offline:
        return const Chip(
          label: Text('Offline — using cached config'),
          backgroundColor: Colors.orange,
          labelStyle: TextStyle(color: Colors.white),
        );
      case BootStatus.failed:
        return const Chip(
          label: Text('Failed to load'),
          backgroundColor: Colors.red,
          labelStyle: TextStyle(color: Colors.white),
        );
    }
  }
}
