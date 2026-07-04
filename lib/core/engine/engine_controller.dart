import 'models/engine_input.dart';
import 'models/engine_output.dart';
import 'output_formatter.dart';
import 'red_flag_evaluator.dart';
import 'scoring_engine.dart';
import 'urgency_determiner.dart';

class EngineController {
  EngineController({
    required List<Map<String, dynamic>> rules,
    required Map<String, dynamic> tokenDictionary,
    required List<Map<String, dynamic>> knowledgeBase,
    required Map<String, dynamic> configMetadata,
    String? currentSeason,
  }) : _evaluator = RedFlagEvaluator(
         rules: rules,
         tokenDictionary: tokenDictionary,
       ),
       _scorer = ScoringEngine(
         knowledgeBase: knowledgeBase,
         currentSeason: currentSeason,
       ),
       _determiner = const UrgencyDeterminer(),
       _formatter = OutputFormatter(configMetadata);

  final RedFlagEvaluator _evaluator;
  final ScoringEngine _scorer;
  final UrgencyDeterminer _determiner;
  final OutputFormatter _formatter;

  EngineOutput run(EngineInput input) {
    final redFlagResult = _evaluator.evaluate(input);

    if (!redFlagResult.proceedToScoring) {
      final urgencyResult = UrgencyResult(
        finalUrgency: 'emergency',
        urgencySource: 'global_red_flag',
        redFlagTriggered: true,
        matchedRuleId: redFlagResult.matchedRuleId,
      );
      return _formatter.format(redFlagResult, null, urgencyResult);
    }

    final scoringResult = _scorer.score(input, redFlagResult);
    final urgencyResult = _determiner.determine(redFlagResult, scoringResult);
    return _formatter.format(redFlagResult, scoringResult, urgencyResult);
  }
}
