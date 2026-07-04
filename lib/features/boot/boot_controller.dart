import '../../core/config/config_service.dart';
import '../../core/storage/storage_service.dart';

enum BootStatus { success, offline, failed }

class BootResult {
  final BootStatus status;
  final Map<String, dynamic>? config;
  final String? errorMessage;

  const BootResult({required this.status, this.config, this.errorMessage});
}

class BootController {
  final ConfigService _configService = ConfigService();

  Future<BootResult> boot() async {
    // Step 1 — Try to fetch fresh config from backend
    final freshConfig = await _configService.fetchConfig();

    if (freshConfig != null) {
      // Step 2 — Save to cache
      await StorageService.saveConfig(freshConfig);
      return BootResult(status: BootStatus.success, config: freshConfig);
    }

    // Step 3 — /config failed, try last known good config
    final cachedConfig = StorageService.getLastKnownConfig();

    if (cachedConfig != null) {
      return BootResult(status: BootStatus.offline, config: cachedConfig);
    }

    // Step 4 — Nothing available
    return const BootResult(
      status: BootStatus.failed,
      errorMessage: 'Unable to load app configuration.',
    );
  }
}
