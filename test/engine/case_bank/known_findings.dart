/// Consumer for the authoritative known-findings registry.
///
/// A known finding is a **pinned observation, never a suppressed failure.** The
/// case still executes, its exact observed output is asserted field by field,
/// and any deviation — better or worse — fails the run, because the registry's
/// description of reality has become wrong.
///
/// Everything case-specific lives in the registry JSON. Nothing in this file
/// knows what CB_211 is, and nothing keys off a case id, a file name or a test
/// name. Adding or removing a finding is a registry change, reviewed in the
/// knowledge base, not a code change here.
///
/// Source of truth:
///   repository : Wellapath-org/wellapath-knowledge-base
///   merge      : 550e8f179021139a4c9084ba19d1f80111edbfba
///   path       : testing/known_findings.json
///   contract   : docs/KNOWN_FINDINGS_CONTRACT.md
///
/// This is an **engineering disposition, not clinical approval.**
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'case_bank_models.dart';

/// Milestones in the order the product passes through them. A registry entry
/// declares the milestone it expires at; using it at or beyond that milestone
/// is a hard failure, so a deferred decision cannot ride quietly into a later
/// release than the one it was deferred to.
const List<String> kMilestoneLadder = <String>[
  'internal_beta',
  'external_beta',
  'production',
];

/// The milestone this repository is currently building for. Raise this when
/// the product advances; a registry entry that expires here then fails until
/// it is re-adjudicated.
const String kCurrentMilestone = 'internal_beta';

/// The only engineering disposition this consumer will honour. Any other value
/// means the registry was written under a policy this code was not reviewed
/// against.
const String kRequiredDisposition = 'option_d_adopted';

/// Substrings that would indicate the registry is claiming an approval it has
/// no authority to grant. Presence of any of these in an approval flag set to
/// true is a hard failure.
const List<String> kForbiddenApprovalFlags = <String>[
  'is_clinical_approval',
  'is_external_beta_approval',
  'is_production_approval',
  'classification_is_clinical_approval',
];

int _milestoneIndex(String milestone) {
  final int index = kMilestoneLadder.indexOf(milestone);
  if (index < 0) {
    throw StateError(
      'Unknown milestone "$milestone". Known milestones: '
      '${kMilestoneLadder.join(', ')}.',
    );
  }
  return index;
}

/// One registered finding: the unchanged case-bank expectation it still misses,
/// and the exact output it is pinned to produce.
class KnownFinding {
  const KnownFinding({
    required this.caseId,
    required this.fixtureSha256,
    required this.classification,
    required this.engineeringDisposition,
    required this.decisionStatus,
    required this.expectedUrgency,
    required this.expectedUrgencySource,
    required this.expectedTopCondition,
    required this.observedUrgency,
    required this.observedUrgencySource,
    required this.observedTopCondition,
    required this.observedRedFlagTriggered,
    required this.triageDirection,
    required this.safetyCritical,
    required this.expiresAtMilestone,
  });

  final String caseId;
  final String fixtureSha256;
  final String classification;
  final String engineeringDisposition;

  /// The registry's own status string. Required to still read as open and
  /// unresolved — a finding that has been closed upstream must not keep
  /// absorbing a failure here.
  final String decisionStatus;

  final String? expectedUrgency;
  final String? expectedUrgencySource;
  final String? expectedTopCondition;

  final String observedUrgency;
  final String observedUrgencySource;
  final String? observedTopCondition;
  final bool observedRedFlagTriggered;

  final String triageDirection;
  final bool safetyCritical;
  final String expiresAtMilestone;

  bool get isOpen =>
      decisionStatus.startsWith('open') && !decisionStatus.contains('resolved');

  static T _require<T>(Map<String, dynamic> json, String key, String context) {
    if (!json.containsKey(key)) {
      throw StateError('$context is missing required field "$key".');
    }
    final Object? value = json[key];
    if (value is! T) {
      throw StateError(
        '$context field "$key" is ${value.runtimeType}, expected $T.',
      );
    }
    return value;
  }

