/// iOS distribution export-options policy — generate and verify.
///
/// **Why this exists.** Build 216 was exported and uploaded with
/// `uploadSymbols` set to `false`, so no dSYMs reached App Store Connect and
/// automatic Apple-side symbolication is unavailable for that build. The cause
/// was not a bad decision recorded somewhere and overridden; it was that the
/// `ExportOptions.plist` was **hand-authored in an untracked build directory**.
/// Nothing in version control described what a distribution export must
/// contain, so nothing could disagree with it.
///
/// This library is that description. It does two jobs:
///
///  * [buildExportOptionsPlist] generates the plist. `uploadSymbols` is a
///    constant `true` here and is not a parameter, so a symbols-disabled file
///    cannot be generated at all.
///  * [verifyExportOptions] inspects a plist that already exists — however it
///    was produced, including by hand — and returns the policy violations. A
///    non-empty result must stop the release step.
///
/// Distribution mode stays **explicit**. There is no default: callers must name
/// [DistributionMode], and only [DistributionMode.internalTesting] emits
/// `testFlightInternalTestingOnly`. An external or public candidate must not
/// inherit an internal-only marker by accident, and an internal build must not
/// silently lose one.
///
/// Nothing here embeds signing credentials. A team identifier is an
/// organisation identifier, not a secret — it is already public in the archive,
/// the store listing and `docs/store/`. Keystore paths, passwords, key aliases
/// and certificate private material never appear in an export-options file and
/// must never be added to one.
library;

/// Whether the exported build is for the internal tester cohort or for
/// external/public distribution. Deliberately has no default value.
enum DistributionMode {
  /// TestFlight internal testers only. Emits
  /// `testFlightInternalTestingOnly`, which bars external testing and Beta App
  /// Review for the build by construction rather than by policy.
  internalTesting,

  /// External/public App Store distribution. Emits no internal-only marker.
  appStore,
}

/// Whether `xcodebuild -exportArchive` writes the container locally or sends it
/// to App Store Connect. Kept explicit because the two are not interchangeable:
/// an `export` run is how an artifact gets hashed and scanned before anyone
/// uploads anything.
enum ExportDestination {
  /// Write the container to `-exportPath`. Uploads nothing.
  export,

  /// Upload to App Store Connect.
  upload,
}

/// The only permitted value of `uploadSymbols` for a distribution export.
///
/// Not a parameter anywhere in this library. Symbols travel with the build or
/// the build is not a distribution build.
const bool kRequiredUploadSymbols = true;

/// Keys whose presence in an export-options file indicates leaked credential
/// material. An export-options plist has no legitimate need for any of them.
const List<String> kForbiddenCredentialKeys = [
  'storePassword',
  'keyPassword',
  'keyAlias',
  'storeFile',
  'password',
  'privateKey',
  'apiKey',
  'apiIssuer',
];

/// Generates an export-options plist for [mode] and [destination].
///
/// `uploadSymbols` is always `true` — see [kRequiredUploadSymbols]. There is no
/// parameter to disable it, which is the point: the 216 regression was a
/// hand-edited `false`, and a generator that cannot express `false` cannot
/// reproduce it.
String buildExportOptionsPlist({
  required DistributionMode mode,
  required ExportDestination destination,
  required String teamId,
}) {
  if (teamId.trim().isEmpty) {
    throw ArgumentError.value(teamId, 'teamId', 'must not be empty');
  }

  final lines = <String>[
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
    '<dict>',
    '\t<key>method</key>',
    '\t<string>app-store-connect</string>',
    '\t<key>destination</key>',
    '\t<string>${destination == ExportDestination.upload ? 'upload' : 'export'}'
        '</string>',
    '\t<key>teamID</key>',
    '\t<string>$teamId</string>',
    '\t<key>signingStyle</key>',
    '\t<string>automatic</string>',
    // The whole reason this file is generated rather than written by hand.
    '\t<key>uploadSymbols</key>',
    '\t<${kRequiredUploadSymbols ? 'true' : 'false'}/>',
    '\t<key>stripSwiftSymbols</key>',
    '\t<true/>',
  ];

  if (mode == DistributionMode.internalTesting) {
    lines
      ..add('\t<key>testFlightInternalTestingOnly</key>')
      ..add('\t<true/>');
  }

  lines
    ..add('</dict>')
    ..add('</plist>')
    ..add('');

  return lines.join('\n');
}

