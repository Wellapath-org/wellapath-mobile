/// Deterministic question ordering: `(priority, tie_break_key, question_id)`.
///
/// Never map iteration order, never file order, never an unstable sort. The
/// question id is the final comparison, so the order is total — two questions
/// cannot compare equal, because their ids differ.
///
/// This is IM-001. It is implemented for the candidate consumer only; the live
/// `QuestionEngine` ordering is untouched. Activation requires the tie-path
/// regression evidence in `test/question_flow/im001_tie_path_test.dart`.
library;

import 'question_flow_models.dart';

/// Compares by priority, then tie-break key, then question id.
///
/// String comparison is `compareTo`, which is code-unit ordering — not locale
/// aware, and therefore identical on every device and locale. A
/// locale-sensitive collation here would make question order depend on the
/// user's phone settings.
int compareFlowQuestions(FlowQuestion a, FlowQuestion b) {
  final int byPriority = a.priority.compareTo(b.priority);
  if (byPriority != 0) return byPriority;

  final int byTieBreak = a.tieBreakKey.compareTo(b.tieBreakKey);
  if (byTieBreak != 0) return byTieBreak;

  return a.id.value.compareTo(b.id.value);
}

/// Returns [questions] in deterministic order.
///
/// Sorts a copy, so the caller's list is never mutated and no hidden ordering
/// dependency can develop.
List<FlowQuestion> orderFlowQuestions(Iterable<FlowQuestion> questions) {
  final List<FlowQuestion> sorted = List<FlowQuestion>.of(questions)
    ..sort(compareFlowQuestions);
  return List<FlowQuestion>.unmodifiable(sorted);
}

/// The order key as a comparable string, for reporting and duplicate checks.
String flowOrderKey(FlowQuestion q) =>
    '${q.priority}|${q.tieBreakKey}|${q.id.value}';