  factory KnownFinding.fromJson(Map<String, dynamic> json) {
    final String caseId = _require<String>(json, 'case_id', 'Registry finding');
    final String context = 'Registry finding $caseId';

    final Map<String, dynamic> expected = Map<String, dynamic>.from(
      _require<Map<dynamic, dynamic>>(json, 'expected_output', context),
    );
    final Map<String, dynamic> observed = Map<String, dynamic>.from(
      _require<Map<dynamic, dynamic>>(json, 'observed_output', context),
    );
    final Map<String, dynamic> safety = Map<String, dynamic>.from(
      _require<Map<dynamic, dynamic>>(json, 'safety_impact', context),
    );
    final Map<String, dynamic> trigger = Map<String, dynamic>.from(
      _require<Map<dynamic, dynamic>>(json, 'review_trigger', context),
    );

    // An entry that claims it is a clinical approval is refused outright
    // rather than honoured — this registry has engineering authority only.
    for (final String flag in kForbiddenApprovalFlags) {
      if (json[flag] == true) {
        throw StateError(
          '$context sets $flag: true. The known-findings registry carries '
          'engineering authority only and cannot record clinical, '
          'external-beta or production approval.',
        );
      }
    }

    return KnownFinding(
      caseId: caseId,
      fixtureSha256: _require<String>(json, 'fixture_sha256', context),
      classification: _require<String>(json, 'classification', context),
      engineeringDisposition: _require<String>(
        json,
        'engineering_disposition',
        context,
      ),
      decisionStatus: _require<String>(json, 'decision_status', context),
      expectedUrgency: expected['urgency'] as String?,
      expectedUrgencySource: expected['urgency_source'] as String?,
      expectedTopCondition: expected['top_condition'] as String?,
      observedUrgency: _require<String>(
        observed,
        'urgency',
        '$context observed',
      ),
      observedUrgencySource: _require<String>(
        observed,
        'urgency_source',
        '$context observed',
      ),
      observedTopCondition: observed['top_condition'] as String?,
      observedRedFlagTriggered: _require<bool>(
        observed,
        'red_flag_triggered',
        '$context observed',
      ),
      triageDirection: _require<String>(
        safety,
        'triage_direction',
        '$context safety_impact',
      ),
      safetyCritical: _require<bool>(
        safety,
        'safety_critical',
        '$context safety_impact',
      ),
      expiresAtMilestone: _require<String>(
        trigger,
        'expires_at_milestone',
        '$context review_trigger',
      ),
    );
  }
}

/// The registry, validated against the exact case bank it was adjudicated for.
class KnownFindingsRegistry {
  const KnownFindingsRegistry({
    required this.version,
    required this.schemaVersion,
    required this.disposition,
    required this.boundFixtureSha256,
    required this.findings,
  });

  final String version;
  final String schemaVersion;
  final String disposition;

  /// The fixture hash every entry was adjudicated against.
  final String boundFixtureSha256;

  final List<KnownFinding> findings;

  Set<String> get caseIds => findings.map((KnownFinding f) => f.caseId).toSet();

  KnownFinding? forCase(String caseId) {
    for (final KnownFinding f in findings) {
      if (f.caseId == caseId) return f;
    }
    return null;
  }

