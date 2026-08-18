/// Provenance and declared counts for the vendored IM-003 evidence.
///
/// Every file under `test/fixtures/im003/` is a byte-for-byte copy from the
/// knowledge base at the commit below. This file makes that enforceable rather
/// than a claim in a commit message.
///
/// Authoritative source:
///   repository : Wellapath-org/wellapath-knowledge-base
///   merge      : 5a8563bf8702bd506a7b67ccc6c9a8faef8ef574 (KB PR #31)
///
/// **IM-003 is not implemented and this package does not implement it.** The
/// harness measures what additive re-branching WOULD do, using the shipped
/// engine. Nothing here is wired to the application.
library;

const String kKbSourceRepository = 'Wellapath-org/wellapath-knowledge-base';
const String kKbSourceCommit = '5a8563bf8702bd506a7b67ccc6c9a8faef8ef574';
const String kMobileBaseCommit = 'd820d6cfc3b96cbbba9d434ef4684b9a36140991';

const String kIm003FixtureRoot = 'test/fixtures/im003';
const String kImpactPath =
    '$kIm003FixtureRoot/evidence/im003_impact_analysis_v1.json';
const String kDecisionPackagePath =
    '$kIm003FixtureRoot/evidence/im003_decision_package_v1.json';
const String kIm003DocPath = '$kIm003FixtureRoot/docs/IM003_IMPACT_ANALYSIS.md';
const String kIm003HandoffPath = '$kIm003FixtureRoot/handoff/README.md';
const String kInvalidIndexPath = '$kIm003FixtureRoot/invalid_im003/index.json';

/// The generated Mobile evidence report.
const String kMeasurementReportPath =
    'docs/evidence/im003_mobile_scoring_measurement_v1.json';

class Im003SourceFile {
  const Im003SourceFile({
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
const List<Im003SourceFile> kIm003SourceFiles = <Im003SourceFile>[
  Im003SourceFile(
    sourcePath: 'reports/im003_impact_analysis_v1.json',
    destinationPath: 'evidence/im003_impact_analysis_v1.json',
    sha256: '3589e1a0fada38a9754f31d4629a9681a7098f4f7c28fb39d716edce25ca1fe9',
    bytes: 164499,
  ),
  Im003SourceFile(
    sourcePath: 'reports/im003_decision_package_v1.json',
    destinationPath: 'evidence/im003_decision_package_v1.json',
    sha256: '62ef20ffceae1a49bf3f92ad653c1e290edc25651973d8b50b87a5863a080f46',
    bytes: 40181,
  ),
  Im003SourceFile(
    sourcePath: 'docs/IM003_IMPACT_ANALYSIS.md',
    destinationPath: 'docs/IM003_IMPACT_ANALYSIS.md',
    sha256: '9e6ad05261343963e89d463d73bb29ff611170b05cefef83975e40e74faf9efb',
    bytes: 13415,
  ),
  Im003SourceFile(
    sourcePath: 'mobile_handoff/im003/README.md',
    destinationPath: 'handoff/README.md',
    sha256: 'da525a0b99b5a175d4ace12a2305ad41eae212408b32f57b55e23c459a04f2ed',
    bytes: 4665,
  ),
  Im003SourceFile(
    sourcePath: 'testing/questions/fixtures/invalid_im003/index.json',
    destinationPath: 'invalid_im003/index.json',
    sha256: '88d63ab809a5b2892f4b7be4449b1f5373feed39ce5d635fc766a265325280fa',
    bytes: 4287,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Declared counts. The harness reproduces every one of these INDEPENDENTLY from
// the vendored graph rather than reading them back, so a drift in either the
// evidence or this consumer fails loudly.
//
// The corrected figures are 15 tokens and 31 conditions. An earlier revision of
// the knowledge-base analysis computed newly reachable tokens from the SECOND
// HOP only — the options of the newly eligible question — which omitted the
// produced token itself and so dropped `pain`. `pain` contributes weight 6 to
// `minor_injury`, which is why that pair is asserted by name below.
// ─────────────────────────────────────────────────────────────────────────────

const int kDeclaredTriggerNodes = 18;
const int kDeclaredTriggerEdges = 56;
const int kDeclaredNewlyReachableTokens = 15;
const int kDeclaredAffectedConditions = 31;
const int kDeclaredTwoCycles = 15;
const int kDeclaredSelfLoops = 0;
const int kDeclaredMaxClosure = 14;
const int kDeclaredMaxConvergenceDepth = 5;
const int kDeclaredMonotonicityViolations = 0;
const int kDeclaredRedFlagAffectingTokens = 0;

/// The token the second-hop-only computation dropped, and its weight.
const String kPainToken = 'pain';
const String kPainCondition = 'minor_injury';
const int kPainWeight = 6;

/// Frozen clinical artifacts the measurement runs against.
const String kKbVersionExpected = '2.4';
const String kRulesVersionExpected = '2.2';
const String kTokenDictVersionExpected = '1.1';

/// This work authorizes nothing.
const List<String> kThisPrDoesNotAuthorize = <String>[
  'implementing IM-003 or any dynamic re-branching',
  'approving any IM-003 decision, including D004',
  'clinical approval',
  'product approval',
  'external beta or production activation',
  'publishing either question-flow candidate',
  'any change to the live QuestionEngine, ScoringEngine, RedFlagEvaluator or '
      'urgency logic',
];
