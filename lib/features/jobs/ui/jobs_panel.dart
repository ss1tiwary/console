import 'package:flutter/material.dart';
import 'package:resolve_theme/resolve_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/di/providers.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class Job {
  final String id;
  final String jobType;
  final String triggeredBy;
  final String status;
  final Map<String, dynamic> params;
  final Map<String, dynamic> progress;
  final Map<String, dynamic>? report;
  final String? error;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime createdAt;

  const Job({
    required this.id,
    required this.jobType,
    required this.triggeredBy,
    required this.status,
    required this.params,
    required this.progress,
    this.report,
    this.error,
    this.startedAt,
    this.finishedAt,
    required this.createdAt,
  });

  factory Job.fromJson(Map<String, dynamic> j) => Job(
        id: j['id'] as String,
        jobType: j['job_type'] as String? ?? '',
        triggeredBy: j['triggered_by'] as String? ?? 'cron',
        status: j['status'] as String? ?? 'pending',
        params: (j['params'] as Map?)?.cast<String, dynamic>() ?? const {},
        progress: (j['progress'] as Map?)?.cast<String, dynamic>() ?? const {},
        report: (j['report'] as Map?)?.cast<String, dynamic>(),
        error: j['error'] as String?,
        startedAt: j['started_at'] != null
            ? DateTime.parse(j['started_at'] as String)
            : null,
        finishedAt: j['finished_at'] != null
            ? DateTime.parse(j['finished_at'] as String)
            : null,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  Duration? get duration => (startedAt != null && finishedAt != null)
      ? finishedAt!.difference(startedAt!)
      : null;
}

// ── Provider ──────────────────────────────────────────────────────────────────

final allJobsProvider = StreamProvider.autoDispose<List<Job>>((ref) {
  return ref
      .watch(supabaseClientProvider)
      .from('jobs')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(100)
      .map((rows) => rows.map((e) => Job.fromJson(e)).toList());
});

// ── Filter ────────────────────────────────────────────────────────────────────

enum _Filter { all, extraction, ingestion, mentionUpdate }

extension _FilterX on _Filter {
  String get label => switch (this) {
        _Filter.all           => 'All',
        _Filter.extraction    => 'Extraction',
        _Filter.ingestion     => 'Ingestion',
        _Filter.mentionUpdate => 'Mentions',
      };

  bool matches(Job j) => switch (this) {
        _Filter.all           => true,
        _Filter.extraction    => j.jobType == 'extraction',
        _Filter.ingestion     => j.jobType == 'ingestion',
        _Filter.mentionUpdate => j.jobType == 'mention_update',
      };
}

// ── Panel ─────────────────────────────────────────────────────────────────────

class JobsPanel extends ConsumerStatefulWidget {
  const JobsPanel({super.key});

  @override
  ConsumerState<JobsPanel> createState() => _JobsPanelState();
}

class _JobsPanelState extends ConsumerState<JobsPanel> {
  _Filter _filter = _Filter.all;
  String? _expandedId;
  bool _deleting = false;

  Future<void> _deleteJob(String id) async {
    setState(() => _deleting = true);
    try {
      await ref.read(supabaseClientProvider).from('jobs').delete().eq('id', id);
      if (mounted) setState(() => _expandedId = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'),
              backgroundColor: context.pal.red),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(allJobsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          filter: _filter,
          onFilter: (f) => setState(() => _filter = f),
          onRefresh: () => ref.invalidate(allJobsProvider),
        ),
        Expanded(
          child: jobsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Error: $e',
                  style: TextStyle(color: context.pal.red)),
            ),
            data: (all) {
              final jobs = all.where(_filter.matches).toList();
              if (jobs.isEmpty) {
                return Center(
                  child: Text(
                    'No jobs yet.',
                    style: TextStyle(color: context.pal.grey400),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: jobs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final job = jobs[i];
                  return _JobRow(
                    job: job,
                    expanded: _expandedId == job.id,
                    deleting: _deleting && _expandedId == job.id,
                    onTap: () => setState(() =>
                        _expandedId = _expandedId == job.id ? null : job.id),
                    onDelete: () => _deleteJob(job.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Header + filter chips ─────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;
  final VoidCallback onRefresh;
  const _Header({required this.filter, required this.onFilter, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.pal.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Worker Jobs',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Refresh',
                color: context.pal.grey600,
                onPressed: onRefresh,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _Filter.values.map((f) {
                final sel = f == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 12),
                  child: GestureDetector(
                    onTap: () => onFilter(f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? context.pal.indigo : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? context.pal.indigo : context.pal.grey200,
                        ),
                      ),
                      child: Text(
                        f.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel ? context.pal.white : context.pal.grey600,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Divider(height: 1, color: context.pal.grey200),
        ],
      ),
    );
  }
}

// ── Job row ───────────────────────────────────────────────────────────────────

class _JobRow extends StatelessWidget {
  final Job job;
  final bool expanded;
  final bool deleting;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _JobRow({
    required this.job,
    required this.expanded,
    required this.deleting,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: context.pal.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: expanded ? context.pal.indigo : context.pal.grey200,
            width: expanded ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                _TypeBadge(type: job.jobType),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _summary(job),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(status: job.status),
                const SizedBox(width: 6),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: context.pal.grey400,
                ),
              ]),
            ),
            // Progress bar for running jobs
            if (job.status == 'running') _ProgressBar(job: job),
            // Expanded details
            if (expanded) ...[
              Divider(height: 1, color: context.pal.grey100),
              _Details(job: job, onDelete: onDelete, deleting: deleting),
            ],
          ],
        ),
      ),
    );
  }

