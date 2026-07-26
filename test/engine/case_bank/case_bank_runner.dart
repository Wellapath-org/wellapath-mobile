import 'package:wellapath_mobile/core/engine/engine_controller.dart';
import 'package:wellapath_mobile/core/engine/models/engine_input.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';

import 'case_bank_models.dart';

/// Runs a case bank through the live [EngineController].
///
/// The runner is deliberately artifact-agnostic: it takes already-parsed
/// rules / token dictionary / knowledge base maps, exactly as
/// `StagedArtifactLoader.loadCoreArtifacts` hands them to the app. That keeps
/// it usable both against the real downloaded artifacts and against small
/// inline fixtures in the runner's own self-tests.
class CaseBankRunner {
  CaseBankRunner({
    required this.rules,
    required this.tokenDictionary,
    required this.knowledgeBase,
    required this.configMetadata,
    this.wiring = EngineWiring.asShipped,
    this.onSafetyCriticalFailure,
  });

  final List<Map<String, dynamic>> rules;
  final Map<String, dynamic> tokenDictionary;
  final List<Map<String, dynamic>> knowledgeBase;
  final Map<String, dynamic> configMetadata;
  final EngineWiring wiring;

  /// Invoked the instant a safety-critical case under-triages, before the run
  /// continues. Per the E8.1 brief these must surface immediately rather than
  /// waiting for the full run to finish.
  final void Function(CaseRunResult result)? onSafetyCriticalFailure;

  /// `EngineController` takes its season at construction, so one controller is
  /// built per distinct season and reused across cases sharing it.
  final Map<String?, EngineController> _controllers =
      <String?, EngineController>{};

  EngineController _controllerFor(String? season) {
    return _controllers.putIfAbsent(
      season,
      () => EngineController(
        rules: rules,
        tokenDictionary: tokenDictionary,
        knowledgeBase: knowledgeBase,
        configMetadata: configMetadata,
        currentSeason: season,
      ),
    );
  }

  /// Every `rule_id` whose `applies_to` contains `all`.
  Set<String> get globalRuleIds => rules
      .where((Map<String, dynamic> rule) {
        final Object? appliesTo = rule['applies_to'];
        return appliesTo is List && appliesTo.contains('all');
      })
      .map((Map<String, dynamic> rule) => rule['rule_id'] as String?)
      .whereType<String>()
      .toSet();

  EngineInput _inputFor(CaseBankCase testCase) {
    switch (wiring) {
      case EngineWiring.asShipped:
        // Mirrors loading_screen.dart exactly — demographics and season are
        // dropped on the floor by the app today.
        return EngineInput(
          symptomTokens: testCase.inputTokens,
          candidateConditionIds: const <String>[],
        );
      case EngineWiring.asIntended:
        // Union of both things candidateConditionIds is read as: demographic
        // modifier names (ScoringEngine) and condition ids (RedFlagEvaluator).
        return EngineInput(
          symptomTokens: testCase.inputTokens,
          candidateConditionIds: <String>[
            ...testCase.demographicTokens,
            if (testCase.conditionTarget.isNotEmpty) testCase.conditionTarget,
          ],
        );
    }
  }

  String? _seasonFor(CaseBankCase testCase) =>
      wiring == EngineWiring.asShipped ? null : testCase.season;

  CaseRunResult runCase(CaseBankCase testCase) {
    EngineOutput? output;
    String? error;

    try {
      output = _controllerFor(_seasonFor(testCase)).run(_inputFor(testCase));
    } on Object catch (e) {
      // Any engine throw is recorded as a failed case rather than aborting the
      // run — an unknown token in one case must not cost us the other 199.
      error = e.toString();
    }

    final String? actualUrgency = output?.urgency;
    final String? actualTopCondition =
        (output != null && output.topCauses.isNotEmpty)
        ? output.topCauses.first['condition_id'] as String?
        : null;

    TriageDirection? direction;
    if (actualUrgency != null) {
      final int expected = urgencyRank(testCase.expectedUrgency);
      final int actual = urgencyRank(actualUrgency);
      if (actual == expected) {
        direction = TriageDirection.match;
      } else if (actual < expected) {
        direction = TriageDirection.underTriage;
      } else {
        direction = TriageDirection.overTriage;
      }
    }

    // A null expectation means the case does not assert a top condition.
    final bool topConditionMatched =
        testCase.expectedTopCondition == null ||
        testCase.expectedTopCondition == actualTopCondition;

    final CaseRunResult result = CaseRunResult(
      testCase: testCase,
      wiring: wiring,
      actualUrgency: actualUrgency,
      actualTopCondition: actualTopCondition,
      urgencyDirection: direction,
      topConditionMatched: topConditionMatched,
      redFlagTriggered: output?.redFlagTriggered ?? false,
      matchedRuleId: output?.matchedRuleId,
      error: error,
    );

    if (result.isSafetyCriticalFailure) {
      onSafetyCriticalFailure?.call(result);
    }

    return result;
  }

  CaseBankReport runAll(List<CaseBankCase> cases) {
    return CaseBankReport(
      wiring: wiring,
      results: cases.map(runCase).toList(),
      globalRuleIds: globalRuleIds,
    );
  }
}

/// Parses a delivered `case_bank_v1.json` payload.
///
/// Accepts either a bare JSON list of cases or an object with a `cases` key,
/// so the harness does not break on a reasonable shape choice by the data
/// engineer.
List<CaseBankCase> parseCaseBank(Object? decoded) {
  final Object? rawCases = decoded is Map<String, dynamic>
      ? decoded['cases']
      : decoded;

  if (rawCases is! List) {
    throw ArgumentError(
      'Case bank must be a JSON list of cases, or an object with a "cases" list',
    );
  }

  return rawCases
      .whereType<Map<String, dynamic>>()
      .map(CaseBankCase.fromJson)
      .toList();
}
