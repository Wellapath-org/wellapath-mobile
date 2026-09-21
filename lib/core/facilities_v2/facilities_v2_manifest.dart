/// Facilities 2.0 manifest — the approval record the gate requires.
///
/// The v2 consumer cannot activate on a flag alone: activation additionally
/// requires a manifest that *explicitly* selects an approved, publishable
/// artifact. The real candidate dataset is `candidate_unapproved` with
/// `may_publish: false`, so no manifest that truthfully describes it can
/// ever satisfy [isApprovedForConsumption]. This repository carries **no**
/// real v2 URL and **no** candidate hash — synthetic values exist only in
/// tests.
library;

class FacilitiesV2Manifest {
  const FacilitiesV2Manifest({
    required this.schemaVersion,
    required this.artifactVersion,
    required this.status,
    required this.mayPublish,
    this.url,
    this.sha256,
  });

  /// Schema family this manifest describes, e.g. `2.0`. Only major version 2
  /// is compatible with this consumer.
  final String schemaVersion;

  /// The artifact version the manifest selects, e.g. `2.0`.
  final String artifactVersion;

  /// Approval status. Only the literal `approved` counts; the candidate is
  /// `candidate_unapproved` and must never be treated as anything else.
  final String status;

  /// Data Engineering's publication flag. `false` means the source has not
  /// authorized publication — consumption is forbidden regardless of status.
  final bool mayPublish;

  /// Where the artifact would be fetched from. Deliberately nullable — no
  /// real endpoint exists in this repository.
  final String? url;

  /// Expected artifact SHA-256. Required for consumption: an approved
  /// manifest without an integrity hash is not usable.
  final String? sha256;

  static const String approvedStatus = 'approved';
  static const String candidateStatus = 'candidate_unapproved';

  /// Strict parse. Returns null (never throws to the caller) for anything
  /// structurally unusable — a broken manifest reads as "no manifest".
  static FacilitiesV2Manifest? tryParse(Map<String, dynamic> json) {
    final schemaVersion = json['schema_version'];
    final artifact = json['artifact'];
    if (schemaVersion is! String || artifact is! Map) return null;

    final version = artifact['version'];
    final status = artifact['status'];
    final mayPublish = artifact['may_publish'];
    if (version is! String || status is! String || mayPublish is! bool) {
      return null;
    }

    return FacilitiesV2Manifest(
      schemaVersion: schemaVersion,
      artifactVersion: version,
      status: status,
      mayPublish: mayPublish,
      url: artifact['url'] is String ? artifact['url'] as String : null,
      sha256: artifact['sha256'] is String
          ? artifact['sha256'] as String
          : null,
    );
  }

  bool get isSchemaCompatible =>
      schemaVersion == '2.0' || schemaVersion.startsWith('2.');

  /// The one condition under which the gate may consider v2 at all:
  /// explicitly approved, publication authorized by the source, schema
  /// major 2, and integrity-verifiable. The candidate fails this on both
  /// `status` and `may_publish`.
  bool get isApprovedForConsumption =>
      status == approvedStatus &&
      mayPublish &&
      isSchemaCompatible &&
      (sha256?.isNotEmpty ?? false);
}
