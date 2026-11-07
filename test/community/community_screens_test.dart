/// Scaffold screens against the in-memory backend: two spaces, safety banner
/// everywhere, text-only compose, single-level comments, report sheet,
/// notification centre, and the kill switch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/community/data/community_repositories.dart';
import 'package:wellapath_mobile/features/community/data/in_memory_community_backend.dart';
import 'package:wellapath_mobile/features/community/domain/comment.dart';
import 'package:wellapath_mobile/features/community/domain/community_permissions.dart';
import 'package:wellapath_mobile/features/community/domain/post.dart';
import 'package:wellapath_mobile/features/community/domain/public_author.dart';
import 'package:wellapath_mobile/features/community/domain/space.dart';
import 'package:wellapath_mobile/features/community/gate/community_features.dart';
import 'package:wellapath_mobile/features/community/gate/community_gate.dart';
import 'package:wellapath_mobile/features/community/ui/community_safety_banner.dart';
import 'package:wellapath_mobile/features/community/ui/community_scope.dart';
import 'package:wellapath_mobile/features/community/ui/space_list_screen.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pump(
  WidgetTester tester,
  CommunityServices services, {
  CommunityGate? gate,
}) async {
  tester.view.physicalSize = const Size(400 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => CommunityScope(
                    gate:
                        gate ??
                        CommunityGate(
                          compileTimeEnabled: true,
                          source: StaticCommunityFeatureSource(
                            const CommunityFeatures(
                              state: CommunityFlagState.internal,
                              allowed: true,
                            ),
                          ),
                        ),
                    services: services,
                    child: const SpaceListScreen(),
                  ),
                ),
              ),
              child: const Text('enter'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('enter'));
  await _settle(tester);
}

void main() {
  late InMemoryCommunityBackend backend;
  late CommunityServices services;

  setUp(() {
    backend = InMemoryCommunityBackend();
    backend.registerAccount('me', displayName: 'Tester');
    backend.registerAccount('other', displayName: 'Other');
    services = CommunityServices(
      community: backend.memberView('me'),
      notifications: backend.notificationsFor('me'),
    );
  });

  testWidgets('space list shows exactly the two spaces and the banner', (
    tester,
  ) async {
    await _pump(tester, services);
    expect(find.byKey(const Key('space_general_health')), findsOneWidget);
    expect(find.byKey(const Key('space_pregnancy_maternal')), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.text(CommunitySafetyBanner.text), findsOneWidget);
  });

  testWidgets('compose: empty rejected, text post appears in feed', (
    tester,
  ) async {
    await _pump(tester, services);
    await tester.tap(find.text('Pregnancy / Maternal Health'));
    await _settle(tester);
    expect(find.text(CommunitySafetyBanner.text), findsOneWidget);
    expect(find.text('No posts yet.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('compose_post')));
    await _settle(tester);
    expect(find.text(CommunitySafetyBanner.text), findsOneWidget);
    // Text only: no image or attachment affordance.
    expect(find.byIcon(Icons.image_outlined), findsNothing);
    expect(find.byIcon(Icons.attach_file), findsNothing);

    await tester.tap(find.byKey(const Key('compose_submit')));
    await _settle(tester);
    expect(find.text('Write something before posting.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('compose_body')),
      'Anyone else tired in week 30?',
    );
    await tester.tap(find.byKey(const Key('compose_submit')));
    await _settle(tester);
    expect(find.text('Anyone else tired in week 30?'), findsOneWidget);
    expect(find.text('Community member (you)'), findsOneWidget);
  });

  testWidgets('post detail: comment, delete-own and report sheet', (
    tester,
  ) async {
    final Post p = await backend
        .memberView('other')
        .createPost(
          PostDraft(
            spaceId: SpaceId.generalHealth,
            body: 'Tips for better sleep?',
            displayMode: DisplayMode.named,
          ),
        );
    await _pump(tester, services);
    await tester.tap(find.text('General Health'));
    await _settle(tester);
    await tester.tap(find.byKey(Key('post_${p.id}')));
    await _settle(tester);
    expect(find.text('Tips for better sleep?'), findsOneWidget);
    expect(find.text(CommunitySafetyBanner.text), findsOneWidget);

    await tester.enterText(find.byKey(const Key('comment_body')), 'Less tea');
    await tester.tap(find.byKey(const Key('comment_submit')));
    await _settle(tester);
    expect(find.text('Less tea'), findsOneWidget);
    // Single level: there is no reply-to-comment control.
    expect(find.text('Reply'), findsNothing);

    // Someone else's post offers Report, not Delete.
    await tester.tap(find.byKey(const Key('post_menu')));
    await _settle(tester);
    expect(find.text('Delete'), findsNothing);
    await tester.tap(find.text('Report'));
    await _settle(tester);
    expect(find.text('Report this post'), findsOneWidget);
    await tester.tap(find.byKey(const Key('report_submit')));
    await _settle(tester);
    expect(find.text('Choose a reason.'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('report_reason_unsafe_medical_advice')),
    );
    await tester.tap(find.byKey(const Key('report_submit')));
    await _settle(tester);
    expect(find.text('Thanks. A moderator will review it.'), findsOneWidget);
    final InMemoryCommunityBackend b = backend;
    b.registerAccount('mod', role: CommunityRole.moderator);
    expect((await b.moderationAs('mod').openReports()).items, hasLength(1));
  });

  testWidgets('notification centre lists replies and marks them read', (
    tester,
  ) async {
    final Post mine = await services.community.createPost(
      PostDraft(
        spaceId: SpaceId.generalHealth,
        body: 'My post',
        displayMode: DisplayMode.pseudonymous,
      ),
    );
    await backend
        .memberView('other')
        .createComment(
          CommentDraft(
            postId: mine.id,
            body: 'A reply',
            displayMode: DisplayMode.named,
          ),
        );
    await _pump(tester, services);
    await tester.tap(find.byKey(const Key('open_notifications')));
    await _settle(tester);
    expect(find.text('Someone commented on your post'), findsOneWidget);
    expect(find.text(CommunitySafetyBanner.text), findsOneWidget);
    await tester.tap(find.byKey(const Key('mark_all_read')));
    await _settle(tester);
    expect(await services.notifications.unreadCount(), 0);
  });

  testWidgets('kill-switch error closes Community and drops the cache', (
    tester,
  ) async {
    final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
      const CommunityFeatures(
        state: CommunityFlagState.internal,
        allowed: true,
      ),
    );
    final CommunityGate gate = CommunityGate(
      compileTimeEnabled: true,
      source: source,
    );
    await gate.isOpen();
    await _pump(
      tester,
      CommunityServices(
        community: _KilledRepository(),
        notifications: services.notifications,
      ),
      gate: gate,
    );
    await _settle(tester);
    expect(find.text('enter'), findsOneWidget, reason: 'popped to the start');
    expect(find.byType(SpaceListScreen), findsNothing);
    await gate.isOpen();
    expect(source.fetchCount, 2, reason: 'cached allow was invalidated');
  });
}

class _KilledRepository implements CommunityRepository {
  @override
  Future<List<Space>> listSpaces() async {
    throw const CommunityException(CommunityErrorCode.communityNotAllowed);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
