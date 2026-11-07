/// Emergency and red-flag result screens must never route anyone into
/// Community (COMMUNITY_BUILD_STATUS.md §3). They offer only Call 112 and
/// Find Care; this pins that, rendered and in source.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';
import 'package:wellapath_mobile/features/assessment/assessment_controller.dart';
import 'package:wellapath_mobile/features/community/ui/community_entry_row.dart';
import 'package:wellapath_mobile/features/results/red_flag_interrupt_screen.dart';
import 'package:wellapath_mobile/features/results/results_screen.dart';

EngineOutput _emergency({required bool redFlag}) {
  return EngineOutput(
    urgencySource: redFlag ? 'global_red_flag' : 'urgency_default',
    urgency: 'emergency',
    redFlagTriggered: redFlag,
    matchedRuleId: redFlag ? 'rf_002' : null,
    matchedRuleName: redFlag ? 'Active Seizures' : null,
    topCauses: const [
      {
        'condition_id': 'malaria',
        'condition_name': 'Malaria',
        'score': 37,
        'explanation': 'Your symptoms may be consistent with malaria.',
        'urgency': 'emergency',
      },
    ],
    explanationPoints: const ['Active Seizures'],
    careInstruction: 'Go to emergency now — do not wait.',
    artifactsUsed: const {
      'kb_version': '1.0',
      'rules_version': '1.0',
      'token_dict_version': '1.0',
    },
  );
}

void _useTallPhone(WidgetTester tester) {
  // Tall enough that lazily built lists render every child.
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void _expectNoCommunity(WidgetTester tester) {
  expect(find.byType(CommunityEntryRow), findsNothing);
  expect(
    find.textContaining(RegExp('community', caseSensitive: false)),
    findsNothing,
  );
  expect(
    find.textContaining(RegExp('forum', caseSensitive: false)),
    findsNothing,
  );
  expect(find.byIcon(Icons.forum_outlined), findsNothing);
}

void main() {
  testWidgets('red-flag interrupt screen has no Community navigation', (
    tester,
  ) async {
    _useTallPhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: RedFlagInterruptScreen(
          engineOutput: _emergency(redFlag: true),
          assessmentController: AssessmentController(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('EMERGENCY'), findsOneWidget);
    _expectNoCommunity(tester);
  });

  testWidgets('results screen at emergency urgency has no Community link', (
    tester,
  ) async {
    _useTallPhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen(
          engineOutput: _emergency(redFlag: false),
          assessmentController: AssessmentController(),
        ),
      ),
    );
    await tester.pump();
    _expectNoCommunity(tester);
  });

  test('results/ source neither imports nor names Community', () {
    final List<String> offenders = [];
    for (final FileSystemEntity e in Directory(
      'lib/features/results',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String src = e.readAsStringSync().toLowerCase();
      if (src.contains('community') || src.contains('forum')) {
        offenders.add(e.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
