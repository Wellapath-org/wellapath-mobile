/// Provenance and integrity constants for the vendored Question Flow **1.1**
/// grouping contract.
///
/// Every file under `test/fixtures/question_flow_v1_1/` is a byte-for-byte copy
/// from the knowledge base at the commit below. This file makes that
/// enforceable rather than a claim in a commit message.
///
/// Authoritative source:
///   repository : Wellapath-org/wellapath-knowledge-base
///   commit     : cffbe8a673c7a5be5dfb882cea77c1705c7515c3
///   PR         : #29, merged; final reviewed head 2defee9f
///
/// **The candidate is unpublished, clinically unreviewed and inactive.** It is
/// a test fixture, not a runtime artifact: it is not in `pubspec.yaml`, not in
/// `assets/`, and not referenced by any application screen.
///
/// Hashes here are FULL sha256 values taken from the knowledge base commit
/// objects, never abbreviated forms copied out of a report.
library;

const String kGroupingSourceRepository =
    'Wellapath-org/wellapath-knowledge-base';
const String kGroupingSourceCommit = 'cffbe8a673c7a5be5dfb882cea77c1705c7515c3';
const String kGroupingReviewedHead = '2defee9f9da86de87f936fab5775e3db62bfcd4d';

/// The Mobile commit whose `QuestionEngine.generateQuestions` produced the
/// captured oracle.
const String kOracleMobileSourceCommit =
    '657739cc1745104dd1194a57ef14cc9793c9b98e';
const String kOracleSourceSymbol = 'QuestionEngine.generateQuestions';

const String kGroupingFixtureRoot = 'test/fixtures/question_flow_v1_1';
const String kGroupingCandidatePath =
    '$kGroupingFixtureRoot/candidate/question_flow.ng.v1.1.json';
const String kGroupingSchemaPath =
    '$kGroupingFixtureRoot/schema/question_flow.v1_1.schema.json';
const String kOraclePath =
    '$kGroupingFixtureRoot/oracle/live_question_oracle_v1.json';
const String kOracleProvenancePath =
    '$kGroupingFixtureRoot/oracle/live_question_oracle_v1.provenance.json';
const String kGroupingPathFixturesPath =
    '$kGroupingFixtureRoot/paths/grouping_path_fixtures_v1_1.json';
const String kInvalidGroupingDir = '$kGroupingFixtureRoot/invalid_grouping';
const String kParityReportPath =
    '$kGroupingFixtureRoot/reports/question_grouping_parity_v1_1.json';
const String kCoverageReportPath =
    '$kGroupingFixtureRoot/reports/question_grouping_coverage_v1_1.json';
const String kNoClinicalChangeReportPath =
    '$kGroupingFixtureRoot/reports/question_no_clinical_change_v1_1.json';
const String kIm001ReviewReportPath =
    '$kGroupingFixtureRoot/reports/im001_product_review_v1_1.json';

/// Candidate 1.1 identity, asserted so a swap or version bump fails loudly.
const String kGroupingVersion = '1.1';
const String kGroupingSchemaVersion = '1.1';
const String kGroupingReleaseStatus = 'candidate_unapproved';
const String kGroupingClinicalReviewStatus = 'not_reviewed';

/// Authoritative controls from the knowledge base. Each is asserted rather
/// than assumed, so a truncated or substituted fixture cannot pass quietly.
const int kCandidate11Bytes = 155532;
const int kOracleBytes = 4231406;
const int kOracleTotalCases = 4625;
const int kOracleForwardCases = 2325;
const int kOracleReversedCases = 2300;
const int kInvalidGroupingFixtureCount = 22;
const int kGroupedPathFixtureCount = 16;
const int kPendingProductDecisions = 135;

/// Authoritative parity figures this consumer must independently reproduce.
const int kExpectedForwardMatches = 2325;
const int kExpectedLiveReversedInstability = 1680;
const int kExpectedCandidateReversedInstability = 0;

