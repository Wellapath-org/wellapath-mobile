/// Cursor pagination (contract §1.1).
library;

import 'community_json.dart';

/// One page of a cursor-paginated list: `{ items, next_cursor }`.
///
/// The cursor is opaque: the client never builds, parses or edits one.
class CommunityPage<T> {
  const CommunityPage({required this.items, this.nextCursor});

  /// Strict parse. [item] parses one element; returning null **skips** it,
  /// which is how unknown response enum values the contract says to skip
  /// (e.g. an unknown notification `type`, §13) are tolerated.
  factory CommunityPage.fromJson(
    Map<String, dynamic> json,
    T? Function(Map<String, dynamic>) item,
  ) {
    final List<T> items = <T>[];
    for (final Object? raw in readList(json, 'items')) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('page item is not an object');
      }
      final T? parsed = item(raw);
      if (parsed != null) items.add(parsed);
    }
    return CommunityPage<T>(
      items: items,
      nextCursor: readNullableString(json, 'next_cursor'),
    );
  }

  final List<T> items;

  /// `null` means the end of the list.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// `GET /v1/community/notifications` adds `unread_count` (§11 N1).
class NotificationPage<T> extends CommunityPage<T> {
  const NotificationPage({
    required super.items,
    required this.unreadCount,
    super.nextCursor,
  });

  final int unreadCount;
}

abstract final class CommunityPaging {
  static const int defaultLimit = 20;
  static const int maxLimit = 50;

  /// Validates a page size before it is sent (server: 400 otherwise).
  static int checkLimit(int limit) {
    if (limit < 1 || limit > maxLimit) {
      throw ArgumentError.value(limit, 'limit', 'must be 1..$maxLimit');
    }
    return limit;
  }
}
