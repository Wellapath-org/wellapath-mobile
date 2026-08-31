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
  BootController({ConfigService? configService})
    : _configService = configService ?? ConfigService();

  final ConfigService _configService;

  /// Runs the boot sequence.
  ///
  /// [onAttempt] reports `/config` attempt progress so the splash can show a
  /// loading state instead of a frozen logo; [isCancelled] lets a disposed
  /// screen stop the retry loop rather than leaving it running against a
  /// widget that has gone away.
  Future<BootResult> boot({
    void Function(int attempt, int maxAttempts)? onAttempt,
    bool Function()? isCancelled,
  }) async {
    // Step 1 — Try to fetch fresh config from backend
    final freshConfig = await _configService.fetchConfig(
      onAttempt: onAttempt,
      isCancelled: isCancelled,
    );

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
