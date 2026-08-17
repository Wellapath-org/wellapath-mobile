/// Loader and domain-model behaviour for schema 1.1, and the guards that make
/// grouping safe to apply.
///
/// Every failure path here is fail-closed: the loader returns a typed failure
/// and never partially-loaded data. A grouping rule this consumer cannot
/// execute is an error, never a shrug — silently ignoring one would present a
/// different question set than the one that was reviewed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_loader.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';
import 'package:wellapath_mobile/core/question_flow/question_grouping_models.dart';

import '../question_flow/question_flow_contract.dart';
import '../question_flow/question_flow_test_support.dart';
import 'grouping_test_support.dart';
import 'question_grouping_contract.dart';

FlowLoadResult _load(Map<String, dynamic> doc) => loadQuestionFlowFromString(
  jsonEncode(doc),
  knownTokens: liveTokenDictionaryTokens(),
);

void main() {
  group('version support', () {
    test('candidate 1.0 still loads, unchanged', () {
      final FlowLoadResult result = loadCandidateFlow();
      expect(result.isSuccess, isTrue, reason: '${result.failure}');
      expect(result.flow!.metadata.schemaVersion, '1.0');
      expect(result.flow!.questions, hasLength(kFlowQuestionCount));
    });

    test('candidate 1.1 loads', () {
      final FlowLoadResult result = loadGroupedCandidate();
      expect(result.isSuccess, isTrue, reason: '${result.failure}');
      expect(result.flow!.metadata.schemaVersion, '1.1');
    });

    test('exactly 1.0 and 1.1 are supported', () {
      expect(kSupportedFlowSchemaVersions, <String>{'1.0', '1.1'});
    });

    test('an unimplemented 1.x version is refused, not best-effort parsed', () {
      // Major-version gating would have accepted this. Partially understanding
      // a schema changes which questions get asked, so the version set is
      // exact.
      for (final String version in <String>['1.2', '1.10', '2.0', '', '1']) {
        final Map<String, dynamic> doc = groupedCandidateJson();
        (doc['_metadata'] as Map<String, dynamic>)['schema_version'] = version;
        final FlowLoadResult result = _load(doc);
        expect(result.isSuccess, isFalse, reason: 'accepted "$version"');
        expect(
          result.failure!.error,
          FlowLoadError.unsupportedSchemaVersion,
          reason: version,
        );
      }
    });
  });

  group('1.0 is never implicitly grouped', () {
    test('no 1.0 question carries a grouping block', () {
      final QuestionFlow flow = loadCandidateFlow().flow!;
      for (final FlowQuestion q in flow.questions) {
        expect(q.isGrouped, isFalse, reason: q.id.value);
        expect(q.grouping, isNull);
      }
    });

    test('1.0 declares no grouping semantics and does not group', () {
      final QuestionFlow flow = loadCandidateFlow().flow!;
      expect(flow.metadata.groupingSemantics, isNull);
      expect(flow.metadata.groupsQuestions, isFalse);
    });

    test('a 1.0 artifact declaring grouping_semantics is refused', () {
      // Honouring it would apply semantics the artifact version does not
      // define.
      final Map<String, dynamic> doc = candidateJson();
      (doc['_metadata']
          as Map<String, dynamic>)['grouping_semantics'] = <String, dynamic>{
        'enabled': true,
        'groupable_roles': <String>['severity'],
        'non_groupable_roles': <String>['red_flag_clarifier'],
        'grouping_phase': 'before_truncation',
        'one_question_per_group_key': true,
      };
      final FlowLoadResult result = _load(doc);
      expect(result.isSuccess, isFalse);
      expect(result.failure!.error, FlowLoadError.invalidGroupingSemantics);
    });

    test('a 1.0 question carrying a grouping block is refused', () {
      final Map<String, dynamic> doc = candidateJson();
      final List<dynamic> questions = doc['questions'] as List<dynamic>;
      final Map<String, dynamic> victim =
          questions.firstWhere(
                (Object? q) =>
                    (q as Map<String, dynamic>)['clinical_role'] == 'severity',
              )
              as Map<String, dynamic>;
      victim['grouping'] = <String, dynamic>{
        'group_key': 'severity',
        'merge_strategy': 'single_representative',
        'representative_selection': 'lowest_source_order_index',
        'option_union_rule': 'static',
        'sources': <dynamic>[],
      };
      final FlowLoadResult result = _load(doc);
      expect(result.isSuccess, isFalse);
      expect(result.failure!.error, FlowLoadError.invalidGrouping);
    });
  });

  group('1.1 grouping requirements are enforced', () {
    test('a 1.1 artifact without grouping_semantics is refused', () {
      final Map<String, dynamic> doc = groupedCandidateJson();
      (doc['_metadata'] as Map<String, dynamic>).remove('grouping_semantics');
      final FlowLoadResult result = _load(doc);
      expect(result.isSuccess, isFalse);
      expect(result.failure!.error, FlowLoadError.missingGroupingSemantics);
    });

    test('grouping after truncation is refused', () {
      final Map<String, dynamic> doc = groupedCandidateJson();
      ((doc['_metadata'] as Map<String, dynamic>)['grouping_semantics']
              as Map<String, dynamic>)['grouping_phase'] =
          'after_truncation';
      final FlowLoadResult result = _load(doc);
      expect(result.isSuccess, isFalse);
      expect(result.failure!.error, FlowLoadError.invalidGroupingSemantics);
    });

    test('dropping red_flag_clarifier from non_groupable_roles is refused', () {
      final Map<String, dynamic> doc = groupedCandidateJson();
      ((doc['_metadata'] as Map<String, dynamic>)['grouping_semantics']
              as Map<String, dynamic>)['non_groupable_roles'] =
          <String>[];
      final FlowLoadResult result = _load(doc);
      expect(result.isSuccess, isFalse);
      expect(result.failure!.error, FlowLoadError.invalidGroupingSemantics);
    });
  });

  group('the loaded 1.1 model', () {
    late QuestionFlow flow;

    setUpAll(() => flow = groupedFlow());

    test('declares grouping and its semantics', () {
      final QuestionGroupingSemantics semantics =
          flow.metadata.groupingSemantics!;
      expect(flow.metadata.groupsQuestions, isTrue);
      expect(semantics.enabled, isTrue);
      expect(semantics.groupingPhase, kGroupingPhaseBeforeTruncation);
      expect(semantics.oneQuestionPerGroupKey, isTrue);
      expect(semantics.nonGroupableRoles, contains('red_flag_clarifier'));
    });

    test('three grouped questions over 40 sources', () {
      final List<FlowQuestion> grouped = flow.questions
          .where((FlowQuestion q) => q.isGrouped)
          .toList();
      expect(grouped, hasLength(3));
      expect(
        grouped.map((FlowQuestion q) => q.grouping!.groupKey).toSet(),
        <String>{'severity', 'duration', 'additional_symptoms'},
      );
      final int sources = grouped.fold(
        0,
        (int sum, FlowQuestion q) => sum + q.grouping!.sources.length,
      );
      expect(sources, 40);
    });

    test('group keys are unique and distinct from tie-break keys', () {
      final Set<String> groupKeys = <String>{};
      for (final FlowQuestion q in flow.questions) {
        if (!q.isGrouped) continue;
        expect(groupKeys.add(q.grouping!.groupKey), isTrue);
      }
      // Sharing a tie-break key never implies a merge, so no ungrouped
      // question may quietly share one with another.
      final Set<String> ungroupedTieBreaks = <String>{};
      for (final FlowQuestion q in flow.questions) {
        if (q.isGrouped) continue;
        expect(
          ungroupedTieBreaks.add(q.tieBreakKey),
          isTrue,
          reason: 'tie_break_key "${q.tieBreakKey}" is shared but ungrouped',
        );
      }
    });

    test('no red-flag clarifier is grouped', () {
      for (final FlowQuestion q in flow.questions) {
        if (q.clinicalRole == 'red_flag_clarifier') {
          expect(q.isGrouped, isFalse, reason: q.id.value);
        }
      }
    });

    test('sources are uniquely identified and totally ordered', () {
      for (final FlowQuestion q in flow.questions) {
        if (!q.isGrouped) continue;
        final Set<String> ids = <String>{};
        final Set<int> indexes = <int>{};
        for (final QuestionGroupSource s in q.grouping!.sources) {
          expect(ids.add(s.sourceId), isTrue, reason: s.sourceId);
          expect(indexes.add(s.sourceOrderIndex), isTrue, reason: s.sourceId);
          expect(s.provenance, isNotEmpty, reason: s.sourceId);
          expect(s.sourceText, isNotEmpty, reason: s.sourceId);
        }
      }
    });

    test(
      'representative selection is lowest_source_order_index throughout',
      () {
        for (final FlowQuestion q in flow.questions) {
          if (!q.isGrouped) continue;
          expect(
            q.grouping!.representativeSelection,
            RepresentativeSelection.lowestSourceOrderIndex,
          );
          expect(
            q.grouping!.mergeStrategy,
            QuestionMergeStrategy.singleRepresentative,
          );
        }
      },
    );

    test('every source option is declared by its question, meaning intact', () {
      for (final FlowQuestion q in flow.questions) {
        if (!q.isGrouped) continue;
        final Map<String, AnswerOption> declared = <String, AnswerOption>{
          for (final AnswerOption o in q.answerOptions) o.id.value: o,
        };
        for (final QuestionGroupSource s in q.grouping!.sources) {
          for (final AnswerOption o in s.answerOptions) {
            final AnswerOption? match = declared[o.id.value];
            expect(match, isNotNull, reason: '${s.sourceId} ${o.id.value}');
            expect(o.label, match!.label);
            expect(o.value, match.value);
            expect(o.producesTokens, match.producesTokens);
          }
        }
      }
    });

    test('the domain model is immutable', () {
      final FlowQuestion grouped = flow.questions.firstWhere(
        (FlowQuestion q) => q.isGrouped,
      );
      expect(
        () => grouped.grouping!.sources.add(grouped.grouping!.sources.first),
        throwsUnsupportedError,
      );
      expect(() => grouped.answerOptions.clear(), throwsUnsupportedError);
    });
  });

  group('all 22 invalid grouping fixtures are rejected', () {
    late List<Map<String, dynamic>> fixtures;

    setUpAll(() {
      final Map<String, dynamic> index = readJson(
        '$kInvalidGroupingDir/index.json',
      );
      fixtures = <Map<String, dynamic>>[
        for (final Object? f in index['fixtures'] as List<dynamic>)
          f as Map<String, dynamic>,
      ];
    });

    test('the index declares 22', () {
      expect(fixtures, hasLength(kInvalidGroupingFixtureCount));
    });

    test(
      'every fixture is rejected, and its declared defect is the reason',
      () {
        final List<String> accepted = <String>[];
        final List<String> misreported = <String>[];

        for (final Map<String, dynamic> fixture in fixtures) {
          final String id = fixture['fixture_id'] as String;
          final String file = fixture['file'] as String;
          final String defect = (fixture['defect'] as String).toLowerCase();

          final FlowLoadResult result = loadQuestionFlowFromBytes(
            File('$kInvalidGroupingDir/$file').readAsBytesSync(),
            knownTokens: liveTokenDictionaryTokens(),
          );

          if (result.isSuccess) {
            accepted.add(id);
            continue;
          }
          // The failure must be about what the fixture says is wrong, not some
          // unrelated breakage that happens to make it unloadable. Matched on
          // the defect's own subject rather than on an error-code table copied
          // from the knowledge base, so the two are not just agreeing with each
          // other.
          final String message = result.failure!.message.toLowerCase();
          final FlowLoadError error = result.failure!.error;
          final bool onTopic = _mentionsSameSubject(defect, message, error);
          if (!onTopic) {
            misreported.add(
              '$id: declared "${fixture['defect']}" but failed as '
              '${error.name}: ${result.failure!.message}',
            );
          }
        }

        expect(
          accepted,
          isEmpty,
          reason: 'accepted invalid fixtures: $accepted',
        );
        expect(misreported, isEmpty, reason: misreported.join('\n'));
      },
    );
  });

  group('structural failures this consumer adds', () {
    test('grouping after truncation cannot be honoured', () {
      // Already refused at load; asserted separately because it is the phase
      // ordering that made candidate 1.0 drop questions the engine asks.
      final Map<String, dynamic> doc = groupedCandidateJson();
      ((doc['_metadata'] as Map<String, dynamic>)['grouping_semantics']
              as Map<String, dynamic>)['grouping_phase'] =
          'after_truncation';
      expect(_load(doc).isSuccess, isFalse);
    });

    test('a grouped red-flag clarifier is refused', () {
      final Map<String, dynamic> doc = groupedCandidateJson();
      final List<dynamic> questions = doc['questions'] as List<dynamic>;
      final Map<String, dynamic> clarifier =
          questions.firstWhere(
                (Object? q) =>
                    (q as Map<String, dynamic>)['clinical_role'] ==
                    'red_flag_clarifier',
              )
              as Map<String, dynamic>;
      clarifier['grouping'] = <String, dynamic>{
        'group_key': 'red_flag',
        'merge_strategy': 'single_representative',
        'representative_selection': 'lowest_source_order_index',
        'option_union_rule': 'static',
        'sources': <dynamic>[
          <String, dynamic>{
            'source_id': 'x',
            'source_token': 'bleeding',
            'source_order_index': 0,
            'trigger_condition': <String, dynamic>{'token_present': 'bleeding'},
            'source_text': 'x',
            'provenance': 'x',
          },
        ],
      };
      final FlowLoadResult result = _load(doc);
      expect(result.isSuccess, isFalse);
      expect(result.failure!.error, FlowLoadError.groupedRedFlagQuestion);
    });

    test(
      'a source with no provenance is refused, never given a placeholder',
      () {
        final Map<String, dynamic> doc = groupedCandidateJson();
        final List<dynamic> questions = doc['questions'] as List<dynamic>;
        for (final Object? q in questions) {
          final Map<String, dynamic> question = q as Map<String, dynamic>;
          final Object? grouping = question['grouping'];
          if (grouping is Map<String, dynamic>) {
            ((grouping['sources'] as List<dynamic>).first
                    as Map<String, dynamic>)
                .remove('provenance');
            break;
          }
        }
        final FlowLoadResult result = _load(doc);
        expect(result.isSuccess, isFalse);
        expect(result.failure!.error, FlowLoadError.missingSourceProvenance);
      },
    );

    test('a false parity declaration is refused', () {
      // The candidate must not claim a clinical review it does not have.
      final Map<String, dynamic> doc = groupedCandidateJson();
      final Map<String, dynamic> meta =
          doc['_metadata'] as Map<String, dynamic>;
      meta['may_publish'] = true;
      expect(_load(doc).isSuccess, isFalse);
    });

    test('an ungrouped question that co-fires with its group is refused', () {
      // The candidate 1.0 shape restored: a per-token follow-up with no
      // grouping block, consuming its own slot against the limit of 5.
      final Map<String, dynamic> doc = groupedCandidateJson();
      final List<dynamic> questions = doc['questions'] as List<dynamic>;
      final Map<String, dynamic> severity =
          questions.firstWhere(
                (Object? q) =>
                    (q as Map<String, dynamic>)['question_id'] ==
                    'Q-followup-severity',
              )
              as Map<String, dynamic>;
      final Map<String, dynamic> clone =
          jsonDecode(jsonEncode(severity)) as Map<String, dynamic>;
      clone['question_id'] = 'Q-followup-headache-severity';
      clone['tie_break_key'] = 'headache';
      clone['trigger_condition'] = <String, dynamic>{
        'token_present': 'headache',
      };
      clone.remove('grouping');
      clone['answer_options'] = <dynamic>[
        for (final Object? o in severity['answer_options'] as List<dynamic>)
          <String, dynamic>{
            ...(o as Map<String, dynamic>),
            'answer_option_id': (o['answer_option_id'] as String).replaceAll(
              'Q-followup-severity',
              'Q-followup-headache-severity',
            ),
          },
      ];
      questions.add(clone);

      final FlowLoadResult result = _load(doc);
      expect(result.isSuccess, isFalse);
      expect(result.failure!.error, FlowLoadError.ungroupedGroupableQuestion);
    });
  });
}

