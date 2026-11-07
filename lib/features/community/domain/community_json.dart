/// Strict JSON readers shared by the Community domain models.
///
/// Every reader throws [FormatException] on a missing or mistyped field, so a
/// malformed server payload fails loudly instead of rendering half a post.
/// Unknown *extra* fields are ignored (contract change process rule 3),
/// except the forbidden identity keys, which are rejected.
///
/// Canonical contract: `WELLAPATH_ENGINEERING/COMMUNITY_API_CONTRACT.md`
/// v1.0-draft (mobile copy of the OpenAPI file:
/// `docs/community/community_api_v1.openapi.yaml`).
library;

/// Keys that would identify an account. They must never appear **anywhere**
/// in a member-facing payload (contract §0.2 rule 2, §8.1, §15 row 64).
///
/// Not applied to the self DTOs (`Me`, `TokenPair`, the export), which carry
/// the caller's own `account_id` and `email` by design (§7.1).
const Set<String> kForbiddenMemberIdentityKeys = {
  'author_id',
  'author_account_id',
  'account_id',
  'user_id',
  'accountable_identity',
  'author_email',
  'email',
  'reporter_id',
};

/// Thrown when a member-facing payload carries an account identifier.
class IdentityLeakException extends FormatException {
  const IdentityLeakException(String path)
    : super('member payload must not carry an account identifier: $path');
}

/// Rejects [json] if any key at any depth is in
/// [kForbiddenMemberIdentityKeys].
void rejectIdentityKeys(Object? json, [String path = '']) {
  if (json is Map) {
    for (final MapEntry<dynamic, dynamic> e in json.entries) {
      final String key = '${e.key}';
      final String here = path.isEmpty ? key : '$path.$key';
      if (kForbiddenMemberIdentityKeys.contains(key)) {
        throw IdentityLeakException(here);
      }
      rejectIdentityKeys(e.value, here);
    }
  } else if (json is List) {
    for (int i = 0; i < json.length; i++) {
      rejectIdentityKeys(json[i], '$path[$i]');
    }
  }
}

/// Requires [key] to be present (its value may still be null).
void requireKey(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) throw FormatException('missing "$key"');
}

String readString(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is String) return value;
  throw FormatException('expected string at "$key"');
}

/// A field that may be null or absent.
String? readOptionalString(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('expected string or null at "$key"');
}

/// A field the contract lists as required whose value may be null.
String? readNullableString(Map<String, dynamic> json, String key) {
  requireKey(json, key);
  return readOptionalString(json, key);
}

bool readBool(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is bool) return value;
  throw FormatException('expected bool at "$key"');
}

int readInt(Map<String, dynamic> json, String key, {int? min}) {
  final Object? value = json[key];
  if (value is int && (min == null || value >= min)) return value;
  throw FormatException('expected int at "$key"');
}

DateTime readTime(Map<String, dynamic> json, String key) {
  final DateTime? value = readOptionalTime(json, key);
  if (value == null) throw FormatException('expected timestamp at "$key"');
  return value;
}

DateTime? readOptionalTime(Map<String, dynamic> json, String key) {
  final String? raw = readOptionalString(json, key);
  if (raw == null) return null;
  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('bad timestamp at "$key"');
  return parsed.toUtc();
}

/// A required key whose value may be a null timestamp.
DateTime? readNullableTime(Map<String, dynamic> json, String key) {
  requireKey(json, key);
  return readOptionalTime(json, key);
}

Map<String, dynamic> readObject(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is Map<String, dynamic>) return value;
  throw FormatException('expected object at "$key"');
}

/// A required key whose value is an object or null.
Map<String, dynamic>? readNullableObject(
  Map<String, dynamic> json,
  String key,
) {
  requireKey(json, key);
  final Object? value = json[key];
  if (value == null || value is Map<String, dynamic>) {
    return value as Map<String, dynamic>?;
  }
  throw FormatException('expected object or null at "$key"');
}

List<Object?> readList(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is List) return value;
  throw FormatException('expected array at "$key"');
}

/// Looks up the enum value whose wire name is [raw], or throws.
T readEnum<T extends Enum>(
  Map<String, dynamic> json,
  String key,
  List<T> values,
  String Function(T) wire,
) {
  final String raw = readString(json, key);
  final T? found = enumFromWire(raw, values, wire);
  if (found == null) throw FormatException('unknown value "$raw" at "$key"');
  return found;
}

/// The enum value whose wire name is [raw], or null.
T? enumFromWire<T extends Enum>(
  String? raw,
  List<T> values,
  String Function(T) wire,
) {
  for (final T value in values) {
    if (wire(value) == raw) return value;
  }
  return null;
}

/// Converts a Dart camelCase enum name into its snake_case wire form.
String snakeCase(String camel) {
  return camel.replaceAllMapped(
    RegExp('[A-Z]'),
    (Match m) => '_${m.group(0)!.toLowerCase()}',
  );
}

/// RFC 3339 UTC with a `Z` suffix and millisecond precision.
String wireTime(DateTime t) => t.toUtc().toIso8601String();