  /// Loads and fully validates the registry.
  ///
  /// Fails closed on every condition the contract names: missing or unreadable
  /// file, hash or byte drift, version or schema mismatch, a disposition this
  /// code was not reviewed against, a binding to a different case bank, an
  /// unknown or duplicated case id, a closed decision, a claimed approval, an
  /// expired entry, or an expectation that disagrees with the bank itself.
  ///
  /// Throws [StateError] with the specific reason. It never returns a
  /// partially-trusted registry, and an unreadable registry is never treated
  /// as permission to ignore a failure.
  static KnownFindingsRegistry load({
    required String path,
    required String expectedSha256,
    required int expectedBytes,
    required String expectedVersion,
    required String expectedSchemaVersion,
    required String caseBankSha256,
    required List<CaseBankCase> cases,
    String currentMilestone = kCurrentMilestone,
  }) {
    final File file = File(path);
    if (!file.existsSync()) {
      throw StateError(
        'Known-findings registry missing at $path. It is required: an absent '
        'registry is not permission to ignore a failure. Vendor it from '
        'wellapath-knowledge-base testing/known_findings.json.',
      );
    }

    final List<int> bytes = file.readAsBytesSync();
    if (bytes.length != expectedBytes) {
      throw StateError(
        'Known-findings registry byte count drifted: expected $expectedBytes, '
        'got ${bytes.length}.',
      );
    }

    final String actualSha = sha256.convert(bytes).toString();
    if (actualSha != expectedSha256) {
      throw StateError(
        'Known-findings registry hash drifted: expected $expectedSha256, got '
        '$actualSha. The registry is immutable; re-vendor it byte-for-byte '
        'rather than editing it.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw StateError('Known-findings registry is not valid JSON: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw StateError(
        'Known-findings registry must be a JSON object, got '
        '${decoded.runtimeType}.',
      );
    }

    final Object? rawMetadata = decoded['_metadata'];
    if (rawMetadata is! Map<String, dynamic>) {
      throw StateError('Known-findings registry is missing "_metadata".');
    }
    final Map<String, dynamic> metadata = rawMetadata;

    final String version = metadata['version'] as String? ?? '';
    if (version != expectedVersion) {
      throw StateError(
        'Known-findings registry version is "$version", expected '
        '"$expectedVersion".',
      );
    }

    final String schemaVersion = metadata['schema_version'] as String? ?? '';
    if (schemaVersion != expectedSchemaVersion) {
      throw StateError(
        'Known-findings registry schema_version is "$schemaVersion", expected '
        '"$expectedSchemaVersion". This consumer was reviewed against the '
        'latter; a schema change needs a reviewed consumer change.',
      );
    }

    final String disposition =
        metadata['engineering_disposition'] as String? ?? '';
    if (disposition != kRequiredDisposition) {
      throw StateError(
        'Known-findings registry disposition is "$disposition", expected '
        '"$kRequiredDisposition".',
      );
    }

    final Object? rawRecord = metadata['engineering_disposition_record'];
    if (rawRecord is Map<String, dynamic>) {
      for (final String flag in kForbiddenApprovalFlags) {
        if (rawRecord[flag] == true) {
          throw StateError(
            'Known-findings registry sets $flag: true in its disposition '
            'record. This registry carries engineering authority only.',
          );
        }
      }
    }

    final Object? rawFixture = decoded['authoritative_fixture'];
    if (rawFixture is! Map<String, dynamic>) {
      throw StateError(
        'Known-findings registry is missing "authoritative_fixture" — without '
        'it the registry cannot be bound to a case bank.',
      );
    }
    final String boundSha = rawFixture['sha256'] as String? ?? '';
    if (boundSha != caseBankSha256) {
      throw StateError(
        'Known-findings registry is bound to case bank $boundSha but the '
        'loaded case bank is $caseBankSha256. Every entry must be '
        're-adjudicated against the new fixture before the registry is used.',
      );
    }

    final Object? rawFindings = decoded['findings'];
    if (rawFindings is! List) {
      throw StateError('Known-findings registry is missing "findings" list.');
    }

    final List<KnownFinding> findings = rawFindings
        .whereType<Map<dynamic, dynamic>>()
        .map(Map<String, dynamic>.from)
        .map(KnownFinding.fromJson)
        .toList();

    final Set<String> seen = <String>{};
    final Map<String, CaseBankCase> byId = <String, CaseBankCase>{
      for (final CaseBankCase c in cases) c.caseId: c,
    };

    for (final KnownFinding f in findings) {
      if (!seen.add(f.caseId)) {
        throw StateError(
          'Known-findings registry lists ${f.caseId} more than once.',
        );
      }

      final CaseBankCase? testCase = byId[f.caseId];
      if (testCase == null) {
        throw StateError(
          'Known-findings registry registers ${f.caseId}, which does not exist '
          'in the loaded case bank.',
        );
      }

      if (f.fixtureSha256 != caseBankSha256) {
        throw StateError(
          '${f.caseId} was adjudicated against fixture ${f.fixtureSha256} but '
          'the loaded case bank is $caseBankSha256.',
        );
      }

      if (f.engineeringDisposition != kRequiredDisposition) {
        throw StateError(
          '${f.caseId} carries disposition "${f.engineeringDisposition}", '
          'expected "$kRequiredDisposition".',
        );
      }

      if (!f.isOpen) {
        throw StateError(
          '${f.caseId} decision_status is "${f.decisionStatus}", which no '
          'longer reads as open and unresolved. A closed finding must not keep '
          'absorbing a failure — remove it from the registry and let the case '
          'pass or fail on its own.',
        );
      }

      if (_milestoneIndex(currentMilestone) >=
          _milestoneIndex(f.expiresAtMilestone)) {
        throw StateError(
          '${f.caseId} expires at milestone "${f.expiresAtMilestone}" and the '
          'build is at "$currentMilestone". The deferred clinical/product '
          'decision is now due; it cannot be carried further.',
        );
      }

      // The registry must agree with the bank about what the case expects.
      // If they disagree, one of the two has been edited and the registry's
      // description of the mismatch is no longer trustworthy.
      if (f.expectedUrgency != testCase.expectedUrgency ||
          f.expectedUrgencySource != testCase.expectedUrgencySource ||
          f.expectedTopCondition != testCase.expectedTopCondition) {
        throw StateError(
          '${f.caseId} registry expectation '
          '(${f.expectedUrgency}/${f.expectedUrgencySource}/'
          '${f.expectedTopCondition}) disagrees with the case bank '
          '(${testCase.expectedUrgency}/${testCase.expectedUrgencySource}/'
          '${testCase.expectedTopCondition}). One of the two has changed.',
        );
      }
    }

    return KnownFindingsRegistry(
      version: version,
      schemaVersion: schemaVersion,
      disposition: disposition,
      boundFixtureSha256: boundSha,
      findings: findings,
    );
  }
}

/// Which bucket a case landed in.
enum CaseClassification {
  /// Met every assertion the bank encodes for it.
  passed,

