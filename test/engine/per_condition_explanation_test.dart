import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/engine_controller.dart';
import 'package:wellapath_mobile/core/engine/models/engine_input.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';

import 'case_bank/artifact_fixtures.dart';

/// E9 Defect B — every "Possible Conditions" card showed the *top* condition's
/// explanation.
///
/// `OutputFormatter` populated `explanationPoints` from the top-ranked
/// condition only, and `results_screen.dart` reused that single string for
/// every card. On a real result the card headed "Lassa Fever" rendered
/// malaria's description — misleading clinical content on the results screen.
///
/// Each entry in `topCauses` now carries its own `explanation`, sourced from
/// that condition's own `explanation_template`.

const String _malariaTemplate = 'Explanation for malaria.';
const String _diarrhoeaTemplate = 'Explanation for acute diarrhoea.';
const String _pneumoniaTemplate = 'Explanation for pneumonia.';

final Map<String, dynamic> _tokenDictionary = <String, dynamic>{
  'symptom_tokens': <String>['fever', 'chills', 'watery_stool', 'cough'],
  'red_flag_tokens': <String>['seizures'],
};

final List<Map<String, dynamic>> _rules = <Map<String, dynamic>>[
  <String, dynamic>{
    'rule_id': 'rf_global',
    'rule_name': 'Seizures',
    'token': 'seizures',
    'priority': 1,
    'applies_to': <String>['all'],
  },
];

/// Three conditions with distinct templates, weighted so all three score and
/// rank in a known order: malaria > acute_diarrhoea > pneumonia.
final List<Map<String, dynamic>> _knowledgeBase = <Map<String, dynamic>>[
  <String, dynamic>{
    'condition_id': 'malaria',
    'condition_name': 'Malaria',
    'base_weight': 10,
    'urgency_default': 'urgent',
    'explanation_template': _malariaTemplate,
    'symptoms': <Map<String, dynamic>>[
      <String, dynamic>{'token': 'fever', 'weight': 9},
      <String, dynamic>{'token': 'chills', 'weight': 7},
    ],
    'demographic_modifiers': <Map<String, dynamic>>[],
    'seasonal_modifiers': <Map<String, dynamic>>[],
  },
  <String, dynamic>{
    'condition_id': 'acute_diarrhoea',
    'condition_name': 'Acute Diarrhoea',
    'base_weight': 8,
    'urgency_default': 'non_urgent',
    'explanation_template': _diarrhoeaTemplate,
    'symptoms': <Map<String, dynamic>>[
      <String, dynamic>{'token': 'watery_stool', 'weight': 6},
    ],
    'demographic_modifiers': <Map<String, dynamic>>[],
    'seasonal_modifiers': <Map<String, dynamic>>[],
  },
  <String, dynamic>{
    'condition_id': 'pneumonia',
    'condition_name': 'Pneumonia',
    'base_weight': 5,
    'urgency_default': 'urgent',
    'explanation_template': _pneumoniaTemplate,
    'symptoms': <Map<String, dynamic>>[
      <String, dynamic>{'token': 'cough', 'weight': 4},
    ],
    'demographic_modifiers': <Map<String, dynamic>>[],
    'seasonal_modifiers': <Map<String, dynamic>>[],
  },
];

EngineOutput _run(List<String> symptoms) {
  final EngineController engine = EngineController(
    rules: _rules,
    tokenDictionary: _tokenDictionary,
    knowledgeBase: _knowledgeBase,
    configMetadata: const <String, dynamic>{},
  );
  return engine.run(
    EngineInput(
      symptomTokens: symptoms,
      candidateConditionIds: const <String>[],
    ),
  );
}

