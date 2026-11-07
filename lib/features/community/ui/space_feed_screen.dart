import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import '../data/community_repositories.dart';
import '../domain/community_me.dart';
import '../domain/community_permissions.dart';
import '../domain/post.dart';
import '../domain/space.dart';
import 'community_scope.dart';
import 'community_widgets.dart';
import 'compose_post_screen.dart';
import 'post_detail_screen.dart';

class SpaceFeedScreen extends StatefulWidget {
  const SpaceFeedScreen({super.key, required this.space});

  final Space space;

  @override
  State<SpaceFeedScreen> createState() => _SpaceFeedScreenState();
}

class _SpaceFeedScreenState extends State<SpaceFeedScreen> {
  Future<CommunityPage<Post>>? _page;
  final List<Post> _more = <Post>[];
  String? _nextCursor;
  bool _loadingMore = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _page ??= _load();
  }

  Future<CommunityPage<Post>> _load() async {
    final CommunityPage<Post> page = await CommunityScope.of(
      context,
    ).services.community.listPosts(widget.space.id);
    _more.clear();
    _nextCursor = page.nextCursor;
    return page;
  }

  void _reload() {
    setState(() {
      _page = _load();
    });
  }

  /// Cursor pagination: the cursor is passed back exactly as received.
  Future<void> _loadMore() async {
    final String? cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final CommunityPage<Post> page = await CommunityScope.of(
        context,
      ).services.community.listPosts(widget.space.id, cursor: cursor);
      if (!mounted) return;
      setState(() {
        _more.addAll(page.items);
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      CommunityScope.handleError(context, e);
    }
  }

  Future<void> _compose() async {
    final Post? created = await pushCommunityRoute<Post>(
      context,
      (BuildContext _) => ComposePostScreen(space: widget.space),
    );
    if (created != null && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return CommunityScreenFrame(
      title: widget.space.name,
      floatingActionButton: ValueListenableBuilder<CommunityMe?>(
        valueListenable: CommunityScope.of(context).services.viewer,
        builder: (BuildContext context, CommunityMe? me, Widget? _) {
          // Offer compose only where the matrix allows it (a restricted
          // account is read-only); the server enforces it regardless.
          if (me != null && !me.can(CommunityCapability.createContent)) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            key: const Key('compose_post'),
            onPressed: _compose,
            backgroundColor: Brand.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Write a post'),
          );
        },
      ),
      body: FutureBuilder<CommunityPage<Post>>(
        future: _page,
        builder:
            (BuildContext context, AsyncSnapshot<CommunityPage<Post>> snap) {
              if (snap.hasError) {
                CommunityScope.handleError(context, snap.error!);
                return const Center(child: Text('Posts could not load.'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final List<Post> posts = <Post>[...snap.data!.items, ..._more];
              if (posts.isEmpty) {
                return const Center(child: Text('No posts yet.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  Brand.gutter,
                  0,
                  Brand.gutter,
                  96,
                ),
                itemCount: posts.length + (_nextCursor == null ? 0 : 1),
                separatorBuilder: (BuildContext _, int _) =>
                    const Divider(height: Brand.space6),
                itemBuilder: (BuildContext context, int i) {
                  if (i == posts.length) {
                    return TextButton(
                      key: const Key('feed_load_more'),
                      onPressed: _loadingMore ? null : _loadMore,
                      child: const Text('Load more'),
                    );
                  }
                  final Post post = posts[i];
                  return InkWell(
                    key: Key('post_${post.id}'),
                    onTap: () async {
                      await pushCommunityRoute<void>(
                        context,
                        (BuildContext _) => PostDetailScreen(postId: post.id),
                      );
                      if (mounted) _reload();
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AuthorLine(
                          author: post.author,
                          isOwn: post.viewerIsAuthor,
                        ),
                        const SizedBox(height: Brand.space2),
                        Text(
                          post.body,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: Brand.body,
                        ),
                        const SizedBox(height: Brand.space2),
                        Text(
                          '${post.commentCount} comments · '
                          '${formatCommunityTime(post.createdAt)}',
                          style: Brand.caption,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
      ),
    );
  }
}
