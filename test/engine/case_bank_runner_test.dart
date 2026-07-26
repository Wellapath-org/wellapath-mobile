import 'package:flutter_test/flutter_test.dart';

import 'case_bank/case_bank_coverage.dart';
import 'case_bank/case_bank_models.dart';
import 'case_bank/case_bank_runner.dart';

/// Self-tests for the E8.1 case bank harness.
///
/// These prove the runner classifies triage direction, flags safety-critical
/// failures and survives engine throws *before* the real case bank lands, so
/// the run itself is a same-day turnaround once
/// `wellapath-knowledge-base/testing/case_bank_v1.json` is delivered.
///
/// They use small inline artifacts rather than the real ones — the point here
/// is the harness, not the knowledge base.

final Map<String, dynamic> _tokenDictionary = <String, dynamic>{
  'symptom_tokens': <String>[
    'fever',
    'chills',
    'headache',
    'watery_stool',
    'vomiting',
    'runny_nose',
  ],
  'red_flag_tokens': <String>['seizures', 'haemoglobinuria'],
};

final List<Map<String, dynamic>> _rules = <Map<String, dynamic>>[
  <String, dynamic>{
    'rule_id': 'RF_GLOBAL_001',
    'rule_name': 'Seizures',
    'token': 'seizures',
    'priority': 1,
    'applies_to': <String>['all'],
  },
  <String, dynamic>{
    'rule_id': 'RF_COND_001',
    'rule_name': 'Haemoglobinuria in suspected malaria',
    'token': 'haemoglobinuria',
    'priority': 2,
    'applies_to': <String>['malaria'],
  },
];

final List<Map<String, dynamic>> _knowledgeBase = <Map<String, dynamic>>[
  <String, dynamic>{
    'condition_id': 'malaria',
    'condition_name': 'Malaria',
    'base_weight': 10,
    'urgency_default': 'urgent',
    'explanation_template': 'Consistent with malaria.',
    'symptoms': <Map<String, dynamic>>[
      <String, dynamic>{'token': 'fever', 'weight': 9},
      <String, dynamic>{'token': 'chills', 'weight': 7},
      <String, dynamic>{'token': 'headache', 'weight': 3},
    ],
    'demographic_modifiers': <Map<String, dynamic>>[
      <String, dynamic>{
        'modifier': 'pregnancy',
        'effect': 'escalate_emergency',
      },
    ],
    'seasonal_modifiers': <Map<String, dynamic>>[
      <String, dynamic>{
        'season': 'rainy_season',
        'effect': 'increase_base_weight',
      },
    ],
  },
  <String, dynamic>{
    // Mirrors cough_common_cold in kb.ng.v2.3: self_care by default, an
    // increase_urgency demographic and a seasonal modifier. Only this shape
    // makes UrgencyDeterminer Priority 4c (demographic + seasonal -> urgent)
    // observable, which is what catches a season that never reaches the
    // engine.
    'condition_id': 'common_cold',
    'condition_name': 'Common Cold',
    'base_weight': 8,
    'urgency_default': 'self_care',
    'explanation_template': 'Consistent with a common cold.',
    'symptoms': <Map<String, dynamic>>[
      <String, dynamic>{'token': 'runny_nose', 'weight': 8},
    ],
    'demographic_modifiers': <Map<String, dynamic>>[
      <String, dynamic>{
        'modifier': 'children_under_5',
        'effect': 'increase_urgency',
      },
    ],
    'seasonal_modifiers': <Map<String, dynamic>>[
      <String, dynamic>{
        'season': 'harmattan_season',
        'effect': 'increase_base_weight',
      },
    ],
  },
  <String, dynamic>{
    'condition_id': 'acute_diarrhoea',
    'condition_name': 'Acute Diarrhoea',
    'base_weight': 6,
    'urgency_default': 'non_urgent',
    'explanation_template': 'Consistent with acute diarrhoea.',
    'symptoms': <Map<String, dynamic>>[
      <String, dynamic>{'token': 'watery_stool', 'weight': 8},
      <String, dynamic>{'token': 'vomiting', 'weight': 5},
    ],
    'demographic_modifiers': <Map<String, dynamic>>[],
    'seasonal_modifiers': <Map<String, dynamic>>[],
  },
];

