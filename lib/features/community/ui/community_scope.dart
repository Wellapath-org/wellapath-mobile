import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/community_auth_api.dart';
import '../data/community_auth_service.dart';
import '../data/community_http_client.dart';
import '../data/community_repositories.dart';
import '../data/community_secure_store.dart';
import '../data/community_session_manager.dart';
import '../data/http_community_repository.dart';
import '../data/in_memory_community_backend.dart';
import '../domain/community_me.dart';
import '../gate/community_features.dart';
import '../gate/community_gate.dart';

/// Which content repositories a build uses. The gate, sign-in and the
/// server flag are identical for both; only where posts live differs.
///
/// `--dart-define=COMMUNITY_DATA_SOURCE=in_memory` keeps content on the
/// device (local development). Anything else means the HTTP API.
const String kCommunityDataSource = String.fromEnvironment(
  'COMMUNITY_DATA_SOURCE',
  defaultValue: 'http',
);

/// The repositories a Community session uses.
class CommunityServices {
  CommunityServices({
    required this.community,
    required this.notifications,
    required this.dataRights,
  });

  /// The real API.
  factory CommunityServices.http(CommunityHttpClient client) {
    final HttpCommunityRepository repo = HttpCommunityRepository(client);
    return CommunityServices(
      community: repo,
      notifications: repo,
      dataRights: repo,
    );
  }

  /// Local development only: an in-memory backend with one local account.
  /// Nothing is persisted or sent anywhere.
  factory CommunityServices.inMemoryDemo() {
    final InMemoryCommunityBackend backend = InMemoryCommunityBackend();
    const String me = 'local_internal_tester';
    backend.registerAccount(me, displayName: 'InternalTester');
    return CommunityServices(
      community: backend.memberView(me),
      notifications: backend.notificationsFor(me),
      dataRights: backend.dataRightsFor(me),
    );
  }

  final CommunityRepository community;
  final NotificationRepository notifications;
  final DataRightsRepository dataRights;

  /// The latest `Me` (M1), loaded when Community opens. Screens use it only
  /// to decide what to *offer* (e.g. hide compose for a restricted
  /// account); the server enforces every rule.
  final ValueNotifier<CommunityMe?> viewer = ValueNotifier<CommunityMe?>(null);

  Future<CommunityMe> refreshViewer() async {
    final CommunityMe me = await community.getMe();
    viewer.value = me;
    return me;
  }
}

/// Everything the More tab needs to offer Community: the gate, sign-in, and
/// how to build the services once the gate opens.
class CommunityModule {
  const CommunityModule({
    required this.gate,
    required this.auth,
    required this.createServices,
  });

  /// Production wiring. Unless the compile flag is on **and**
  /// `COMMUNITY_API_BASE_URL` is set, nothing is constructed: no client, no
  /// secure-storage access, no request.
  factory CommunityModule.fromEnvironment() {
    if (!kCommunityScaffoldEnabled || kCommunityApiBaseUrl.isEmpty) {
      return CommunityModule(
        gate: CommunityGate.fromEnvironment(),
        auth: DisabledCommunityAuthService(),
        createServices: () => throw StateError('Community is not configured'),
      );
    }
    final CommunityHttpClient raw = CommunityHttpClient.forBaseUrl(
      kCommunityApiBaseUrl,
    );
    final CommunitySessionManager session = CommunitySessionManager(
      api: CommunityAuthApi(raw),
      store: FlutterCommunitySecureStore(),
      deviceLabel: _deviceLabel(),
    );
    final CommunityHttpClient authed = raw.withTokens(session);
    final CommunityAuthService auth = SessionCommunityAuthService(
      session,
      CommunityDeviceSessionsApi(authed),
    );
    return CommunityModule(
      gate: CommunityGate.fromEnvironment(
        source: RemoteCommunityFeatureSource(authed),
        isSignedIn: auth.hasSession,
      ),
      auth: auth,
      createServices: kCommunityDataSource == 'in_memory'
          ? CommunityServices.inMemoryDemo
          : () => CommunityServices.http(authed),
    );
  }

  final CommunityGate gate;
  final CommunityAuthService auth;
  final CommunityServices Function() createServices;
}

/// A generic label for the session list (A5); never a device name or model.
String _deviceLabel() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'WellaPath app on Android';
    case TargetPlatform.iOS:
      return 'WellaPath app on iOS';
    default:
      return 'WellaPath app';
  }
}

class CommunityScope extends InheritedWidget {
  const CommunityScope({
    super.key,
    required this.gate,
    required this.services,
    required this.auth,
    required super.child,
  });

  final CommunityGate gate;
  final CommunityServices services;
  final CommunityAuthService auth;

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

  /// Routes a repository error: a kill-switch code, or a session that has
  /// ended (401 `unauthenticated`), closes Community; anything else returns
  /// false so the caller can show its own message.
  ///
  /// Safe to call from `build`: navigation is deferred to after the frame.
  static bool handleError(BuildContext context, Object error) {
    if (error is CommunityException &&
        (error.isKillSwitch || error.requiresSignIn)) {
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
    return gate != oldWidget.gate ||
        services != oldWidget.services ||
        auth != oldWidget.auth;
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
        auth: scope.auth,
        child: Builder(builder: builder),
      ),
    ),
  );
}

/// Shared user-facing wording for errors the contract defines.
String communityErrorText(Object error, {required String fallback}) {
  if (error is CommunityException) {
    switch (error.code) {
      case CommunityErrorCode.rateLimited:
        final int? s = error.retryAfter?.inSeconds;
        return s == null
            ? 'Too many attempts. Please wait and try again.'
            : 'Too many attempts. Please try again in ${_wait(s)}.';
      case CommunityErrorCode.accountRestricted:
        return 'Your account is read-only for now. You can still read and '
            'report posts.';
      case CommunityErrorCode.communityUnavailable:
        return 'Community is unavailable right now. Please try later.';
      case CommunityErrorCode.notFound:
        return 'This is no longer available.';
      default:
        return fallback;
    }
  }
  if (error is CommunityNetworkException) {
    return 'No connection. Check your internet and try again.';
  }
  return fallback;
}

String _wait(int seconds) {
  if (seconds < 60) return '$seconds seconds';
  final int minutes = (seconds / 60).ceil();
  return minutes == 1 ? '1 minute' : '$minutes minutes';
}
