import 'package:flutter/foundation.dart';

import 'community_json.dart';
import 'professional_verification.dart';

/// How an author chose to appear on one post or comment.
enum DisplayMode {
  named,
  pseudonymous;

  String get wire => name;
}

/// Status of a post or comment.
enum ContentStatus {
  visible,
  hidden,
  removed,
  deletedByAuthor;

  String get wire => snakeCase(name);
}

/// The author as other members see them. Deliberately has **no account id
/// field** — the accountable identity is a moderator-only DTO
/// (`AccountableIdentity`), reached only through an audited reveal.
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
    final String? name = readOptionalString(json, 'display_name');
    final Object? rawBadge = json['badge'];
    if (rawBadge != null && rawBadge is! Map<String, dynamic>) {
      throw const FormatException('expected object or null at "badge"');
    }
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
      badge: rawBadge == null
          ? null
          : ProfessionalBadge.fromJson(rawBadge as Map<String, dynamic>),
    );
  }

  final DisplayMode displayMode;
  final String? displayName;
  final ProfessionalBadge? badge;

  /// What the UI prints for this author.
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