final Map<String, dynamic> _configMetadata = <String, dynamic>{
  'artifacts': <String, dynamic>{
    'knowledge_base': <String, dynamic>{'version': '2.3'},
    'rules': <String, dynamic>{'version': '2.1'},
    'token_dictionary': <String, dynamic>{'version': '1.1'},
  },
};

CaseBankRunner _runner({
  EngineWiring wiring = EngineWiring.asShipped,
  void Function(CaseRunResult)? onSafetyCriticalFailure,
}) {
  return CaseBankRunner(
    rules: _rules,
    tokenDictionary: _tokenDictionary,
    knowledgeBase: _knowledgeBase,
    configMetadata: _configMetadata,
    wiring: wiring,
    onSafetyCriticalFailure: onSafetyCriticalFailure,
  );
}

CaseBankCase _case({
  String caseId = 'CB_TEST',
  String conditionTarget = 'malaria',
  List<String> inputTokens = const <String>['fever', 'chills'],
  List<String> demographicTokens = const <String>[],
  String? season,
  String expectedUrgency = 'urgent',
  String? expectedTopCondition,
  bool safetyCritical = false,
}) {
  return CaseBankCase(
    caseId: caseId,
    conditionTarget: conditionTarget,
    description: 'test case',
    inputTokens: inputTokens,
    demographicTokens: demographicTokens,
    season: season,
    expectedUrgency: expectedUrgency,
    expectedTopCondition: expectedTopCondition,
    safetyCritical: safetyCritical,
  );
}

