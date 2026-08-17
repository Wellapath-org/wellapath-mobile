/// Provenance and integrity constants for the vendored Question Flow 1.0
/// contract.
///
/// Every file under `test/fixtures/question_flow/` is a byte-for-byte copy
/// from the knowledge base at the commit below. This file makes that
/// enforceable rather than a claim in a commit message.
///
/// Authoritative source:
///   repository : Wellapath-org/wellapath-knowledge-base
///   commit     : aa7a2f13c577ea23f78235d9d8585416bd07f9de
///
/// **The candidate is unpublished, clinically unreviewed and inactive.** It is
/// a test fixture, not a runtime artifact: it is not in `pubspec.yaml`, not in
/// `assets/`, and not referenced by any application screen.
library;

const String kFlowSourceRepository = 'Wellapath-org/wellapath-knowledge-base';
const String kFlowSourceCommit = 'aa7a2f13c577ea23f78235d9d8585416bd07f9de';

const String kFlowFixtureRoot = 'test/fixtures/question_flow';
const String kFlowCandidatePath =
    '$kFlowFixtureRoot/candidate/question_flow.ng.v1.0.json';

/// Candidate identity, asserted so a swap or a version bump fails loudly.
const String kFlowVersion = '1.0';
const String kFlowSchemaVersion = '1.0';
const String kFlowReleaseStatus = 'candidate_unapproved';
const String kFlowClinicalReviewStatus = 'not_reviewed';
const int kFlowQuestionCount = 50;
const int kFlowAnswerOptionCount = 300;
const int kFlowPathLimit = 5;
const int kFlowOptionalSkipCount = 0;

/// The frozen clinical inputs the candidate was projected against.
const String kLiveTokenDictionarySha =
    '0cc47ad9537c0bd4c6ef3aec8f1931eb9b4c62103a8809d16544f94a90b5c019';

class FlowContractFile {
  const FlowContractFile({
    required this.sourcePath,
    required this.destinationPath,
    required this.sha256,
    required this.bytes,
  });

  final String sourcePath;
  final String destinationPath;
  final String sha256;
  final int bytes;
}

