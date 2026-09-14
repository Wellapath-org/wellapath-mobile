/// Shared helpers for the Facilities 2.0 tests: the synthetic fixture and
/// manifests. All values are invented — no candidate URL, hash or record
/// exists anywhere in this repository.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:wellapath_mobile/core/facilities_v2/facilities_v2_manifest.dart';
import 'package:wellapath_mobile/core/facilities_v2/facilities_v2_parser.dart';

const String kFixturePath =
    'test/fixtures/facilities_v2/synthetic_facilities_v2_fixture.json';

String readFixtureRaw() => File(kFixturePath).readAsStringSync();

Map<String, dynamic> readFixtureJson() =>
    jsonDecode(readFixtureRaw()) as Map<String, dynamic>;

Map<String, dynamic> readFixtureJsonFrom(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

String sha256Of(String body) => sha256.convert(utf8.encode(body)).toString();

/// The fixture parsed synchronously on the calling isolate — the reference
/// result the loader's background-isolate parse must match exactly.
FacilitiesV2ParseResult parseFixtureDirectly() =>
    const FacilitiesV2Parser().parse(readFixtureJson());

/// A manifest that would authorize consumption — synthetic, test-only. Its
/// URL is a reserved example domain and its hash is computed over the
/// synthetic fixture, so it can never describe a real artifact.
FacilitiesV2Manifest syntheticApprovedManifest({String? hash}) =>
    FacilitiesV2Manifest(
      schemaVersion: '2.0',
      artifactVersion: '2.0-synthetic-test',
      status: FacilitiesV2Manifest.approvedStatus,
      mayPublish: true,
      url: 'https://example.invalid/synthetic/facilities_v2.json',
      sha256: hash ?? sha256Of(readFixtureRaw()),
    );

/// A manifest that truthfully describes the real candidate's approval
/// state (unapproved, unpublishable) — with NO url and NO hash, because
/// neither may exist in this repository.
FacilitiesV2Manifest candidateUnapprovedManifest() =>
    const FacilitiesV2Manifest(
      schemaVersion: '2.0',
      artifactVersion: '2.0',
      status: FacilitiesV2Manifest.candidateStatus,
      mayPublish: false,
    );
