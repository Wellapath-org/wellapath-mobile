import 'package:flutter/foundation.dart';

import 'community_json.dart';
import 'community_validation.dart';

enum ReportTargetType {
  post,
  comment;

  String get wire => name;
}

enum ReportReason {
  spam,
  harassment,
  misinformation,
  unsafeMedicalAdvice,
  selfHarmOrEmergency,
  personalInformation,
  other;

  String get wire => snakeCase(name);

  /// Neutral label for the report sheet.
  String get label {
    switch (this) {
      case ReportReason.spam:
        return 'Spam or advertising';
      case ReportReason.harassment:
        return 'Harassment or abuse';
      case ReportReason.misinformation:
        return 'False or misleading health information';
      case ReportReason.unsafeMedicalAdvice:
        return 'Unsafe medical advice';
      case ReportReason.selfHarmOrEmergency:
        return 'Someone may be in danger';
      case ReportReason.personalInformation:
        return 'Shares personal information';
      case ReportReason.other:
        return 'Something else';
    }
  }
}

enum ReportStatus {
  open,
  actioned,
  dismissed;

  String get wire => name;
}

/// A report about to be sent. The server records reporter and time.
@immutable
class ReportDraft {
  ReportDraft({
    required this.targetType,
    required String targetId,
    required this.reason,
    String? note,
  }) : targetId = validateBody(targetId, field: 'target_id', max: 128),
       note = validateOptionalNote(note, max: CommunityLimits.reportNoteMax);

  final ReportTargetType targetType;
  final String targetId;
  final ReportReason reason;
  final String? note;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'target_type': targetType.wire,
      'target_id': targetId,
      'reason': reason.wire,
      if (note != null) 'note': note,
    };
  }
}

/// A stored report, as the moderator queue sees it. Carries no identities.
@immutable
class Report {
  const Report({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.note,
    required this.status,
    required this.createdAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    rejectIdentityKeys(json);
    return Report(
      id: readString(json, 'id'),
      targetType: readEnum(
        json,
        'target_type',
        ReportTargetType.values,
        (ReportTargetType t) => t.wire,
      ),
      targetId: readString(json, 'target_id'),
      reason: readEnum(
        json,
        'reason',
        ReportReason.values,
        (ReportReason r) => r.wire,
      ),
      note: readOptionalString(json, 'note'),
      status: readEnum(
        json,
        'status',
        ReportStatus.values,
        (ReportStatus s) => s.wire,
      ),
      createdAt: readTime(json, 'created_at'),
    );
  }

  final String id;
  final ReportTargetType targetType;
  final String targetId;
  final ReportReason reason;
  final String? note;
  final ReportStatus status;
  final DateTime createdAt;

  Report copyWith({ReportStatus? status}) {
    return Report(
      id: id,
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      note: note,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'target_type': targetType.wire,
      'target_id': targetId,
      'reason': reason.wire,
      'note': note,
      'status': status.wire,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is Report &&
        other.id == id &&
        other.targetType == targetType &&
        other.targetId == targetId &&
        other.reason == reason &&
        other.note == note &&
        other.status == status &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, targetType, targetId, reason, note, status, createdAt);
}
