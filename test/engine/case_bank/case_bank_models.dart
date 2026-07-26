/// Models for the E8.1 case bank validation harness.
///
/// The case bank itself is built by the data engineer and delivered as
/// `wellapath-knowledge-base/testing/case_bank_v1.json`. This file defines the
/// Dart-side representation of one case, one case result, and the aggregate
/// report written back out as `case_bank_results_v1.json`.
library;

/// The four locked urgency values, ordered least to most urgent.
///
/// Order matters: it is what makes "under-triage" and "over-triage" decidable.
/// Kept in sync with `output_formatter.dart`'s `_validUrgencies`.
const List<String> kUrgencyLadder = <String>[
  'self_care',
  'non_urgent',
  'urgent',
  'emergency',
];

/// Position of [urgency] on [kUrgencyLadder]. Throws on any value outside the
/// four locked ones rather than silently ranking it — an unrecognised urgency
/// in a case bank is a bank defect that must surface, not be averaged away.
int urgencyRank(String urgency) {
  final int index = kUrgencyLadder.indexOf(urgency);
  if (index < 0) {
    throw ArgumentError('Unknown urgency value: $urgency');
  }
  return index;
}

/// Which direction a case's actual urgency missed its expected urgency in.
///
/// [underTriage] is the patient-safety-relevant direction: the engine told the
/// user their situation was less urgent than the clinical expectation.
enum TriageDirection { match, underTriage, overTriage }

/// How the case's inputs are fed into the engine.
///
/// The two modes exist because they currently disagree. See the E8.1 section
/// of PROGRESS.md for the full finding.
enum EngineWiring {
  /// Exactly what `loading_screen.dart` does in the shipping app today:
  /// symptom tokens only, `candidateConditionIds` empty, no season. Under
  /// this wiring the engine's demographic modifiers, seasonal modifiers and
  /// condition-specific red flag rules are all unreachable.
  asShipped,

  /// What the engine's own modules are written to consume: demographic
  /// tokens and the target condition id in `candidateConditionIds`, and the
  /// case's season passed to `EngineController`.
  ///
  /// NOTE: `candidateConditionIds` is read by two modules that expect
  /// different contents — `RedFlagEvaluator` matches condition ids against
  /// it, `ScoringEngine` matches demographic modifier names against it — so
  /// this mode passes the union of both. That overloading is flagged for
  /// engineering lead review; this mode encodes an assumption, not a
  /// confirmed contract.
  asIntended,
}

String wiringName(EngineWiring wiring) =>
    wiring == EngineWiring.asShipped ? 'as_shipped' : 'as_intended';

/// One scenario from the case bank.
class CaseBankCase {
  const CaseBankCase({
    required this.caseId,
    required this.conditionTarget,
    required this.description,
    required this.inputTokens,
    required this.demographicTokens,
    required this.expectedUrgency,
    required this.safetyCritical,
    this.season,
    this.expectedTopCondition,
  });

  final String caseId;
  final String conditionTarget;
  final String description;
  final List<String> inputTokens;
  final List<String> demographicTokens;
  final String? season;
  final String expectedUrgency;

  /// Null means "not asserted for this case". Red flag cases legitimately
  /// have no top condition — see [CaseRunResult.actualTopCondition].
  final String? expectedTopCondition;

  /// True where under-triage would be a patient safety failure. Per the E8.1
  /// brief this is every case with `expected_urgency: emergency`; the runner
  /// does not infer it, it is read from the bank as delivered.
  final bool safetyCritical;

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value.whereType<String>().toList();
  }

  factory CaseBankCase.fromJson(Map<String, dynamic> json) {
    final String? caseId = json['case_id'] as String?;
    if (caseId == null || caseId.isEmpty) {
      throw ArgumentError('Case bank entry missing case_id');
    }
    final String? expectedUrgency = json['expected_urgency'] as String?;
    if (expectedUrgency == null) {
      throw ArgumentError('Case $caseId missing expected_urgency');
    }
    // Validate eagerly so a malformed bank fails at load, not mid-run.
    urgencyRank(expectedUrgency);

    return CaseBankCase(
      caseId: caseId,
      conditionTarget: json['condition_target'] as String? ?? '',
      description: json['description'] as String? ?? '',
      inputTokens: _stringList(json['input_tokens']),
      demographicTokens: _stringList(json['demographic_tokens']),
      season: json['season'] as String?,
      expectedUrgency: expectedUrgency,
      expectedTopCondition: json['expected_top_condition'] as String?,
      safetyCritical: json['safety_critical'] as bool? ?? false,
    );
  }
}

/// The outcome of running one [CaseBankCase] through the engine under one
/// [EngineWiring].
class CaseRunResult {
  const CaseRunResult({
    required this.testCase,
    required this.wiring,
    required this.actualUrgency,
    required this.actualTopCondition,
    required this.urgencyDirection,
    required this.topConditionMatched,
    required this.redFlagTriggered,
    this.matchedRuleId,
    this.error,
  });

  final CaseBankCase testCase;
  final EngineWiring wiring;

