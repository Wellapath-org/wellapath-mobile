/// Facility data source attribution for the shipped v1.1 artifact.
///
/// This is a licence obligation, not a nicety. `facilities.ng.v1.1.json` is
/// built from GRID3 (CC BY 4.0) and HOTOSM/OpenStreetMap (ODbL 1.0). Both
/// licences require attribution wherever the data is used, and 896 of the
/// 5,344 shipped records are OpenStreetMap-derived — including every clinic
/// and every pharmacy the app can show.
///
/// Distinct from `core/facilities_v2/facility_data_source_entry.dart`, which
/// attributes the *future* GRID3-lineage v2 artifact and renders nothing
/// while the v2 gate is inactive. This widget covers what actually ships
/// today, so it is not gated.
///
/// Trust rules, matching the v2 entry:
///
///  * Every string here is a compile-time constant. Nothing is read from the
///    artifact, so no artifact field can alter what the app claims.
///  * Links are `https://` literals, opened through `url_launcher` with
///    `externalApplication`. Nothing is interpreted as markup.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The fixed attribution text and links for the shipped facility dataset.
class FacilityAttribution {
  const FacilityAttribution._();

  static const String grid3Citation =
      'Center for Integrated Earth System Information (CIESIN), '
      'Columbia University (2024). GRID3 NGA Health Facilities v2.0.';
  static const String grid3Licence = 'CC BY 4.0';
  static const String grid3LicenceUrl =
      'https://creativecommons.org/licenses/by/4.0/';
  static const String grid3SourceUrl = 'https://data.grid3.org/';

  static const String osmCredit = '© OpenStreetMap contributors';
  static const String osmLicence = 'ODbL 1.0';
  static const String osmLicenceUrl =
      'https://opendatacommons.org/licenses/odbl/1-0/';
  static const String osmSourceUrl = 'https://www.openstreetmap.org/copyright';

  /// Required by both licences: the data shown is not the data as published.
  static const String modificationStatement =
      'WellaPath filtered these sources to Lagos, the FCT and Kano, mapped '
      'facility types onto its own categories, normalised names and '
      'validated coordinates. The data shown is modified from the originals.';

  /// Required by CC BY 4.0 §3(a)(1), and true of every source here.
  static const String nonEndorsementStatement =
      'GRID3, CIESIN, Columbia University, the Humanitarian OpenStreetMap '
      'Team, OpenStreetMap contributors and the Government of Nigeria do not '
      'endorse WellaPath or this derived work.';

  /// One-line summary shown before the reader expands the detail.
  static const String summary =
      'GRID3 ($grid3Licence) · $osmCredit ($osmLicence). Modified by WellaPath.';
}

/// Collapsed attribution footer for the locator, expanding to full detail.
///
/// Collapsed it satisfies the credit both licences require; expanded it
/// carries the citation, the licence links and the modification and
/// non-endorsement statements.
class FacilityAttributionFooter extends StatefulWidget {
  const FacilityAttributionFooter({super.key});

  @override
  State<FacilityAttributionFooter> createState() =>
      _FacilityAttributionFooterState();
}

class _FacilityAttributionFooterState extends State<FacilityAttributionFooter> {
  bool _expanded = false;

  Future<void> _open(String url) async {
    final Uri uri = Uri.parse(url);
    // Belt and braces: these are const https literals, but the scheme is
    // checked anyway so a future edit cannot introduce another scheme.
    if (uri.scheme != 'https') {
      debugPrint('Refused non-https attribution link');
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle? base = Theme.of(context).textTheme.bodySmall;
    final TextStyle small = (base ?? const TextStyle()).copyWith(
      fontSize: 11,
      color: const Color(0xFF5F6368),
      height: 1.35,
    );

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Facility data sources',
            style: small.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF3C4043),
            ),
          ),
          const SizedBox(height: 3),
          Text(FacilityAttribution.summary, style: small),
          if (_expanded) ...[
            const SizedBox(height: 10),
            Text(FacilityAttribution.grid3Citation, style: small),
            const SizedBox(height: 6),
            _LinkRow(
              label: 'GRID3 licence — ${FacilityAttribution.grid3Licence}',
              onTap: () => _open(FacilityAttribution.grid3LicenceUrl),
              style: small,
            ),
            _LinkRow(
              label: 'GRID3 source',
              onTap: () => _open(FacilityAttribution.grid3SourceUrl),
              style: small,
            ),
            const SizedBox(height: 8),
            Text(FacilityAttribution.osmCredit, style: small),
            const SizedBox(height: 6),
            _LinkRow(
              label:
                  'OpenStreetMap licence — ${FacilityAttribution.osmLicence}',
              onTap: () => _open(FacilityAttribution.osmLicenceUrl),
              style: small,
            ),
            _LinkRow(
              label: 'OpenStreetMap copyright',
              onTap: () => _open(FacilityAttribution.osmSourceUrl),
              style: small,
            ),
            const SizedBox(height: 10),
            Text(FacilityAttribution.modificationStatement, style: small),
            const SizedBox(height: 8),
            Text(FacilityAttribution.nonEndorsementStatement, style: small),
          ],
          const SizedBox(height: 4),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            // Constrained rather than padded: an 11px label with symmetric
            // padding lands around 38px, short of the 44px minimum, and the
            // arithmetic silently changes with the text scale.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _expanded ? 'Show less' : 'Licences and credits',
                  style: small.copyWith(
                    color: const Color(0xFF1A73E8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.label,
    required this.onTap,
    required this.style,
  });

  final String label;
  final VoidCallback onTap;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: style.copyWith(
              color: const Color(0xFF1A73E8),
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }
}
