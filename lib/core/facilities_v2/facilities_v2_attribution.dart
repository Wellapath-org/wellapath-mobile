/// Facilities 2.0 source attribution — the CC BY 4.0 notice that must ship
/// with any approved GRID3-lineage artifact (Knowledge Base handoff
/// requirement: `facilities/ATTRIBUTION_GRID3.md` §"Where this notice must
/// appear").
///
/// Trust rules:
///
///  * **Artifact metadata is data, never markup or code.** Every field is
///    consumed as plain text, length-capped and control-character-checked;
///    nothing from the artifact is ever interpreted as HTML, a widget, or
///    an executable scheme.
///  * **Links are HTTPS or nothing.** A link only renders if it parses as
///    an absolute `https://` URL with a real host. `http:`, `javascript:`,
///    `data:`, `file:` and every other scheme are dropped, not repaired.
///  * **Invalid metadata falls back to the vendored notice**, because the
///    citation is a licence obligation — it must not disappear just
///    because a metadata field is malformed.
///  * The fixed statements (normalization disclosure, non-endorsement) are
///    compile-time constants and can never be overridden by artifact data.
library;

class FacilitiesV2Attribution {
  const FacilitiesV2Attribution({
    required this.citation,
    required this.licenceName,
    this.licenceUrl,
    this.doiUrl,
  });

  /// The source citation, displayed verbatim.
  final String citation;

  /// Licence display name, e.g. `CC BY 4.0`.
  final String licenceName;

  /// Validated HTTPS link to the licence text, or null (no link rendered).
  final Uri? licenceUrl;

  /// Validated HTTPS DOI link for the source dataset, or null.
  final Uri? doiUrl;

  /// WellaPath's modification disclosure, required by CC BY 4.0. Constant —
  /// artifact metadata cannot override what the app claims about itself.
  static const String normalizationStatement =
      'WellaPath normalized and projected the source data. '
      'No coordinate was moved or invented and no value was added from '
      'any other source.';

  /// Non-endorsement, required by CC BY 4.0 §3(a)(1) and the Knowledge
  /// Base attribution notice. Constant for the same reason.
  static const String nonEndorsementStatement =
      'GRID3, CIESIN, Columbia University and the Government of Nigeria '
      'do not endorse WellaPath or this derived work.';

  /// The vendored GRID3 notice — the exact citation the Knowledge Base
  /// records as the licence obligation for this lineage. Used whenever
  /// artifact metadata is absent or fails validation.
  static const FacilitiesV2Attribution grid3Default = FacilitiesV2Attribution(
    citation:
        'Center for Integrated Earth System Information (CIESIN), '
        'Columbia University 2024. GRID3 NGA - Health Facilities v2.0. '
        'New York: GRID3. https://doi.org/10.7916/kv1n-0743. '
        'Accessed 20 July 2026.',
    licenceName: 'CC BY 4.0',
    // Static, reviewed constants — not artifact input.
    licenceUrl: null,
    doiUrl: null,
  );

  /// Static reviewed links for the default notice. Kept out of the const
  /// constructor only because `Uri` has no const parser.
  static Uri get grid3DefaultLicenceUrl =>
      Uri.parse('https://creativecommons.org/licenses/by/4.0');
  static Uri get grid3DefaultDoiUrl =>
      Uri.parse('https://doi.org/10.7916/kv1n-0743');

  /// The default notice with its reviewed links attached.
  static FacilitiesV2Attribution get grid3DefaultWithLinks =>
      FacilitiesV2Attribution(
        citation: grid3Default.citation,
        licenceName: grid3Default.licenceName,
        licenceUrl: grid3DefaultLicenceUrl,
        doiUrl: grid3DefaultDoiUrl,
      );

  static const int _maxTextLength = 600;

  /// Accepts only a plausible plain-text value: a non-empty string within
  /// the length cap and free of control characters. Anything else → null.
  static String? _plainText(Object? value, {int max = _maxTextLength}) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > max) return null;
    if (trimmed.codeUnits.any((u) => u < 0x20 || u == 0x7f)) return null;
    return trimmed;
  }

  /// Accepts only an absolute `https://` URL with a non-empty host — every
  /// other scheme (http, javascript, data, file, intent, tel, …) is
  /// rejected. Rejection means "render no link", never "render as text".
  static Uri? validatedHttpsUrl(Object? value) {
    final text = _plainText(value);
    if (text == null) return null;
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    if (!uri.isAbsolute || uri.scheme != 'https' || uri.host.isEmpty) {
      return null;
    }
    if (uri.userInfo.isNotEmpty) return null;
    return uri;
  }

  /// Builds the display attribution from artifact `_metadata`. Per-field
  /// fallback to [grid3Default]: a valid citation with a malformed licence
  /// URL keeps the citation and simply renders the licence without a link.
  static FacilitiesV2Attribution fromArtifactMetadata(Object? metadata) {
    if (metadata is! Map) return grid3DefaultWithLinks;
    final source = metadata['source'];
    if (source is! Map) return grid3DefaultWithLinks;

    return FacilitiesV2Attribution(
      citation:
          _plainText(source['attribution_citation']) ?? grid3Default.citation,
      licenceName:
          _plainText(source['licence'], max: 60) ?? grid3Default.licenceName,
      licenceUrl:
          validatedHttpsUrl(source['attribution_licence_url']) ??
          grid3DefaultLicenceUrl,
      doiUrl: validatedHttpsUrl(source['doi']) ?? grid3DefaultDoiUrl,
    );
  }
}
