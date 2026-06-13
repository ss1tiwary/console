import 'package:flutter/material.dart';
import 'package:resolve_theme/resolve_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/spacing.dart';
import '../../feedback/data/feedback_model.dart';

// ── Models ─────────────────────────────────────────────────────────────────────

class _DashStats {
  final int postsToday;
  final int postsThisWeek;
  final int avgScoreThisWeek;
  final int feedbackPending;
  final int reviewsDone;
  final int openIdeas;
  final int inProgressIdeas;
  final DateTime? lastPipelineRun;

  const _DashStats({
    required this.postsToday,
    required this.postsThisWeek,
    required this.avgScoreThisWeek,
    required this.feedbackPending,
    required this.reviewsDone,
    required this.openIdeas,
    required this.inProgressIdeas,
    required this.lastPipelineRun,
  });
}

class _FeedItem {
  final String text;
  final DateTime time;
  final String source;
  const _FeedItem({
    required this.text,
    required this.time,
    required this.source,
  });
}

// ── Providers ──────────────────────────────────────────────────────────────────

final _dashStatsProvider =
    FutureProvider.autoDispose<_DashStats>((ref) async {
  final sb = ref.watch(supabaseClientProvider);
  final now = DateTime.now().toUtc();
  final todayStart =
      DateTime.utc(now.year, now.month, now.day).toIso8601String();
  final weekStart =
      now.subtract(const Duration(days: 7)).toIso8601String();

  final results = await Future.wait([
    sb.from('posts').select('id').gte('published_at', todayStart),
    sb.from('posts').select('relevance_score').gte('published_at', weekStart),
    sb.from('content_feedback').select('id').eq('status', 'pending'),
    sb.from('relevance_reviews').select('id'),
    sb.from('ideas').select('status'),
    sb
        .from('posts')
        .select('fetched_at')
        .order('fetched_at', ascending: false)
        .limit(1),
  ]);

  final postsToday = (results[0] as List).length;

  final weekRows = results[1] as List;
  final postsThisWeek = weekRows.length;
  final avgScore = postsThisWeek == 0
      ? 0
      : (weekRows
                  .map((r) => (r['relevance_score'] as num?)?.toInt() ?? 0)
                  .fold<int>(0, (s, v) => s + v) /
              postsThisWeek)
          .round();

  final feedbackPending = (results[2] as List).length;
  final reviewsDone = (results[3] as List).length;

  final ideasRows = results[4] as List;
  final openIdeas =
      ideasRows.where((r) => r['status'] == 'open').length;
  final inProgressIdeas =
      ideasRows.where((r) => r['status'] == 'in_progress').length;

  DateTime? lastRun;
  final latestPosts = results[5] as List;
  if (latestPosts.isNotEmpty) {
    lastRun = DateTime.tryParse(
        (latestPosts.first['fetched_at'] as String?) ?? '');
  }

  return _DashStats(
    postsToday: postsToday,
    postsThisWeek: postsThisWeek,
    avgScoreThisWeek: avgScore,
    feedbackPending: feedbackPending,
    reviewsDone: reviewsDone,
    openIdeas: openIdeas,
    inProgressIdeas: inProgressIdeas,
    lastPipelineRun: lastRun,
  );
});

