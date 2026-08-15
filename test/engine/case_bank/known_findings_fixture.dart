/// Integrity constants for the vendored known-findings registry.
///
/// Kept in one place so the validation run, the provenance guard and the
/// negative-guard tests all assert the same values — a hash that only one of
/// them checks is a hash that can drift.
///
/// Authoritative source:
///   repository   : Wellapath-org/wellapath-knowledge-base
///   merge commit : 550e8f179021139a4c9084ba19d1f80111edbfba
///   source path  : testing/known_findings.json
///   contract     : docs/KNOWN_FINDINGS_CONTRACT.md
///                  sha256 81455b4f5995d9ea403dcc174d54329a097a35b4af09332e61f50d53564163e2
///   decision pkg : docs/CB_211_DECISION_PACKAGE.md
///                  sha256 fdda2501bbffd4979972ec3d3a0431639eea876a65e8528512e10dde699f9701
///
/// The registry records an **engineering disposition, not clinical approval.**
library;

const String kKnownFindingsPath = 'test/fixtures/known_findings.json';

const String kKnownFindingsSourceRepository =
    'Wellapath-org/wellapath-knowledge-base';
const String kKnownFindingsSourceCommit =
    '550e8f179021139a4c9084ba19d1f80111edbfba';
const String kKnownFindingsSourcePath = 'testing/known_findings.json';

const String kKnownFindingsSha256 =
    'fadaea063303ecd27a90c233dba7782f8840c85aef4e3a7cca61b1e4793537ed';
const int kKnownFindingsBytes = 9730;
const String kKnownFindingsVersion = '1.0';
const String kKnownFindingsSchemaVersion = '1.0';

/// The case bank the registry is adjudicated against. Duplicated here from the
/// case-bank provenance guard on purpose: the binding between the two files is
/// the thing being asserted, so each side states its own expectation.
const String kCaseBankSha256 =
    'c7bdc434a33d341e21e015f0defe567274d7f6271c332352b19ba21e7d998834';
