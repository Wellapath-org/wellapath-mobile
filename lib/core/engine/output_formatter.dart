import 'models/engine_output.dart';

const _validUrgencies = {'emergency', 'urgent', 'non_urgent', 'self_care'};

const _careInstructions = {
  'emergency': 'Go to emergency now — do not wait.',
  'urgent': 'Visit a clinic or health facility today.',
  'non_urgent': 'Visit a clinic within 1-2 days.',
  'self_care':
      'Rest, stay hydrated, use OTC care if needed. Seek help if symptoms worsen.',
};

class OutputFormatter {
  OutputFormatter(this._configMetadata);

  final Map<String, dynamic> _configMetadata;

  EngineOutput format(
    RedFlagResult redFlagResult,
    ScoringResult? scoringResult,
    UrgencyResult urgencyResult,
  ) {
    final urgency = urgencyResult.finalUrgency;
    if (!_validUrgencies.contains(urgency)) {
      throw ArgumentError('Invalid urgency value: $urgency');
    }

    final topCauses = <Map<String, dynamic>>[];
    if (scoringResult != null) {
      for (final condition in scoringResult.scoredConditions.take(3)) {
        topCauses.add({
          'condition_id': condition.conditionId,
          'condition_name': condition.conditionName,
          'score': condition.score,
        });
      }
    }

    final explanationPoints = <String>[];
    if (redFlagResult.redFlagTriggered &&
        redFlagResult.matchedRuleName != null) {
      explanationPoints.add(redFlagResult.matchedRuleName!);
    } else if (scoringResult != null &&
        scoringResult.scoredConditions.isNotEmpty) {
      final top = scoringResult.scoredConditions.first;
      if (top.explanationTemplate != null) {
        explanationPoints.add(top.explanationTemplate!);
      }
    }

    final careInstruction = _careInstructions[urgency]!;

    final artifactsUsed = <String, String>{};
    final artifacts = _configMetadata['artifacts'];
    if (artifacts is Map<String, dynamic>) {
      final kb = artifacts['knowledge_base'];
      if (kb is Map<String, dynamic> && kb['version'] is String) {
        artifactsUsed['kb_version'] = kb['version'] as String;
      }
      final rules = artifacts['rules'];
      if (rules is Map<String, dynamic> && rules['version'] is String) {
        artifactsUsed['rules_version'] = rules['version'] as String;
      }
      final tokenDict = artifacts['token_dictionary'];
      if (tokenDict is Map<String, dynamic> && tokenDict['version'] is String) {
        artifactsUsed['token_dict_version'] = tokenDict['version'] as String;
      }
    }

    return EngineOutput(
      urgency: urgency,
      redFlagTriggered: redFlagResult.redFlagTriggered,
      matchedRuleId: redFlagResult.matchedRuleId,
      matchedRuleName: redFlagResult.matchedRuleName,
      topCauses: topCauses,
      explanationPoints: explanationPoints,
      careInstruction: careInstruction,
      artifactsUsed: artifactsUsed,
    );
  }
}