final _activityProvider =
    FutureProvider.autoDispose<List<_FeedItem>>((ref) async {
  final sb = ref.watch(supabaseClientProvider);

  final feedbackRows = await sb
      .from('content_feedback')
      .select('feedback_type, created_at')
      .order('created_at', ascending: false)
      .limit(4);

  final reviewRows = await sb
      .from('relevance_reviews')
      .select('created_at')
      .order('created_at', ascending: false)
      .limit(3);

  List extractionRows = [];
  try {
    extractionRows = await sb
        .from('extraction_jobs')
        .select('status, year, paper, created_at')
        .order('created_at', ascending: false)
        .limit(2);
  } catch (_) {}

  final items = <_FeedItem>[];

  for (final r in (feedbackRows as List)) {
    final type =
        FeedbackType.fromValue(r['feedback_type'] as String? ?? 'other');
    final t = DateTime.tryParse(r['created_at'] as String? ?? '') ??
        DateTime.now();
    items.add(_FeedItem(
      text: 'User feedback: ${type.label}',
      time: t,
      source: 'Feedback',
    ));
  }

  for (final r in (reviewRows as List)) {
    final t = DateTime.tryParse(r['created_at'] as String? ?? '') ??
        DateTime.now();
    items.add(_FeedItem(
      text: 'Relevance review saved',
      time: t,
      source: 'Relevance',
    ));
  }

  for (final r in extractionRows) {
    final t = DateTime.tryParse(r['created_at'] as String? ?? '') ??
        DateTime.now();
    final status = r['status'] as String? ?? '';
    final year = r['year'] as int? ?? 0;
    final paper = r['paper'] as String? ?? '';
    items.add(_FeedItem(
      text: 'Extraction $status — $year $paper',
      time: t,
      source: 'Extraction',
    ));
  }

  items.sort((a, b) => b.time.compareTo(a.time));
  return items.take(6).toList();
});

// ── Panel ──────────────────────────────────────────────────────────────────────

class DashboardPanel extends ConsumerWidget {
  const DashboardPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_dashStatsProvider);
    final activityAsync = ref.watch(_activityProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 620;
        return SingleChildScrollView(
          padding: EdgeInsets.all(wide ? 24 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 20),
              statsAsync.when(
                loading: () => const _StatsShimmer(),
                error: (e, _) => _ErrorBanner('Could not load stats: $e'),
                data: (s) => _buildStatGrid(context, s, wide),
              ),
              const SizedBox(height: 24),
              if (wide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: activityAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) =>
                            _ErrorBanner('Activity error: $e'),
                        data: (items) => _buildActivity(context, items),
                      )),
                      const SizedBox(width: 16),
                      Expanded(
                          child: statsAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (s) => _buildPipeline(context, s),
                      )),
                    ],
                  ),
                )
              else ...[
                activityAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _ErrorBanner('Activity error: $e'),
                  data: (items) => _buildActivity(context, items),
                ),
                const SizedBox(height: 16),
                statsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (s) => _buildPipeline(context, s),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final now = DateTime.now();
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final dateStr =
        '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(greeting,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(dateStr,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: context.pal.grey400)),
      ],
    );
  }

  Widget _buildStatGrid(BuildContext context, _DashStats s, bool wide) {
    final cards = [
      _StatCard(
        icon: Icons.article_outlined,
        label: 'Posts today',
        value: '${s.postsToday}',
        sub: '${s.postsThisWeek} this week',
        iconColor: context.pal.indigo,
      ),
      _StatCard(
        icon: Icons.feedback_outlined,
        label: 'Feedback pending',
        value: '${s.feedbackPending}',
        sub: 'needs attention',
        iconColor: context.pal.amber,
        highlight: s.feedbackPending > 0,
      ),
      _StatCard(
        icon: Icons.rate_review_outlined,
        label: 'Reviews done',
        value: '${s.reviewsDone}',
        sub: 'all time',
        iconColor: context.pal.green,
      ),
      _StatCard(
        icon: Icons.lightbulb_outline,
        label: 'Open ideas',
        value: '${s.openIdeas}',
        sub: '${s.inProgressIdeas} in progress',
        iconColor: const Color(0xFF7C3AED),
      ),
    ];

    return GridView.count(
      crossAxisCount: wide ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: wide ? 1.55 : 1.4,
      children: cards,
    );
  }

  Widget _buildActivity(BuildContext context, List<_FeedItem> items) {
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'Recent activity',
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('No recent activity.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: context.pal.grey400)),
            )
          : Column(
              children: items
                  .map((item) => _FeedRow(item: item))
                  .toList(),
            ),
    );
  }

  Widget _buildPipeline(BuildContext context, _DashStats s) {
    String lastRunLabel = 'Unknown';
    if (s.lastPipelineRun != null) {
      final diff =
          DateTime.now().difference(s.lastPipelineRun!.toLocal());
      if (diff.inMinutes < 60) {
        lastRunLabel = '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        lastRunLabel = '${diff.inHours}h ago';
      } else {
        lastRunLabel = '${diff.inDays}d ago';
      }
    }

    return _SectionCard(
      title: 'Pipeline status',
      child: Column(
        children: [
          _PipeRow('Last run', lastRunLabel,
              badge: s.lastPipelineRun != null
                  ? _PipeBadge.ok
                  : _PipeBadge.none),
          _PipeRow('Schedule', 'Runs 5× daily'),
          _PipeRow('Posts this week', '${s.postsThisWeek}'),
          _PipeRow('Avg score (7d)',
              s.avgScoreThisWeek > 0
                  ? '${s.avgScoreThisWeek} / 100'
                  : '—'),
        ],
      ),
    );
  }
}

