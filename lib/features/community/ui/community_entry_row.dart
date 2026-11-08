import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import '../gate/community_gate.dart';
import 'community_scope.dart';
import 'sign_in_screen.dart';
import 'space_list_screen.dart';

/// The Community entry point (Home and More).
///
/// **Visibility.** Callers build this widget only when the compile-time flag
/// is on (`module.gate.compileTimeEnabled`), so a default build never has it
/// in the tree and never makes a request. When it is built, it is always
/// visible: an entry that silently disappeared whenever `/v1/features` was
/// slow (a sleeping staging instance) or the server said no was not
/// discoverable (build 218).
///
/// **Access is unchanged.** Visibility grants nothing. Every tap re-asks the
/// server, bypassing the cache (`gate.check(fresh: true)`), and only
/// [CommunityGateDecision.open] ever builds Community content:
///  - `signInRequired` → the existing Community sign-in screen, then the gate
///    is asked again; content opens only if the server now allows the account;
///  - `hidden` → no navigation; a short message says why (not available for
///    this account, switched off, or unreachable). No blank page, no route.
class CommunityEntryRow extends StatefulWidget {
  const CommunityEntryRow({super.key, required this.module});

  final CommunityModule module;

  static const String label = 'Community';
  static const String subtitle = 'Ask questions and connect with others.';

  /// Messages for a tap that does not open Community.
  static const String notAllowedMessage =
      'Community is not available for this account.';
  static const String disabledMessage = 'Community is not available right now.';
  static const String unreachableMessage =
      'Could not reach Community. Check your connection and try again.';

  static String messageFor(CommunityUnavailableReason? reason) {
    return switch (reason) {
      CommunityUnavailableReason.notAllowed => notAllowedMessage,
      CommunityUnavailableReason.unreachable => unreachableMessage,
      CommunityUnavailableReason.disabled ||
      CommunityUnavailableReason.notConfigured ||
      null => disabledMessage,
    };
  }

  @override
  State<CommunityEntryRow> createState() => _CommunityEntryRowState();
}

class _CommunityEntryRowState extends State<CommunityEntryRow> {
  bool _opening = false;
  CommunityServices? _services;

  void _tell(CommunityUnavailableReason? reason) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(CommunityEntryRow.messageFor(reason))),
      );
  }

  Future<void> _enter() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      CommunityGateResult r = await widget.module.gate.check(fresh: true);
      if (!mounted) return;
      if (r.decision == CommunityGateDecision.signInRequired) {
        final bool? signedIn = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (BuildContext _) =>
                CommunitySignInScreen(auth: widget.module.auth),
          ),
        );
        if (!mounted || signedIn != true) return;
        r = await widget.module.gate.check(fresh: true);
        if (!mounted) return;
      }
      if (r.decision != CommunityGateDecision.open) {
        // A second signInRequired (still no session) or hidden: nothing opens.
        _tell(r.reason);
        return;
      }
      final CommunityServices services = _services ??= widget.module
          .createServices();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => CommunityScope(
            gate: widget.module.gate,
            services: services,
            auth: widget.module.auth,
            child: const SpaceListScreen(),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The same shape as the Home screen's secondary action rows.
    return Semantics(
      button: true,
      label: '${CommunityEntryRow.label}. ${CommunityEntryRow.subtitle}',
      excludeSemantics: true,
      child: Material(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(Brand.radiusSurface),
        child: InkWell(
          key: const Key('community_entry_row'),
          onTap: _enter,
          borderRadius: BorderRadius.circular(Brand.radiusSurface),
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.symmetric(
              horizontal: Brand.space4,
              vertical: Brand.space3,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radiusSurface),
              border: Border.all(color: Brand.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.forum_outlined,
                  color: Brand.primary,
                  size: 24,
                ),
                const SizedBox(width: Brand.space3),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(CommunityEntryRow.label, style: Brand.cardTitle),
                      SizedBox(height: 2),
                      Text(CommunityEntryRow.subtitle, style: Brand.caption),
                    ],
                  ),
                ),
                if (_opening)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.chevron_right_rounded, color: Brand.inkSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