/// Live instability measured three ways. The knowledge base publishes the
/// WORDING figure (1,680); the other two are measured here and disclosed
/// because they are larger, not smaller.
///
/// The live engine appends additional-symptom options in tap order, so a path
/// can show identical wording with a different option order. Reporting only
/// the wording figure would understate how order-dependent the baseline is.
const int kLiveReversedOptionInstability = 1872;
const int kLiveReversedAnyInstability = 1887;
const int kLiveReversedOptionOnlyInstability = 207;

/// GF-008: captured paths presenting two or more clarifiers, and how many
/// candidate 1.0's ordering got wrong.
const int kGf008PathsWithTwoOrMoreClarifiers = 248;
const int kGf008PathsV10DifferedFromLive = 168;
const int kGf008PathsV11DifferedFromLive = 0;

/// Model-derived supplemental coverage. NOT captured Mobile output.
const int kModelDerivedPaths = 53130;

/// Candidate 1.0, which must remain byte-identical and loadable.
const String kCandidate10Sha =
    'c403648f8d4d80184879f4d467d4ae74e63df5be77c461298754b82737024998';
const String kSchema10Sha =
    '4b9f09384842968c2c093e2d4a1b246447eaef896980feff84da36d4fdbd4726';

class GroupingContractFile {
  const GroupingContractFile({
    required this.sourcePath,
    required this.destinationPath,
    required this.sha256,
    required this.bytes,
  });

  /// Path within the knowledge base at [kGroupingSourceCommit].
  final String sourcePath;

  /// Path within this repository, relative to [kGroupingFixtureRoot].
  final String destinationPath;

  final String sha256;
  final int bytes;
}

