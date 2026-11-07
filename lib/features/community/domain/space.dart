import 'package:flutter/foundation.dart';

import 'community_json.dart';

/// The only two Community spaces in the approved internal MVP. There is no
/// way to create another one, client or server.
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

  final SpaceId id;
  final String name;
  final String description;

  /// The approved spaces, in display order. Exactly two.
  static const List<Space> approved = [
    Space(
      id: SpaceId.generalHealth,
      name: 'General Health',
      description: 'Everyday health questions and shared experiences.',
    ),
    Space(
      id: SpaceId.pregnancyMaternal,
      name: 'Pregnancy / Maternal Health',
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
