/// Where Community keeps its long-lived secrets (ADR-001 §8 A2):
/// the refresh token and the per-install `device_id`, in the platform
/// keystore via `flutter_secure_storage` (Keychain / Android Keystore).
///
/// The access token is **never** written here; it lives in memory only.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CommunitySecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// The keys Community owns. Nothing else is stored.
abstract final class CommunitySecureKeys {
  static const String refreshToken = 'wellapath.community.refresh_token';
  static const String deviceId = 'wellapath.community.device_id';

  static const List<String> all = <String>[refreshToken, deviceId];
}

/// The production store.
class FlutterCommunitySecureStore implements CommunitySecureStore {
  FlutterCommunitySecureStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Readable only while the device is unlocked, never migrated to
            // another device by backup.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// A process-local store for tests and the in-memory dev backend.
class InMemoryCommunitySecureStore implements CommunitySecureStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