  /// Null when the engine threw — see [error].
  final String? actualUrgency;

  /// Null when the engine short-circuited on a red flag: that path returns
  /// `format(redFlagResult, null, urgencyResult)`, so `topCauses` is empty by
  /// design and there is no differential to report.
  final String? actualTopCondition;

  final TriageDirection? urgencyDirection;
  final bool topConditionMatched;
  final bool redFlagTriggered;
  final String? matchedRuleId;

  /// Set when the engine threw for this case (e.g. `ArgumentError` for a
  /// token absent from the token dictionary). An errored case is a failure,
  /// but it is neither under- nor over-triage.
  final String? error;

  bool get urgencyMatched => urgencyDirection == TriageDirection.match;

  bool get passed => error == null && urgencyMatched && topConditionMatched;

  /// Under-triage on a case the bank marked safety critical. This is exit
  /// criterion 5 — it must be zero.
  bool get isSafetyCriticalFailure =>
      testCase.safetyCritical &&
      (error != null || urgencyDirection == TriageDirection.underTriage);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'case_id': testCase.caseId,
    'wiring': wiringName(wiring),
    'condition_target': testCase.conditionTarget,
    'description': testCase.description,
    'input_tokens': testCase.inputTokens,
    'demographic_tokens': testCase.demographicTokens,
    'season': testCase.season,
    'expected_urgency': testCase.expectedUrgency,
    'actual_urgency': actualUrgency,
    'expected_top_condition': testCase.expectedTopCondition,
    'actual_top_condition': actualTopCondition,
    'pass': passed,
    'triage_direction': urgencyDirection == null
        ? null
        : switch (urgencyDirection!) {
            TriageDirection.match => 'match',
            TriageDirection.underTriage => 'under_triage',
            TriageDirection.overTriage => 'over_triage',
          },
    'top_condition_matched': topConditionMatched,
    'red_flag_triggered': redFlagTriggered,
    'matched_rule_id': matchedRuleId,
    'safety_critical': testCase.safetyCritical,
    'safety_critical_failure': isSafetyCriticalFailure,
    'error': error,
  };
}

/// Aggregate outcome of a full case bank run under one wiring.
class CaseBankReport {
  const CaseBankReport({
    required this.wiring,
    required this.results,
    required this.globalRuleIds,
  });

  final EngineWiring wiring;
  final List<CaseRunResult> results;

  /// Every `rule_id` whose `applies_to` contains `all`, taken from the rules
  /// artifact — the denominator for exit criterion 4.
  final Set<String> globalRuleIds;

  int get total => results.length;
  int get passed => results.where((CaseRunResult r) => r.passed).length;
  int get failed => total - passed;

  List<CaseRunResult> get failures =>
      results.where((CaseRunResult r) => !r.passed).toList();

  List<CaseRunResult> get underTriage => results
      .where(
        (CaseRunResult r) => r.urgencyDirection == TriageDirection.underTriage,
      )
      .toList();

  List<CaseRunResult> get overTriage => results
      .where(
        (CaseRunResult r) => r.urgencyDirection == TriageDirection.overTriage,
      )
      .toList();

  List<CaseRunResult> get errored =>
      results.where((CaseRunResult r) => r.error != null).toList();

  List<CaseRunResult> get safetyCriticalFailures =>
      results.where((CaseRunResult r) => r.isSafetyCriticalFailure).toList();

  double get passRate => total == 0 ? 0 : passed / total;

  /// Global red flag rule ids actually exercised by this run.
  Set<String> get globalRulesTriggered => results
      .where((CaseRunResult r) => r.matchedRuleId != null)
      .map((CaseRunResult r) => r.matchedRuleId!)
      .where(globalRuleIds.contains)
      .toSet();

  Set<String> get globalRulesNotTriggered =>
      globalRuleIds.difference(globalRulesTriggered);

  /// Cases per `condition_target`, for exit criteria 2 and 3.
  Map<String, int> get casesPerCondition {
    final Map<String, int> counts = <String, int>{};
    for (final CaseRunResult r in results) {
      final String key = r.testCase.conditionTarget;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'wiring': wiringName(wiring),
    'summary': <String, dynamic>{
      'total_cases': total,
      'passed': passed,
      'failed': failed,
      'pass_rate': double.parse((passRate * 100).toStringAsFixed(2)),
      'under_triage': underTriage.length,
      'over_triage': overTriage.length,
      'errored': errored.length,
      'safety_critical_failures': safetyCriticalFailures.length,
    },
    'red_flag_coverage': <String, dynamic>{
      'global_rules_total': globalRuleIds.length,
      'global_rules_triggered': globalRulesTriggered.length,
      'global_rules_not_triggered': globalRulesNotTriggered.toList()..sort(),
    },
    'safety_critical_failures': safetyCriticalFailures
        .map((CaseRunResult r) => r.toJson())
        .toList(),
    'failures': failures.map((CaseRunResult r) => r.toJson()).toList(),
    'results': results.map((CaseRunResult r) => r.toJson()).toList(),
  };
}
