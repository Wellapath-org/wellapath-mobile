import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import '../data/community_repositories.dart';
import '../domain/community_notification.dart';
import 'community_scope.dart';
import 'community_widgets.dart';
import 'post_detail_screen.dart';

/// In-app notification centre (polling; no push).
class NotificationCentreScreen extends StatefulWidget {
  const NotificationCentreScreen({super.key});

  @override
  State<NotificationCentreScreen> createState() =>
      _NotificationCentreScreenState();
}

class _NotificationCentreScreenState extends State<NotificationCentreScreen> {
  Future<CommunityPage<CommunityNotification>>? _page;

  NotificationRepository get _repo =>
      CommunityScope.of(context).services.notifications;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _page ??= _repo.list();
  }

  void _reload() {
    setState(() {
      _page = _repo.list();
    });
  }

  Future<void> _open(CommunityNotification n) async {
    await _repo.markRead(n.id);
    if (!mounted) return;
    final String? postId = n.postId;
    if (postId != null) {
      await pushCommunityRoute<void>(
        context,
        (BuildContext _) => PostDetailScreen(postId: postId),
      );
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return CommunityScreenFrame(
      title: 'Notifications',
      actions: [
        TextButton(
          key: const Key('mark_all_read'),
          onPressed: () async {
            await _repo.markAllRead();
            if (mounted) _reload();
          },
          child: const Text('Mark all read'),
        ),
      ],
      body: FutureBuilder<CommunityPage<CommunityNotification>>(
        future: _page,
        builder:
            (
              BuildContext context,
              AsyncSnapshot<CommunityPage<CommunityNotification>> snap,
            ) {
              if (snap.hasError) {
                CommunityScope.handleError(context, snap.error!);
                return const Center(child: Text('Could not load.'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final List<CommunityNotification> items = snap.data!.items;
              if (items.isEmpty) {
                return const Center(child: Text('No notifications yet.'));
              }
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (BuildContext context, int i) {
                  final CommunityNotification n = items[i];
                  return ListTile(
                    key: Key('notification_${n.id}'),
                    leading: Icon(
                      n.isRead
                          ? Icons.notifications_none_rounded
                          : Icons.notifications_active_outlined,
                      color: n.isRead ? Brand.inkSoft : Brand.primary,
                    ),
                    title: Text(
                      n.summary,
                      style: TextStyle(
                        fontWeight: n.isRead
                            ? FontWeight.w400
                            : FontWeight.w700,
                        color: Brand.ink,
                      ),
                    ),
                    subtitle: Text(formatCommunityTime(n.createdAt)),
                    onTap: () => _open(n),
                  );
                },
              );
            },
      ),
    );
  }
}