/// Keys this policy reasons about. A duplicate of any of them is a violation,
/// because a reader resolving the wrong one reaches a different conclusion than
/// Apple does.
const List<String> kPolicyKeys = [
  'uploadSymbols',
  'method',
  'destination',
  'teamID',
  'signingStyle',
  'stripSwiftSymbols',
  'testFlightInternalTestingOnly',
];

/// Removes XML comments from [xml].
///
/// Without this, a key commented out and overridden below it satisfies a
/// presence check while Apple's parser never sees the commented copy at all.
String stripXmlComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// Number of live (non-commented) `<key>$key</key>` occurrences in [plistXml].
int countKeyOccurrences(String plistXml, String key) => RegExp(
  '<key>${RegExp.escape(key)}</key>',
).allMatches(stripXmlComments(plistXml)).length;

/// Reads the value node that follows `<key>$key</key>` in [plistXml].
///
/// Returns the raw node text (`'<true/>'`, `'<false/>'`, `'<string>x</string>'`)
/// or `null` when the key is absent. Deliberately a small scanner rather than a
/// package dependency: this runs from `scripts/` on both macOS and Linux CI with
/// nothing but the Dart SDK.
///
/// Two deliberate choices, both so this agrees with the parser that actually
/// matters:
///
///  * Comments are stripped first. A commented-out key is not a key.
///  * When a key appears more than once this returns the **last** value, because
///    that is what Apple's plist parser resolves to. An earlier version took the
///    first, which meant a file `plutil` reads as `uploadSymbols => false` could
///    be reported CLEAN — the exact outcome this library exists to prevent.
///    [verifyExportOptions] additionally rejects duplicates outright, so this is
///    defence in depth rather than the only guard.
String? rawValueForKey(String plistXml, String key) {
  final stripped = stripXmlComments(plistXml);
  final keyNode = '<key>$key</key>';
  final keyIndex = stripped.lastIndexOf(keyNode);
  if (keyIndex < 0) return null;

  final rest = stripped.substring(keyIndex + keyNode.length);
  final match = RegExp(
    r'^\s*(<(?:true|false)\s*/>|<(string|integer|real)>.*?</\2>)',
    dotAll: true,
  ).firstMatch(rest);

  return match?.group(1)?.trim();
}

/// Policy violations in [plistXml]. An empty list means the file is acceptable.
///
/// Every entry is a sentence a release engineer can act on. A non-empty result
/// must abort the export or upload step — there is deliberately no
/// warning-only mode and no bypass flag, for the same reason
/// `scripts/scan_symbol_artifacts.dart` has none.
List<String> verifyExportOptions(String plistXml) {
  final violations = <String>[];

  // Duplicates first: until they are ruled out, no other answer about this file
  // is trustworthy. Apple resolves the last occurrence, a careless reader the
  // first, and the two can disagree about whether symbols are uploaded.
  for (final key in kPolicyKeys) {
    final occurrences = countKeyOccurrences(plistXml, key);
    if (occurrences > 1) {
      violations.add(
        '"$key" appears $occurrences times. A duplicated key is ambiguous: '
        'Apple resolves the LAST occurrence, so a file whose first '
        '$key looks correct can still take effect as the opposite. '
        'Keep exactly one.',
      );
    }
  }

  final uploadSymbols = rawValueForKey(plistXml, 'uploadSymbols');
  if (uploadSymbols == null) {
    violations.add(
      'uploadSymbols is OMITTED. A distribution export must set '
      '<key>uploadSymbols</key><true/> so dSYMs reach App Store Connect. '
      'Omitting it leaves Apple-side symbolication unavailable, which is the '
      'build-216 regression.',
    );
  } else if (!uploadSymbols.startsWith('<true')) {
    violations.add(
      'uploadSymbols is DISABLED ($uploadSymbols). A distribution export must '
      'set it true; build 216 shipped with it false and no dSYMs reached App '
      'Store Connect.',
    );
  }

  if (rawValueForKey(plistXml, 'method') == null) {
    violations.add(
      'method is missing. The distribution method must be explicit, never '
      'inherited from an xcodebuild default.',
    );
  }

  if (rawValueForKey(plistXml, 'destination') == null) {
    violations.add(
      'destination is missing. export and upload are not interchangeable: an '
      'export run is how an artifact is hashed and scanned before anyone '
      'uploads it. State which one this is.',
    );
  }

  if (rawValueForKey(plistXml, 'teamID') == null) {
    violations.add('teamID is missing.');
  }

  for (final key in kForbiddenCredentialKeys) {
    if (plistXml.contains('<key>$key</key>')) {
      violations.add(
        'forbidden key "$key" is present. An export-options file must never '
        'carry credential material.',
      );
    }
  }

  return violations;
}
