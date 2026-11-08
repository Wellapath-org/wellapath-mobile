import 'package:flutter/foundation.dart';

import 'community_json.dart';

/// The only two Community spaces (§1 conventions, §13 `SpaceId`). Seeded by
/// migration; no endpoint creates, renames or deletes one.
enum SpaceId {
  generalHealth,
  pregnancyMaternal;

  String get wire => snakeCase(name);
}

@immutable
class Space {
  const Space({
    required this.id,
    required this.name,
    required this.description,
  });

  factory Space.fromJson(Map<String, dynamic> json) {
    return Space(
      id: readEnum(json, 'id', SpaceId.values, (SpaceId s) => s.wire),
      name: readString(json, 'name'),
      description: readString(json, 'description'),
    );
  }

  /// Parses `GET /v1/community/spaces` (`{ "items": [Space] }`, no cursor).
  /// A space id the client does not know is ignored (§8.1, §13).
  static List<Space> listFromJson(Map<String, dynamic> json) {
    final List<Space> out = <Space>[];
    for (final Object? raw in readList(json, 'items')) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('space is not an object');
      }
      final String id = readString(raw, 'id');
      if (enumFromWire(id, SpaceId.values, (SpaceId s) => s.wire) == null) {
        continue;
      }
      out.add(Space.fromJson(raw));
    }
    return out;
  }

  final SpaceId id;
  final String name;
  final String description;

  /// The seeded spaces, in display order, used by the in-memory backend.
  /// Names follow the canonical seed (§8.1, §15 row 29).
  static const List<Space> approved = [
    Space(
      id: SpaceId.generalHealth,
      name: 'General Health',
      // CLINICAL REVIEW REQUIRED: space description is clinical-review copy
      // (§8.1); the server's seeded text is what members see in production.
      description: 'Everyday health questions and shared experiences.',
    ),
    Space(
      id: SpaceId.pregnancyMaternal,
      name: 'Pregnancy and Maternal Health',
      // CLINICAL REVIEW REQUIRED: as above.
      description: 'Pregnancy, birth and caring for yourself afterwards.',
    ),
  ];

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id.wire,
      'name': name,
      'description': description,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is Space &&
        other.id == id &&
        other.name == name &&
        other.description == description;
  }

  @override
  int get hashCode => Object.hash(id, name, description);
}
