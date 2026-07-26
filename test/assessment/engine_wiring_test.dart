import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/engine_controller.dart';
import 'package:wellapath_mobile/core/engine/models/engine_input.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';
import 'package:wellapath_mobile/features/assessment/engine_input_builder.dart';
import 'package:wellapath_mobile/features/assessment/models/assessment_input.dart';

import '../engine/case_bank/artifact_fixtures.dart';

/// Verification for the E8 engine wiring fix, run against the real pinned
/// production artifacts (kb.ng.v2.3, rules.ng.v2.1, token_dictionary.ng.v1.1)
/// rather than mocks — the point is that these escalations fire against the
/// knowledge base that actually ships, not against a fixture written to agree
/// with the test.
///
/// Before the fix, `loading_screen.dart` built its engine input with
/// `candidateConditionIds: const []` and never passed a season, which closed
/// three gates at once: condition-specific red flag rules, demographic
/// modifiers and seasonal modifiers. Each group below asserts both the fixed
/// behaviour and the pre-fix behaviour, so the tests fail loudly if the wiring
/// is ever reverted.

void main() {
  late PinnedArtifacts artifacts;

  setUpAll(() {
    artifacts = loadPinnedArtifacts();
  });

  EngineOutput run(AssessmentInput input, {bool preFixWiring = false}) {
    final EngineController engine = EngineController(
      rules: artifacts.rules,
      tokenDictionary: artifacts.tokenDictionary,
      knowledgeBase: artifacts.conditions,
      configMetadata: artifacts.configMetadata,
      currentSeason: preFixWiring ? null : input.season,
    );

    final EngineInput engineInput = preFixWiring
        ? EngineInput(
            symptomTokens: input.symptomTokens,
            candidateConditionIds: const <String>[],
          )
        : buildEngineInput(
            assessmentInput: input,
            knowledgeBase: artifacts.conditions,
          );

    return engine.run(engineInput);
  }

  AssessmentInput input({
    required List<String> symptoms,
    List<String> demographics = const <String>[],
    String? season,
  }) {
    return AssessmentInput(
      symptomTokens: symptoms,
      demographicTokens: demographics,
      severityTokens: const <String>[],
      durationTokens: const <String>[],
      season: season,
    );
  }

  group('candidate condition selection', () {
    test('selects conditions sharing at least one reported symptom', () {
      final List<String> candidates = selectCandidateConditionIds(
        symptomTokens: <String>['fever', 'chills'],
        knowledgeBase: artifacts.conditions,
      );

      expect(candidates, contains('malaria'));
      expect(candidates.length, lessThan(artifacts.conditions.length));
    });

    test('selects nothing when no symptoms are reported', () {
      expect(
        selectCandidateConditionIds(
          symptomTokens: const <String>[],
          knowledgeBase: artifacts.conditions,
        ),
        isEmpty,
      );
    });

    test('engine input carries demographics alongside candidate ids', () {
      final EngineInput built = buildEngineInput(
        assessmentInput: input(
          symptoms: <String>['fever', 'chills'],
          demographics: <String>['pregnancy'],
        ),
        knowledgeBase: artifacts.conditions,
      );

      expect(built.symptomTokens, <String>['fever', 'chills']);
      expect(built.candidateConditionIds, contains('pregnancy'));
      expect(built.candidateConditionIds, contains('malaria'));
    });
  });

  group('confirmation 2 — SAM/MAM escalation on acute diarrhoea', () {
    final AssessmentInput sam = input(
      symptoms: <String>['watery_stool', 'abdominal_cramps'],
      demographics: <String>['severe_malnutrition_sam'],
    );
    final AssessmentInput mam = input(
      symptoms: <String>['watery_stool', 'abdominal_cramps'],
      demographics: <String>['moderate_malnutrition_mam'],
    );

    test('SAM + diarrhoea escalates to emergency', () {
      final EngineOutput output = run(sam);

      expect(output.topCauses.first['condition_id'], 'acute_diarrhoea');
      expect(output.urgency, 'emergency');
    });

    test('MAM + diarrhoea escalates one level, non_urgent to urgent', () {
      final EngineOutput output = run(mam);

      expect(output.topCauses.first['condition_id'], 'acute_diarrhoea');
      expect(output.urgency, 'urgent');
    });

    test('SAM and MAM differ — MAM must not reach emergency', () {
      expect(run(sam).urgency, 'emergency');
      expect(run(mam).urgency, isNot('emergency'));
    });

    test('pre-fix wiring under-triaged both to the bare default', () {
      expect(run(sam, preFixWiring: true).urgency, 'non_urgent');
      expect(run(mam, preFixWiring: true).urgency, 'non_urgent');
    });
  });

  group('confirmation 3 — children_under_5 + rainy_season + malaria', () {
    final AssessmentInput malariaChildRainy = input(
      symptoms: <String>['fever', 'chills', 'headache'],
      demographics: <String>['children_under_5'],
      season: 'rainy_season',
    );

    test('resolves to urgent, not emergency (Option B)', () {
      final EngineOutput output = run(malariaChildRainy);

      expect(output.topCauses.first['condition_id'], 'malaria');
      expect(output.urgency, 'urgent');
      expect(output.urgency, isNot('emergency'));
    });

    test('same case without the season also resolves to urgent', () {
      final EngineOutput output = run(
        input(
          symptoms: <String>['fever', 'chills', 'headache'],
          demographics: <String>['children_under_5'],
        ),
      );

      expect(output.urgency, 'urgent');
    });

    test('pre-fix wiring reached urgent only via the bare default', () {
      final EngineOutput output = run(malariaChildRainy, preFixWiring: true);

      // Same answer, different reason: malaria's urgency_default is already
      // urgent, so the demographic and seasonal modifiers being dead was
      // invisible on this particular case. That is exactly why the SAM case
      // above matters — there the gap is a two-level under-triage.
      expect(output.urgency, 'urgent');
    });
  });

  group('confirmation — condition-specific red flags now reachable', () {
    final AssessmentInput haemoglobinuria = input(
      symptoms: <String>['fever', 'chills', 'haemoglobinuria'],
    );

    test('rf_100 fires when malaria is a candidate condition', () {
      final EngineOutput output = run(haemoglobinuria);

      expect(output.redFlagTriggered, isTrue);
      expect(output.matchedRuleId, 'rf_100');
      expect(output.urgency, 'emergency');
    });

    test('pre-fix wiring never reached the rule', () {
      final EngineOutput output = run(haemoglobinuria, preFixWiring: true);

      expect(output.redFlagTriggered, isFalse);
      expect(output.urgency, isNot('emergency'));
    });

    test('the rule does not fire without its own red flag token', () {
      final EngineOutput output = run(
        input(symptoms: <String>['fever', 'chills']),
      );

      expect(output.matchedRuleId, isNot('rf_100'));
    });
  });

  group('global red flags are unaffected by the change', () {
    test('a global rule still overrides everything', () {
      final EngineOutput output = run(
        input(
          symptoms: <String>['fever', 'seizures'],
          demographics: <String>['adults'],
        ),
      );

      expect(output.redFlagTriggered, isTrue);
      expect(output.urgency, 'emergency');
      expect(output.topCauses, isEmpty);
    });
  });

  group('empty input', () {
    test('still fabricates a result if it ever reaches the engine', () {
      // Documents why loading_screen.dart guards before calling run():
      // with no symptoms every condition is scored on base_weight alone and
      // the highest-weighted one is presented as the user's top cause.
      final EngineOutput output = run(input(symptoms: const <String>[]));

      expect(output.topCauses, isNotEmpty);
      expect(output.topCauses.first['condition_id'], 'malaria');
      expect(output.urgency, 'urgent');
    });
  });
}