  /// Registered in the registry, still mismatching its bank expectation, and
  /// matching its pinned observation exactly. Never counted as passed.
  knownFinding,

  /// Anything else — including a registered case that drifted from its pin in
  /// *either* direction.
  unexpectedFailure,
}

/// One case's classification, with the reason it landed there.
class ClassifiedCase {
  const ClassifiedCase({
    required this.result,
    required this.classification,
    required this.reason,
    this.finding,
  });

  final CaseRunResult result;
  final CaseClassification classification;

  /// Human-readable reason. Empty for a plain pass.
  final String reason;

  /// The registry entry, when this case is registered.
  final KnownFinding? finding;

  String get caseId => result.testCase.caseId;
}

/// Partitions a completed run into passed / known findings / unexpected
/// failures, using the registry as the only source of case-specific knowledge.
class KnownFindingsClassification {
  KnownFindingsClassification({required this.report, required this.registry})
    : cases = report.results
          .map(
            (CaseRunResult r) =>
                _classify(r, registry.forCase(r.testCase.caseId)),
          )
          .toList();

  final CaseBankReport report;
  final KnownFindingsRegistry registry;
  final List<ClassifiedCase> cases;

  static ClassifiedCase _classify(CaseRunResult r, KnownFinding? finding) {
    if (finding == null) {
      // Unregistered: it must simply pass. An observe case asserts nothing
      // beyond running cleanly, so it passes when the engine did not throw.
      if (r.error != null) {
        return ClassifiedCase(
          result: r,
          classification: CaseClassification.unexpectedFailure,
          reason: 'engine threw: ${r.error}',
        );
      }
      if (r.graded && !r.passed) {
        return ClassifiedCase(
          result: r,
          classification: CaseClassification.unexpectedFailure,
          reason:
              'unregistered mismatch — expected '
              '${r.testCase.expectedUrgency}/'
              '${r.testCase.expectedUrgencySource}/'
              '${r.testCase.expectedTopCondition}, got '
              '${r.actualUrgency}/${r.actualUrgencySource}/'
              '${r.actualTopCondition}',
        );
      }
      return ClassifiedCase(
        result: r,
        classification: CaseClassification.passed,
        reason: '',
      );
    }

    // Registered. It ran normally; now it must still be broken in exactly the
    // way the registry says it is.
    if (r.error != null) {
      return ClassifiedCase(
        result: r,
        classification: CaseClassification.unexpectedFailure,
        reason:
            'registered finding now throws instead of producing its pinned '
            'output: ${r.error}',
        finding: finding,
      );
    }

    if (r.passed) {
      return ClassifiedCase(
        result: r,
        classification: CaseClassification.unexpectedFailure,
        reason:
            'registered finding now MATCHES its case-bank expectation. This is '
            'not an automatic pass — the registry is stale and the entry must '
            'be reviewed and removed before this case can count as passing.',
        finding: finding,
      );
    }

    final List<String> drift = <String>[];
    if (r.actualUrgency != finding.observedUrgency) {
      drift.add(
        'urgency pinned ${finding.observedUrgency}, got ${r.actualUrgency}',
      );
    }
    if (r.actualUrgencySource != finding.observedUrgencySource) {
      drift.add(
        'urgency_source pinned ${finding.observedUrgencySource}, got '
        '${r.actualUrgencySource}',
      );
    }
    if (r.actualTopCondition != finding.observedTopCondition) {
      drift.add(
        'top_condition pinned ${finding.observedTopCondition}, got '
        '${r.actualTopCondition}',
      );
    }
    if (r.redFlagTriggered != finding.observedRedFlagTriggered) {
      drift.add(
        'red_flag_triggered pinned ${finding.observedRedFlagTriggered}, got '
        '${r.redFlagTriggered}',
      );
    }

    if (drift.isNotEmpty) {
      return ClassifiedCase(
        result: r,
        classification: CaseClassification.unexpectedFailure,
        reason:
            'registered finding drifted from its pin — ${drift.join('; ')}. '
            'Any change, in either direction, requires registry review.',
        finding: finding,
      );
    }

    return ClassifiedCase(
      result: r,
      classification: CaseClassification.knownFinding,
      reason: finding.decisionStatus,
      finding: finding,
    );
  }

