import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import '../domain/community_me.dart';
import '../domain/community_permissions.dart';
import '../domain/space.dart';
import 'account_screen.dart';
import 'community_scope.dart';
import 'community_widgets.dart';
import 'notification_centre_screen.dart';
import 'profile_setup_screen.dart';
import 'space_feed_screen.dart';

class _Home {
  const _Home(this.me, this.spaces);

  final CommunityMe me;
  final List<Space> spaces;
}

/// The Community home: exactly the two seeded spaces.
class SpaceListScreen extends StatefulWidget {
  const SpaceListScreen({super.key});

  @override
  State<SpaceListScreen> createState() => _SpaceListScreenState();
}

class _SpaceListScreenState extends State<SpaceListScreen> {
  Future<_Home>? _home;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _home ??= _load();
  }

  Future<_Home> _load() async {
    final CommunityServices services = CommunityScope.of(context).services;
    final CommunityMe me = await services.refreshViewer();
    final List<Space> spaces = await services.community.listSpaces();
    return _Home(me, spaces);
  }

  /// False once Community has been closed underneath this screen (sign-out,
  /// deletion, kill switch): never reload then.
  bool get _stillShown =>
      mounted && (ModalRoute.of(context)?.isCurrent ?? false);

  void _reload() {
    setState(() {
      _home = _load();
    });
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
        IconButton(
          key: const Key('open_account'),
          tooltip: 'Account',
          icon: const Icon(Icons.person_outline_rounded),
          onPressed: () async {
            await pushCommunityRoute<void>(
              context,
              (BuildContext _) => const CommunityAccountScreen(),
            );
            if (_stillShown) _reload();
          },
        ),
      ],
      body: FutureBuilder<_Home>(
        future: _home,
        builder: (BuildContext context, AsyncSnapshot<_Home> snap) {
          if (snap.hasError) {
            CommunityScope.handleError(context, snap.error!);
            return const Center(child: Text('Community could not load.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final CommunityMe me = snap.data!.me;
          final List<Space> spaces = snap.data!.spaces;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Brand.gutter),
            children: [
              if (me.status == AccountStatus.restricted)
                const Padding(
                  key: Key('restricted_notice'),
                  padding: EdgeInsets.only(bottom: Brand.space3),
                  child: Text(
                    'Your account is read-only for now. You can still read '
                    'and report posts.',
                    style: Brand.caption,
                  ),
                ),
              if (me.profile == null && me.can(CommunityCapability.setProfile))
                Padding(
                  padding: const EdgeInsets.only(bottom: Brand.space3),
                  child: OutlinedButton(
                    key: const Key('setup_profile'),
                    onPressed: () async {
                      await pushCommunityRoute<void>(
                        context,
                        (BuildContext _) => const ProfileSetupScreen(),
                      );
                      if (_stillShown) _reload();
                    },
                    child: const Text('Choose your Community name to post'),
                  ),
                ),
              // Only known ids can appear: SpaceId has exactly two values
              // and Space.listFromJson drops anything else.
              for (final Space space in spaces)
                Padding(
                  padding: const EdgeInsets.only(bottom: Brand.space3),
                  child: Material(
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
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