void main() {
  group('per-condition explanation', () {
    test('each of three causes carries its own explanation_template', () {
      final EngineOutput output = _run(<String>[
        'fever',
        'chills',
        'watery_stool',
        'cough',
      ]);

      expect(output.topCauses, hasLength(3));

      // Ranking is malaria (26) > acute_diarrhoea (14) > pneumonia (9).
      expect(output.topCauses[0]['condition_id'], 'malaria');
      expect(output.topCauses[1]['condition_id'], 'acute_diarrhoea');
      expect(output.topCauses[2]['condition_id'], 'pneumonia');

      expect(output.topCauses[0]['explanation'], _malariaTemplate);
      expect(output.topCauses[1]['explanation'], _diarrhoeaTemplate);
      expect(output.topCauses[2]['explanation'], _pneumoniaTemplate);
    });

    test('a lower-ranked cause does not carry the top condition text', () {
      // The defect itself: card 2 rendered card 1's explanation.
      final EngineOutput output = _run(<String>[
        'fever',
        'chills',
        'watery_stool',
        'cough',
      ]);

      expect(output.topCauses[1]['explanation'], isNot(_malariaTemplate));
      expect(output.topCauses[2]['explanation'], isNot(_malariaTemplate));
    });

    test('every cause explanation is distinct when the templates are', () {
      final EngineOutput output = _run(<String>[
        'fever',
        'chills',
        'watery_stool',
        'cough',
      ]);

      final Set<String> explanations = output.topCauses
          .map((Map<String, dynamic> c) => c['explanation'] as String)
          .toSet();

      expect(explanations, hasLength(3));
    });

    test('explanationPoints still holds the top condition only', () {
      // Unchanged contract — the red flag interrupt screen reads this.
      final EngineOutput output = _run(<String>['fever', 'chills']);

      expect(output.explanationPoints, <String>[_malariaTemplate]);
    });

    test(
      'a condition with no template yields an empty explanation, not null',
      () {
        final EngineController engine = EngineController(
          rules: _rules,
          tokenDictionary: _tokenDictionary,
          knowledgeBase: <Map<String, dynamic>>[
            <String, dynamic>{
              'condition_id': 'untemplated',
              'condition_name': 'Untemplated',
              'base_weight': 5,
              'urgency_default': 'self_care',
              'symptoms': <Map<String, dynamic>>[
                <String, dynamic>{'token': 'fever', 'weight': 3},
              ],
              'demographic_modifiers': <Map<String, dynamic>>[],
              'seasonal_modifiers': <Map<String, dynamic>>[],
            },
          ],
          configMetadata: const <String, dynamic>{},
        );

        final EngineOutput output = engine.run(
          const EngineInput(
            symptomTokens: <String>['fever'],
            candidateConditionIds: <String>[],
          ),
        );

        expect(output.topCauses.single['explanation'], '');
      },
    );

    test('the red flag path still returns no causes at all', () {
      final EngineOutput output = _run(<String>['fever', 'seizures']);

      expect(output.redFlagTriggered, isTrue);
      expect(output.topCauses, isEmpty);
    });
  });

  group('against the real knowledge base', () {
    test('kb.ng.v2.4 gives each cause its own distinct explanation', () {
      final PinnedArtifacts artifacts = loadPinnedArtifacts();
      final EngineController engine = EngineController(
        rules: artifacts.rules,
        tokenDictionary: artifacts.tokenDictionary,
        knowledgeBase: artifacts.conditions,
        configMetadata: artifacts.configMetadata,
      );

      // The exact presentation that surfaced the defect on device: card 2 was
      // Lassa Fever showing malaria's text.
      final EngineOutput output = engine.run(
        const EngineInput(
          symptomTokens: <String>['fever', 'headache', 'chills'],
          candidateConditionIds: <String>[],
        ),
      );

      expect(output.topCauses.length, greaterThanOrEqualTo(2));
      expect(output.topCauses[0]['condition_id'], 'malaria');

      final String topExplanation =
          output.topCauses[0]['explanation'] as String;
      final String secondExplanation =
          output.topCauses[1]['explanation'] as String;

      expect(topExplanation, isNotEmpty);
      expect(secondExplanation, isNotEmpty);
      expect(secondExplanation, isNot(topExplanation));
    });
  });
}
