/// Loader behaviour: the real candidate, all 23 authoritative invalid
/// fixtures, and the fail-closed guarantees.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_loader.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';

import 'question_flow_contract.dart';
import 'question_flow_test_support.dart';

void main() {
  group('the real candidate loads and validates', () {
    late QuestionFlow flow;

    setUpAll(() {
      final FlowLoadResult r = loadCandidateFlow();
      expect(r.isSuccess, isTrue, reason: '${r.failure}');
      flow = r.flow!;
    });

    test('metadata reflects an unapproved candidate', () {
      expect(flow.metadata.version, '1.0');
      expect(flow.metadata.schemaVersion, '1.0');
      expect(flow.metadata.releaseStatus, 'candidate_unapproved');
      expect(flow.metadata.isCandidateUnapproved, isTrue);
      expect(flow.metadata.claimsPublishable, isFalse);
      expect(flow.metadata.clinicalReviewStatus, 'not_reviewed');
      expect(flow.metadata.vocabulary20Used, isFalse);
    });

    test('all 50 questions and 300 options load with unique ids', () {
      expect(flow.questions, hasLength(50));
      expect(flow.questionIds, hasLength(50));

      final Set<String> optionIds = <String>{
        for (final FlowQuestion q in flow.questions)
          for (final AnswerOption o in q.answerOptions) o.id.value,
      };
      final int total = flow.questions.fold<int>(
        0,
        (int s, FlowQuestion q) => s + q.answerOptions.length,
      );
      expect(total, 300);
      expect(optionIds, hasLength(300), reason: 'option ids must be unique');
    });

    test('all seven impedance mismatches are present', () {
      expect(flow.metadata.impedanceMismatchIds, hasLength(7));
      expect(
        flow.metadata.impedanceMismatchIds,
        containsAll(kRequiredImpedanceMismatches),
      );
    });

    test('path controls are the adopted ones', () {
      expect(flow.pathControls.maxFollowupQuestions, 5);
      expect(flow.pathControls.redFlagQuestionsExemptFromTruncation, isTrue);
    });

    test('no content is approved and no question is skippable', () {
      expect(
        flow.questions.where((FlowQuestion q) => q.contentApproved),
        isEmpty,
      );
      expect(flow.questions.where((FlowQuestion q) => q.skippable), isEmpty);
    });

    test('every red-flag question is marked for immediate evaluation', () {
      for (final FlowQuestion q in flow.questions) {
        if (!q.isRedFlagQuestion) continue;
        expect(
          q.redFlagEvaluation.evaluateAfterAnswer,
          isTrue,
          reason: '${q.id} can affect a red flag but is not evaluated at once',
        );
        expect(q.effects.affectsRedFlags, isTrue, reason: '${q.id}');
      }
    });

    test('every produced token resolves against token dictionary 1.1', () {
      final Set<String> known = liveTokenDictionaryTokens();
      for (final FlowQuestion q in flow.questions) {
        for (final AnswerOption o in q.answerOptions) {
          for (final String t in o.producesTokens) {
            expect(known, contains(t), reason: '${o.id} produces $t');
          }
        }
      }
    });

    test('order keys are unique across all 50 questions', () {
      final Set<String> keys = <String>{
        for (final FlowQuestion q in flow.questions)
          '${q.priority}|${q.tieBreakKey}|${q.id.value}',
      };
      expect(keys, hasLength(50));
    });
  });

  group('every authoritative invalid fixture is rejected', () {
    late List<Map<String, dynamic>> fixtures;

    setUpAll(() {
      fixtures =
          ((jsonDecode(
                        File(
                          '$kFlowFixtureRoot/invalid/index.json',
                        ).readAsStringSync(),
                      )
                      as Map<String, dynamic>)['fixtures']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
    });

    test('the index names 23 fixtures', () => expect(fixtures, hasLength(23)));

    test('none of them loads, and each names why', () {
      final Set<String> known = liveTokenDictionaryTokens();
      final List<String> accepted = <String>[];
      final List<String> rejected = <String>[];

      for (final Map<String, dynamic> f in fixtures) {
        final String name = f['file'] as String;
        final FlowLoadResult r = loadQuestionFlowFromBytes(
          File('$kFlowFixtureRoot/invalid/$name').readAsBytesSync(),
          knownTokens: known,
        );
        if (r.isSuccess) {
          accepted.add('$name (expected ${f['expected_failing_check']})');
        } else {
          rejected.add('$name -> ${r.failure!.error.name}');
        }
      }

      expect(
        accepted,
        isEmpty,
        reason:
            'These defective fixtures were accepted by the loader:\n'
            '${accepted.join('\n')}',
      );
      expect(rejected, hasLength(23));
    });
  });

  group('fails closed', () {
    test('malformed JSON returns a typed failure, not an exception', () {
      final FlowLoadResult r = loadQuestionFlowFromString(
        '{"questions": [',
        knownTokens: liveTokenDictionaryTokens(),
      );
      expect(r.isSuccess, isFalse);
      expect(r.failure!.error, FlowLoadError.malformedJson);
      expect(r.flow, isNull);
    });

    test('an unsupported major schema version is refused, not parsed', () {
      final Map<String, dynamic> doc = candidateJson();
      (doc['_metadata'] as Map<String, dynamic>)['schema_version'] = '2.0';
      expect(
        loadFlowFromMap(doc).failure!.error,
        FlowLoadError.unsupportedSchemaVersion,
      );
    });

    test('a publication claim without clinical review is refused', () {
      final Map<String, dynamic> doc = candidateJson();
      (doc['_metadata'] as Map<String, dynamic>)['may_publish'] = true;
      expect(
        loadFlowFromMap(doc).failure!.error,
        FlowLoadError.invalidReviewOrPublication,
      );
    });

    test('a path limit other than 5 is refused', () {
      for (final int limit in <int>[3, 7, 11]) {
        final Map<String, dynamic> doc = candidateJson();
        (doc['path_controls']
                as Map<String, dynamic>)['max_followup_questions'] =
            limit;
        expect(
          loadFlowFromMap(doc).failure!.error,
          FlowLoadError.invalidPathControls,
          reason: 'limit $limit must be refused',
        );
      }
    });

    test('removing the red-flag truncation exemption is refused', () {
      final Map<String, dynamic> doc = candidateJson();
      (doc['path_controls']
              as Map<
                String,
                dynamic
              >)['red_flag_questions_exempt_from_truncation'] =
          false;
      expect(
        loadFlowFromMap(doc).failure!.error,
        FlowLoadError.invalidPathControls,
      );
    });

    test('a missing impedance mismatch is refused', () {
      final Map<String, dynamic> doc = candidateJson();
      final List<dynamic> ims =
          (doc['_metadata'] as Map<String, dynamic>)['impedance_mismatches']
              as List<dynamic>;
      ims.removeWhere(
        (dynamic im) => (im as Map<String, dynamic>)['id'] == 'IM-003',
      );
      expect(
        loadFlowFromMap(doc).failure!.error,
        FlowLoadError.missingImpedanceRecord,
        reason: 'an undisclosed behavioural difference must not load',
      );
    });

    test('a flow claiming Vocabulary 2.0 participates is refused', () {
      final Map<String, dynamic> doc = candidateJson();
      ((doc['_metadata'] as Map<String, dynamic>)['vocabulary_2_0']
              as Map<String, dynamic>)['used'] =
          true;
      expect(
        loadFlowFromMap(doc).failure!.error,
        FlowLoadError.vocabularyActivated,
      );
    });

    test('an operator suggesting fuzzy matching is refused', () {
      for (final String op in const <String>[
        'matches_regex',
        'contains',
        'similarity',
        'score',
      ]) {
        final Map<String, dynamic> doc = candidateJson();
        (doc['condition_language'] as Map<String, dynamic>)['operators'] =
            <String>[op];
        expect(
          loadFlowFromMap(doc).failure!.error,
          FlowLoadError.unknownOperator,
          reason: op,
        );
      }
    });

    test('a malformed condition is an error, never false', () {
      final Map<String, dynamic> doc = candidateJson();
      (doc['questions'] as List<dynamic>)[0]['trigger_condition'] =
          <String, dynamic>{'token_present': 42};
      final FlowLoadResult r = loadFlowFromMap(doc);
      expect(r.isSuccess, isFalse);
      expect(r.failure!.error, FlowLoadError.conditionTypeMismatch);
    });

    test('a condition with two operator keys is refused', () {
      final Map<String, dynamic> doc = candidateJson();
      (doc['questions'] as List<dynamic>)[0]['trigger_condition'] =
          <String, dynamic>{'always': true, 'never': true};
      expect(
        loadFlowFromMap(doc).failure!.error,
        FlowLoadError.invalidCondition,
      );
    });

    test('a token that does not exist is refused', () {
      final Map<String, dynamic> doc = candidateJson();
      (doc['questions'] as List<dynamic>)[0]['trigger_condition'] =
          <String, dynamic>{'token_present': 'not_a_real_token'};
      expect(
        loadFlowFromMap(doc).failure!.error,
        FlowLoadError.unknownTokenReference,
      );
    });

    test('a required question marked skippable is refused', () {
      final Map<String, dynamic> doc = candidateJson();
      final Map<String, dynamic> q =
          (doc['questions'] as List<dynamic>)[0] as Map<String, dynamic>;
      q['required'] = true;
      q['skippable'] = true;
      expect(
        loadFlowFromMap(doc).failure!.error,
        FlowLoadError.requiredQuestionSkippable,
      );
    });

    test('a failure never yields partial data', () {
      for (final String name in const <String>[
        'duplicate_question_id.json',
        'unknown_token.json',
        'branch_cycle.json',
        'invalid_condition_operator.json',
      ]) {
        final FlowLoadResult r = loadQuestionFlowFromBytes(
          File('$kFlowFixtureRoot/invalid/$name').readAsBytesSync(),
          knownTokens: liveTokenDictionaryTokens(),
        );
        expect(r.flow, isNull, reason: '$name leaked partial data');
        expect(r.failure, isNotNull);
      }
    });
  });

  group('offline', () {
    test('loading needs no network and no plugins', () {
      // The binding has no HTTP client wired; completing proves none is used.
      expect(loadCandidateFlow().isSuccess, isTrue);
    });

    test('repeated loads from the same bytes are identical', () {
      final QuestionFlow a = loadCandidateFlow().flow!;
      final QuestionFlow b = loadCandidateFlow().flow!;
      expect(
        a.questions.map((FlowQuestion q) => q.id.value).toList(),
        b.questions.map((FlowQuestion q) => q.id.value).toList(),
      );
    });
  });
}
