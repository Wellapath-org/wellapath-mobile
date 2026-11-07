import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';
import '../data/community_repositories.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _page ??= _load();
  }

  Future<CommunityPage<Post>> _load() {
    return CommunityScope.of(
      context,
    ).services.community.listPosts(widget.space.id);
  }

  void _reload() {
    setState(() {
      _page = _load();
    });
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
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('compose_post'),
        onPressed: _compose,
        backgroundColor: Brand.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Write a post'),
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
              final List<Post> posts = snap.data!.items;
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
                itemCount: posts.length,
                separatorBuilder: (BuildContext _, int _) =>
                    const Divider(height: Brand.space6),
                itemBuilder: (BuildContext context, int i) {
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
