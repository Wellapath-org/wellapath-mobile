import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import '../domain/community_profile.dart';
import '../domain/community_validation.dart';
import '../domain/post.dart';
import '../domain/public_author.dart';
import '../domain/space.dart';
import 'community_scope.dart';
import 'community_widgets.dart';

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
  Future<CommunityProfile?>? _profile;

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
    final PostDraft draft;
    try {
      draft = PostDraft(
        spaceId: widget.space.id,
        body: _body.text,
        displayMode: _mode,
      );
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
      setState(() {
        _sending = false;
        _error = 'Your post could not be sent. Please try again.';
      });
    }
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
                  return DisplayModeSelector(
                    value: _mode,
                    displayName: snap.data?.displayName,
                    onChanged: (DisplayMode m) => setState(() => _mode = m),
                  );
                },
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
