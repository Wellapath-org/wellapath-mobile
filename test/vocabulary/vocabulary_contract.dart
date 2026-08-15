/// Provenance and integrity constants for the vendored Vocabulary 2.0 contract.
///
/// Every file under `test/fixtures/vocabulary/` is a byte-for-byte copy from
/// the knowledge base at the commit below. This file is what makes that
/// enforceable: `vocabulary_contract_test.dart` hashes each destination and
/// compares it here, so a fixture cannot be edited, regenerated or
/// "helpfully corrected" without CI going red.
///
/// Authoritative source:
///   repository : Wellapath-org/wellapath-knowledge-base
///   commit     : dceecde2ee7545664bf45ea5edfa137a52acdebd
///
/// **The candidate is unpublished and unapproved.** It has no R2 object, no
/// live-manifest entry, zero approved aliases, zero approved associations and
/// `display_safe: false` on all 295 tokens. Vendoring it here is a test
/// fixture, not a publication.
library;

const String kVocabSourceRepository = 'Wellapath-org/wellapath-knowledge-base';
const String kVocabSourceCommit = 'dceecde2ee7545664bf45ea5edfa137a52acdebd';

/// The live token dictionary. Unchanged by this work, and still the only
/// artifact the scoring engine ever sees.
const String kLiveTokenDictionaryVersion = '1.1';
const String kLiveTokenDictionarySha256 =
    '0cc47ad9537c0bd4c6ef3aec8f1931eb9b4c62103a8809d16544f94a90b5c019';

/// Candidate identity, asserted so a swap or a version bump fails loudly.
const String kCandidateVersion = '2.0';
const String kCandidateSchemaVersion = '2.0';
const String kCandidateReleaseStatus = 'candidate_unapproved';
const String kCandidateClinicalReviewStatus = 'not_reviewed';
const int kCandidateTokenCount = 295;

