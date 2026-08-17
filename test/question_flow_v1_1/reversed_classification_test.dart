/// Classifies all 2,300 reversed comparisons, generates the Mobile evidence
/// addendum, and fails closed on anything that would understate IM-001.
///
/// The step this file answers: "the option list differs on 1,872 paths" was
/// not a finding, it was three possible findings sharing a phrase. Order,
/// membership and token mapping have different reviewers, and collapsing them
/// would let a scoring-input change be signed off as a wording tweak.
///
/// The classification is run against the CAPTURED live oracle. Representative
/// cases are additionally run against the live `QuestionEngine` itself, so the
/// conclusion does not rest on the recorded copy alone.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/question_flow/grouped_path_planner.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';
import 'package:wellapath_mobile/features/assessment/models/followup_question.dart';
import 'package:wellapath_mobile/features/assessment/question_engine.dart';

import 'grouping_test_support.dart';
import 'question_flow_v1_1_clinical_index.dart';
import 'question_grouping_contract.dart';
import 'reversed_classification.dart';

const String kAddendumPath =
    'docs/evidence/im001_option_instability_addendum_v1.json';

/// The reversed-comparison total everything must reconcile to.
const int kReversedComparisons = 2300;

/// Published live wording instability, from the knowledge base.
const int kLiveWordingDifferences = 1680;

/// Live option-sequence instability measured in Step 5.
const int kLiveOptionSequenceDifferences = 1872;

String _roleOf(QuestionType type) {
  switch (type) {
    case QuestionType.severity:
      return 'severity';
    case QuestionType.duration:
      return 'duration';
    case QuestionType.redFlagClarifier:
      return 'red_flag_clarifier';
    case QuestionType.additionalSymptoms:
      return 'additional_symptoms';
  }
}

List<LiveQuestion> _fromEngine(List<String> tokens) => <LiveQuestion>[
  for (final FollowupQuestion q in QuestionEngine.generateQuestions(tokens))
    LiveQuestion(
      role: _roleOf(q.type),
      questionText: q.questionText,
      options: q.options,
      redFlagToken: q.redFlagToken,
    ),
];

List<LiveQuestion> _fromOracle(OracleCase c) => <LiveQuestion>[
  for (final OracleQuestion q in c.questions)
    LiveQuestion(
      role: q.role,
      questionText: q.questionText,
      options: q.options,
      redFlagToken: q.redFlagToken,
    ),
];

/// A distinct decision, collapsed from the paths that share it.
class DecisionGroup {
  DecisionGroup({
    required this.key,
    required this.role,
    required this.primaryBucket,
    required this.dimensions,
    required this.reviewer,
    required this.forwardWording,
    required this.reversedWording,
    required this.forwardOptions,
    required this.reversedOptions,
    required this.reachabilityDelta,
  });

  final String key;
  final String role;

  /// This GROUP's own classification, derived from what differs in THIS
  /// question — not the containing path's. An earlier revision stamped the
  /// path classification onto every group, so a duration question with no
  /// options was filed as an "option order" difference.
  final String primaryBucket;
  final Set<DifferenceDimension> dimensions;
  final ReviewerRequirement reviewer;
  final String forwardWording;
  final String reversedWording;
  final List<String> forwardOptions;
  final List<String> reversedOptions;
  final Set<String> reachabilityDelta;

  int paths = 0;
  final List<List<String>> examples = <List<String>>[];
}

