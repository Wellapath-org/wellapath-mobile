import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import '../data/community_repositories.dart';
import '../domain/community_profile.dart';
import '../domain/community_validation.dart';
import 'community_scope.dart';
import 'community_widgets.dart';

/// Choose (or change) the public Community display name (`PUT
/// /v1/community/me/profile`). A profile is required before posting,
/// commenting or claiming a profession, pseudonymous posting included.
/// Pops the saved [CommunityProfile].
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, this.current});

  final String? current;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.current ?? '',
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static String _ruleText(String rule) {
    switch (rule) {
      case 'required':
      case 'min_length':
        return 'Use at least ${CommunityLimits.displayNameMin} characters.';
      case 'max_length':
        return 'Use at most ${CommunityLimits.displayNameMax} characters.';
      case 'not_allowed_value':
        return 'Do not use an email address or phone number.';
      default:
        return 'Use letters, numbers, single spaces, and . _ or - only.';
    }
  }

  Future<void> _save() async {
    try {
      CommunityProfile.validateDisplayName(_name.text);
    } on CommunityValidationException catch (e) {
      setState(() => _error = _ruleText(e.rule));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final CommunityProfile p = await CommunityScope.of(
        context,
      ).services.community.setDisplayName(_name.text);
      if (mounted) Navigator.of(context).pop(p);
    } catch (e) {
      if (!mounted || CommunityScope.handleError(context, e)) return;
      String message = communityErrorText(
        e,
        fallback: 'Your name could not be saved. Please try again.',
      );
      if (e is CommunityException) {
        if (e.reason == 'display_name_taken') {
          message = 'That name is taken. Try another.';
        } else if (e.code == CommunityErrorCode.validationFailed) {
          message = _ruleText(e.rule ?? 'pattern');
        }
      }
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommunityScreenFrame(
      title: 'Your Community name',
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Brand.gutter),
        children: [
          const Text(
            'Other members see this name when you post as yourself. You can '
            'still post as "Community member" without showing it. Moderators '
            'can always see who wrote a post.',
            style: Brand.body,
          ),
          const SizedBox(height: Brand.space4),
          TextField(
            key: const Key('profile_display_name'),
            controller: _name,
            maxLength: CommunityLimits.displayNameMax,
            decoration: InputDecoration(
              labelText: 'Display name',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Brand.space3),
          FilledButton(
            key: const Key('profile_save'),
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: Brand.primary,
              minimumSize: const Size.fromHeight(Brand.minTapTarget),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
