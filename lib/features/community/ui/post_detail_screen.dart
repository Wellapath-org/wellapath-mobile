import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import '../data/community_repositories.dart';
import '../domain/comment.dart';
import '../domain/community_me.dart';
import '../domain/community_permissions.dart';
import '../domain/community_validation.dart';
import '../domain/post.dart';
import '../domain/public_author.dart';
import '../domain/report.dart';
import 'community_scope.dart';
import 'community_widgets.dart';
import 'report_sheet.dart';

/// A post and its single-level comments. No replies to comments.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailData {
  const _PostDetailData(this.post, this.comments);

  final Post post;
  final List<Comment> comments;
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Future<_PostDetailData>? _data;
  final TextEditingController _comment = TextEditingController();
  DisplayMode _mode = DisplayMode.pseudonymous;
  String? _commentError;

  /// Same-intent retries reuse the draft and its `Idempotency-Key` (§1.2).
  CommentDraft? _pendingComment;

  CommunityRepository get _repo =>
      CommunityScope.of(context).services.community;

  /// Restricted accounts are read-only (they may still report and delete
  /// their own content); unknown viewer means "offer it, let the server
  /// decide".
  bool get _canComment {
    final CommunityMe? me = CommunityScope.of(context).services.viewer.value;
    return me == null || me.can(CommunityCapability.createContent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<_PostDetailData> _load() async {
    final Post post = await _repo.getPost(widget.postId);
    final CommunityPage<Comment> comments = await _repo.listComments(post.id);
    return _PostDetailData(post, comments.items);
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _sendComment() async {
    CommentDraft draft;
    try {
      draft = CommentDraft(
        postId: widget.postId,
        body: _comment.text,
        displayMode: _mode,
      );
      final CommentDraft? pending = _pendingComment;
      if (pending != null &&
          pending.body == draft.body &&
          pending.displayMode == draft.displayMode) {
        draft = pending;
      }
      _pendingComment = draft;
    } on CommunityValidationException catch (e) {
      setState(() {
        _commentError = e.rule == 'required'
            ? 'Write a comment first.'
            : 'Comments can be up to ${CommunityLimits.commentBodyMax} '
                  'characters.';
      });
      return;
    }
    try {
      await _repo.createComment(draft);
      _comment.clear();
      _commentError = null;
      _pendingComment = null;
      _reload();
    } catch (e) {
      if (!mounted || CommunityScope.handleError(context, e)) return;
      _snack(
        e is CommunityException && e.reason == 'profile_required'
            ? 'Choose your Community name before commenting.'
            : communityErrorText(
                e,
                fallback: 'Your comment could not be sent.',
              ),
      );
    }
  }

  Future<void> _deletePost(Post post) async {
    try {
      await _repo.deletePost(post.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted || CommunityScope.handleError(context, e)) return;
      _snack('The post could not be deleted.');
    }
  }

  Future<void> _deleteComment(Comment c) async {
    try {
      await _repo.deleteComment(c.id);
      _reload();
    } catch (e) {
      if (!mounted || CommunityScope.handleError(context, e)) return;
      _snack('The comment could not be deleted.');
    }
  }

  Future<void> _report(ReportTargetType type, String id) async {
    final bool sent = await showReportSheet(
      context,
      targetType: type,
      targetId: id,
    );
    if (sent && mounted) _snack('Thanks. A moderator will review it.');
  }

  Widget _menu({
    required bool own,
    required VoidCallback onDelete,
    required VoidCallback onReport,
    required String keyPrefix,
  }) {
    return PopupMenuButton<String>(
      key: Key('${keyPrefix}_menu'),
      onSelected: (String v) => v == 'delete' ? onDelete() : onReport(),
      itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
        if (own)
          const PopupMenuItem<String>(value: 'delete', child: Text('Delete'))
        else
          const PopupMenuItem<String>(value: 'report', child: Text('Report')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommunityScreenFrame(
      title: 'Post',
      body: FutureBuilder<_PostDetailData>(
        future: _data,
        builder: (BuildContext context, AsyncSnapshot<_PostDetailData> snap) {
          if (snap.hasError) {
            CommunityScope.handleError(context, snap.error!);
            final Object e = snap.error!;
            // §8.2 C4: anything not visible (hidden, removed, deleted,
            // tombstoned) is a plain 404. Neutral copy, no reason given.
            final bool gone =
                e is CommunityException &&
                e.code == CommunityErrorCode.notFound;
            return Center(
              child: Text(
                gone ? 'This post is no longer available.' : 'Could not load.',
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final Post post = snap.data!.post;
          final List<Comment> comments = snap.data!.comments;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Brand.gutter),
            children: [
              Row(
                children: [
                  Expanded(
                    child: AuthorLine(
                      author: post.author,
                      isOwn: post.viewerIsAuthor,
                    ),
                  ),
                  _menu(
                    own: post.viewerIsAuthor,
                    keyPrefix: 'post',
                    onDelete: () => _deletePost(post),
                    onReport: () => _report(ReportTargetType.post, post.id),
                  ),
                ],
              ),
              const SizedBox(height: Brand.space2),
              Text(post.body, style: Brand.body),
              const SizedBox(height: Brand.space2),
              Text(formatCommunityTime(post.createdAt), style: Brand.caption),
              const Divider(height: Brand.space8),
              Text('Comments (${comments.length})', style: Brand.bodyStrong),
              const SizedBox(height: Brand.space2),
              for (final Comment c in comments)
                Padding(
                  key: Key('comment_${c.id}'),
                  padding: const EdgeInsets.only(bottom: Brand.space3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AuthorLine(
                              author: c.author,
                              isOwn: c.viewerIsAuthor,
                            ),
                            const SizedBox(height: Brand.space1),
                            Text(c.body, style: Brand.body),
                          ],
                        ),
                      ),
                      _menu(
                        own: c.viewerIsAuthor,
                        keyPrefix: 'comment_${c.id}',
                        onDelete: () => _deleteComment(c),
                        onReport: () => _report(ReportTargetType.comment, c.id),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Brand.space3),
              if (_canComment) ...[
                TextField(
                  key: const Key('comment_body'),
                  controller: _comment,
                  maxLength: CommunityLimits.commentBodyMax,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'Add a comment',
                    errorText: _commentError,
                    border: const OutlineInputBorder(),
                  ),
                ),
                DisplayModeSelector(
                  value: _mode,
                  displayName: null,
                  onChanged: (DisplayMode m) => setState(() => _mode = m),
                ),
                const SizedBox(height: Brand.space2),
                FilledButton(
                  key: const Key('comment_submit'),
                  onPressed: _sendComment,
                  style: FilledButton.styleFrom(
                    backgroundColor: Brand.primary,
                    minimumSize: const Size.fromHeight(Brand.minTapTarget),
                  ),
                  child: const Text('Comment'),
                ),
              ],
              const SizedBox(height: Brand.space8),
            ],
          );
        },
      ),
    );
  }
}
