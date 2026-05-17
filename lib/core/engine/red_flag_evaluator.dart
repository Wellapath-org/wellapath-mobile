import 'package:flutter/foundation.dart';

import 'models/engine_input.dart';
import 'models/engine_output.dart';

class RedFlagEvaluator {
  RedFlagEvaluator({required this.rules, required this.tokenDictionary});

  final List<Map<String, dynamic>> rules;
  final Map<String, dynamic> tokenDictionary;

  RedFlagResult evaluate(EngineInput input) {
    final validTokens = <String>{};

    final symptomTokensList = tokenDictionary['symptom_tokens'];
    if (symptomTokensList is List) {
      validTokens.addAll(symptomTokensList.whereType<String>());
    }

    final redFlagTokensList = tokenDictionary['red_flag_tokens'];
    if (redFlagTokensList is List) {
      validTokens.addAll(redFlagTokensList.whereType<String>());
    }

    final unknownTokens = input.validate(validTokens);
    if (unknownTokens.isNotEmpty) {
      // Count only — never log token values (PHI risk)
      debugPrint(
        'RedFlagEvaluator: ${unknownTokens.length} unknown token(s) rejected from input',
      );
      throw ArgumentError(
        'Input contains unknown token(s) not found in token dictionary: $unknownTokens',
      );
    }

    final globalRules =
        rules.where((rule) {
          final appliesTo = rule['applies_to'];
          return appliesTo is List && appliesTo.contains('all');
        }).toList()..sort((a, b) {
          final aPriority = (a['priority'] as num?)?.toInt() ?? 999;
          final bPriority = (b['priority'] as num?)?.toInt() ?? 999;
          return aPriority.compareTo(bPriority);
        });

    final symptomSet = input.symptomTokens.toSet();

    for (final rule in globalRules) {
      final ruleToken = rule['token'] as String?;
      if (ruleToken != null && symptomSet.contains(ruleToken)) {
        return RedFlagResult(
          redFlagTriggered: true,
          proceedToScoring: false,
          redFlagType: 'global',
          matchedRuleId: rule['rule_id'] as String?,
          matchedRuleName: rule['rule_name'] as String?,
          overrideUrgency: 'emergency',
        );
      }
    }

    return const RedFlagResult(redFlagTriggered: false, proceedToScoring: true);
  }
}
