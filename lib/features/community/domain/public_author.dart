import 'package:flutter/foundation.dart';

import 'community_json.dart';
import 'professional_verification.dart';

/// How an author chose to appear on one post or comment (§13 `DisplayMode`).
/// Required on every create; there is no default. An unknown value rejects
/// the payload.
enum DisplayMode {
  named,
  pseudonymous;

  String get wire => name;
}

/// Content status as the **server** stores it (§13 `ContentStatus`
/// (moderator)). Members only ever receive `visible`; anything else is not
/// visible and comes back as 404 `not_found` (§15 row 14). The non-visible
/// values exist here only for the in-memory test backend.
enum ContentStatus {
  visible,
  hidden,
  removed,
  deletedByAuthor,
  tombstoned;

  String get wire => snakeCase(name);
}

/// The only status a member DTO may carry (`status: const "visible"`).
const String kMemberVisibleStatus = 'visible';

/// The author as other members see them (`PublicAuthor`). Deliberately has
/// **no id field of any kind** (§8.1). Ownership is conveyed only by the
/// server-computed `viewer_is_author` on the post or comment.
@immutable
class PublicAuthor {
  const PublicAuthor._({
    required this.displayMode,
    required this.displayName,
    required this.badge,
  });

  const PublicAuthor.named({required String this.displayName, this.badge})
    : displayMode = DisplayMode.named;

  /// Pseudonymous: no name, no badge, no stable handle.
  const PublicAuthor.pseudonymous()
    : displayMode = DisplayMode.pseudonymous,
      displayName = null,
      badge = null;

  factory PublicAuthor.fromJson(Map<String, dynamic> json) {
    rejectIdentityKeys(json);
    final DisplayMode mode = readEnum(
      json,
      'display_mode',
      DisplayMode.values,
      (DisplayMode m) => m.wire,
    );
    final String? name = readNullableString(json, 'display_name');
    final Map<String, dynamic>? rawBadge = readNullableObject(json, 'badge');
    if (mode == DisplayMode.pseudonymous) {
      if (name != null || rawBadge != null) {
        throw const FormatException(
          'pseudonymous author must not carry a name or badge',
        );
      }
      return const PublicAuthor.pseudonymous();
    }
    if (name == null || name.isEmpty) {
      throw const FormatException('named author requires display_name');
    }
    return PublicAuthor._(
      displayMode: mode,
      displayName: name,
      badge: rawBadge == null ? null : ProfessionalBadge.fromJson(rawBadge),
    );
  }

  final DisplayMode displayMode;
  final String? displayName;
  final ProfessionalBadge? badge;

  /// What the UI prints for this author (§8.1: pseudonymous renders
  /// "Community member").
  String get label => displayName ?? 'Community member';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'display_mode': displayMode.wire,
      'display_name': displayName,
      'badge': badge?.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is PublicAuthor &&
        other.displayMode == displayMode &&
        other.displayName == displayName &&
        other.badge == badge;
  }

  @override
  int get hashCode => Object.hash(displayMode, displayName, badge);
}

/// Rejects a member DTO whose `status` is anything but `visible`.
void requireMemberVisible(Map<String, dynamic> json) {
  if (readString(json, 'status') != kMemberVisibleStatus) {
    throw const FormatException('member payloads are only ever visible');
  }
}
