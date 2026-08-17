/// Scoring and red-flag references for a canonical token, read from the frozen
/// clinical artifacts.
///
/// This index **duplicates no clinical rule**. It reads `kb.ng.v2.4.json` and
/// `rules.ng.v2.2.json` and reports where a token is referenced, so an option
/// difference can be traced to the conditions and rules it could affect. It
/// makes no judgement about urgency, ranking or triage, and nothing here is
/// used to score anything.
library;

import 'dart:convert';
import 'dart:io';

const String kKbPath = 'test/fixtures/artifacts/kb.ng.v2.4.json';
const String kRulesPath = 'test/fixtures/artifacts/rules.ng.v2.2.json';

/// Where one token appears in the clinical artifacts.
class TokenClinicalReferences {
  TokenClinicalReferences({
    required this.token,
    required this.scoringConditionIds,
    required this.conditionSpecificRedFlagIds,
    required this.globalRedFlagRuleIds,
    required this.maxScoringWeight,
    required this.demographicEscalationConditionIds,
  });

  final String token;

  /// Conditions whose `symptoms` list references this token.
  final List<String> scoringConditionIds;

  /// Conditions whose `red_flags` list references this token.
  final List<String> conditionSpecificRedFlagIds;

  /// Global rules in `rules.ng.v2.2.json` keyed on this token.
  final List<String> globalRedFlagRuleIds;

  final int maxScoringWeight;

  /// Conditions that carry a demographic modifier and reference this token.
  /// A token reachable in one order only could change a demographic
  /// escalation, so the linkage is recorded rather than assumed absent.
  final List<String> demographicEscalationConditionIds;

  bool get affectsScoring => scoringConditionIds.isNotEmpty;
  bool get affectsRedFlags =>
      globalRedFlagRuleIds.isNotEmpty || conditionSpecificRedFlagIds.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'token': token,
    'affects_scoring': affectsScoring,
    'affects_red_flags': affectsRedFlags,
    'scoring_condition_ids': scoringConditionIds,
    'scoring_condition_count': scoringConditionIds.length,
    'max_scoring_weight': maxScoringWeight,
    'condition_specific_red_flag_ids': conditionSpecificRedFlagIds,
    'condition_specific_red_flag_count': conditionSpecificRedFlagIds.length,
    'global_red_flag_rule_ids': globalRedFlagRuleIds,
    'global_red_flag_rule_count': globalRedFlagRuleIds.length,
    'demographic_escalation_condition_ids': demographicEscalationConditionIds,
  };
}

class ClinicalIndex {
  ClinicalIndex._(this._byToken, this.conditionCount, this.ruleCount);

  factory ClinicalIndex.load() {
    final Map<String, dynamic> kb =
        jsonDecode(File(kKbPath).readAsStringSync()) as Map<String, dynamic>;
    final Map<String, dynamic> rules =
        jsonDecode(File(kRulesPath).readAsStringSync()) as Map<String, dynamic>;

    final Map<String, List<String>> scoring = <String, List<String>>{};
    final Map<String, int> weights = <String, int>{};
    final Map<String, List<String>> conditionRedFlags =
        <String, List<String>>{};
    final Map<String, List<String>> demographic = <String, List<String>>{};

    final List<dynamic> conditions = kb['conditions'] as List<dynamic>;
    for (final Object? c in conditions) {
      final Map<String, dynamic> condition = c as Map<String, dynamic>;
      final String id = condition['condition_id'] as String;
      final bool hasDemographicModifier =
          ((condition['demographic_modifiers'] as List<dynamic>?) ??
                  const <dynamic>[])
              .isNotEmpty;

      for (final Object? s
          in (condition['symptoms'] as List<dynamic>?) ?? const <dynamic>[]) {
        final Map<String, dynamic> symptom = s as Map<String, dynamic>;
        final String token = symptom['token'] as String;
        final int weight = (symptom['weight'] as num?)?.toInt() ?? 0;
        scoring.putIfAbsent(token, () => <String>[]).add(id);
        weights[token] = weight > (weights[token] ?? 0)
            ? weight
            : weights[token]!;
        if (hasDemographicModifier) {
          demographic.putIfAbsent(token, () => <String>[]).add(id);
        }
      }
      for (final Object? f
          in (condition['red_flags'] as List<dynamic>?) ?? const <dynamic>[]) {
        conditionRedFlags.putIfAbsent(f as String, () => <String>[]).add(id);
      }
    }

    final Map<String, List<String>> globalRules = <String, List<String>>{};
    final List<dynamic> ruleList = rules['rules'] as List<dynamic>;
    for (final Object? r in ruleList) {
      final Map<String, dynamic> rule = r as Map<String, dynamic>;
      globalRules
          .putIfAbsent(rule['token'] as String, () => <String>[])
          .add(rule['rule_id'] as String);
    }

    final Set<String> allTokens = <String>{
      ...scoring.keys,
      ...conditionRedFlags.keys,
      ...globalRules.keys,
      ...demographic.keys,
    };
    final Map<String, TokenClinicalReferences>
    byToken = <String, TokenClinicalReferences>{
      for (final String token in allTokens)
        token: TokenClinicalReferences(
          token: token,
          scoringConditionIds: (scoring[token] ?? <String>[])..sort(),
          conditionSpecificRedFlagIds: (conditionRedFlags[token] ?? <String>[])
            ..sort(),
          globalRedFlagRuleIds: (globalRules[token] ?? <String>[])..sort(),
          maxScoringWeight: weights[token] ?? 0,
          demographicEscalationConditionIds: (demographic[token] ?? <String>[])
            ..sort(),
        ),
    };

    return ClinicalIndex._(byToken, conditions.length, ruleList.length);
  }

  final Map<String, TokenClinicalReferences> _byToken;
  final int conditionCount;
  final int ruleCount;

  /// References for [token]. A token with no clinical reference still returns
  /// a record — absence is a finding, not a lookup failure.
  TokenClinicalReferences references(String token) =>
      _byToken[token] ??
      TokenClinicalReferences(
        token: token,
        scoringConditionIds: const <String>[],
        conditionSpecificRedFlagIds: const <String>[],
        globalRedFlagRuleIds: const <String>[],
        maxScoringWeight: 0,
        demographicEscalationConditionIds: const <String>[],
      );

  Set<String> scoringAffecting(Set<String> tokens) => <String>{
    for (final String t in tokens)
      if (references(t).affectsScoring) t,
  };

  Set<String> redFlagAffecting(Set<String> tokens) => <String>{
    for (final String t in tokens)
      if (references(t).affectsRedFlags) t,
  };
}