void main() {
  group('urgency ladder', () {
    test('ranks the four locked urgencies least to most urgent', () {
      expect(urgencyRank('self_care'), 0);
      expect(urgencyRank('non_urgent'), 1);
      expect(urgencyRank('urgent'), 2);
      expect(urgencyRank('emergency'), 3);
    });

    test('throws on an urgency outside the locked four', () {
      expect(() => urgencyRank('routine'), throwsArgumentError);
    });
  });

  group('triage direction', () {
    test('matching urgency passes with direction match', () {
      final CaseRunResult result = _runner().runCase(
        _case(expectedUrgency: 'urgent', expectedTopCondition: 'malaria'),
      );

      expect(result.actualUrgency, 'urgent');
      expect(result.urgencyDirection, TriageDirection.match);
      expect(result.actualTopCondition, 'malaria');
      expect(result.passed, isTrue);
    });

    test('actual below expected is classified as under-triage', () {
      final CaseRunResult result = _runner().runCase(
        _case(expectedUrgency: 'emergency'),
      );

      expect(result.actualUrgency, 'urgent');
      expect(result.urgencyDirection, TriageDirection.underTriage);
      expect(result.passed, isFalse);
    });

    test('actual above expected is classified as over-triage', () {
      final CaseRunResult result = _runner().runCase(
        _case(expectedUrgency: 'self_care'),
      );

      expect(result.urgencyDirection, TriageDirection.overTriage);
      expect(result.passed, isFalse);
    });

    test(
      'a case passes on urgency alone when no top condition is asserted',
      () {
        final CaseRunResult result = _runner().runCase(
          _case(expectedTopCondition: null),
        );

        expect(result.topConditionMatched, isTrue);
        expect(result.passed, isTrue);
      },
    );

    test('wrong top condition fails even when urgency matches', () {
      final CaseRunResult result = _runner().runCase(
        _case(expectedTopCondition: 'acute_diarrhoea'),
      );

      expect(result.urgencyDirection, TriageDirection.match);
      expect(result.topConditionMatched, isFalse);
      expect(result.passed, isFalse);
    });
  });

  group('safety critical failures', () {
    test('under-triage on a safety critical case is flagged', () {
      final CaseRunResult result = _runner().runCase(
        _case(expectedUrgency: 'emergency', safetyCritical: true),
      );

      expect(result.urgencyDirection, TriageDirection.underTriage);
      expect(result.isSafetyCriticalFailure, isTrue);
    });

    test('over-triage on a safety critical case is not a safety failure', () {
      final CaseRunResult result = _runner().runCase(
        _case(expectedUrgency: 'self_care', safetyCritical: true),
      );

      expect(result.urgencyDirection, TriageDirection.overTriage);
      expect(result.isSafetyCriticalFailure, isFalse);
    });

    test('the callback fires during the run, not after it', () {
      final List<String> flagged = <String>[];
      final CaseBankRunner runner = _runner(
        onSafetyCriticalFailure: (CaseRunResult r) =>
            flagged.add(r.testCase.caseId),
      );

      runner.runAll(<CaseBankCase>[
        _case(caseId: 'CB_001', expectedUrgency: 'urgent'),
        _case(
          caseId: 'CB_002',
          expectedUrgency: 'emergency',
          safetyCritical: true,
        ),
        _case(caseId: 'CB_003', expectedUrgency: 'urgent'),
      ]);

      expect(flagged, <String>['CB_002']);
    });
  });

  group('engine errors', () {
    test('an unknown token is recorded as an error, not a crash', () {
      final CaseBankReport report = _runner().runAll(<CaseBankCase>[
        _case(caseId: 'CB_001'),
        _case(caseId: 'CB_002', inputTokens: <String>['not_a_real_token']),
        _case(caseId: 'CB_003'),
      ]);

      expect(report.total, 3);
      expect(report.errored.length, 1);
      expect(report.errored.single.testCase.caseId, 'CB_002');
      expect(report.errored.single.actualUrgency, isNull);
      // The run continued past the throw.
      expect(report.passed, 2);
    });

    test('an errored safety critical case counts as a safety failure', () {
      final CaseRunResult result = _runner().runCase(
        _case(
          inputTokens: <String>['not_a_real_token'],
          expectedUrgency: 'emergency',
          safetyCritical: true,
        ),
      );

      expect(result.error, isNotNull);
      expect(result.isSafetyCriticalFailure, isTrue);
    });

    test('empty input does not crash the engine', () {
      final CaseRunResult result = _runner().runCase(
        _case(inputTokens: const <String>[], expectedUrgency: 'urgent'),
      );

      expect(result.error, isNull);
      expect(result.actualUrgency, isNotNull);
    });
  });

  group('red flag cases', () {
    test('a global red flag returns emergency with no top condition', () {
      final CaseRunResult result = _runner().runCase(
        _case(
          inputTokens: <String>['seizures'],
          expectedUrgency: 'emergency',
          safetyCritical: true,
        ),
      );

      expect(result.actualUrgency, 'emergency');
      expect(result.redFlagTriggered, isTrue);
      expect(result.matchedRuleId, 'RF_GLOBAL_001');
      // The red flag path short-circuits scoring, so there is no differential.
      expect(result.actualTopCondition, isNull);
      expect(result.isSafetyCriticalFailure, isFalse);
    });

    test('report tracks which global rules a run exercised', () {
      final CaseBankReport report = _runner().runAll(<CaseBankCase>[
        _case(inputTokens: <String>['seizures'], expectedUrgency: 'emergency'),
      ]);

      expect(report.globalRuleIds, <String>{'RF_GLOBAL_001'});
      expect(report.globalRulesTriggered, <String>{'RF_GLOBAL_001'});
      expect(report.globalRulesNotTriggered, isEmpty);
    });
  });

  group('wiring modes', () {
    // asShipped goes through buildEngineInput — the same function
    // loading_screen.dart calls — so these assert the production path.
    // preFix is retained only to pin what issue #34 looked like, so a silent
    // revert of the wiring fix fails loudly here.
    test(
      'asShipped passes demographics — pregnancy escalates to emergency',
      () {
        final CaseRunResult result = _runner(wiring: EngineWiring.asShipped)
            .runCase(
              _case(
                inputTokens: <String>['fever', 'chills'],
                demographicTokens: <String>['pregnancy'],
                expectedUrgency: 'emergency',
                safetyCritical: true,
              ),
            );

        expect(result.actualUrgency, 'emergency');
        expect(result.urgencyDirection, TriageDirection.match);
        expect(result.isSafetyCriticalFailure, isFalse);
      },
    );

    test('preFix dropped demographics — the defect this fixture pins', () {
      final CaseRunResult result = _runner(wiring: EngineWiring.preFix).runCase(
        _case(
          inputTokens: <String>['fever', 'chills'],
          demographicTokens: <String>['pregnancy'],
          expectedUrgency: 'emergency',
          safetyCritical: true,
        ),
      );

      expect(result.actualUrgency, 'urgent');
      expect(result.urgencyDirection, TriageDirection.underTriage);
      expect(result.isSafetyCriticalFailure, isTrue);
    });

    test('asShipped reaches condition-specific red flag rules', () {
      // fever makes malaria a candidate; the rule then matches on its own
      // red flag token.
      final CaseBankCase testCase = _case(
        inputTokens: <String>['fever', 'haemoglobinuria'],
        expectedUrgency: 'emergency',
      );

      final CaseRunResult shipped = _runner(
        wiring: EngineWiring.asShipped,
      ).runCase(testCase);
      final CaseRunResult preFix = _runner(
        wiring: EngineWiring.preFix,
      ).runCase(testCase);

      expect(shipped.redFlagTriggered, isTrue);
      expect(shipped.matchedRuleId, 'RF_COND_001');
      expect(preFix.redFlagTriggered, isFalse);
    });

    test('asShipped derives no candidates from an unmatched token alone', () {
      // Without a symptom that maps to malaria, the condition-specific rule
      // has no candidate to attach to — the derivation is symptom-driven,
      // not a blanket "every condition is a candidate".
      final CaseRunResult result = _runner(wiring: EngineWiring.asShipped)
          .runCase(
            _case(
              inputTokens: <String>['haemoglobinuria'],
              expectedUrgency: 'emergency',
            ),
          );

      expect(result.redFlagTriggered, isFalse);
    });

    test('asShipped passes the season through — Priority 4c fires', () {
      // Without the season reaching EngineController, Priority 4a escalates
      // self_care one level to non_urgent. With it, Priority 4c returns
      // urgent. This is the assertion that catches a dropped season; a case
      // whose condition already defaults to urgent cannot distinguish them.
      final CaseBankCase seasonal = _case(
        conditionTarget: 'common_cold',
        inputTokens: <String>['runny_nose'],
        demographicTokens: <String>['children_under_5'],
        season: 'harmattan_season',
        expectedUrgency: 'urgent',
      );

      expect(
        _runner(wiring: EngineWiring.asShipped).runCase(seasonal).actualUrgency,
        'urgent',
      );
    });

    test('the same case without a season escalates only one level', () {
      final CaseRunResult result = _runner(wiring: EngineWiring.asShipped)
          .runCase(
            _case(
              conditionTarget: 'common_cold',
              inputTokens: <String>['runny_nose'],
              demographicTokens: <String>['children_under_5'],
            ),
          );

      expect(result.actualUrgency, 'non_urgent');
    });

    test('preFix dropped the season entirely', () {
      final CaseRunResult result = _runner(wiring: EngineWiring.preFix).runCase(
        _case(
          conditionTarget: 'common_cold',
          inputTokens: <String>['runny_nose'],
          demographicTokens: <String>['children_under_5'],
          season: 'harmattan_season',
        ),
      );

      // No demographics either, so not even the one-level escalation.
      expect(result.actualUrgency, 'self_care');
    });
  });

  group('report aggregation', () {
    test('counts pass rate, triage split and safety failures', () {
      final CaseBankReport report = _runner().runAll(<CaseBankCase>[
        _case(caseId: 'CB_001', expectedUrgency: 'urgent'),
        _case(caseId: 'CB_002', expectedUrgency: 'urgent'),
        _case(
          caseId: 'CB_003',
          expectedUrgency: 'emergency',
          safetyCritical: true,
        ),
        _case(caseId: 'CB_004', expectedUrgency: 'self_care'),
      ]);

      expect(report.total, 4);
      expect(report.passed, 2);
      expect(report.failed, 2);
      expect(report.passRate, 0.5);
      expect(report.underTriage.length, 1);
      expect(report.overTriage.length, 1);
      expect(report.safetyCriticalFailures.length, 1);
      expect(report.safetyCriticalFailures.single.testCase.caseId, 'CB_003');
    });

    test('serialises to the documented results shape', () {
      final CaseBankReport report = _runner().runAll(<CaseBankCase>[
        _case(caseId: 'CB_001', expectedUrgency: 'urgent'),
      ]);
      final Map<String, dynamic> json = report.toJson();

      expect(json['wiring'], 'as_shipped');
      expect((json['summary'] as Map<String, dynamic>)['total_cases'], 1);
      expect((json['summary'] as Map<String, dynamic>)['pass_rate'], 100.0);
      expect(json['results'], hasLength(1));

      final Map<String, dynamic> first =
          (json['results'] as List<dynamic>).first as Map<String, dynamic>;
      expect(first['case_id'], 'CB_001');
      expect(first['expected_urgency'], 'urgent');
      expect(first['actual_urgency'], 'urgent');
      expect(first['triage_direction'], 'match');
      expect(first['pass'], isTrue);
    });
  });

  group('case bank parsing', () {
    final Map<String, dynamic> rawCase = <String, dynamic>{
      'case_id': 'CB_001',
      'condition_target': 'malaria',
      'description': 'Classic malaria, adult, no modifiers',
      'input_tokens': <String>['fever', 'chills'],
      'demographic_tokens': <String>[],
      'season': null,
      'expected_urgency': 'urgent',
      'expected_top_condition': 'malaria',
      'safety_critical': false,
    };

    test('parses the documented case shape', () {
      final List<CaseBankCase> cases = parseCaseBank(<dynamic>[rawCase]);

      expect(cases, hasLength(1));
      expect(cases.single.caseId, 'CB_001');
      expect(cases.single.inputTokens, <String>['fever', 'chills']);
      expect(cases.single.season, isNull);
      expect(cases.single.safetyCritical, isFalse);
    });

    test('accepts either a bare list or an object with a cases key', () {
      expect(parseCaseBank(<dynamic>[rawCase]), hasLength(1));
      expect(
        parseCaseBank(<String, dynamic>{
          'cases': <dynamic>[rawCase],
        }),
        hasLength(1),
      );
    });

    test('rejects a bank with a missing case_id', () {
      expect(
        () => parseCaseBank(<dynamic>[
          <String, dynamic>{'expected_urgency': 'urgent'},
        ]),
        throwsArgumentError,
      );
    });

    test('rejects a bank with an invalid expected_urgency at load time', () {
      expect(
        () => parseCaseBank(<dynamic>[
          <String, dynamic>{'case_id': 'CB_001', 'expected_urgency': 'routine'},
        ]),
        throwsArgumentError,
      );
    });
  });

  group('coverage validation', () {
    List<CaseBankCase> buildBank({
      int perCondition = 3,
      int perEmergencyCondition = 5,
    }) {
      final List<CaseBankCase> cases = <CaseBankCase>[];
      for (final String id in <String>['malaria', 'acute_diarrhoea']) {
        for (int i = 0; i < perCondition; i++) {
          cases.add(_case(caseId: '${id}_$i', conditionTarget: id));
        }
      }
      for (int i = 0; i < perEmergencyCondition; i++) {
        cases.add(_case(caseId: 'cholera_$i', conditionTarget: 'cholera'));
      }
      return cases;
    }

    CaseBankCoverage coverage(List<CaseBankCase> cases) => CaseBankCoverage(
      cases: cases,
      knownConditionIds: <String>{'malaria', 'acute_diarrhoea', 'cholera'},
      emergencyConditionIds: <String>{'cholera'},
      minimumCases: 11,
    );

    test('passes a bank that meets every minimum', () {
      final CaseBankCoverage result = coverage(buildBank());

      expect(result.meetsMinimumCases, isTrue);
      expect(result.meetsPerConditionMinimum, isTrue);
      expect(result.meetsEmergencyMinimum, isTrue);
      expect(result.passes, isTrue);
    });

    test('names conditions with fewer than three cases', () {
      final CaseBankCoverage result = coverage(buildBank(perCondition: 2));

      expect(result.conditionsBelowMinimum, <String>{
        'malaria',
        'acute_diarrhoea',
      });
      expect(result.passes, isFalse);
    });

    test('names emergency conditions with fewer than five cases', () {
      final CaseBankCoverage result = coverage(
        buildBank(perEmergencyCondition: 4),
      );

      expect(result.emergencyConditionsBelowMinimum, <String>{'cholera'});
      expect(result.passes, isFalse);
    });

    test('separates edge cases from condition coverage', () {
      final List<CaseBankCase> cases = buildBank()
        ..add(_case(caseId: 'EDGE_001', conditionTarget: 'edge_case'));

      expect(coverage(cases).unmappedCases, hasLength(1));
    });

    test('reports emergency cases the bank left unmarked', () {
      final List<CaseBankCase> cases = <CaseBankCase>[
        _case(
          caseId: 'CB_001',
          expectedUrgency: 'emergency',
          safetyCritical: false,
        ),
        _case(
          caseId: 'CB_002',
          expectedUrgency: 'emergency',
          safetyCritical: true,
        ),
      ];

      final CaseBankCoverage result = coverage(cases);
      expect(
        result.unmarkedSafetyCriticalCases.map((CaseBankCase c) => c.caseId),
        <String>['CB_001'],
      );
      expect(result.safetyCriticalCount, 1);
    });
  });
}
