/// CB_211 release disposition — carried openly, never silently.
///
/// CB_211 is the case bank's only known finding: with an empty symptom set the
/// engine still ranks `malaria` and returns `urgent`, where the bank expects
/// `non_urgent` / `empty_default`. The expectation names an `urgency_source`
/// value that does not exist in the shipped contract.
///
/// An **engineering-lead** disposition (Option D) authorises carrying it,
/// pinned and fail-closed, until clinical/product adjudicate. It is explicitly
/// **not** clinical, external-beta or production approval, and the registry
/// requires resolution before external beta.
///
/// This file is the release gate on that arrangement. It does not re-test the
/// engine — `case_bank_validation_test.dart` pins the observed output field by
/// field. It asserts the things that would let the finding go quiet: the
/// product guards disappearing, the registry claiming authority it does not
/// have, or the status flipping to resolved without a clinical decision.
///
/// Changing clinical logic to make this pass is not authorized.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exact fixture the disposition is bound to. A different bank cannot
/// inherit an adjudication made against this one.
const String kBoundFixtureSha256 =
    'c7bdc434a33d341e21e015f0defe567274d7f6271c332352b19ba21e7d998834';

void main() {
  late Map<String, dynamic> registry;
  late Map<String, dynamic> finding;

  setUpAll(() {
    registry =
        jsonDecode(File('test/fixtures/known_findings.json').readAsStringSync())
            as Map<String, dynamic>;
    final findings = registry['findings'] as List;
    finding =
        findings.firstWhere((f) => (f as Map)['case_id'] == 'CB_211')
            as Map<String, dynamic>;
  });

  group('the finding is still registered and still unresolved', () {
    test('CB_211 is present in the registry', () {
      expect(finding['case_id'], equals('CB_211'));
    });

    test('exactly one known finding is registered', () {
      // A second entry means something new was quietly added to the same
      // engineering-authority envelope, which covers CB_211 only.
      expect((registry['findings'] as List), hasLength(1));
    });

    test('its status is open, awaiting clinical/product adjudication', () {
      expect(
        finding['decision_status'],
        equals('open_option_d_adopted_awaiting_clinical_product_adjudication'),
        reason:
            'flipping this to resolved requires a clinical decision that does '
            'not exist; the release must keep reporting it as open',
      );
    });

    test('the tracking issue is still referenced', () {
      final refs = (finding['evidence_references'] as List).join(' ');
      expect(refs, contains('issue #35'));
    });
  });

  group('the registry claims only engineering authority', () {
    test('it is not clinical approval', () {
      expect(finding['classification_is_clinical_approval'], isFalse);
    });

    test(
      'the disposition record disclaims clinical/beta/production approval',
      () {
        final record =
            registry['_metadata']['engineering_disposition_record']
                as Map<String, dynamic>;

        expect(record['authority'], equals('engineering'));
        expect(record['is_clinical_approval'], isFalse);
        expect(record['is_external_beta_approval'], isFalse);
        expect(record['is_production_approval'], isFalse);
      },
    );

    test('it does not claim to resolve the finding', () {
      final notAuthorised =
          (registry['_metadata']['engineering_disposition_record']
                  as Map<String, dynamic>)['what_it_does_not_authorise']
              as List;

      expect(notAuthorised.join(' '), contains('does not resolve CB_211'));
    });
  });

  group('the disposition is bound to this exact case bank', () {
    test('the registry names the bound fixture hash', () {
      expect(
        registry['authoritative_fixture']['sha256'],
        equals(kBoundFixtureSha256),
      );
      expect(finding['fixture_sha256'], equals(kBoundFixtureSha256));
    });

    test('the shipped fixture still matches that hash', () {
      final bytes = File('test/fixtures/case_bank_v1.json').readAsBytesSync();
      final digest = sha256.convert(bytes).toString();

      expect(
        digest,
        equals(kBoundFixtureSha256),
        reason:
            'the case bank changed — every registry entry must be '
            're-adjudicated before the registry may be used again',
      );
    });
  });

  group('the finding stays out of reach of users', () {
    test('guard 1 — Continue is disabled with no symptom selected', () {
      final screen = File(
        'lib/features/assessment/symptom_selection_screen.dart',
      ).readAsStringSync();

      expect(screen, contains('final isEnabled = tokens.isNotEmpty;'));
      expect(screen, contains('onPressed: isEnabled ?'));
    });

    test('guard 2 — the engine is not entered with an empty token set', () {
      final loading = File(
        'lib/features/assessment/loading_screen.dart',
      ).readAsStringSync();

      expect(
        loading,
        contains('symptomTokens.isEmpty'),
        reason:
            'removing this guard would make CB_211 reachable in the product '
            'and immediately invalidate the disposition',
      );
    });

    test('the guard test still exists', () {
      expect(
        File('test/assessment/empty_input_guard_test.dart').existsSync(),
        isTrue,
      );
    });

    test('the registry still records the finding as UI-unreachable', () {
      expect(
        finding['product_reachability']['reachable_via_normal_ui'],
        isFalse,
      );
    });
  });

  group('severity is what the disposition relies on', () {
    test('it is not safety critical and is over-triage', () {
      final impact = finding['safety_impact'] as Map<String, dynamic>;

      expect(impact['safety_critical'], isFalse);
      expect(impact['triage_direction'], equals('over_triage'));
    });

    test('it cannot suppress a red flag', () {
      final impact = finding['safety_impact'] as Map<String, dynamic>;

      expect(impact['can_suppress_or_bypass_a_red_flag'], isFalse);
      expect(impact['can_change_a_non_empty_assessment_result'], isFalse);
    });
  });

  group('it must not survive into external beta unadjudicated', () {
    test('the review trigger still names external beta', () {
      expect(
        finding['review_trigger']['must_be_resolved_before'],
        equals('external beta'),
      );
    });

    test('the release checklist carries it as a blocker', () {
      final checklist = File(
        'docs/release/RELEASE_CHECKLIST.md',
      ).readAsStringSync();

      expect(
        checklist,
        contains('RC-BLK-016'),
        reason: 'CB_211 must appear in the classified blocker list',
      );
    });

    test('the disposition document exists', () {
      expect(
        File('docs/release/CB_211_DISPOSITION.md').existsSync(),
        isTrue,
        reason: 'the finding may not be carried without a written disposition',
      );
    });
  });
}
