import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/brand.dart';
import '../data/community_repositories.dart';
import '../domain/community_session.dart';
import '../domain/community_validation.dart';
import 'community_scope.dart';
import 'community_widgets.dart';
import 'profile_setup_screen.dart';

/// The member's own Community account: name, signed-in devices (recovery),
/// data export, account deletion and sign-out. No privileged controls: the
/// app has no moderator or admin UI.
class CommunityAccountScreen extends StatefulWidget {
  const CommunityAccountScreen({super.key});

  @override
  State<CommunityAccountScreen> createState() => _CommunityAccountScreenState();
}

class _CommunityAccountScreenState extends State<CommunityAccountScreen> {
  Future<List<DeviceSession>>? _devices;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devices ??= CommunityScope.of(context).auth.devices();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted && !CommunityScope.handleError(context, e)) {
        _snack(communityErrorText(e, fallback: failure));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOutOthers() {
    return _run(() async {
      final int n = await CommunityScope.of(context).auth.signOutOtherDevices();
      if (!mounted) return;
      _snack(
        n == 1 ? 'Signed out 1 other device.' : 'Signed out $n other devices.',
      );
      setState(() {
        _devices = CommunityScope.of(context).auth.devices();
      });
    }, 'Other devices could not be signed out.');
  }

  Future<void> _export() {
    return _run(() async {
      final Map<String, dynamic> doc = await CommunityScope.of(
        context,
      ).services.dataRights.exportMyData();
      if (!mounted) return;
      await pushCommunityRoute<void>(
        context,
        (BuildContext _) => CommunityExportScreen(document: doc),
      );
    }, 'Your data could not be downloaded. Please try again later.');
  }

  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext _) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) return;
    final CommunityScope scope = CommunityScope.of(context);
    await _run(() async {
      try {
        await scope.services.dataRights.deleteMyAccount(
          CommunityLimits.deleteAccountPhrase,
        );
      } on CommunityException catch (e) {
        if (e.reason == 'privileged_account') {
          _snack(
            'Moderator and admin accounts must be changed to member first.',
          );
          return;
        }
        rethrow;
      }
      await scope.auth.forgetDevice();
      if (!mounted) return;
      CommunityScope.close(context);
    }, 'Your account could not be deleted. Please try again later.');
  }

  Future<void> _signOut() async {
    final CommunityScope scope = CommunityScope.of(context);
    await scope.auth.signOut();
    if (mounted) CommunityScope.close(context);
  }

  @override
  Widget build(BuildContext context) {
    return CommunityScreenFrame(
      title: 'Account',
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Brand.gutter),
        children: [
          ListTile(
            key: const Key('account_change_name'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Change my Community name'),
            onTap: () => pushCommunityRoute<void>(
              context,
              (BuildContext _) => const ProfileSetupScreen(),
            ),
          ),
          const Divider(),
          const Text('Signed-in devices', style: Brand.bodyStrong),
          FutureBuilder<List<DeviceSession>>(
            future: _devices,
            builder:
                (BuildContext context, AsyncSnapshot<List<DeviceSession>> s) {
                  if (s.hasError) {
                    return const Text('Devices could not load.');
                  }
                  if (!s.hasData) return const LinearProgressIndicator();
                  return Column(
                    children: [
                      for (final DeviceSession d in s.data!)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.phone_android_outlined),
                          title: Text(
                            (d.deviceLabel ?? 'A device') +
                                (d.current ? ' (this device)' : ''),
                          ),
                          subtitle: Text(
                            'Last used ${formatCommunityTime(d.lastUsedAt)}',
                          ),
                        ),
                    ],
                  );
                },
          ),
          TextButton(
            key: const Key('account_revoke_others'),
            onPressed: _busy ? null : _signOutOthers,
            child: const Text('Sign out other devices'),
          ),
          const Divider(),
          ListTile(
            key: const Key('account_export'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: const Text('Get a copy of my Community data'),
            onTap: _busy ? null : _export,
          ),
          ListTile(
            key: const Key('account_delete'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete my Community account'),
            onTap: _busy ? null : _delete,
          ),
          const Divider(),
          ListTile(
            key: const Key('account_sign_out'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: _busy ? null : _signOut,
          ),
        ],
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final TextEditingController _phrase = TextEditingController();

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool matches = _phrase.text == CommunityLimits.deleteAccountPhrase;
    return AlertDialog(
      title: const Text('Delete your Community account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Your name, profile and notifications are erased and your posts '
            'and comments are removed. This cannot be undone. Type '
            '${CommunityLimits.deleteAccountPhrase} to confirm.',
          ),
          TextField(
            key: const Key('delete_phrase'),
            controller: _phrase,
            onChanged: (String _) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('delete_confirm'),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

/// Shows the M7 export to its owner, with a copy action. It is never logged
/// or written anywhere by the app.
class CommunityExportScreen extends StatelessWidget {
  const CommunityExportScreen({super.key, required this.document});

  final Map<String, dynamic> document;

  @override
  Widget build(BuildContext context) {
    final String text = const JsonEncoder.withIndent('  ').convert(document);
    return CommunityScreenFrame(
      title: 'Your Community data',
      actions: [
        IconButton(
          key: const Key('export_copy'),
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_outlined),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Copied.')));
            }
          },
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Brand.gutter),
        child: SelectableText(text, style: Brand.caption),
      ),
    );
  }
}
