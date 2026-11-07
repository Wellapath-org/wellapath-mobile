import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import 'community_scope.dart';
import 'space_list_screen.dart';

/// The More-tab entry point. Renders nothing until the gate says yes, and
/// re-asks the server (bypassing the cache) on every tap before navigating.
///
/// The More screen only builds this widget at all when the compile-time flag
/// is on; in a default build it is not in the tree.
class CommunityEntryRow extends StatefulWidget {
  const CommunityEntryRow({super.key, required this.module});

  final CommunityModule module;

  static const String label = 'Community (internal)';

  @override
  State<CommunityEntryRow> createState() => _CommunityEntryRowState();
}

class _CommunityEntryRowState extends State<CommunityEntryRow> {
  bool _visible = false;
  bool _opening = false;
  CommunityServices? _services;

  @override
  void initState() {
    super.initState();
    _evaluate();
  }

  Future<void> _evaluate() async {
    final bool open = await widget.module.gate.isOpen();
    if (mounted) setState(() => _visible = open);
  }

  Future<void> _enter() async {
    if (_opening) return;
    setState(() => _opening = true);
    final bool open = await widget.module.gate.isOpen(fresh: true);
    if (!mounted) return;
    setState(() {
      _opening = false;
      _visible = open;
    });
    if (!open) return;
    final CommunityServices services = _services ??= widget.module
        .createServices();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => CommunityScope(
          gate: widget.module.gate,
          services: services,
          child: const SpaceListScreen(),
        ),
      ),
    );
    if (mounted) await _evaluate();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(Brand.radiusSurface),
        child: InkWell(
          key: const Key('community_entry_row'),
          onTap: _enter,
          borderRadius: BorderRadius.circular(Brand.radiusSurface),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radiusSurface),
              border: Border.all(color: Brand.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.forum_outlined, color: Brand.primary, size: 21),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    CommunityEntryRow.label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Brand.ink,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Brand.inkSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