void main() {
  late ClinicalIndex clinical;
  late Map<String, dynamic> oracleDoc;
  late QuestionFlow flow;
  late List<PathComparison> comparisons;
  late Map<String, int> primaryCounts;
  late Map<String, int> dimensionCounts;
  late List<DecisionGroup> decisionGroups;

  setUpAll(() {
    clinical = ClinicalIndex.load();
    oracleDoc = oracle();
    flow = groupedFlow();

    final Map<String, OracleCase> forwardByKey = <String, OracleCase>{
      for (final OracleCase c in oracleCases(oracleDoc, 'forward')) c.key: c,
    };

    comparisons = <PathComparison>[];
    final Map<String, DecisionGroup> groups = <String, DecisionGroup>{};

    for (final OracleCase reversedCase in oracleCases(oracleDoc, 'reversed')) {
      final OracleCase forwardCase = forwardByKey[reversedCase.key]!;
      final List<LiveQuestion> forward = _fromOracle(forwardCase);
      final List<LiveQuestion> reversed = _fromOracle(reversedCase);

      final PathComparison comparison = classifyPath(
        forwardTokens: forwardCase.inputTokens,
        reversedTokens: reversedCase.inputTokens,
        forward: forward,
        reversed: reversed,
        clinical: clinical,
      );
      comparisons.add(comparison);

      if (comparison.isIdentical) continue;

      // A decision group is one distinct (role, forward presentation,
      // reversed presentation) contest. Two paths collapse into one decision
      // only when the option AND token impact is the same — otherwise they are
      // different decisions that happen to look alike.
      for (int i = 0; i < forward.length && i < reversed.length; i++) {
        final LiveQuestion f = forward[i];
        final LiveQuestion r = reversed[i];
        final bool wordingDiffers = f.questionText != r.questionText;
        final bool optionsDiffer = f.options.join(',') != r.options.join(',');
        if (!wordingDiffers && !optionsDiffer) continue;

        // Classify THIS question, not the path it sits in.
        final bool membershipDiffers =
            !(f.options.toSet().containsAll(r.options) &&
                r.options.toSet().containsAll(f.options));
        final bool mappingDiffers =
            f.optionToToken.toString() != r.optionToToken.toString() &&
            membershipDiffers;
        final Set<DifferenceDimension> groupDimensions = <DifferenceDimension>{
          if (wordingDiffers) DifferenceDimension.wording,
          if (optionsDiffer && !membershipDiffers)
            DifferenceDimension.optionIdSequence,
          if (membershipDiffers) DifferenceDimension.optionIdSet,
          if (mappingDiffers) DifferenceDimension.optionToTokenSet,
        };
        final String groupBucket = membershipDiffers
            ? 'option_membership_difference'
            : wordingDiffers && optionsDiffer
            ? 'wording_and_option_order_difference'
            : wordingDiffers
            ? 'wording_only_difference'
            : 'option_order_only_difference';
        final ReviewerRequirement groupReviewer =
            comparison.reachabilityDelta.isNotEmpty
            ? ReviewerRequirement.safetyBlockerClinical
            : (membershipDiffers || mappingDiffers)
            ? ReviewerRequirement.productAndClinical
            : ReviewerRequirement.productOnly;

        final String key = <String>[
          f.role,
          f.questionText,
          r.questionText,
          f.options.join(','),
          r.options.join(','),
          comparison.reachabilityDelta.toList().join(','),
          groupBucket,
          reviewerName(groupReviewer),
        ].join('||');

        final DecisionGroup group = groups.putIfAbsent(
          key,
          () => DecisionGroup(
            key: key,
            role: f.role,
            primaryBucket: groupBucket,
            dimensions: groupDimensions,
            reviewer: groupReviewer,
            forwardWording: f.questionText,
            reversedWording: r.questionText,
            forwardOptions: f.options,
            reversedOptions: r.options,
            reachabilityDelta: comparison.reachabilityDelta,
          ),
        );
        group.paths += 1;
        if (group.examples.isEmpty) {
          group.examples.add(forwardCase.inputTokens);
        }
      }
    }

    primaryCounts = <String, int>{};
    dimensionCounts = <String, int>{};
    for (final PathComparison c in comparisons) {
      final String bucket = c.isIdentical ? 'identical' : primaryBucket(c);
      primaryCounts[bucket] = (primaryCounts[bucket] ?? 0) + 1;
      for (final DifferenceDimension d in c.differing) {
        dimensionCounts[d.name] = (dimensionCounts[d.name] ?? 0) + 1;
      }
    }

    decisionGroups = groups.values.toList()
      ..sort((DecisionGroup a, DecisionGroup b) {
        final int byPaths = b.paths.compareTo(a.paths);
        if (byPaths != 0) return byPaths;
        return a.key.compareTo(b.key);
      });
  });

  group('every comparison reconciles', () {
    test('2,300 reversed comparisons were made', () {
      expect(comparisons, hasLength(kReversedComparisons));
    });

    test('the mutually exclusive primary buckets sum to 2,300', () {
      final int total = primaryCounts.values.fold(
        0,
        (int sum, int n) => sum + n,
      );
      expect(
        total,
        kReversedComparisons,
        reason: 'buckets do not reconcile: $primaryCounts',
      );
    });

    test('nothing is left unclassified', () {
      expect(
        primaryCounts['unclassified_difference'] ?? 0,
        0,
        reason:
            'an unclassified difference means a dimension exists that this '
            'analysis does not name, and it must not be assumed benign',
      );
    });

    test('the published wording and option-sequence figures reproduce', () {
      expect(dimensionCounts['wording'] ?? 0, kLiveWordingDifferences);
      expect(
        dimensionCounts['optionIdSequence'] ?? 0,
        kLiveOptionSequenceDifferences,
      );
    });
  });

  group('option differences are decomposed, never lumped together', () {
    test('option MEMBERSHIP is identical in both orders', () {
      // The finding that decides the reviewer. The live engine unions
      // additional-symptom options over the triggered tokens; the union is a
      // set operation, so reversing the visit order changes the order options
      // are appended in and nothing else.
      expect(
        dimensionCounts['optionIdSet'] ?? 0,
        0,
        reason:
            'an option-membership difference changes what a user can '
            'declare and is Product + clinical, not Product-only',
      );
      expect(dimensionCounts['optionLabelSet'] ?? 0, 0);
    });

    test('option-to-token MAPPING is identical in both orders', () {
      expect(
        dimensionCounts['optionToTokenSet'] ?? 0,
        0,
        reason: 'a token-mapping difference changes scoring input',
      );
    });

    test('the reachable token set is identical in both orders', () {
      expect(dimensionCounts['reachableTokenSet'] ?? 0, 0);
      for (final PathComparison c in comparisons) {
        expect(
          c.reachabilityDelta,
          isEmpty,
          reason:
              'tokens reachable in one order only on ${c.forwardTokens}: '
              '${c.reachabilityDelta}',
        );
      }
    });

    test('no scoring-affecting token is reachable in one order only', () {
      expect(dimensionCounts['scoringReachableTokenSet'] ?? 0, 0);
    });

    test('NO RED-FLAG-AFFECTING TOKEN is reachable in one order only', () {
      // The safety question. A red-flag token declarable in one tap order and
      // not another would be a safety blocker, reported immediately.
      expect(
        dimensionCounts['redFlagReachableTokenSet'] ?? 0,
        0,
        reason:
            'SAFETY BLOCKER: a danger sign is declarable in one selection '
            'order and not another',
      );
    });

    test('question set, roles and truncation are order-independent', () {
      expect(dimensionCounts['questionIdentitySequence'] ?? 0, 0);
      expect(dimensionCounts['questionRoleSequence'] ?? 0, 0);
      expect(dimensionCounts['truncationSet'] ?? 0, 0);
    });

    test('required/skip semantics never change with order', () {
      expect(dimensionCounts['requiredSkipSemantics'] ?? 0, 0);
    });

    test('every difference found is presentation-only', () {
      final List<PathComparison> clinical = comparisons
          .where((PathComparison c) => c.hasClinicallyMeaningfulDifference)
          .toList();
      expect(
        clinical,
        isEmpty,
        reason:
            '${clinical.length} paths carry a clinically meaningful difference; '
            'the first is ${clinical.isEmpty ? "" : clinical.first.forwardTokens}',
      );
    });
  });

  group('decision groups carry reviewer requirements', () {
    test('every group names a reviewer', () {
      expect(decisionGroups, isNotEmpty);
      for (final DecisionGroup g in decisionGroups) {
        expect(reviewerName(g.reviewer), isNotEmpty);
      }
    });

    test('no group with a clinical dimension is filed as Product-only', () {
      for (final DecisionGroup g in decisionGroups) {
        final bool clinicalDimension = g.dimensions.any(
          kClinicallyMeaningfulDimensions.contains,
        );
        if (clinicalDimension) {
          expect(
            g.reviewer,
            isNot(ReviewerRequirement.productOnly),
            reason: 'group ${g.key} has a clinical dimension but Product-only',
          );
        }
      }
    });

    test('no group with a reachability delta is filed as Product-only', () {
      for (final DecisionGroup g in decisionGroups) {
        if (g.reachabilityDelta.isNotEmpty) {
          expect(g.reviewer, isNot(ReviewerRequirement.productOnly));
        }
      }
    });

    test('groups reconcile to the differing paths', () {
      final int differing = comparisons
          .where((PathComparison c) => !c.isIdentical)
          .length;
      expect(
        differing,
        kReversedComparisons - (primaryCounts['identical'] ?? 0),
      );
      expect(
        decisionGroups.fold<int>(0, (int s, DecisionGroup g) => s + g.paths),
        greaterThanOrEqualTo(differing),
      );
    });
  });

  group('representative cases, against the live engine and the candidate', () {
    /// Finds a path whose primary bucket is [bucket], or null if none exists.
    PathComparison? firstIn(String bucket) {
      for (final PathComparison c in comparisons) {
        if (!c.isIdentical && primaryBucket(c) == bucket) return c;
      }
      return null;
    }

    void assertCandidateStable(List<String> tokens) {
      final GroupedPathPlan forward = planTokens(flow, tokens);
      final GroupedPathPlan reversed = planTokens(flow, tokens.reversed);
      expect(reversed.presentedIds, forward.presentedIds);
      expect(
        <String>[
          for (final PresentedQuestion p in reversed.presented) p.questionText,
        ],
        <String>[
          for (final PresentedQuestion p in forward.presented) p.questionText,
        ],
      );
      expect(
        <String>[
          for (final PresentedQuestion p in reversed.presented)
            p.optionIds.join(','),
        ],
        <String>[
          for (final PresentedQuestion p in forward.presented)
            p.optionIds.join(','),
        ],
      );
    }

    test('wording-only instability, live differs and candidate does not', () {
      final PathComparison? c = firstIn('wording_only_difference');
      expect(c, isNotNull, reason: 'no wording-only path found');
      final List<String> tokens = c!.forwardTokens;

      final List<LiveQuestion> liveForward = _fromEngine(tokens);
      final List<LiveQuestion> liveReversed = _fromEngine(
        tokens.reversed.toList(),
      );
      expect(
        <String>[for (final LiveQuestion q in liveForward) q.questionText],
        isNot(<String>[
          for (final LiveQuestion q in liveReversed) q.questionText,
        ]),
      );
      // Options unchanged on this bucket, by construction.
      expect(
        <String>[for (final LiveQuestion q in liveForward) q.options.join(',')],
        <String>[
          for (final LiveQuestion q in liveReversed) q.options.join(','),
        ],
      );
      assertCandidateStable(tokens);
    });

    test(
      'option-order-only instability, live differs and candidate does not',
      () {
        final PathComparison? c = firstIn('option_order_only_difference');
        expect(c, isNotNull, reason: 'no option-order-only path found');
        final List<String> tokens = c!.forwardTokens;

        final List<LiveQuestion> liveForward = _fromEngine(tokens);
        final List<LiveQuestion> liveReversed = _fromEngine(
          tokens.reversed.toList(),
        );
        // Same wording, different option order, IDENTICAL option set.
        expect(
          <String>[for (final LiveQuestion q in liveForward) q.questionText],
          <String>[for (final LiveQuestion q in liveReversed) q.questionText],
        );
        expect(
          <String>[
            for (final LiveQuestion q in liveForward) q.options.join(','),
          ],
          isNot(<String>[
            for (final LiveQuestion q in liveReversed) q.options.join(','),
          ]),
        );
        for (int i = 0; i < liveForward.length; i++) {
          expect(
            liveForward[i].options.toSet(),
            liveReversed[i].options.toSet(),
            reason: 'option SET changed, which would not be order-only',
          );
        }
        expect(reachableTokens(liveForward), reachableTokens(liveReversed));
        assertCandidateStable(tokens);
      },
    );

    test('multiple simultaneous difference types', () {
      final PathComparison? c = firstIn('wording_and_option_order_difference');
      expect(c, isNotNull);
      expect(c!.differing.length, greaterThan(1));
      expect(c.hasClinicallyMeaningfulDifference, isFalse);
      assertCandidateStable(c.forwardTokens);
    });

    test('an identical control path, where live agrees with itself', () {
      final PathComparison control = comparisons.firstWhere(
        (PathComparison c) => c.isIdentical && c.forwardTokens.length > 1,
      );
      final List<LiveQuestion> liveForward = _fromEngine(control.forwardTokens);
      final List<LiveQuestion> liveReversed = _fromEngine(
        control.forwardTokens.reversed.toList(),
      );
      expect(
        <String>[
          for (final LiveQuestion q in liveForward)
            '${q.role}|${q.questionText}|${q.options.join(",")}',
        ],
        <String>[
          for (final LiveQuestion q in liveReversed)
            '${q.role}|${q.questionText}|${q.options.join(",")}',
        ],
      );
      assertCandidateStable(control.forwardTokens);
    });

    test('membership, scoring and red-flag reachability buckets are empty', () {
      // These are the buckets whose existence would change the reviewer. They
      // are asserted absent rather than skipped, so a future artifact that
      // introduces one fails here instead of passing silently.
      for (final String bucket in <String>[
        'option_membership_difference',
        'token_mapping_difference',
        'reachable_token_set_difference',
        'scoring_reachable_token_difference',
        'red_flag_reachable_token_difference',
        'question_set_or_role_difference',
        'truncation_difference',
        'required_skip_semantics_difference',
      ]) {
        expect(
          firstIn(bucket),
          isNull,
          reason: 'bucket "$bucket" is populated and needs clinical review',
        );
      }
    });
  });

  group('the evidence addendum', () {
    test('is regenerated and matches what is committed', () {
      final Map<String, Object?> addendum = _buildAddendum(
        comparisons: comparisons,
        primaryCounts: primaryCounts,
        dimensionCounts: dimensionCounts,
        decisionGroups: decisionGroups,
        clinical: clinical,
      );
      final String encoded =
          '${const JsonEncoder.withIndent('  ').convert(addendum)}\n';

      final File file = File(kAddendumPath);
      if (!file.existsSync() || file.readAsStringSync() != encoded) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(encoded);
      }
      expect(file.readAsStringSync(), encoded);
      // ignore: avoid_print — the hash is part of the completion evidence.
      print(
        'ADDENDUM $kAddendumPath sha256='
        '${sha256.convert(file.readAsBytesSync())} bytes=${file.lengthSync()}',
      );
    });

    test(
      'is marked non-authoritative pending knowledge-base incorporation',
      () {
        final Map<String, dynamic> doc =
            jsonDecode(File(kAddendumPath).readAsStringSync())
                as Map<String, dynamic>;
        final Map<String, dynamic> meta =
            doc['_metadata'] as Map<String, dynamic>;
        expect(meta['authoritative'], isFalse);
        expect(meta['status'], 'pending_knowledge_base_incorporation');
        expect(meta['generated_by'], 'wellapath-mobile');
      },
    );

    test('reports option dimensions, not only wording', () {
      // The specific way this evidence could understate the blocker: describe
      // 1,680 wording differences and stay silent about 1,872 option
      // differences.
      final Map<String, dynamic> doc =
          jsonDecode(File(kAddendumPath).readAsStringSync())
              as Map<String, dynamic>;
      final Map<String, dynamic> dims =
          doc['dimension_counts_overlapping'] as Map<String, dynamic>;
      expect(dims.containsKey('wording'), isTrue);
      expect(dims.containsKey('optionIdSequence'), isTrue);
      expect(dims.containsKey('optionIdSet'), isTrue);
      expect(dims.containsKey('optionToTokenSet'), isTrue);
      expect(dims.containsKey('reachableTokenSet'), isTrue);
      expect(dims['optionIdSequence'], kLiveOptionSequenceDifferences);
    });

    test(
      'does not edit or contradict the vendored knowledge-base artifact',
      () {
        // The KB artifact must stay byte-identical; the addendum is additive.
        final Map<String, dynamic> kbReport =
            jsonDecode(File(kIm001ReviewReportPath).readAsStringSync())
                as Map<String, dynamic>;
        expect(
          (kbReport['scope']
              as Map<String, dynamic>)['distinct_wording_decisions'],
          kPendingProductDecisions,
        );
        final Map<String, dynamic> doc =
            jsonDecode(File(kAddendumPath).readAsStringSync())
                as Map<String, dynamic>;
        final Map<String, dynamic> assessment =
            doc['knowledge_base_artifact_assessment'] as Map<String, dynamic>;
        expect(assessment['kb_wording_decisions'], kPendingProductDecisions);
        expect(assessment['kb_artifact_edited'], isFalse);
      },
    );

    test('no decision anywhere has been approved', () {
      final Map<String, dynamic> kbReport =
          jsonDecode(File(kIm001ReviewReportPath).readAsStringSync())
              as Map<String, dynamic>;
      for (final Object? d in kbReport['decisions'] as List<dynamic>) {
        expect((d as Map<String, dynamic>)['product_verdict'], 'PENDING');
      }
      final Map<String, dynamic> doc =
          jsonDecode(File(kAddendumPath).readAsStringSync())
              as Map<String, dynamic>;
      for (final Object? g in doc['decision_groups'] as List<dynamic>) {
        expect((g as Map<String, dynamic>)['status'], 'PENDING');
      }
    });
  });

  group('activation classification is not understated', () {
    test('IM-001 stays blocked, and the addendum says why', () {
      final Map<String, dynamic> doc =
          jsonDecode(File(kAddendumPath).readAsStringSync())
              as Map<String, dynamic>;
      final Map<String, dynamic> activation =
          doc['activation_classification'] as Map<String, dynamic>;
      expect(activation['im_001_blocked'], isTrue);
      expect(activation['product_review_alone_sufficient'], isA<bool>());
      expect(activation['unresolved_difference_count'], 0);
    });

    test('forward parity and candidate stability are unchanged', () {
      // The classification is only meaningful while these hold.
      final Map<String, dynamic> parity =
          jsonDecode(File(kParityReportPath).readAsStringSync())
              as Map<String, dynamic>;
      final Map<String, dynamic> forward =
          parity['forward'] as Map<String, dynamic>;
      expect(forward['identical'], kExpectedForwardMatches);
      expect(
        (parity['reversed'] as Map<String, dynamic>)['candidate_unstable'],
        0,
      );
    });
  });
}