/// Every vendored 1.1 file, with the hash and byte count it must still have.
const List<GroupingContractFile>
kGroupingContractFiles = <GroupingContractFile>[
  GroupingContractFile(
    sourcePath: 'candidate/question_flow.ng.v1.1.json',
    destinationPath: 'candidate/question_flow.ng.v1.1.json',
    sha256: '3ea534b0797f382ec895e56accfd631d37fd61ae1bb2ecf173a666d5b888c02b',
    bytes: 155532,
  ),
  GroupingContractFile(
    sourcePath: 'docs/W3_QUESTION_GROUPING_CONTRACT.md',
    destinationPath: 'docs/W3_QUESTION_GROUPING_CONTRACT.md',
    sha256: '22339b20ce33320e124581c2f63e02ec0caa8ad758466446951154d2edf130ab',
    bytes: 14599,
  ),
  GroupingContractFile(
    sourcePath: 'mobile_handoff/question_flow_v1_1/README.md',
    destinationPath: 'handoff/README.md',
    sha256: '4f5207820c84bffa4fe0b850965c8a91c16ba44b2f3b205784732b8bddb4ea0f',
    bytes: 8832,
  ),
  GroupingContractFile(
    sourcePath:
        'mobile_handoff/question_flow_v1_1/question_grouping_types.dart',
    destinationPath: 'handoff/question_grouping_types.dart.txt',
    sha256: 'e729b46bd7e213d87260df76458032f5fa3211cfc16b23f264483a06c21a8b8d',
    bytes: 11712,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_clarifier_grouped.json',
    destinationPath: 'invalid_grouping/grouping_clarifier_grouped.json',
    sha256: 'b308002f377cd13dafa23a0aa0c4bf1b964a5999f30778af0d31cdb6f7356e62',
    bytes: 156682,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_clarifier_role_declared_groupable.json',
    destinationPath:
        'invalid_grouping/grouping_clarifier_role_declared_groupable.json',
    sha256: '1d17f4dd305e3e9819466e33449ea493781211e83e7ee6e123c16113b8d2217b',
    bytes: 156019,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_duplicate_group_key.json',
    destinationPath: 'invalid_grouping/grouping_duplicate_group_key.json',
    sha256: '3cedf83b39a314ea2bc7c5df5785e24f6fdbc0cce76cfa7eb12491601cee776e',
    bytes: 155997,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_duplicate_source_id.json',
    destinationPath: 'invalid_grouping/grouping_duplicate_source_id.json',
    sha256: '7f427801b3f2a849b61ae3933f7ba9c7deeff23bb8ebbdf33b0ff68f8abf7ec6',
    bytes: 155992,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_duplicate_source_order_index.json',
    destinationPath:
        'invalid_grouping/grouping_duplicate_source_order_index.json',
    sha256: 'b9f1da663f7351ff9cfba059e02e992bdf6341801bb58e1feead93eb4a9fc03a',
    bytes: 156015,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_empty_sources.json',
    destinationPath: 'invalid_grouping/grouping_empty_sources.json',
    sha256: 'ec9080ee662ed5b710e23e1f4dedbf13553afd4546f5815283ff6ca923cc49cb',
    bytes: 153471,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_group_can_yield_two_questions.json',
    destinationPath:
        'invalid_grouping/grouping_group_can_yield_two_questions.json',
    sha256: '5fc7ce0f95f481d7411060e0d7cb7a11575559b11df40fd655f47135821ca906',
    bytes: 156034,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_option_conflict_not_preserving.json',
    destinationPath:
        'invalid_grouping/grouping_option_conflict_not_preserving.json',
    sha256: '482e4e2e5077ee15e7c0ef53080172fcf740a019e2740831c1550d29b5595740',
    bytes: 155970,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_phase_after_truncation.json',
    destinationPath: 'invalid_grouping/grouping_phase_after_truncation.json',
    sha256: 'd11adbb65d18c64e108696aaf9a88b55632e27f84139961d5bdbe01f634865ef',
    bytes: 156028,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_semantics_absent.json',
    destinationPath: 'invalid_grouping/grouping_semantics_absent.json',
    sha256: '92f32505059bded4e126b1448c1d35c485c23317aa024d5931cb6c4690871eda',
    bytes: 155696,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_source_option_dropped.json',
    destinationPath: 'invalid_grouping/grouping_source_option_dropped.json',
    sha256: '0cdd067b8092f66c192ba9157e6fd6e95c7d2b33255e0f34a660083eae6e8a21',
    bytes: 154780,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_source_option_not_declared.json',
    destinationPath:
        'invalid_grouping/grouping_source_option_not_declared.json',
    sha256: 'd3373efc3c20b1aaabbe6cabeb0e4638e8c68aa5d959120955c44930a70bff92',
    bytes: 156384,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_source_option_relabelled.json',
    destinationPath: 'invalid_grouping/grouping_source_option_relabelled.json',
    sha256: 'a2ff4d0b48905f93adeff97b79e5ff4f7dfa1964a7a976a2c69ef0ab50b09f44',
    bytes: 156034,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_source_order_index_not_integer.json',
    destinationPath:
        'invalid_grouping/grouping_source_order_index_not_integer.json',
    sha256: '078f868d2921170cb27cc5832be524f7a907feebbc6543c41283daaaa3a9929f',
    bytes: 156029,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_source_triggers_outside_question.json',
    destinationPath:
        'invalid_grouping/grouping_source_triggers_outside_question.json',
    sha256: '46ebb496d83813e8947d50592d40483370dea9e64665d85a672e2234556e95b6',
    bytes: 156033,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_static_rule_with_source_options.json',
    destinationPath:
        'invalid_grouping/grouping_static_rule_with_source_options.json',
    sha256: '3cb5cda1425b441f0b4e2e19b559f4226f240485948f2e3125ccc2d8398af316',
    bytes: 156358,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_tie_break_key_reused_as_group_key.json',
    destinationPath:
        'invalid_grouping/grouping_tie_break_key_reused_as_group_key.json',
    sha256: '04e527876f8a152d687f3ccb01411076319216d4e7519c97cf019366dd0e3f7d',
    bytes: 156060,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_ungrouped_question_in_groupable_role.json',
    destinationPath:
        'invalid_grouping/grouping_ungrouped_question_in_groupable_role.json',
    sha256: '7674f9643914dcc9d864c626b1e06ae4abe3229e1f92eb62565db30a56cadfb4',
    bytes: 158400,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_unknown_field.json',
    destinationPath: 'invalid_grouping/grouping_unknown_field.json',
    sha256: '973d9bd79de4cf983f23bf514bc4a31dbaa7168d39090afeaf4dfd038c68fb29',
    bytes: 156043,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_unknown_option_union_rule.json',
    destinationPath: 'invalid_grouping/grouping_unknown_option_union_rule.json',
    sha256: '6e1a38d6234de4d2125660ae2277ed612f457f741fe58fc8c014176bdb380340',
    bytes: 156028,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_unknown_representative_selection.json',
    destinationPath:
        'invalid_grouping/grouping_unknown_representative_selection.json',
    sha256: 'b150664923dc33b53bb228fcb85369dfd55d40d11a7588ed7585cad95e4b73ba',
    bytes: 156035,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid_grouping/grouping_value_type_conflict_accepted.json',
    destinationPath:
        'invalid_grouping/grouping_value_type_conflict_accepted.json',
    sha256: '9e9fcbafa0d18db391c138a47319dfdf42d6e88d47c80b6c96445a78c1a161ca',
    bytes: 156042,
  ),
  GroupingContractFile(
    sourcePath: 'testing/questions/fixtures/invalid_grouping/index.json',
    destinationPath: 'invalid_grouping/index.json',
    sha256: '7e072484d9d55b67a56cf67da40e5349bf6a863891c823ca429f8865c1ff11b9',
    bytes: 8880,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/oracle/live_question_oracle_v1.harness.dart.txt',
    destinationPath: 'oracle/live_question_oracle_v1.harness.dart.txt',
    sha256: '13a5c322e29b1388348be7b877d0d8a6c07d35fbac595a041b04715069de80d1',
    bytes: 8455,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/oracle/live_question_oracle_v1.json',
    destinationPath: 'oracle/live_question_oracle_v1.json',
    sha256: '18c163067eb6ee8f0b436e2a46294570d2260ec673fc9e293b25efc89a14c0a1',
    bytes: 4231406,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/oracle/live_question_oracle_v1.provenance.json',
    destinationPath: 'oracle/live_question_oracle_v1.provenance.json',
    sha256: 'cfcdee7cfd5607bbd92291c5b17b9f36b9c0c4a9075eeddb19a3ed671188f915',
    bytes: 4741,
  ),
  GroupingContractFile(
    sourcePath:
        'testing/questions/fixtures/paths/grouping_path_fixtures_v1_1.json',
    destinationPath: 'paths/grouping_path_fixtures_v1_1.json',
    sha256: 'e3a51c55ff6ee325dbc76bfaff628614f7220b0e8c3b0019d40067a70e72aec1',
    bytes: 40060,
  ),
  GroupingContractFile(
    sourcePath: 'reports/im001_product_review_v1_1.json',
    destinationPath: 'reports/im001_product_review_v1_1.json',
    sha256: '4788fee0b6bcf764c22add101d9e4ea806c70a4119c73e6b16b2ebdd2d4324c2',
    bytes: 103154,
  ),
  GroupingContractFile(
    sourcePath: 'reports/question_grouping_coverage_v1_1.json',
    destinationPath: 'reports/question_grouping_coverage_v1_1.json',
    sha256: '9f0dd0f3b7286ff474ce7f4d5ebb894e0079b3e5ecf603fbf7f440395406e174',
    bytes: 2451,
  ),
  GroupingContractFile(
    sourcePath: 'reports/question_grouping_parity_v1_1.json',
    destinationPath: 'reports/question_grouping_parity_v1_1.json',
    sha256: 'e82e9baaa48013d0f95df24eddf574ab37c5383217d8fecc3646e3c48adb57e1',
    bytes: 4108,
  ),
  GroupingContractFile(
    sourcePath: 'reports/question_no_clinical_change_v1_1.json',
    destinationPath: 'reports/question_no_clinical_change_v1_1.json',
    sha256: 'cbaf08cadeb1e204c539e09272f2dbb8be9f159b47aac857a14ba65cf99e160e',
    bytes: 13128,
  ),
  GroupingContractFile(
    sourcePath: 'schema/question_flow.v1_1.schema.json',
    destinationPath: 'schema/question_flow.v1_1.schema.json',
    sha256: 'ef0372b572e0553d3b33ec8c10ea6468cb169a15887820a4f33fb53e507e1f43',
    bytes: 24307,
  ),
];
