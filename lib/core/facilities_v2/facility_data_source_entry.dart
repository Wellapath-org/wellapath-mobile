/// "Facility data source" — the attribution entry the facility locator
/// must show when (and only when) an approved Facilities 2.0 artifact is
/// actually serving results.
///
/// Visibility is bound to the same two facts as every other v2 behaviour:
/// [FacilitiesV2Gate.active] and a successful v2 load. Today the gate can
/// never be active (the candidate is `candidate_unapproved` /
/// `may_publish: false`), so this widget renders nothing in every build
/// that exists — including build 210 — and the shipped v1.1 locator is not
/// changed by it in any way: nothing outside `lib/core/facilities_v2/`
/// references this file, and the v1.1 path keeps its current (absent)
/// facility-data attribution behaviour.
///
/// Mounting this entry inside the locator screen is part of the future v2
/// activation change, recorded as a launch requirement in
/// `docs/FACILITIES_V2_CONSUMER.md` — the Knowledge Base attribution
/// notice makes in-app attribution a condition of first publication.
///
/// Safety: all displayed values come from [FacilitiesV2Attribution], which
/// admits plain text and validated `https://` links only. This widget
/// never interprets artifact data as markup and never launches any URI
/// that is not one of those validated links.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'facilities_v2_attribution.dart';
import 'facilities_v2_gate.dart';
import 'facilities_v2_loader.dart';

class FacilityDataSourceEntry extends StatelessWidget {
  const FacilityDataSourceEntry({
    required this.gate,
    required this.loadStatus,
    required this.attribution,
    this.launchLink,
    super.key,
  });

  final FacilitiesV2Gate gate;

  /// The most recent v2 load outcome, or null when no load has happened.
  final FacilitiesV2LoadStatus? loadStatus;

  final FacilitiesV2Attribution attribution;

  /// Test seam. Production uses url_launcher's [launchUrl] in an external
  /// browser; the URL reaching this point is already HTTPS-validated.
  final Future<bool> Function(Uri url)? launchLink;

  /// Attribution accompanies v2 data only: the gate must be active AND v2
  /// must actually be serving (from network or its own cache). A fallback
  /// to v1.1 shows v1.1 data, so the GRID3 notice must not appear.
  bool get isVisible =>
      gate.active &&
      (loadStatus == FacilitiesV2LoadStatus.loadedFromNetwork ||
          loadStatus == FacilitiesV2LoadStatus.loadedFromCache);

  Future<void> _open(Uri url) async {
    // Defence in depth: even a future caller bug cannot launch a non-HTTPS
    // scheme from here.
    if (url.scheme != 'https' || url.host.isEmpty) return;
    final launcher =
        launchLink ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    try {
      await launcher(url);
    } on Object {
      // A missing browser must never crash the locator.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Facility data source information',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Facility data source',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(attribution.citation, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              FacilitiesV2Attribution.normalizationStatement,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              FacilitiesV2Attribution.nonEndorsementStatement,
              style: theme.textTheme.bodySmall,
            ),
            Wrap(
              spacing: 8,
              children: [
                if (attribution.licenceUrl != null)
                  TextButton(
                    onPressed: () => _open(attribution.licenceUrl!),
                    child: Text(
                      'Licence: ${attribution.licenceName}',
                      semanticsLabel:
                          'Open the ${attribution.licenceName} licence '
                          'in your browser',
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Licence: ${attribution.licenceName}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (attribution.doiUrl != null)
                  TextButton(
                    onPressed: () => _open(attribution.doiUrl!),
                    child: const Text(
                      'Source dataset (DOI)',
                      semanticsLabel:
                          'Open the source dataset DOI page in your browser',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
