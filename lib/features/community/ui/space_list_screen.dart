import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import '../domain/space.dart';
import 'community_scope.dart';
import 'community_widgets.dart';
import 'notification_centre_screen.dart';
import 'space_feed_screen.dart';

/// The Community home: exactly the two approved spaces.
class SpaceListScreen extends StatefulWidget {
  const SpaceListScreen({super.key});

  @override
  State<SpaceListScreen> createState() => _SpaceListScreenState();
}

class _SpaceListScreenState extends State<SpaceListScreen> {
  late Future<List<Space>> _spaces;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _spaces = CommunityScope.of(context).services.community.listSpaces();
  }

  @override
  Widget build(BuildContext context) {
    return CommunityScreenFrame(
      title: 'Community',
      actions: [
        IconButton(
          key: const Key('open_notifications'),
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none_rounded),
          onPressed: () => pushCommunityRoute<void>(
            context,
            (BuildContext _) => const NotificationCentreScreen(),
          ),
        ),
      ],
      body: FutureBuilder<List<Space>>(
        future: _spaces,
        builder: (BuildContext context, AsyncSnapshot<List<Space>> snap) {
          if (snap.hasError) {
            CommunityScope.handleError(context, snap.error!);
            return const Center(child: Text('Community could not load.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          // Only the two approved ids can exist: SpaceId has exactly two
          // values and Space.fromJson rejects anything else.
          final List<Space> spaces = snap.data!;
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: Brand.gutter),
            itemCount: spaces.length,
            separatorBuilder: (BuildContext _, int _) =>
                const SizedBox(height: Brand.space3),
            itemBuilder: (BuildContext context, int i) {
              final Space space = spaces[i];
              return Material(
                color: Brand.surfaceMuted,
                borderRadius: BorderRadius.circular(Brand.radiusSurface),
                child: ListTile(
                  key: Key('space_${space.id.wire}'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Brand.space4,
                    vertical: Brand.space2,
                  ),
                  title: Text(space.name, style: Brand.cardTitle),
                  subtitle: Text(space.description),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => pushCommunityRoute<void>(
                    context,
                    (BuildContext _) => SpaceFeedScreen(space: space),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
