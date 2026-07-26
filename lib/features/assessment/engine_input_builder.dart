import '../../core/engine/models/engine_input.dart';
import 'models/assessment_input.dart';

/// Builds the [EngineInput] the assessment flow hands to `EngineController`.
///
/// Extracted from `loading_screen.dart` so the wiring itself is unit-testable:
/// before E8, the screen built the input inline as
/// `candidateConditionIds: const []`, which silently disabled every
/// demographic modifier, every seasonal modifier and all 63 condition-specific
/// red flag rules. A defect that severe must be covered by tests that exercise
/// the same code path the app runs, not a copy of it.

/// Conditions the user's symptoms make plausible, used by
/// `RedFlagEvaluator`'s condition-specific pass.
///
/// A condition is a candidate when at least one of its knowledge base symptom
/// tokens appears in [symptomTokens]. This is deliberately broad: it runs
/// *before* scoring (red flags are evaluated first and must be able to
/// override scoring entirely), so it cannot depend on rank, and a
/// condition-specific rule only fires if the user additionally reports that
/// rule's own red flag token — a serious symptom in its own right. Erring
/// wide here errs toward escalation, which is the safe direction for a CDSS.
///
/// NOTE: `candidateConditionIds` is read by two engine modules that expect
/// different contents — `RedFlagEvaluator` matches condition ids against it,
/// `ScoringEngine` matches demographic modifier names against it. This
/// function supplies the condition-id half; [buildEngineInput] passes the
/// union of both. Flagged for engineering lead confirmation.
List<String> selectCandidateConditionIds({
  required List<String> symptomTokens,
  required List<Map<String, dynamic>> knowledgeBase,
}) {
  if (symptomTokens.isEmpty) return const <String>[];

  final Set<String> reported = symptomTokens.toSet();
  final List<String> candidates = <String>[];

  for (final Map<String, dynamic> condition in knowledgeBase) {
    final String? conditionId = condition['condition_id'] as String?;
    if (conditionId == null) continue;

    final Object? symptoms = condition['symptoms'];
    if (symptoms is! List) continue;

    for (final Object? symptom in symptoms) {
      if (symptom is! Map) continue;
      final Object? token = symptom['token'];
      if (token is String && reported.contains(token)) {
        candidates.add(conditionId);
        break;
      }
    }
  }

  return candidates;
}

/// Assembles the engine input from the assessment the user actually completed.
///
/// [AssessmentInput.demographicTokens] carries the answers from the sex, age,
/// pregnancy and medical-conditions screens; `ScoringEngine` matches those
/// against each condition's `demographic_modifiers`. They are passed together
/// with the derived candidate condition ids because the single
/// `candidateConditionIds` field feeds both consumers.
EngineInput buildEngineInput({
  required AssessmentInput assessmentInput,
  required List<Map<String, dynamic>> knowledgeBase,
}) {
  return EngineInput(
    symptomTokens: assessmentInput.symptomTokens,
    candidateConditionIds: <String>[
      ...assessmentInput.demographicTokens,
      ...selectCandidateConditionIds(
        symptomTokens: assessmentInput.symptomTokens,
        knowledgeBase: knowledgeBase,
      ),
    ],
  );
}
