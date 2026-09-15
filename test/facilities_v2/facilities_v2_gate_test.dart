import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/facilities_v2/facilities_v2_gate.dart';
import 'package:wellapath_mobile/core/facilities_v2/facilities_v2_manifest.dart';

import 'fixture_support.dart';

void main() {
  group('the gate is off by default', () {
    test('no defines at all -> inactive', () {
      final gate = FacilitiesV2Gate.evaluate(
        defines: const {},
        manifest: syntheticApprovedManifest(),
      );
      expect(gate.active, isFalse);
      expect(gate.reason, 'evaluation_flag_off');
    });

    test('an ordinary build (compile-time defines absent) -> inactive', () {
      // Exactly what build 210 resolves: no FACILITIES_V2_* define exists.
      final gate = FacilitiesV2Gate.evaluate(
        manifest: syntheticApprovedManifest(),
      );
      expect(gate.active, isFalse);
    });

    test('the tracked .env carries no facilities-v2 key', () {
      final env = File('.env').readAsStringSync();
      expect(env.contains('FACILITIES_V2'), isFalse);
    });
  });

  group('production is blocked', () {
    test('evaluation flag alone cannot activate production', () {
      final gate = FacilitiesV2Gate.evaluate(
        defines: const {
          'FACILITIES_V2_EVALUATION': 'true',
          'APP_ENV': 'production',
        },
        manifest: syntheticApprovedManifest(),
      );
      expect(gate.active, isFalse);
      expect(gate.reason, 'production_blocked');
    });

    test('nothing in the repository sets the production-approval key', () {
      final env = File('.env').readAsStringSync();
      expect(env.contains('FACILITIES_V2_PRODUCTION_APPROVED'), isFalse);
    });
  });

  group('an approved manifest is mandatory', () {
    test('flag on, no manifest -> inactive', () {
      final gate = FacilitiesV2Gate.evaluate(
        defines: const {'FACILITIES_V2_EVALUATION': 'true'},
      );
      expect(gate.active, isFalse);
      expect(gate.reason, 'no_manifest');
    });

    test('flag on, candidate_unapproved manifest -> inactive', () {
      // The real candidate is candidate_unapproved / may_publish:false —
      // no flag combination can activate it.
      final gate = FacilitiesV2Gate.evaluate(
        defines: const {'FACILITIES_V2_EVALUATION': 'true'},
        manifest: candidateUnapprovedManifest(),
      );
      expect(gate.active, isFalse);
      expect(gate.reason, 'manifest_not_approved');
    });

    test('approved status without may_publish is still refused', () {
      // A status flip alone is not enough: the source's publication
      // authorization is a separate, independently required fact.
      const approvedButUnpublishable = FacilitiesV2Manifest(
        schemaVersion: '2.0',
        artifactVersion: '2.0',
        status: FacilitiesV2Manifest.approvedStatus,
        mayPublish: false,
        url: 'https://example.invalid/synthetic.json',
        sha256: 'deadbeef',
      );
      final gate = FacilitiesV2Gate.evaluate(
        defines: const {'FACILITIES_V2_EVALUATION': 'true'},
        manifest: approvedButUnpublishable,
      );
      expect(gate.active, isFalse);
      expect(gate.reason, 'manifest_not_approved');
    });

    test('flag on + synthetic approved manifest -> active (dev only)', () {
      final gate = FacilitiesV2Gate.evaluate(
        defines: const {
          'FACILITIES_V2_EVALUATION': 'true',
          'APP_ENV': 'staging',
        },
        manifest: syntheticApprovedManifest(),
      );
      expect(gate.active, isTrue);
      expect(gate.reason, 'approved_manifest');
    });
  });
}
