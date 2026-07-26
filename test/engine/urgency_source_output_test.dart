import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/engine_controller.dart';
import 'package:wellapath_mobile/core/engine/models/engine_input.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';

/// E8 — `EngineOutput.urgencySource`.
///
/// The E8.1 case bank asserts an `expected_urgency_source` on every case, but
/// the engine did not surface the source `UrgencyDeterminer` computes, so a
/// case that reached the right urgency down the wrong priority path was
/// indistinguishable from a correct one. These tests pin each path's reported
/// source.

final Map<String, dynamic> _tokenDictionary = <String, dynamic>{
  'symptom_tokens': <String>['fever', 'chills', 'watery_stool'],
  'red_flag_tokens': <String>['seizures', 'haemoglobinuria'],
};

final List<Map<String, dynamic>> _rules = <Map<String, dynamic>>[
  <String, dynamic>{
    'rule_id': 'rf_global',
    'rule_name': 'Seizures',
    'token': 'seizures',
    'priority': 1,
    'applies_to': <String>['all'],
  },
  <String, dynamic>{
    'rule_id': 'rf_condition',
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
    ],
    'demographic_modifiers': <Map<String, dynamic>>[
      <String, dynamic>{
        'modifier': 'pregnancy',
        'effect': 'escalate_emergency',
      },
    ],
    'seasonal_modifiers': <Map<String, dynamic>>[],
  },
];

const Map<String, dynamic> _configMetadata = <String, dynamic>{};

EngineOutput _run({
  required List<String> symptoms,
  List<String> candidates = const <String>[],
}) {
  final EngineController engine = EngineController(
    rules: _rules,
    tokenDictionary: _tokenDictionary,
    knowledgeBase: _knowledgeBase,
    configMetadata: _configMetadata,
  );
  return engine.run(
    EngineInput(symptomTokens: symptoms, candidateConditionIds: candidates),
  );
}

void main() {
  test('a global red flag reports global_red_flag', () {
    final EngineOutput output = _run(symptoms: <String>['seizures']);

    expect(output.urgency, 'emergency');
    expect(output.urgencySource, 'global_red_flag');
  });

  test('a condition-specific red flag reports condition_specific_red_flag', () {
    // Previously this path also reported 'global_red_flag' — the controller
    // hardcoded the source regardless of which pass matched.
    final EngineOutput output = _run(
      symptoms: <String>['fever', 'haemoglobinuria'],
      candidates: <String>['malaria'],
    );

    expect(output.urgency, 'emergency');
    expect(output.redFlagTriggered, isTrue);
    expect(output.matchedRuleId, 'rf_condition');
    expect(output.urgencySource, 'condition_specific_red_flag');
  });

  test('the two red flag paths are distinguishable', () {
    expect(
      _run(symptoms: <String>['seizures']).urgencySource,
      isNot(
        _run(
          symptoms: <String>['fever', 'haemoglobinuria'],
          candidates: <String>['malaria'],
        ).urgencySource,
      ),
    );
  });

  test('a demographic escalation reports demographic_escalation', () {
    final EngineOutput output = _run(
      symptoms: <String>['fever', 'chills'],
      candidates: <String>['pregnancy'],
    );

    expect(output.urgency, 'emergency');
    expect(output.redFlagTriggered, isFalse);
    expect(output.urgencySource, 'demographic_escalation');
  });

  test('an unmodified result reports urgency_default', () {
    final EngineOutput output = _run(symptoms: <String>['fever', 'chills']);

    expect(output.urgency, 'urgent');
    expect(output.urgencySource, 'urgency_default');
  });

  test('same urgency, different source — the case this field exists for', () {
    // Both return emergency. Without urgencySource these are identical
    // outputs, and a case bank asserting "emergency via demographic
    // escalation" could not tell it had been reached by a red flag instead.
    final EngineOutput viaRedFlag = _run(symptoms: <String>['seizures']);
    final EngineOutput viaDemographic = _run(
      symptoms: <String>['fever', 'chills'],
      candidates: <String>['pregnancy'],
    );

    expect(viaRedFlag.urgency, viaDemographic.urgency);
    expect(viaRedFlag.urgencySource, isNot(viaDemographic.urgencySource));
  });
}