  String _summary(Job job) {
    switch (job.jobType) {
      case 'extraction':
        final exam = job.params['exam_slug'] as String? ?? '';
        final year = job.params['year']?.toString() ?? '';
        final paper = job.params['paper'] as String? ?? '';
        return '$exam · $year · $paper'.replaceAll('_', ' ');
      case 'ingestion':
        return 'PIB ingestion · cap ${job.params['articles_cap'] ?? '?'}';
      case 'mention_update':
        return 'Mention update · cap ${job.params['mentions_cap'] ?? '?'}';
      default:
        return job.jobType;
    }
  }
}

// ── Progress bar ──────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final Job job;
  const _ProgressBar({required this.job});

  @override
  Widget build(BuildContext context) {
    final total = (job.progress['pages_total'] as num?)?.toInt() ?? 0;
    final done = (job.progress['pages_done'] as num?)?.toInt() ?? 0;

    if (total == 0) {
      return LinearProgressIndicator(
        minHeight: 3,
        backgroundColor: context.pal.grey100,
        color: context.pal.indigo,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          child: LinearProgressIndicator(
            value: done / total,
            minHeight: 3,
            backgroundColor: context.pal.grey100,
            color: context.pal.indigo,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Text(
            'Page $done / $total · ${job.progress['questions_extracted'] ?? 0} questions',
            style: TextStyle(fontSize: 11, color: context.pal.grey600),
          ),
        ),
      ],
    );
  }
}

// ── Expanded details ──────────────────────────────────────────────────────────

class _Details extends StatelessWidget {
  final Job job;
  final VoidCallback onDelete;
  final bool deleting;
  const _Details({required this.job, required this.onDelete, required this.deleting});

  static final _dtFmt = DateFormat('dd MMM · HH:mm');
  static String _durFmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String, Color?)>[];

    rows.add(('ID', job.id, null));
    rows.add(('Triggered by', job.triggeredBy, null));
    rows.add(('Created', _dtFmt.format(job.createdAt.toLocal()), null));
    if (job.startedAt != null) {
      rows.add(('Started', _dtFmt.format(job.startedAt!.toLocal()), null));
    }
    if (job.finishedAt != null) {
      rows.add(('Finished', _dtFmt.format(job.finishedAt!.toLocal()), null));
    }
    if (job.duration != null) {
      rows.add(('Duration', _durFmt(job.duration!), null));
    }

    if (job.report != null) {
      for (final entry in job.report!.entries) {
        if (entry.value is Map || entry.value is List) continue;
        rows.add((entry.key, '${entry.value}', null));
      }
    }

    if (job.error != null) {
      rows.add(('Error', job.error!, context.pal.red));
    }

    final canDelete = job.status == 'failed' || job.status == 'completed';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(r.$1,
                          style: TextStyle(
                              fontSize: 11, color: context.pal.grey400)),
                    ),
                    Expanded(
                      child: SelectableText(
                        r.$2,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: r.$3 ?? context.pal.grey900,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          if (canDelete) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: deleting ? null : onDelete,
                icon: deleting
                    ? const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5))
                    : const Icon(Icons.delete_outline_rounded, size: 14),
                label: Text(deleting ? 'Deleting…' : 'Delete job',
                    style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.pal.red,
                  side: BorderSide(color: context.pal.red.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Type badge ────────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (type) {
      'extraction'    => ('EXT',     context.pal.indigo,       context.pal.indigoLight),
      'ingestion'     => ('ING',     context.pal.green,        context.pal.greenLight),
      'mention_update'=> ('MEN',     context.pal.amber,        context.pal.amberLight),
      _               => (type.substring(0, 3).toUpperCase(), context.pal.grey600, context.pal.grey100),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(label,
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: color)),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status) {
      'pending'      => ('Queued',  context.pal.grey600,  context.pal.grey100),
      'running'      => ('Running', context.pal.indigo,   context.pal.indigoLight),
      'needs_review' => ('Review',  context.pal.amber,    context.pal.amberLight),
      'completed'    => ('Done',    context.pal.green,    context.pal.greenLight),
      _              => ('Failed',  context.pal.red,      context.pal.redLight),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
