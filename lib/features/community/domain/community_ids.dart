/// Client-generated identifiers: `Idempotency-Key` values (§1.2) and the
/// per-install `device_id` (§3.3 A2). Both are UUID v4 from a CSPRNG.
library;

import 'dart:math';

final Random _random = Random.secure();

/// A random RFC 4122 version-4 UUID, lowercase and hyphenated.
String newUuidV4() {
  final List<int> b = List<int>.generate(16, (int _) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final String hex = b
      .map((int v) => v.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

bool isUuid(String value) => _uuid.hasMatch(value);
