import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import '../domain/public_author.dart';
import 'community_safety_banner.dart';

/// Standard scaffold for every Community screen: app bar, the persistent
/// safety banner, then the body.
class CommunityScreenFrame extends StatelessWidget {
  const CommunityScreenFrame({
    super.key,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: AppBar(
        title: Text(title),
        actions: actions,
        backgroundColor: Brand.surface,
        foregroundColor: Brand.ink,
        elevation: 0,
      ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                Brand.gutter,
                Brand.space2,
                Brand.gutter,
                Brand.space3,
              ),
              child: CommunitySafetyBanner(),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// "SunnyMum · Midwife (verified)" or "Community member".
class AuthorLine extends StatelessWidget {
  const AuthorLine({super.key, required this.author, this.isOwn = false});

  final PublicAuthor author;
  final bool isOwn;

  @override
  Widget build(BuildContext context) {
    final String? badge = author.badge == null
        ? null
        : 'Verified ${author.badge!.profession}';
    return Wrap(
      spacing: Brand.space2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          author.label + (isOwn ? ' (you)' : ''),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Brand.ink,
          ),
        ),
        if (badge != null)
          Container(
            key: const Key('verified_badge'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Brand.primarySurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badge,
              style: const TextStyle(fontSize: 12, color: Brand.primary),
            ),
          ),
      ],
    );
  }
}

/// Named / pseudonymous choice for a post or comment.
class DisplayModeSelector extends StatelessWidget {
  const DisplayModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.displayName,
  });

  final DisplayMode value;
  final ValueChanged<DisplayMode> onChanged;
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<DisplayMode>(
      segments: <ButtonSegment<DisplayMode>>[
        const ButtonSegment<DisplayMode>(
          value: DisplayMode.pseudonymous,
          label: Text('Community member'),
        ),
        ButtonSegment<DisplayMode>(
          value: DisplayMode.named,
          label: Text(displayName ?? 'Display name'),
        ),
      ],
      selected: <DisplayMode>{value},
      onSelectionChanged: (Set<DisplayMode> s) => onChanged(s.first),
    );
  }
}

String formatCommunityTime(DateTime t) {
  final DateTime local = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