  List<ClassifiedCase> _of(CaseClassification c) =>
      cases.where((ClassifiedCase e) => e.classification == c).toList();

  List<ClassifiedCase> get passed => _of(CaseClassification.passed);
  List<ClassifiedCase> get knownFindings =>
      _of(CaseClassification.knownFinding);
  List<ClassifiedCase> get unexpectedFailures =>
      _of(CaseClassification.unexpectedFailure);

  int get executed => cases.length;

  /// Registered entries that produced no result at all — a case that was
  /// dropped from the run rather than executed.
  Set<String> get registeredButNotExecuted => registry.caseIds.difference(
    cases.map((ClassifiedCase e) => e.caseId).toSet(),
  );

  /// Every case is in exactly one bucket and none was lost.
  bool get reconciles =>
      passed.length + knownFindings.length + unexpectedFailures.length ==
          executed &&
      registeredButNotExecuted.isEmpty;

  String get headline =>
      '$executed executed · ${passed.length} passed · '
      '${knownFindings.length} known finding'
      '${knownFindings.length == 1 ? '' : 's'} · '
      '${unexpectedFailures.length} unexpected failure'
      '${unexpectedFailures.length == 1 ? '' : 's'}';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'headline': headline,
    'executed': executed,
    'passed': passed.length,
    'known_findings': knownFindings.length,
    'unexpected_failures': unexpectedFailures.length,
    'reconciles': reconciles,
    'registry': <String, dynamic>{
      'version': registry.version,
      'schema_version': registry.schemaVersion,
      'engineering_disposition': registry.disposition,
      'bound_fixture_sha256': registry.boundFixtureSha256,
      'is_clinical_approval': false,
      'registered_case_ids': (registry.caseIds.toList()..sort()),
    },
    'known_finding_detail': knownFindings
        .map(
          (ClassifiedCase e) => <String, dynamic>{
            'case_id': e.caseId,
            'classification': e.finding!.classification,
            'decision_status': e.finding!.decisionStatus,
            'expires_at_milestone': e.finding!.expiresAtMilestone,
            'triage_direction': e.finding!.triageDirection,
            'safety_critical': e.finding!.safetyCritical,
            'expected': <String, dynamic>{
              'urgency': e.finding!.expectedUrgency,
              'urgency_source': e.finding!.expectedUrgencySource,
              'top_condition': e.finding!.expectedTopCondition,
            },
            'observed': <String, dynamic>{
              'urgency': e.result.actualUrgency,
              'urgency_source': e.result.actualUrgencySource,
              'top_condition': e.result.actualTopCondition,
              'red_flag_triggered': e.result.redFlagTriggered,
            },
            'counted_as_passed': false,
          },
        )
        .toList(),
    'unexpected_failure_detail': unexpectedFailures
        .map(
          (ClassifiedCase e) => <String, dynamic>{
            'case_id': e.caseId,
            'reason': e.reason,
          },
        )
        .toList(),
  };
}
