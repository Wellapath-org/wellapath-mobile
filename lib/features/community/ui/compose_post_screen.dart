import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import '../data/community_repositories.dart';
import '../domain/community_profile.dart';
import '../domain/community_validation.dart';
import '../domain/post.dart';
import '../domain/public_author.dart';
import '../domain/space.dart';
import 'community_scope.dart';
import 'community_widgets.dart';
import 'profile_setup_screen.dart';

/// Text-only compose. No images, attachments, links preview or AI help.
class ComposePostScreen extends StatefulWidget {
  const ComposePostScreen({super.key, required this.space});

  final Space space;

  @override
  State<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends State<ComposePostScreen> {
  final TextEditingController _body = TextEditingController();
  DisplayMode _mode = DisplayMode.pseudonymous;
  String? _error;
  bool _sending = false;
  bool _needsProfile = false;
  Future<CommunityProfile?>? _profile;

  /// The intent being sent. A retry of the same text and mode reuses it, and
  /// so its `Idempotency-Key` (§1.2): a lost response never double-posts.
  PostDraft? _pending;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _profile ??= CommunityScope.of(context).services.community.getProfile();
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    PostDraft draft;
    try {
      draft = PostDraft(
        spaceId: widget.space.id,
        body: _body.text,
        displayMode: _mode,
      );
      final PostDraft? pending = _pending;
      if (pending != null &&
          pending.body == draft.body &&
          pending.displayMode == draft.displayMode) {
        draft = pending;
      }
      _pending = draft;
    } on CommunityValidationException catch (e) {
      setState(() {
        _error = e.rule == 'required'
            ? 'Write something before posting.'
            : 'Posts can be up to ${CommunityLimits.postBodyMax} characters.';
      });
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final Post post = await CommunityScope.of(
        context,
      ).services.community.createPost(draft);
      if (mounted) Navigator.of(context).pop(post);
    } catch (e) {
      if (!mounted) return;
      if (CommunityScope.handleError(context, e)) return;
      final bool needsProfile =
          e is CommunityException && e.reason == 'profile_required';
      setState(() {
        _sending = false;
        _needsProfile = needsProfile;
        _error = needsProfile
            ? 'Choose your Community name before posting.'
            : communityErrorText(
                e,
                fallback: 'Your post could not be sent. Please try again.',
              );
      });
    }
  }

  Future<void> _setUpProfile() async {
    await pushCommunityRoute<CommunityProfile>(
      context,
      (BuildContext _) => const ProfileSetupScreen(),
    );
    if (!mounted) return;
    setState(() {
      _needsProfile = false;
      _error = null;
      _profile = CommunityScope.of(context).services.community.getProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    return CommunityScreenFrame(
      title: 'New post',
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Brand.gutter),
        children: [
          Text('Posting in ${widget.space.name}', style: Brand.caption),
          const SizedBox(height: Brand.space3),
          TextField(
            key: const Key('compose_body'),
            controller: _body,
            minLines: 5,
            maxLines: 10,
            maxLength: CommunityLimits.postBodyMax,
            decoration: InputDecoration(
              hintText: 'Share an experience or ask the community',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Brand.space3),
          const Text('Show my post as', style: Brand.bodyStrong),
          const SizedBox(height: Brand.space2),
          FutureBuilder<CommunityProfile?>(
            future: _profile,
            builder:
                (BuildContext context, AsyncSnapshot<CommunityProfile?> snap) {
                  if (snap.connectionState == ConnectionState.done &&
                      snap.data == null) {
                    return OutlinedButton(
                      key: const Key('compose_setup_profile'),
                      onPressed: _setUpProfile,
                      child: const Text('Choose your Community name first'),
                    );
                  }
                  return DisplayModeSelector(
                    value: _mode,
                    displayName: snap.data?.displayName,
                    onChanged: (DisplayMode m) => setState(() => _mode = m),
                  );
                },
          ),
          if (_needsProfile)
            TextButton(
              onPressed: _setUpProfile,
              child: const Text('Choose a name'),
            ),
          const SizedBox(height: Brand.space6),
          FilledButton(
            key: const Key('compose_submit'),
            onPressed: _sending ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: Brand.primary,
              minimumSize: const Size.fromHeight(Brand.minTapTarget),
            ),
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }
}