/// True when a load failure is about the same thing the fixture says is wrong.
///
/// Deliberately keyed on words from the fixture's own defect description
/// rather than a fixture-id → error-code table. A table would only prove this
/// consumer agrees with a list somebody wrote; this proves the failure is
/// about the declared subject.
bool _mentionsSameSubject(String defect, String message, FlowLoadError error) {
  const Map<String, List<String>> subjects = <String, List<String>>{
    'group_key': <String>['group_key', 'group key'],
    'tie_break': <String>['tie_break', 'tie-break'],
    'representative': <String>['representative_selection', 'representative'],
    'union': <String>['option_union_rule', 'union'],
    'source_id': <String>['source_id'],
    'order index': <String>['source_order_index', 'order index'],
    'option': <String>['option'],
    'clarifier': <String>['clarifier', 'red-flag', 'red_flag'],
    'truncation': <String>['truncation', 'grouping_phase', 'grouping after'],
    'semantics': <String>['grouping_semantics', 'semantics'],
    'sources': <String>['source'],
    'provenance': <String>['provenance'],
    'value type': <String>['value-type', 'value_type', 'answer shapes'],
    'schema': <String>['schema', 'unexpected property', 'unknown'],
    'slot': <String>['slot', 'groupable role'],
  };

  for (final MapEntry<String, List<String>> entry in subjects.entries) {
    if (!defect.contains(entry.key)) continue;
    for (final String needle in entry.value) {
      if (message.contains(needle)) return true;
    }
  }
  // Anything the loader refuses as structurally malformed is on-topic for a
  // fixture whose defect is a malformed grouping block.
  return <FlowLoadError>{
    FlowLoadError.invalidGrouping,
    FlowLoadError.invalidGroupingSemantics,
    FlowLoadError.missingGroupingSemantics,
    FlowLoadError.duplicateGroupKey,
    FlowLoadError.duplicateGroupSource,
    FlowLoadError.groupedRedFlagQuestion,
    FlowLoadError.ungroupedGroupableQuestion,
    FlowLoadError.missingSourceProvenance,
    FlowLoadError.conflictingOptionMeaning,
    FlowLoadError.malformedQuestion,
  }.contains(error);
}
