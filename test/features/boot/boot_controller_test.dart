import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wellapath_mobile/core/config/config_service.dart';
import 'package:wellapath_mobile/core/storage/storage_service.dart';
import 'package:wellapath_mobile/features/boot/boot_controller.dart';

Response<dynamic> _okResponse(Map<String, dynamic> data) => Response(
  requestOptions: RequestOptions(path: '/config'),
  statusCode: 200,
  data: data,
);

// A ConfigService whose requestOverride always fails, with tiny backoff
// durations so these tests run fast while still exercising the real
// retry-then-give-up path used in production.
ConfigService _alwaysFailingConfigService() => ConfigService(
  backoffDurations: const [
    Duration(milliseconds: 1),
    Duration(milliseconds: 1),
    Duration(milliseconds: 1),
  ],
  requestOverride: () async => throw Exception('simulated network failure'),
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('boot_controller_test_');
    Hive.init(tempDir.path);
    // Open the same box StorageService reads/writes directly, rather than
    // going through StorageService.init() — that calls Hive.initFlutter(),
    // which needs a real platform channel (path_provider) unavailable in a
    // plain unit test.
    await Hive.openBox('config_cache');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'boot() returns BootStatus.failed when /config exhausts retries and no cached config exists '
    '— this is what triggers the first-launch-offline screen',
    () async {
      final controller = BootController(
        configService: _alwaysFailingConfigService(),
      );

      final result = await controller.boot();

      expect(result.status, equals(BootStatus.failed));
      expect(result.config, isNull);
      expect(result.errorMessage, isNotNull);
    },
  );

  test(
    'boot() returns BootStatus.offline with the cached config when /config exhausts retries '
    'but a cached config exists — used silently, no change from current offline fallback behaviour',
    () async {
      const cachedConfig = {
        'version': '1.0',
        'artifacts': {'knowledge_base': {}},
      };
      await StorageService.saveConfig(cachedConfig);

      final controller = BootController(
        configService: _alwaysFailingConfigService(),
      );

      final result = await controller.boot();

      expect(result.status, equals(BootStatus.offline));
      expect(result.config!['version'], equals('1.0'));
    },
  );

  test('boot() returns BootStatus.success and does not touch the cache path '
      'when /config succeeds (even if it took a couple of retries)', () async {
    var callCount = 0;
    final configService = ConfigService(
      backoffDurations: const [
        Duration(milliseconds: 1),
        Duration(milliseconds: 1),
        Duration(milliseconds: 1),
      ],
      requestOverride: () async {
        callCount++;
        if (callCount < 2) throw Exception('transient failure');
        return _okResponse({
          'version': '3.0',
          'artifacts': <String, dynamic>{},
        });
      },
    );

    final controller = BootController(configService: configService);
    final result = await controller.boot();

    expect(result.status, equals(BootStatus.success));
    expect(result.config!['version'], equals('3.0'));
    expect(StorageService.getLastKnownConfig()!['version'], equals('3.0'));
  });
}