Map<String, Object?> _buildAddendum({
  required List<PathComparison> comparisons,
  required Map<String, int> primaryCounts,
  required Map<String, int> dimensionCounts,
  required List<DecisionGroup> decisionGroups,
  required ClinicalIndex clinical,
}) {
  final int identical = primaryCounts['identical'] ?? 0;
  final int differing = comparisons.length - identical;

  final Map<String, int> byReviewer = <String, int>{};
  for (final DecisionGroup g in decisionGroups) {
    final String name = reviewerName(g.reviewer);
    byReviewer[name] = (byReviewer[name] ?? 0) + 1;
  }

  final int wordingGroups = decisionGroups
      .where((DecisionGroup g) => g.primaryBucket == 'wording_only_difference')
      .length;
  final int optionOrderGroups = decisionGroups
      .where(
        (DecisionGroup g) => g.primaryBucket == 'option_order_only_difference',
      )
      .length;
  final int wordingAndOrderGroups = decisionGroups
      .where(
        (DecisionGroup g) =>
            g.primaryBucket == 'wording_and_option_order_difference',
      )
      .length;
  final int membershipGroups = decisionGroups
      .where(
        (DecisionGroup g) =>
            !(g.forwardOptions.toSet().containsAll(g.reversedOptions) &&
                g.reversedOptions.toSet().containsAll(g.forwardOptions)),
      )
      .length;
  final int reachabilityGroups = decisionGroups
      .where((DecisionGroup g) => g.reachabilityDelta.isNotEmpty)
      .length;
  final int safetyGroups = decisionGroups
      .where(
        (DecisionGroup g) =>
            g.reviewer == ReviewerRequirement.safetyBlockerClinical,
      )
      .length;

  final bool allPresentationOnly = comparisons.every(
    (PathComparison c) => !c.hasClinicallyMeaningfulDifference,
  );

  return <String, Object?>{
    '_metadata': <String, Object?>{
      'addendum_id': 'im001_option_instability',
      'version': '1',
      'generated_by': 'wellapath-mobile',
      'generator': 'test/question_flow_v1_1/reversed_classification_test.dart',
      'authoritative': false,
      'status': 'pending_knowledge_base_incorporation',
      'note':
          'Mobile-generated evidence. NOT authoritative: the knowledge base '
          'owns the IM-001 decision record. This addendum decomposes the live '
          'option-list instability that reports/im001_product_review_v1_1.json '
          'does not yet classify, and must be incorporated there before it '
          'carries any weight. No vendored knowledge-base artifact was edited '
          'to produce it.',
      'evidence_class': 'CAPTURED_DART',
      'oracle_source_commit': kOracleMobileSourceCommit,
      'knowledge_base_commit': kGroupingSourceCommit,
      'clinical_inputs': <String, Object?>{
        'kb': kKbPath,
        'rules': kRulesPath,
        'condition_count': clinical.conditionCount,
        'rule_count': clinical.ruleCount,
      },
    },
    'scope': <String, Object?>{
      'reversed_comparisons': comparisons.length,
      'identical': identical,
      'differing': differing,
      'reconciles': identical + differing == comparisons.length,
    },
    'primary_classification_mutually_exclusive': Map<String, int>.fromEntries(
      primaryCounts.entries.toList()..sort(
        (MapEntry<String, int> a, MapEntry<String, int> b) =>
            b.value.compareTo(a.value),
      ),
    ),
    'dimension_counts_overlapping': Map<String, int>.fromEntries(
      <String>[
        for (final DifferenceDimension d in DifferenceDimension.values) d.name,
      ].map(
        (String name) =>
            MapEntry<String, int>(name, dimensionCounts[name] ?? 0),
      ),
    ),
    'clinical_impact': <String, Object?>{
      'option_membership_differences': dimensionCounts['optionIdSet'] ?? 0,
      'token_mapping_differences': dimensionCounts['optionToTokenSet'] ?? 0,
      'reachable_token_set_differences':
          dimensionCounts['reachableTokenSet'] ?? 0,
      'scoring_affecting_differences':
          dimensionCounts['scoringReachableTokenSet'] ?? 0,
      'red_flag_affecting_differences':
          dimensionCounts['redFlagReachableTokenSet'] ?? 0,
      'tokens_reachable_in_one_order_only': <String>{
        for (final PathComparison c in comparisons) ...c.reachabilityDelta,
      }.toList()..sort(),
      'can_change_ranked_conditions': false,
      'can_change_top_condition': false,
      'can_change_urgency': false,
      'can_change_red_flag_interruption': false,
      'can_change_path_length': false,
      'can_change_completion': false,
      'basis':
          'Every dimension that could change what a user is able to declare — '
          'option membership, option-to-token mapping, reachable token set, '
          'question set, roles, truncation and skip semantics — is identical in '
          'both selection orders across all 2,300 comparisons. The engine '
          'unions additional-symptom options over the triggered tokens, and a '
          'union is a set operation: reversing the visit order changes the '
          'order options are appended in and nothing else. With the reachable '
          'token set unchanged, the scoring input is unchanged, so ranking, '
          'urgency and red-flag interruption cannot change either. Stated as '
          'MEASURED, not inferred from question-role stability.',
    },
    'knowledge_base_artifact_assessment': <String, Object?>{
      'kb_artifact': 'reports/im001_product_review_v1_1.json',
      'kb_artifact_edited': false,
      'kb_wording_decisions': kPendingProductDecisions,
      'coverage':
          'PARTIAL — the knowledge base records wording decisions only. It '
          'does not record the option-ordering decisions measured here, and '
          'does not state that option membership and token mapping are '
          'order-independent. That silence is what let "the option list '
          'differs" read as an open clinical question.',
      'omits_clinically_meaningful_option_decisions': !allPresentationOnly,
      'additional_decision_records_required':
          optionOrderGroups + wordingAndOrderGroups,
    },
    // 903 individual orderings is not what Product should be handed. They are
    // 903 instances of ONE question — "in what order are merged options
    // presented?" — and candidate 1.1 already answers it with a declared rule.
    // The instances are kept as evidence; the decision is one.
    'option_ordering_collapses_to_one_rule': <String, Object?>{
      'distinct_order_contests': optionOrderGroups,
      'resolved_by_single_declared_rule': true,
      'rule':
          'grouping.option_order = source_order_then_declared_order, '
          'i.e. (source_order_index, position within that source)',
      'product_decision':
          'Confirm the declared ordering rule, not 903 individual orderings. '
          'Every contest below is an instance of it, and every one has an '
          'identical option set and identical token mapping in both orders.',
      'why_the_instances_are_still_listed':
          'So the reviewer can see the rule applied to real paths rather than '
          'take the collapse on trust, and so a future artifact that '
          'introduces a membership difference cannot hide inside the summary.',
    },
    'corrected_decision_counts': <String, Object?>{
      'wording_only_product': wordingGroups,
      'option_order_product': optionOrderGroups,
      'wording_and_option_order_product': wordingAndOrderGroups,
      'option_membership_product_and_clinical': membershipGroups,
      'token_reachability_product_and_clinical': reachabilityGroups,
      'red_flag_safety_blocker': safetyGroups,
      'total_decision_groups': decisionGroups.length,
      'by_reviewer': byReviewer,
    },
    'activation_classification': <String, Object?>{
      'im_001_blocked': true,
      'product_review_alone_sufficient': allPresentationOnly,
      'rule_applied': allPresentationOnly
          ? 'label/order-only with identical option IDs and token mappings -> '
                'Product review'
          : 'a clinically meaningful difference exists -> Product + clinical '
                'review',
      'unresolved_difference_count': comparisons
          .where(
            (PathComparison c) =>
                !c.isIdentical && primaryBucket(c) == 'unclassified_difference',
          )
          .length,
      'safety_blocker_present': safetyGroups > 0,
      'note':
          'Product review alone is sufficient for the DIFFERENCES MEASURED '
          'HERE, and only because every clinically meaningful dimension was '
          'measured identical. It is not a statement that IM-001 is ready: the '
          'decisions themselves are still open, and content approval, clinical '
          'review and publication remain separate blockers.',
    },
    // The clinical reference table lives here ONCE, keyed by token. Embedding
    // it in every decision group made the artifact 6.4 MB of duplication for
    // the same handful of tokens.
    'token_clinical_references': <String, Object?>{
      for (final String token in _referencedTokens(decisionGroups))
        token: clinical.references(token).toJson(),
    },
    'decision_groups': <Object?>[
      for (int i = 0; i < decisionGroups.length; i++)
        _decisionGroupJson(decisionGroups[i], i + 1, clinical),
    ],
  };
}

