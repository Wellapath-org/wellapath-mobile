import 'package:flutter/material.dart';

import '../data/community_repositories.dart';
import '../data/in_memory_community_backend.dart';
import '../gate/community_gate.dart';

/// The repositories a Community session uses.
class CommunityServices {
  const CommunityServices({
    required this.community,
    required this.notifications,
  });

  /// Internal scaffold only: an in-memory backend with one local account.
  /// Nothing is persisted or sent anywhere.
  factory CommunityServices.inMemoryDemo() {
    final InMemoryCommunityBackend backend = InMemoryCommunityBackend();
    const String me = 'local_internal_tester';
    backend.registerAccount(me, displayName: 'InternalTester');
    return CommunityServices(
      community: backend.memberView(me),
      notifications: backend.notificationsFor(me),
    );
  }

  final CommunityRepository community;
  final NotificationRepository notifications;
}

/// Everything the More tab needs to offer Community: the gate, and how to
/// build the services once the gate opens.
class CommunityModule {
  const CommunityModule({required this.gate, required this.createServices});

  factory CommunityModule.fromEnvironment() {
    return CommunityModule(
      gate: CommunityGate.fromEnvironment(),
      createServices: CommunityServices.inMemoryDemo,
    );
  }

  final CommunityGate gate;
  final CommunityServices Function() createServices;
}

class CommunityScope extends InheritedWidget {
  const CommunityScope({
    super.key,
    required this.gate,
    required this.services,
    required super.child,
  });

  final CommunityGate gate;
  final CommunityServices services;

  static CommunityScope of(BuildContext context) {
    final CommunityScope? scope = context
        .dependOnInheritedWidgetOfExactType<CommunityScope>();
    assert(scope != null, 'CommunityScope missing above a Community screen');
    return scope!;
  }

  /// Kill switch: drop the cached allow and leave Community entirely.
  static void close(BuildContext context) {
    of(context).gate.invalidate();
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
  }

  /// Routes a repository error: a kill-switch code closes Community, anything
  /// else returns false so the caller can show its own message.
  ///
  /// Safe to call from `build`: navigation is deferred to after the frame.
  static bool handleError(BuildContext context, Object error) {
    if (error is CommunityException && error.isKillSwitch) {
      of(context).gate.invalidate();
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (context.mounted) close(context);
      });
      return true;
    }
    return false;
  }

  @override
  bool updateShouldNotify(CommunityScope oldWidget) {
    return gate != oldWidget.gate || services != oldWidget.services;
  }
}

/// Pushes a Community route that keeps the scope above it.
Future<T?> pushCommunityRoute<T>(BuildContext context, WidgetBuilder builder) {
  final CommunityScope scope = CommunityScope.of(context);
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      builder: (BuildContext _) => CommunityScope(
        gate: scope.gate,
        services: scope.services,
        child: Builder(builder: builder),
      ),
    ),
  );
}
