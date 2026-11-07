/// Strict JSON readers shared by the Community domain models.
///
/// Every reader throws [FormatException] on a missing or mistyped field, so a
/// malformed server payload fails loudly instead of rendering half a post.
/// See `docs/community/API_CONTRACT.md`.
library;

/// Keys that would identify an author's account. They must never appear in a
/// member-facing payload (API contract §0 rule 3). A payload carrying any of
/// them is rejected as a contract violation, not silently ignored.
const Set<String> kForbiddenMemberIdentityKeys = {
  'author_account_id',
  'author_id',
  'account_id',
  'user_id',
  'accountable_identity',
};

/// Thrown when a member-facing payload carries an account identifier.
class IdentityLeakException extends FormatException {
  const IdentityLeakException(String key)
    : super('member payload must not carry an account identifier: $key');
}

/// Rejects [json] if it, or its nested `author` object, carries any key in
/// [kForbiddenMemberIdentityKeys].
void rejectIdentityKeys(Map<String, dynamic> json) {
  for (final String key in kForbiddenMemberIdentityKeys) {
    if (json.containsKey(key)) throw IdentityLeakException(key);
  }
  final Object? author = json['author'];
  if (author is Map<String, dynamic>) {
    for (final String key in kForbiddenMemberIdentityKeys) {
      if (author.containsKey(key)) throw IdentityLeakException('author.$key');
    }
  }
}

String readString(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is String) return value;
  throw FormatException('expected string at "$key"');
}

String? readOptionalString(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('expected string or null at "$key"');
}

bool readBool(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is bool) return value;
  throw FormatException('expected bool at "$key"');
}

int readInt(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is int) return value;
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

Map<String, dynamic> readObject(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is Map<String, dynamic>) return value;
  throw FormatException('expected object at "$key"');
}

/// Looks up the enum value whose wire name is [raw], or throws.
T readEnum<T extends Enum>(
  Map<String, dynamic> json,
  String key,
  List<T> values,
  String Function(T) wire,
) {
  final String raw = readString(json, key);
  for (final T value in values) {
    if (wire(value) == raw) return value;
  }
  throw FormatException('unknown value "$raw" at "$key"');
}

/// Converts a Dart camelCase enum name into its snake_case wire form.
String snakeCase(String camel) {
  return camel.replaceAllMapped(
    RegExp('[A-Z]'),
    (Match m) => '_${m.group(0)!.toLowerCase()}',
  );
}