/// One vendored contract file.
class VocabContractFile {
  const VocabContractFile({
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
const List<VocabContractFile> kVocabContractFiles = <VocabContractFile>[
  VocabContractFile(
    sourcePath: 'candidate/manifest.candidate.json',
    destinationPath: 'candidate/manifest.candidate.json',
    sha256: 'fa7045a07f726d73242698562c9af42e258bbcfa291a35d7381b61d31c7c545b',
    bytes: 3065,
  ),
  VocabContractFile(
    sourcePath: 'candidate/token_dictionary.ng.v2.0.json',
    destinationPath: 'candidate/token_dictionary.ng.v2.0.json',
    sha256: '07f935967acb1d5515cb53ffd1c8e39b59b8daf85c67cf36fa3e25094e34cd2d',
    bytes: 339948,
  ),
  VocabContractFile(
    sourcePath: 'docs/VOCABULARY_AMBIGUITY_SPEC.md',
    destinationPath: 'docs/VOCABULARY_AMBIGUITY_SPEC.md',
    sha256: '78c9095e5813a8e6a30dcc5e2c2c2ab57f77fc9485c01900224b815c7688ab34',
    bytes: 7949,
  ),
  VocabContractFile(
    sourcePath: 'docs/VOCABULARY_NORMALIZATION_SPEC.md',
    destinationPath: 'docs/VOCABULARY_NORMALIZATION_SPEC.md',
    sha256: 'b7c901fa544eeeb837b51a808d8f10e136e1c4b59e5b88c612e9fd1f26e307bc',
    bytes: 6903,
  ),
  VocabContractFile(
    sourcePath: 'mobile_handoff/vocabulary_v2/vocabulary_types.dart',
    destinationPath: 'handoff/vocabulary_types.dart.txt',
    sha256: 'd3a1fa28c2eeadaf158d900a5a446a506504f0bf8bc49372899a5d132b7c5399',
    bytes: 14781,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/alias_equals_own_canonical.json',
    destinationPath: 'invalid/alias_equals_own_canonical.json',
    sha256: '0b08570858f6a18138c5fc3407d3ab4f834aa2f5f4e84112e23ffefa0164c049',
    bytes: 7974,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/alias_shadows_another_canonical.json',
    destinationPath: 'invalid/alias_shadows_another_canonical.json',
    sha256: 'e3bf95928c3ccbf6a65aba2b339754da4a18dedf32b36140f3bc084387e2d133',
    bytes: 7943,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/deprecated_without_replacement.json',
    destinationPath: 'invalid/deprecated_without_replacement.json',
    sha256: '219473f7bbf6b987395640b7395ee6f2c7c329bbd60a775ce7d2f02e24fe3560',
    bytes: 7958,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/display_safe_without_approval.json',
    destinationPath: 'invalid/display_safe_without_approval.json',
    sha256: 'a716d4e8be8f35beb7c47869c15e1e7fff724b2ec23914b7acc142a6966de968',
    bytes: 7956,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/duplicate_alias_within_entry.json',
    destinationPath: 'invalid/duplicate_alias_within_entry.json',
    sha256: 'd4d6788f07c1b9fac90a1f3a259d6e83f1adf493811593bdec14a4eebee17f3b',
    bytes: 7969,
  ),
  VocabContractFile(
    sourcePath: 'testing/vocabulary/fixtures/invalid/duplicate_token_id.json',
    destinationPath: 'invalid/duplicate_token_id.json',
    sha256: '1a1c42fe3bee95ce798ac05e5a7b49188e30427f7f3b3cd417314a221f54e0c9',
    bytes: 9002,
  ),
  VocabContractFile(
    sourcePath: 'testing/vocabulary/fixtures/invalid/index.json',
    destinationPath: 'invalid/index.json',
    sha256: 'f5d5c135e97d58f83b1f137462fd777c5b5e87a899eabf2820b4286084bc6aed',
    bytes: 3296,
  ),
  VocabContractFile(
    sourcePath: 'testing/vocabulary/fixtures/invalid/legacy_order_changed.json',
    destinationPath: 'invalid/legacy_order_changed.json',
    sha256: 'fd8706b3e66e90d1a6f760950ea29d34ea07af47b13807501a8bb4f6ce1b4c98',
    bytes: 7947,
  ),
  VocabContractFile(
    sourcePath: 'testing/vocabulary/fixtures/invalid/malformed_token_id.json',
    destinationPath: 'invalid/malformed_token_id.json',
    sha256: '6b9f6db2e17a145ca6a20fcd4f1a964fa81fe2511792e4f82d0f39dc243691d4',
    bytes: 7961,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/missing_canonical_label.json',
    destinationPath: 'invalid/missing_canonical_label.json',
    sha256: '1d595f86532effe96f3f934f1a5dcbac0a265ecfc3a80f6dc7affb317b60144b',
    bytes: 7937,
  ),
  VocabContractFile(
    sourcePath: 'testing/vocabulary/fixtures/invalid/missing_provenance.json',
    destinationPath: 'invalid/missing_provenance.json',
    sha256: 'c505f798deabfe45e9bcc9c7ae82d133d015f0ededc8f920d99a7f5fd61e2663',
    bytes: 7898,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/published_without_review.json',
    destinationPath: 'invalid/published_without_review.json',
    sha256: '8a2c24783b4cd47aed30fb9159c526e6ac9d73fef76798c8ba45fdecda1d6fc2',
    bytes: 7949,
  ),
  VocabContractFile(
    sourcePath: 'testing/vocabulary/fixtures/invalid/replacement_cycle.json',
    destinationPath: 'invalid/replacement_cycle.json',
    sha256: '32c6da35d46a46393dbd5aa8c281693cb2d57096df2b3533adf80fdc86a2217b',
    bytes: 7953,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/review_claim_without_evidence.json',
    destinationPath: 'invalid/review_claim_without_evidence.json',
    sha256: '2d41414f68a455e4996e41d2701e037be0b5a8ad6966f9cb69312f06a8cca315',
    bytes: 7956,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/search_not_marked_search_only.json',
    destinationPath: 'invalid/search_not_marked_search_only.json',
    sha256: '31d1c543afef7e4edf391ae1fe2fa2169b5e8a9aa59a2fea7678e3b38de6ac10',
    bytes: 7952,
  ),
  VocabContractFile(
    sourcePath: 'testing/vocabulary/fixtures/invalid/stale_search_index.json',
    destinationPath: 'invalid/stale_search_index.json',
    sha256: '947eecb2bdeeb31cf5d97ba19f22eaeec5cb042955f6db47894686c6df39da8a',
    bytes: 7950,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/tokens_disagree_with_legacy_arrays.json',
    destinationPath: 'invalid/tokens_disagree_with_legacy_arrays.json',
    sha256: '6011cd4b729a999dfb01e7b69728e17ef61b39e9b63ef88e39adad682f88f06c',
    bytes: 7950,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/unknown_top_level_key.json',
    destinationPath: 'invalid/unknown_top_level_key.json',
    sha256: '47acb2efc1630246f7fd9bae897c22bb207509d0295b40f805068abd744df9bf',
    bytes: 7991,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/unresolvable_body_area.json',
    destinationPath: 'invalid/unresolvable_body_area.json',
    sha256: '66cc4a06bb32a7f0ff2f6771b0e73837cc46bb673dbf59385527b30a28ab2f4d',
    bytes: 7973,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/unresolvable_complaint_group.json',
    destinationPath: 'invalid/unresolvable_complaint_group.json',
    sha256: 'f505e6cf77925ffa700d672303a30549b4eb2473e5ef87aaf78f72c6d8209c50',
    bytes: 7981,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/invalid/unresolvable_replacement.json',
    destinationPath: 'invalid/unresolvable_replacement.json',
    sha256: '0b3f1c54b5ef959ab9d14697352d35c21ecfb6515d24e627c5e9e3a0afaf03e1',
    bytes: 7953,
  ),
  VocabContractFile(
    sourcePath: 'testing/vocabulary/fixtures/invalid/wrong_schema_version.json',
    destinationPath: 'invalid/wrong_schema_version.json',
    sha256: '58dcb9386bddeaa65903ca93146691089bc3e849c313071fd788355fe238694b',
    bytes: 7942,
  ),
  VocabContractFile(
    sourcePath: 'schema/token_dictionary.v2.schema.json',
    destinationPath: 'schema/token_dictionary.v2.schema.json',
    sha256: '397227a1ce60a4df82ce73af17aea003c4b4898e947142df24e1f5323f47580f',
    bytes: 15898,
  ),
  VocabContractFile(
    sourcePath: 'schema/token_dictionary_schema_v2.0.json',
    destinationPath: 'schema/token_dictionary_schema_v2.0.json',
    sha256: 'f2b1d73ac93ba23671ab1a95fa99d4f36596fed6a272476160554001cebfaf80',
    bytes: 35409,
  ),
  VocabContractFile(
    sourcePath: 'testing/vocabulary/fixtures/search/ambiguity_cases_v1.json',
    destinationPath: 'search/ambiguity_cases_v1.json',
    sha256: '7964cb05519b964441d9e4066ad3346a74054ceb8d6033b9ef8945ca1870c156',
    bytes: 4382,
  ),
  VocabContractFile(
    sourcePath: 'testing/vocabulary/fixtures/search/search_cases_v1.json',
    destinationPath: 'search/search_cases_v1.json',
    sha256: '6472a698787decda8d7d0502b94de5c94972b7711e38bcc366b1a3f3c3d370e7',
    bytes: 11852,
  ),
  VocabContractFile(
    sourcePath:
        'testing/vocabulary/fixtures/search/synthetic_vocabulary_v1.json',
    destinationPath: 'search/synthetic_vocabulary_v1.json',
    sha256: 'e60dee1d5e5647fa2ce056d1538023932b6eed0bd4640c55fc3c3d8e708ff362',
    bytes: 7823,
  ),
];
