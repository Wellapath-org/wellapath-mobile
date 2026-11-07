/// Writes a release receipt for a built AAB or IPA.
///
/// See `docs/release/receipts/README.md` and `scripts/release_receipt.dart`.
/// Run `dart run scripts/make_release_receipt.dart --help` for options.
/// Exit codes: 0 written · 1 bad input (or receipt exists) · 2 bad usage.
library;

import 'dart:io';

import 'release_receipt.dart';

Future<void> main(List<String> args) async {
  exitCode = await makeReleaseReceipt(args, out: stdout, err: stderr);
}