/// Every vendored file, with the hash and byte count it must still have.
const List<FlowContractFile> kFlowContractFiles = <FlowContractFile>[
  FlowContractFile(
    sourcePath: 'candidate/question_flow.ng.v1.0.json',
    destinationPath: 'candidate/question_flow.ng.v1.0.json',
    sha256: 'c403648f8d4d80184879f4d467d4ae74e63df5be77c461298754b82737024998',
    bytes: 177357,
  ),
  FlowContractFile(
    sourcePath: 'docs/W3_QUESTION_FLOW_CONTRACT.md',
    destinationPath: 'docs/W3_QUESTION_FLOW_CONTRACT.md',
    sha256: '63cacb199a4864a1dbf5cef03e57413636975ff3ecc202dd5611a6423f224ffa',
    bytes: 16145,
  ),
  FlowContractFile(
    sourcePath: 'mobile_handoff/question_flow_v1/README.md',
    destinationPath: 'handoff/README.md',
    sha256: 'deec14f79801646a882fc1eaac73a87500c0e82a6ba7661f1ad4424d88b8526b',
    bytes: 8159,
  ),
  FlowContractFile(
    sourcePath: 'mobile_handoff/question_flow_v1/question_flow_types.dart',
    destinationPath: 'handoff/question_flow_types.dart.txt',
    sha256: '4576fb2277d50a2b6bed445a4be4547a615629b8f8bb7b3c82831fc932fba53a',
    bytes: 13751,
  ),
  FlowContractFile(
    sourcePath: 'testing/questions/fixtures/invalid/branch_cycle.json',
    destinationPath: 'invalid/branch_cycle.json',
    sha256: '722728031664399bb5f6cc47e695f0359ad07dd94d027634a20516b22e4adec2',
    bytes: 177737,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/candidate_marked_publishable.json',
    destinationPath: 'invalid/candidate_marked_publishable.json',
    sha256: '0d612135262afaede83cb66948a9721e338a4f0f0944a3372c8a42c80ff7c6dc',
    bytes: 177517,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/condition_type_mismatch.json',
    destinationPath: 'invalid/condition_type_mismatch.json',
    sha256: 'a3372dd24c959d60450b77a10520d986067c3534e77ca6ff037f7d9ffb2f0f8a',
    bytes: 177514,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/content_marked_approved_without_review.json',
    destinationPath: 'invalid/content_marked_approved_without_review.json',
    sha256: '0ac02ecf997aa6aee2aa82f590de6f0b6819fa67f81e579fd3750e029f75db8a',
    bytes: 177530,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/contradictory_condition.json',
    destinationPath: 'invalid/contradictory_condition.json',
    sha256: '7306d6cc6c9f85571d048a80a07b01e937600a490f1a8326a73b5b4f7aa6d8ca',
    bytes: 177625,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/duplicate_answer_option_id.json',
    destinationPath: 'invalid/duplicate_answer_option_id.json',
    sha256: '16bfa47831b1a79b75f4af7cbc4f25b447f134984dc43da9712c60fd89c5dac9',
    bytes: 177773,
  ),
  FlowContractFile(
    sourcePath: 'testing/questions/fixtures/invalid/duplicate_question_id.json',
    destinationPath: 'invalid/duplicate_question_id.json',
    sha256: '57f52da0f6de67092be20e6e59afb424f21112275bdf3def428a61c258a5320b',
    bytes: 179050,
  ),
  FlowContractFile(
    sourcePath: 'testing/questions/fixtures/invalid/index.json',
    destinationPath: 'invalid/index.json',
    sha256: 'c3973ab28c7b1087e29a3d083accecc5dd9b63a7e56a240650aea65a8a1cd8c7',
    bytes: 3547,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/invalid_condition_operator.json',
    destinationPath: 'invalid/invalid_condition_operator.json',
    sha256: '239f4b80e73f35e02c92d4f341dcf0c3fa7ed31220a50a08c2ed4f34df2ab0aa',
    bytes: 177538,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/invalid_edit_dependency.json',
    destinationPath: 'invalid/invalid_edit_dependency.json',
    sha256: '7d023056767fe77d7d9d29953471b9574be1bf0a0c6c068d7dfdfa4212d49625',
    bytes: 177495,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/nondeterministic_priority_tie.json',
    destinationPath: 'invalid/nondeterministic_priority_tie.json',
    sha256: '3a5f805c1b53710453e7a08493fffd12b0f75eb084910c496146d84d8d765bd8',
    bytes: 177504,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/path_limit_starves_ordinary_questions.json',
    destinationPath: 'invalid/path_limit_starves_ordinary_questions.json',
    sha256: '50ae2e8b04c30539f1b5d4b7b00f705ed9405daa404e74dea5abb162eca5a901',
    bytes: 177509,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/published_without_clinical_review.json',
    destinationPath: 'invalid/published_without_clinical_review.json',
    sha256: 'd9c229f62e2577041adc0b80b004207193d9470614dbbfb7b75f2da3b8de6b07',
    bytes: 177508,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/red_flag_impact_understated.json',
    destinationPath: 'invalid/red_flag_impact_understated.json',
    sha256: 'a623be3a02c558a2203f444fcbb59dafa763f8789dcf3a62962fe33476345ddb',
    bytes: 177507,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/red_flag_question_behind_ordinary.json',
    destinationPath: 'invalid/red_flag_question_behind_ordinary.json',
    sha256: '4ba066dfdb909cfd365e12bc3dff646650f79b4ef44a675d7d6dbc1780084879',
    bytes: 177535,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/red_flag_question_not_evaluated_immediately.json',
    destinationPath: 'invalid/red_flag_question_not_evaluated_immediately.json',
    sha256: '3001d47df7375911e55d679d82dc5f091bfc70924a484e2f86bb92aff56ee19e',
    bytes: 177549,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/red_flag_truncation_not_exempt.json',
    destinationPath: 'invalid/red_flag_truncation_not_exempt.json',
    sha256: '0628573d0f8594f36d33f9aeb174a43190ea48a86b04a0f690d04533f2859a0b',
    bytes: 177513,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/required_question_silently_skippable.json',
    destinationPath: 'invalid/required_question_silently_skippable.json',
    sha256: '8203b97747f5d681a0c0eaabe970abd05eca5401900ce7f09578b54d519374af',
    bytes: 177521,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/self_invalidating_question.json',
    destinationPath: 'invalid/self_invalidating_question.json',
    sha256: '3db8a029ca4191447161db4f26dd4e9418ce0df421f554ab1e60144e01308ab6',
    bytes: 177503,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/skip_sentinel_produces_token.json',
    destinationPath: 'invalid/skip_sentinel_produces_token.json',
    sha256: '7be9da73050491f0081b70aebf9a109f81a95f4942df84beb6b3ede5bac91892',
    bytes: 177767,
  ),
  FlowContractFile(
    sourcePath: 'testing/questions/fixtures/invalid/unknown_next_question.json',
    destinationPath: 'invalid/unknown_next_question.json',
    sha256: '9ca2c91c789d1ae21bd2b04ae15d695dd8a1ab1cfa74f57a3eebea155d337d2b',
    bytes: 177643,
  ),
  FlowContractFile(
    sourcePath: 'testing/questions/fixtures/invalid/unknown_token.json',
    destinationPath: 'invalid/unknown_token.json',
    sha256: 'd8fb2ee539d7b81d6f342f5bfda6f9da959e4f11109bdaea1d9b478d0f3e5a4d',
    bytes: 177514,
  ),
  FlowContractFile(
    sourcePath: 'testing/questions/fixtures/invalid/unreachable_question.json',
    destinationPath: 'invalid/unreachable_question.json',
    sha256: '21afbdd49dabf1fb0be303f7740842335a140736c13e1590904f70f908767ce3',
    bytes: 177492,
  ),
  FlowContractFile(
    sourcePath:
        'testing/questions/fixtures/invalid/vocabulary_2_0_activated.json',
    destinationPath: 'invalid/vocabulary_2_0_activated.json',
    sha256: 'f4aadfe5d89211e79667d5ca2c6ed9cad416cc0540da92a5dc9b3418c80fe12e',
    bytes: 177511,
  ),
  FlowContractFile(
    sourcePath: 'testing/questions/fixtures/paths/path_fixtures_v1.json',
    destinationPath: 'paths/path_fixtures_v1.json',
    sha256: '6d11e908ee1249061d8aece48616a8063443f93e1e50f83740a183eb70e4604f',
    bytes: 29515,
  ),
  FlowContractFile(
    sourcePath: 'reports/qb002_evidence_v1.json',
    destinationPath: 'reports/qb002_evidence_v1.json',
    sha256: '3a82e89571371344271302aaa2a9bcd640fb0582a0dc7c1a54f6270c163b4f8a',
    bytes: 16351,
  ),
  FlowContractFile(
    sourcePath: 'reports/question_baseline_freeze_v1.json',
    destinationPath: 'reports/question_baseline_freeze_v1.json',
    sha256: '031f3f8fd830e9ec9a476aab2b7d27634b3d75553e76ded239c5926e936387b3',
    bytes: 84373,
  ),
  FlowContractFile(
    sourcePath: 'reports/question_compatibility_v1.json',
    destinationPath: 'reports/question_compatibility_v1.json',
    sha256: 'ba6e5c07b396ce6c99fea46adc3c1fd8196a364e9720e0611207a3399be4410a',
    bytes: 22516,
  ),
  FlowContractFile(
    sourcePath: 'reports/question_graph_analysis_v1.json',
    destinationPath: 'reports/question_graph_analysis_v1.json',
    sha256: '18ee9fcd5f65374d44cfb9424c2d349925da61b33fd45f923169a8764aa361b7',
    bytes: 1836,
  ),
  FlowContractFile(
    sourcePath: 'schema/question_flow.v1.schema.json',
    destinationPath: 'schema/question_flow.v1.schema.json',
    sha256: '4b9f09384842968c2c093e2d4a1b246447eaef896980feff84da36d4fdbd4726',
    bytes: 12178,
  ),
];
