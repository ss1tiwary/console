import 'package:flutter/material.dart';
import 'package:resolve_theme/resolve_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/spacing.dart';
import 'relevance_review_screen.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

class _PostSummary {
  final String id;
  final String title;
  final DateTime publishedAt;
  final int prelimsScore;
  final int mainsScore;
  final int relevanceScore;
  const _PostSummary({
    required this.id,
    required this.title,
    required this.publishedAt,
    required this.prelimsScore,
    required this.mainsScore,
    required this.relevanceScore,
  });
}

final _recentPostsProvider =
    FutureProvider.autoDispose<List<_PostSummary>>((ref) async {
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('posts')
      .select('id, title, published_at, prelims_score, mains_score, relevance_score')
      .order('published_at', ascending: false)
      .limit(200);
  return (rows as List)
      .map((r) => _PostSummary(
            id: r['id'] as String,
            title: (r['title'] as String?) ?? '(untitled)',
            publishedAt: DateTime.parse(r['published_at'] as String),
            prelimsScore: (r['prelims_score'] as num?)?.toInt() ?? 0,
            mainsScore: (r['mains_score'] as num?)?.toInt() ?? 0,
            relevanceScore: (r['relevance_score'] as num?)?.toInt() ?? 0,
          ))
      .toList();
});

// ── Panel ─────────────────────────────────────────────────────────────────────

class RelevanceHubPanel extends ConsumerStatefulWidget {
  const RelevanceHubPanel({super.key});

  @override
  ConsumerState<RelevanceHubPanel> createState() =>
      _RelevanceHubPanelState();
}

class _RelevanceHubPanelState
    extends ConsumerState<RelevanceHubPanel> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
        () => setState(() => _query = _searchCtrl.text.trim()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final postsAsync = ref.watch(_recentPostsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: context.pal.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Relevance Review',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search posts…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: context.pal.grey100,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: context.pal.grey200),
        Expanded(
          child: postsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (posts) {
              final filtered = _query.isEmpty
                  ? posts
                  : posts
                      .where((p) => p.title
                          .toLowerCase()
                          .contains(_query.toLowerCase()))
                      .toList();
              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    _query.isEmpty
                        ? 'No posts found.'
                        : 'No posts matching "$_query".',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: context.pal.grey400),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: AppSpacing.pagePadding),
                itemCount: filtered.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final post = filtered[i];
                  return _PostTile(
                    post: post,
                    onTap: () =>
                        _openReview(context, post),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _openReview(BuildContext context, _PostSummary post) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 600,
          child: RelevanceReviewScreen(
            postId: post.id,
            postTitle: post.title,
            onDone: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  final _PostSummary post;
  final VoidCallback onTap;
  const _PostTile({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (badgeColor, badgeLabel) = switch (post.relevanceScore) {
      >= 70 => (context.pal.green, 'HIGH'),
      >= 40 => (context.pal.amber, 'MED'),
      _ => (context.pal.grey400, 'LOW'),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.pal.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.pal.grey200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Relevance badge — top of each post tile
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: badgeColor),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formatDate(post.publishedAt),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: context.pal.grey400),
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 16, color: context.pal.grey400),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              post.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Row(children: [
              _ScorePill('P', post.prelimsScore, context.pal.indigo),
              const SizedBox(width: 6),
              _ScorePill('M', post.mainsScore, context.pal.green),
            ]),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

class _ScorePill extends StatelessWidget {
  final String track;
  final int score;
  final Color color;
  const _ScorePill(this.track, this.score, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '$track $score',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