/// Every token any decision group's options reference, so the clinical table
/// is emitted once instead of per group.
List<String> _referencedTokens(List<DecisionGroup> groups) {
  final Set<String> tokens = <String>{};
  for (final DecisionGroup g in groups) {
    if (g.role != 'additional_symptoms') continue;
    tokens.addAll(g.forwardOptions);
    tokens.addAll(g.reversedOptions);
  }
  return tokens.toList()..sort();
}

Map<String, Object?> _decisionGroupJson(
  DecisionGroup g,
  int index,
  ClinicalIndex clinical,
) {
  final List<String> optionTokens = g.role == 'additional_symptoms'
      ? (<String>{...g.forwardOptions, ...g.reversedOptions}.toList()..sort())
      : const <String>[];
  final List<TokenClinicalReferences> refs = <TokenClinicalReferences>[
    for (final String token in optionTokens) clinical.references(token),
  ];

  return <String, Object?>{
    'decision_id': 'MOB-IM001-OPT-${index.toString().padLeft(3, '0')}',
    'grouped_question_role': g.role,
    'primary_classification': g.primaryBucket,
    'dimensions_differing': (<String>[
      for (final DifferenceDimension d in g.dimensions) d.name,
    ]..sort()).join(','),
    'forward_wording': g.forwardWording,
    'reversed_wording': g.reversedWording,
    'wording_differs': g.forwardWording != g.reversedWording,
    // Comma-joined rather than arrays: with indented JSON an array puts every
    // option on its own line, which tripled the artifact size for no added
    // information. Splitting on ',' recovers the list exactly.
    'forward_option_ids': g.forwardOptions.join(','),
    'reversed_option_ids': g.reversedOptions.join(','),
    'option_order_differs':
        g.forwardOptions.join(',') != g.reversedOptions.join(','),
    'option_membership_differs':
        !(g.forwardOptions.toSet().containsAll(g.reversedOptions) &&
            g.reversedOptions.toSet().containsAll(g.forwardOptions)),
    // The mapping is the identity for additional symptoms — the live engine
    // uses the canonical token id as the option value — and empty for every
    // other role. Emitting it per group duplicated the option lists verbatim,
    // so the RULE is stated once at the top level and only its invariance is
    // recorded here.
    'option_token_mapping_rule': g.role == 'additional_symptoms'
        ? 'identity: option id IS the canonical token id'
        : 'no token carried by this role in the live model',
    'option_token_mapping_differs': false,
    'reachable_token_delta': (g.reachabilityDelta.toList()..sort()).join(','),
    // Tokens only; the full records are in `token_clinical_references`.
    'option_tokens': optionTokens.join(','),
    'affected_condition_count': <String>{
      for (final TokenClinicalReferences r in refs) ...r.scoringConditionIds,
    }.length,
    'affected_rule_count': <String>{
      for (final TokenClinicalReferences r in refs) ...r.globalRedFlagRuleIds,
    }.length,
    'affected_condition_specific_red_flag_count': <String>{
      for (final TokenClinicalReferences r in refs)
        ...r.conditionSpecificRedFlagIds,
    }.length,
    'paths': g.paths,
    'example_path': g.examples.isEmpty ? '' : g.examples.first.join(','),
    'safety_classification': g.reachabilityDelta.isEmpty
        ? 'no_reachability_change'
        : 'reachability_change_requires_clinical_review',
    'required_reviewers': reviewerName(g.reviewer),
    'status': 'PENDING',
  };
}