// ── Stat card ──────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color iconColor;
  final bool highlight;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.iconColor,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.pal.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(
          color: highlight ? context.pal.amber : context.pal.grey200,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: context.pal.grey600, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(value,
              style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 28,
                  color: context.pal.grey900)),
          const SizedBox(height: 2),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: context.pal.grey400, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Section card ───────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.pal.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: context.pal.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Activity feed row ──────────────────────────────────────────────────────────

/// Activity-feed dot colour by source (resolved from the active theme).
Color _sourceColor(BuildContext context, String source) => switch (source) {
      'Feedback' => context.pal.amber,
      'Relevance' => context.pal.green,
      'Extraction' => context.pal.indigo,
      _ => context.pal.grey400,
    };

class _FeedRow extends StatelessWidget {
  final _FeedItem item;
  const _FeedRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diff = DateTime.now().difference(item.time);
    final timeLabel = diff.inMinutes < 60
        ? '${diff.inMinutes}m ago'
        : diff.inHours < 24
            ? '${diff.inHours}h ago'
            : '${diff.inDays}d ago';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
                color: _sourceColor(context, item.source),
                shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.text,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: context.pal.grey900, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('$timeLabel · ${item.source}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: context.pal.grey400, fontSize: 10)),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Pipeline row ───────────────────────────────────────────────────────────────

enum _PipeBadge { ok, warn, err, none }

class _PipeRow extends StatelessWidget {
  final String label;
  final String value;
  final _PipeBadge badge;
  const _PipeRow(this.label, this.value, {this.badge = _PipeBadge.none});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: context.pal.grey600)),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(value,
              style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.pal.grey900)),
          if (badge != _PipeBadge.none) ...[
            const SizedBox(width: 6),
            _BadgeChip(badge),
          ],
        ]),
      ]),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final _PipeBadge badge;
  const _BadgeChip(this.badge);

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (badge) {
      _PipeBadge.ok => ('OK', context.pal.green, context.pal.greenLight),
      _PipeBadge.warn =>
        ('HIGH', context.pal.amber, context.pal.amberLight),
      _PipeBadge.err => ('ERR', context.pal.red, context.pal.redLight),
      _PipeBadge.none => ('', context.pal.grey400, context.pal.grey100),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ── Loading shimmer ────────────────────────────────────────────────────────────

class _StatsShimmer extends StatelessWidget {
  const _StatsShimmer();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: List.generate(
        4,
        (_) => Container(
          decoration: BoxDecoration(
            color: context.pal.grey100,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
        ),
      ),
    );
  }
}

// ── Error banner ───────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.pal.redLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message,
          style: TextStyle(color: context.pal.red, fontSize: 12)),
    );
  }
}
