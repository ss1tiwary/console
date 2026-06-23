import 'package:resolve_theme/resolve_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qbank_contracts/qbank_contracts.dart';

import '../../../core/config_options.dart';
import '../../../core/di/providers.dart';
import '../../../core/spacing.dart';
import 'extraction_review_panel.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class ExtractionJob {
  final String id;
  final String examSlug;
  final int year;
  final String paper;
  final String paperSlug;
  final String paperSet;
  final String? pdfName;
  final String status;
  final Map<String, dynamic> params;
  final Map<String, dynamic> progress;
  final Map<String, dynamic>? report;
  final String? error;
  final DateTime createdAt;

  const ExtractionJob({
    required this.id,
    required this.examSlug,
    required this.year,
    required this.paper,
    required this.paperSlug,
    required this.paperSet,
    this.pdfName,
    required this.status,
    required this.params,
    required this.progress,
    this.report,
    this.error,
    required this.createdAt,
  });

  String get examLabel => examSlug.replaceAll('_', ' ').toUpperCase();

  String get mode {
    final raw = (report?['mode'] ?? params['mode'])?.toString();
    return raw == 'adhoc' ? 'adhoc' : 'full_paper';
  }

  bool get isAdhoc => mode == 'adhoc';

  factory ExtractionJob.fromDto(QbankExtractionJobDto dto) {
    return ExtractionJob(
      id: dto.id,
      examSlug: dto.examSlug,
      year: dto.year,
      paper: dto.paper,
      paperSlug: dto.paperSlug,
      paperSet: dto.paperSet,
      pdfName: dto.pdfName,
      status: dto.status,
      params: Map<String, dynamic>.from(dto.params),
      progress: Map<String, dynamic>.from(dto.progress),
      report: dto.report.isEmpty ? null : Map<String, dynamic>.from(dto.report),
      error: dto.error,
      createdAt: dto.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final extractionJobsProvider = FutureProvider.autoDispose<List<ExtractionJob>>((
  ref,
) async {
  final jobs = await ref.watch(qbankApiProvider).listExtractionJobs();
  return jobs.map(ExtractionJob.fromDto).toList();
});

// Shared slug→short_name map used for display in cards, headers, review panel.
// Falls back to selecting just name if short_name column doesn't exist yet.
final examNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final exams = await ref.watch(qbankApiProvider).examOptions();
  return {for (final exam in exams) exam.slug: exam.label};
});

final _examsListProvider =
    FutureProvider.autoDispose<List<({String slug, String name})>>((ref) async {
      final exams = await ref.watch(qbankApiProvider).examOptions();
      return exams.map((exam) => (slug: exam.slug, name: exam.label)).toList();
    });

// Live missing qnos for a job. The qbank backend contract owns how this is
// computed so the panel stays accurate after review deletions and independent
// of storage details.
final liveMissingProvider = FutureProvider.autoDispose
    .family<List<int>, ({String jobId, int expected})>((ref, args) async {
      if (args.expected <= 0) return const [];
      return ref
          .watch(qbankApiProvider)
          .getMissingQnos(QbankMissingQnosRequestDto(jobId: args.jobId));
    });

final _papersListProvider =
    FutureProvider.autoDispose<List<({String paper, String paperSlug})>>((
      ref,
    ) async {
      final jobs = await ref.watch(qbankApiProvider).listExtractionJobs();
      final seen = <String>{};
      final result = <({String paper, String paperSlug})>[];
      for (final job in jobs) {
        final slug = job.paperSlug;
        final paper = job.paper;
        if (slug.isNotEmpty && seen.add(slug)) {
          result.add((paper: paper, paperSlug: slug));
        }
      }
      return result;
    });

final extractionCredentialsProvider =
    FutureProvider.autoDispose<List<QbankExtractionCredentialDto>>((ref) {
      return ref.watch(qbankApiProvider).listExtractionCredentials();
    });

// ── Tab filter ────────────────────────────────────────────────────────────────

enum _Tab { all, queued, review, done }

extension _TabX on _Tab {
  String get label => switch (this) {
    _Tab.all => 'All',
    _Tab.queued => 'Queued',
    _Tab.review => 'Review',
    _Tab.done => 'Done',
  };

  bool matches(ExtractionJob j) => switch (this) {
    _Tab.all => true,
    _Tab.queued => _activeExtractionStatuses.contains(j.status),
    _Tab.review => j.status == 'needs_review',
    _Tab.done => j.status == 'completed' || j.status == 'failed',
  };
}

const _activeExtractionStatuses = {
  'pending',
  'running',
  'profiling',
  'planning',
  'extracting',
  'pairing',
  'validating',
  'repairing',
};

// ── Panel ─────────────────────────────────────────────────────────────────────

class ExtractionPanel extends ConsumerStatefulWidget {
  const ExtractionPanel({super.key});

  @override
  ConsumerState<ExtractionPanel> createState() => _ExtractionPanelState();
}

class _ExtractionPanelState extends ConsumerState<ExtractionPanel> {
  ExtractionJob? _selected;
  _Tab _tab = _Tab.all;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) => c.maxWidth >= 600 ? _wideLayout() : _narrowLayout(),
    );
  }

  Widget _wideLayout() {
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: _JobListPane(
            selected: _selected,
            tab: _tab,
            onTabChanged: (t) => setState(() => _tab = t),
            onSelect: (j) => setState(() => _selected = j),
            onNewJob: () => _showNewJobSheet(context),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: _rightPane()),
      ],
    );
  }

  Widget _narrowLayout() {
    if (_selected != null) {
      return ExtractionReviewPanel(
        key: ValueKey(_selected!.id),
        job: _selected!,
        onBack: () => setState(() => _selected = null),
        onShowStats: () => _showJobDetail(context, _selected!),
      );
    }
    return _JobListPane(
      selected: _selected,
      tab: _tab,
      onTabChanged: (t) => setState(() => _tab = t),
      onSelect: (j) => setState(() => _selected = j),
      onNewJob: () => _showNewJobSheet(context),
    );
  }

  Widget _rightPane() {
    final job = _selected;
    if (job == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.document_scanner_outlined,
              size: 48,
              color: context.pal.grey300,
            ),
            const SizedBox(height: 12),
            Text(
              'Select a job to review',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.pal.grey400),
            ),
          ],
        ),
      );
    }
    return ExtractionReviewPanel(
      key: ValueKey(job.id),
      job: job,
      onShowStats: () => _showJobDetail(context, job),
    );
  }

  void _showJobDetail(BuildContext context, ExtractionJob job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.pal.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _JobDetailSheet(jobId: job.id),
    );
  }

  void _showNewJobSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.pal.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _NewJobSheet(),
    );
  }
}

// ── Job list pane ─────────────────────────────────────────────────────────────

class _JobListPane extends ConsumerWidget {
  final ExtractionJob? selected;
  final _Tab tab;
  final ValueChanged<_Tab> onTabChanged;
  final ValueChanged<ExtractionJob> onSelect;
  final VoidCallback onNewJob;

  const _JobListPane({
    required this.selected,
    required this.tab,
    required this.onTabChanged,
    required this.onSelect,
    required this.onNewJob,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(extractionJobsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabStrip(current: tab, onChanged: onTabChanged),
        Expanded(
          child: jobsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (all) {
              final jobs = all.where((j) => tab.matches(j)).toList();
              if (jobs.isEmpty) return _EmptyList(tab: tab);
              return _JobListBody(
                jobs: jobs,
                selected: selected,
                onSelect: onSelect,
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            color: context.pal.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: context.pal.indigo,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('New extraction'),
              onPressed: onNewJob,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Tab strip ─────────────────────────────────────────────────────────────────

class _TabStrip extends StatelessWidget {
  final _Tab current;
  final ValueChanged<_Tab> onChanged;
  const _TabStrip({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.pal.white,
      child: Column(
        children: [
          Row(
            children: _Tab.values.map((t) {
              final sel = t == current;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: sel ? context.pal.indigo : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      t.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                        color: sel ? context.pal.indigo : context.pal.grey600,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          Divider(height: 1, color: context.pal.grey200),
        ],
      ),
    );
  }
}

// ── Job list body (Active / Recent sections) ──────────────────────────────────

class _JobListBody extends StatelessWidget {
  final List<ExtractionJob> jobs;
  final ExtractionJob? selected;
  final ValueChanged<ExtractionJob> onSelect;
  const _JobListBody({
    required this.jobs,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final active = jobs
        .where((j) => _activeExtractionStatuses.contains(j.status))
        .toList();
    final recent = jobs
        .where((j) => !_activeExtractionStatuses.contains(j.status))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      children: [
        if (active.isNotEmpty) ...[
          _sectionLabel(context, active.length),
          ...active.map(
            (j) => _JobCard(
              job: j,
              isSelected: j.id == selected?.id,
              onTap: () => onSelect(j),
            ),
          ),
        ],
        if (recent.isNotEmpty) ...[
          _recentLabel(context),
          ...recent.map(
            (j) => _JobCard(
              job: j,
              isSelected: j.id == selected?.id,
              onTap: () => onSelect(j),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
    child: Row(
      children: [
        Text(
          'ACTIVE',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: context.pal.grey400,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: context.pal.indigoLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: context.pal.indigo,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _recentLabel(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(4, 10, 4, 6),
    child: Text(
      'RECENT',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: context.pal.grey400,
      ),
    ),
  );
}

// ── Job card ──────────────────────────────────────────────────────────────────

class _JobCard extends ConsumerWidget {
  final ExtractionJob job;
  final bool isSelected;
  final VoidCallback onTap;
  const _JobCard({
    required this.job,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final examNames = ref.watch(examNamesProvider).valueOrNull ?? const {};
    final total = (job.progress['pages_total'] as num?)?.toInt() ?? 0;
    final done = (job.progress['pages_done'] as num?)?.toInt() ?? 0;
    final qs = (job.progress['questions_extracted'] as num?)?.toInt() ?? 0;
    final active = job.status == 'running' || job.status == 'pending';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? context.pal.indigoLight : context.pal.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? context.pal.indigo : context.pal.grey200,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${job.year} · ${job.paper} · Set ${job.paperSet}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        examNames[job.examSlug] ?? job.examLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.pal.grey400,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _ModeChip(isAdhoc: job.isAdhoc),
                const SizedBox(width: 6),
                _StatusChip(status: job.status),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: context.pal.grey400,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'Job actions',
                  onSelected: (v) {
                    if (v == 'delete') _confirmDelete(context, ref);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: context.pal.red,
                          ),
                          const SizedBox(width: 8),
                          const Text('Delete job'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (job.pdfName != null) ...[
              const SizedBox(height: 4),
              Text(
                job.pdfName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.pal.grey400,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (active && total > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: done / total,
                  minHeight: 4,
                  backgroundColor: context.pal.grey100,
                  color: context.pal.indigo,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Page $done / $total · $qs questions',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.pal.grey600,
                ),
              ),
            ] else if (active) ...[
              Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Queued — waiting for worker…',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.pal.grey600,
                    ),
                  ),
                ],
              ),
            ] else
              _coverageLine(context, theme),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete job?'),
        content: Text(
          'Remove "${job.year} · ${job.paper} · Set ${job.paperSet}" from the '
          'list? This deletes the extraction job. Drafts already in review are '
          'not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.pal.red),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(qbankApiProvider).deleteJob(job.id);
      ref.invalidate(extractionJobsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Job deleted')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Widget _coverageLine(BuildContext context, ThemeData theme) {
    final cov = (job.report?['coverage'] as Map?)?.cast<String, dynamic>();
    if (cov == null) {
      if (job.status == 'failed') {
        return Text(
          job.error ?? 'Failed',
          style: theme.textTheme.bodySmall?.copyWith(color: context.pal.red),
        );
      }
      return const SizedBox.shrink();
    }
    final found = (cov['found'] as num?)?.toInt() ?? 0;
    final expected = (cov['expected_count'] as num?)?.toInt() ?? 0;
    final missing = (cov['missing'] as List?)?.length ?? 0;
    final countLabel = expected > 0 ? '$found / $expected' : '$found';
    return Text(
      '$countLabel extracted'
      '${missing > 0 ? ' · $missing missing' : ' · complete'}',
      style: theme.textTheme.bodySmall?.copyWith(
        color: missing > 0 ? context.pal.amber : const Color(0xFF16A34A),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final bool isAdhoc;
  const _ModeChip({required this.isAdhoc});

  @override
  Widget build(BuildContext context) {
    final label = isAdhoc ? 'ADHOC' : 'FULL';
    final color = isAdhoc ? context.pal.indigo : context.pal.grey600;
    final bg = isAdhoc ? context.pal.indigoLight : context.pal.grey100;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status) {
      'pending' => ('Queued', context.pal.grey600, context.pal.grey100),
      'running' => ('Running', context.pal.indigo, context.pal.indigoLight),
      'profiling' => ('Profiling', context.pal.indigo, context.pal.indigoLight),
      'planning' => ('Planning', context.pal.indigo, context.pal.indigoLight),
      'extracting' => (
        'Extracting',
        context.pal.indigo,
        context.pal.indigoLight,
      ),
      'pairing' => ('Pairing', context.pal.indigo, context.pal.indigoLight),
      'validating' => (
        'Validating',
        context.pal.indigo,
        context.pal.indigoLight,
      ),
      'repairing' => ('Repairing', context.pal.indigo, context.pal.indigoLight),
      'needs_review' => ('Review', context.pal.amber, context.pal.amberLight),
      'completed' => ('Done', const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
      _ => ('Failed', context.pal.red, const Color(0xFFFEE2E2)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── Empty list ─────────────────────────────────────────────────────────────────

class _EmptyList extends StatelessWidget {
  final _Tab tab;
  const _EmptyList({required this.tab});

  @override
  Widget build(BuildContext context) {
    final msg = switch (tab) {
      _Tab.queued => 'No queued jobs.',
      _Tab.review => 'Nothing needs review.',
      _Tab.done => 'No completed jobs yet.',
      _Tab.all => 'No jobs yet.\nTap New extraction to start.',
    };
    return Center(
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.pal.grey400),
      ),
    );
  }
}

// ── Paper / exam constants ────────────────────────────────────────────────────

// ── Layout presets ────────────────────────────────────────────────────────────
// A preset is the human-facing choice; it maps to the worker contract's `layout`
// value + the page knobs (start_page / page_step / hindi_offset) so the user never
// has to reason about raw page numbers. See question-bank/extract_worker.py.

enum _LayoutPreset { autoBilingual, upscPagePair, samePage, englishOnly }

extension _LayoutPresetX on _LayoutPreset {
  String get title => switch (this) {
    _LayoutPreset.autoBilingual => 'Auto bilingual',
    _LayoutPreset.upscPagePair => 'UPSC bilingual',
    _LayoutPreset.samePage => 'Bilingual · same page',
    _LayoutPreset.englishOnly => 'English only',
  };

  String get subtitle => switch (this) {
    _LayoutPreset.autoBilingual => 'Detect pages and pair languages by qno',
    _LayoutPreset.upscPagePair => 'Hindi printed on a separate page',
    _LayoutPreset.samePage => 'English + Hindi in one page (2 columns)',
    _LayoutPreset.englishOnly => 'No Hindi extraction',
  };

  IconData get icon => switch (this) {
    _LayoutPreset.autoBilingual => Icons.auto_awesome_outlined,
    _LayoutPreset.upscPagePair => Icons.auto_stories_outlined,
    _LayoutPreset.samePage => Icons.vertical_split_outlined,
    _LayoutPreset.englishOnly => Icons.subject,
  };

  // Value sent to the extraction backend contract.
  String get contractValue => switch (this) {
    _LayoutPreset.autoBilingual => 'auto',
    _LayoutPreset.upscPagePair => 'page_pair',
    _LayoutPreset.samePage => 'same_page',
    _LayoutPreset.englishOnly => 'single',
  };

  bool get wantHindi => this != _LayoutPreset.englishOnly;

  // Default page knobs for a PDF. Images always override to 1 / 1 / 0.
  (int start, int step, int offset) get pdfDefaults => switch (this) {
    _LayoutPreset.autoBilingual => (1, 1, 0),
    _LayoutPreset.upscPagePair => (3, 2, -1),
    _LayoutPreset.samePage => (1, 1, 0),
    _LayoutPreset.englishOnly => (1, 1, 0),
  };
}

enum _ExtractionProvider { gemini, groq, openRouter }

enum _ExtractionMode { adhoc, fullPaper }

extension _ExtractionModeX on _ExtractionMode {
  String get label => switch (this) {
    _ExtractionMode.adhoc => 'Adhoc page',
    _ExtractionMode.fullPaper => 'Full paper',
  };

  String get value => switch (this) {
    _ExtractionMode.adhoc => 'adhoc',
    _ExtractionMode.fullPaper => 'full_paper',
  };
}

extension _ExtractionProviderX on _ExtractionProvider {
  String get label => switch (this) {
    _ExtractionProvider.gemini => 'Gemini',
    _ExtractionProvider.groq => 'Groq',
    _ExtractionProvider.openRouter => 'OpenRouter',
  };

  String get value => switch (this) {
    _ExtractionProvider.gemini => 'gemini',
    _ExtractionProvider.groq => 'groq',
    _ExtractionProvider.openRouter => 'openrouter',
  };

  String get defaultModel => switch (this) {
    _ExtractionProvider.gemini => 'gemini-2.5-flash',
    _ExtractionProvider.groq => 'meta-llama/llama-4-scout-17b-16e-instruct',
    _ExtractionProvider.openRouter => 'qwen/qwen2.5-vl-72b-instruct:free',
  };
}

// ── New job sheet ─────────────────────────────────────────────────────────────

class _NewJobSheet extends ConsumerStatefulWidget {
  const _NewJobSheet();

  @override
  ConsumerState<_NewJobSheet> createState() => _NewJobSheetState();
}

class _NewJobSheetState extends ConsumerState<_NewJobSheet> {
  String? _examSlug;
  String? _paperSlug;
  String? _paper;
  String _set = 'A';
  _LayoutPreset _preset = _LayoutPreset.autoBilingual;
  _ExtractionMode _mode = _ExtractionMode.adhoc;
  _ExtractionProvider _provider = _ExtractionProvider.gemini;
  String? _credentialId;
  bool _showCredentialForm = false;
  bool _savingCredential = false;
  String? _credentialErr;
  final _year = TextEditingController(text: '');
  final _expected = TextEditingController(text: '100');
  final _paperCtrl = TextEditingController();
  final _modelCtrl = TextEditingController(
    text: _ExtractionProvider.gemini.defaultModel,
  );
  final _credentialLabelCtrl = TextEditingController();
  final _credentialApiKeyCtrl = TextEditingController();
  int _pageScope = 1;
  int _startPage = 1;
  int _pageStep = 1;
  int _hindiOffset = 0;
  PlatformFile? _pdf;
  bool _isImage = false;
  bool _busy = false;
  String? _err;

  static const _imageExts = {'png', 'jpg', 'jpeg'};

  bool get _isAdhoc => _mode == _ExtractionMode.adhoc;

  List<_LayoutPreset> get _availablePresets => _isAdhoc
      ? const [_LayoutPreset.autoBilingual, _LayoutPreset.englishOnly]
      : _isImage
      ? const [
          _LayoutPreset.autoBilingual,
          _LayoutPreset.samePage,
          _LayoutPreset.englishOnly,
        ]
      : _LayoutPreset.values;

  void _setMode(_ExtractionMode mode) {
    if (_busy) return;
    if (mode == _ExtractionMode.fullPaper && _isImage) {
      setState(() => _err = 'Full paper mode needs a PDF. Pick a PDF first.');
      return;
    }
    setState(() {
      _mode = mode;
      _err = null;
      if (_isAdhoc) {
        _pageScope = _isImage ? 1 : _pageScope.clamp(1, 2).toInt();
        _expected.text = '0';
        if (_preset != _LayoutPreset.autoBilingual &&
            _preset != _LayoutPreset.englishOnly) {
          _preset = _LayoutPreset.autoBilingual;
        }
        _startPage = 1;
        _pageStep = 1;
        _hindiOffset = 0;
      } else {
        if (_expected.text == '0') _expected.text = '100';
        final defaults = _preset.pdfDefaults;
        _startPage = defaults.$1;
        _pageStep = defaults.$2;
        _hindiOffset = defaults.$3;
      }
    });
  }

  void _applyPreset(_LayoutPreset p) {
    final (start, step, offset) = p.pdfDefaults;
    setState(() {
      _preset = p;
      _startPage = _isAdhoc || _isImage ? 1 : start;
      _pageStep = _isAdhoc || _isImage ? 1 : step;
      _hindiOffset = _isAdhoc || _isImage ? 0 : offset;
    });
  }

  String _slugify(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  QbankExtractionCredentialDto? _selectedCredential(
    List<QbankExtractionCredentialDto> credentials,
  ) {
    final id = _credentialId;
    if (id == null || id.isEmpty) return null;
    for (final credential in credentials) {
      if (credential.id == id) return credential;
    }
    return null;
  }

  @override
  void dispose() {
    _year.dispose();
    _expected.dispose();
    _paperCtrl.dispose();
    _modelCtrl.dispose();
    _credentialLabelCtrl.dispose();
    _credentialApiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (r != null && r.files.isNotEmpty) {
      final file = r.files.single;
      final ext = (file.extension ?? '').toLowerCase();
      final isImg = _imageExts.contains(ext);
      setState(() {
        _pdf = file;
        _isImage = isImg;
        _err = null;
        if (isImg) {
          _mode = _ExtractionMode.adhoc;
          _pageScope = 1;
          _expected.text = '0';
          if (_preset != _LayoutPreset.autoBilingual &&
              _preset != _LayoutPreset.englishOnly) {
            _preset = _LayoutPreset.autoBilingual;
          }
          _startPage = 1;
          _pageStep = 1;
          _hindiOffset = 0;
        } else if (_isAdhoc) {
          _pageScope = _pageScope.clamp(1, 2).toInt();
          _expected.text = '0';
          _startPage = 1;
          _pageStep = 1;
          _hindiOffset = 0;
        } else {
          if (_expected.text == '0') _expected.text = '100';
          final defaults = _preset.pdfDefaults;
          _startPage = defaults.$1;
          _pageStep = defaults.$2;
          _hindiOffset = defaults.$3;
        }
      });
    }
  }

  Future<void> _submit() async {
    final year = int.tryParse(_year.text.trim());
    if (_pdf == null || _pdf!.bytes == null) {
      setState(() => _err = 'Pick a file first.');
      return;
    }
    if (year == null) {
      setState(() => _err = 'Enter a valid year.');
      return;
    }
    if (_examSlug == null) {
      setState(() => _err = 'Select an exam.');
      return;
    }
    final paper = (_paper?.isNotEmpty == true)
        ? _paper!
        : _paperCtrl.text.trim();
    if (paper.isEmpty) {
      setState(() => _err = 'Enter a paper name.');
      return;
    }
    final paperSlug = _paperSlug ?? _slugify(paper);
    final credential = _selectedCredential(
      ref.read(extractionCredentialsProvider).valueOrNull ?? const [],
    );
    final modelName = _modelCtrl.text.trim();
    if (credential == null && modelName.isEmpty) {
      setState(() => _err = 'Enter a model name.');
      return;
    }
    final isAdhoc = _isAdhoc;
    final pageScope = isAdhoc ? (_isImage ? 1 : _pageScope) : 0;
    final layout = isAdhoc
        ? _LayoutPreset.autoBilingual.contractValue
        : _preset.contractValue;
    final expectedCount = isAdhoc
        ? 0
        : (int.tryParse(_expected.text.trim()) ?? 0);
    final startPage = isAdhoc ? 1 : _startPage;
    final endPage = isAdhoc ? pageScope : 0;
    final pageStep = isAdhoc ? 1 : _pageStep;
    final hindiOffset = isAdhoc ? 0 : _hindiOffset;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await ref
          .read(extractionRepositoryProvider)
          .uploadAndCreateJob(
            examSlug: _examSlug!,
            year: year,
            paper: paper,
            paperSlug: paperSlug,
            paperSet: _set,
            fileName: _pdf!.name,
            fileExtension: _pdf!.extension,
            bytes: _pdf!.bytes!,
            isImage: _isImage,
            mode: _mode.value,
            pageScope: pageScope,
            layout: layout,
            wantHindi: _preset.wantHindi,
            expectedCount: expectedCount,
            startPage: startPage,
            endPage: endPage,
            pageStep: pageStep,
            hindiOffset: hindiOffset,
            modelProvider: credential?.provider ?? _provider.value,
            modelName: credential?.model ?? modelName,
            credentialId: _credentialId,
          );
      ref.invalidate(extractionJobsProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job queued — waiting for worker')),
        );
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _err = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final examsAsync = ref.watch(_examsListProvider);
    final papersAsync = ref.watch(_papersListProvider);
    final credentialsAsync = ref.watch(extractionCredentialsProvider);
    final sets =
        ref.watch(configOptionsProvider('paper_set')).valueOrNull ??
        defaultConfigOptions['paper_set']!;

    return Padding(
      padding: EdgeInsets.only(
        bottom:
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
        left: AppSpacing.pagePadding,
        right: AppSpacing.pagePadding,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.pal.grey200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'New extraction',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),

            _sectionLabel('Mode'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _ExtractionMode.values
                  .map(
                    (mode) => _Chip(
                      label: mode.label,
                      selected: _mode == mode,
                      onTap: () => _setMode(mode),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),

            // File picker
            GestureDetector(
              onTap: _busy ? null : _pick,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.pal.grey100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _pdf == null
                        ? context.pal.grey200
                        : context.pal.indigo,
                    width: _pdf == null ? 1 : 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _pdf == null
                          ? Icons.upload_file_outlined
                          : Icons.check_circle,
                      color: _pdf == null
                          ? context.pal.grey400
                          : context.pal.indigo,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _pdf?.name ??
                                (_isAdhoc
                                    ? 'Choose image or 1-2 page PDF'
                                    : 'Choose full paper PDF'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (_pdf == null)
                            Text(
                              _isAdhoc
                                  ? 'PDF / PNG / JPG - max 50 MB'
                                  : 'PDF only - max 50 MB',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: context.pal.grey400,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isAdhoc) ...[
              _sectionLabel('Page scope'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Chip(
                    label: '1 page',
                    selected: _pageScope == 1,
                    onTap: () => setState(() => _pageScope = 1),
                  ),
                  _Chip(
                    label: '2 pages',
                    selected: !_isImage && _pageScope == 2,
                    onTap: _isImage
                        ? () {}
                        : () => setState(() => _pageScope = 2),
                  ),
                  if (_isImage)
                    Text(
                      'Image uploads run as one page.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.pal.grey400,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Exam dropdown (loaded from DB)
            examsAsync.when(
              loading: () => const SizedBox(
                height: 48,
                child: LinearProgressIndicator(minHeight: 2),
              ),
              error: (e, _) => Text(
                'Could not load exams: $e',
                style: TextStyle(color: context.pal.red, fontSize: 12),
              ),
              data: (exams) => DropdownButtonFormField<String>(
                initialValue: _examSlug,
                decoration: InputDecoration(
                  labelText: 'Exam',
                  filled: true,
                  fillColor: context.pal.grey100,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                hint: const Text('Select exam'),
                isExpanded: true,
                items: exams
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.slug,
                        child: Text(e.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _examSlug = v),
              ),
            ),
            const SizedBox(height: 14),

            // Paper — suggestion chips from previous jobs + free-text entry
            _sectionLabel('Paper'),
            const SizedBox(height: 8),
            papersAsync.maybeWhen(
              data: (papers) {
                if (papers.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: papers
                        .map(
                          (p) => _Chip(
                            label: p.paper,
                            selected: _paperSlug == p.paperSlug,
                            onTap: () => setState(() {
                              _paper = p.paper;
                              _paperSlug = p.paperSlug;
                              _paperCtrl.text = p.paper;
                            }),
                          ),
                        )
                        .toList(),
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
            _field(
              'Paper name',
              _paperCtrl,
              hint: 'e.g. GS Paper I',
              onChanged: (v) => setState(() {
                _paper = v;
                _paperSlug = null;
              }),
            ),
            const SizedBox(height: 14),

            // Year + Set
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field('Year', _year, hint: 'e.g. 2024', number: true),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('Set'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: sets
                            .map(
                              (s) => _Chip(
                                label: s,
                                selected: _set == s,
                                onTap: () => setState(() => _set = s),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            _sectionLabel('Model provider'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _ExtractionProvider.values
                  .map(
                    (provider) => _Chip(
                      label: provider.label,
                      selected: _provider == provider,
                      onTap: _busy
                          ? () {}
                          : () => setState(() {
                              final oldDefault = _provider.defaultModel;
                              _provider = provider;
                              _credentialId = null;
                              if (_modelCtrl.text.trim().isEmpty ||
                                  _modelCtrl.text.trim() == oldDefault) {
                                _modelCtrl.text = provider.defaultModel;
                              }
                            }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            _sectionLabel('Model'),
            const SizedBox(height: 6),
            TextField(
              controller: _modelCtrl,
              onChanged: (_) => setState(() => _credentialId = null),
              decoration: _softFieldDecoration(
                context,
              ).copyWith(hintText: _provider.defaultModel),
            ),
            const SizedBox(height: 14),

            _credentialPicker(context, theme, credentialsAsync),
            const SizedBox(height: 14),

            _sectionLabel('Language mode'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(
                  label: 'Auto bilingual',
                  selected: _preset == _LayoutPreset.autoBilingual,
                  onTap: () => _applyPreset(_LayoutPreset.autoBilingual),
                ),
                _Chip(
                  label: 'English only',
                  selected: _preset == _LayoutPreset.englishOnly,
                  onTap: () => _applyPreset(_LayoutPreset.englishOnly),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_isAdhoc) ...[
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  'Advanced layout override',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: _availablePresets
                    .where((p) => p != _LayoutPreset.autoBilingual)
                    .map(
                      (p) => _PresetCard(
                        preset: p,
                        selected: _preset == p,
                        onTap: () => _applyPreset(p),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),

              _field('Expected questions', _expected, number: true),
            ],

            if (_err != null) ...[
              const SizedBox(height: 12),
              Text(
                _err!,
                style: TextStyle(color: context.pal.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: context.pal.indigo,
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.upload_outlined, size: 16),
                  label: const Text('Upload and queue'),
                  onPressed: _busy ? null : _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveCredential() async {
    final apiKey = _credentialApiKeyCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    if (apiKey.isEmpty || model.isEmpty) {
      setState(() => _credentialErr = 'API key and model are required.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _savingCredential = true;
      _credentialErr = null;
    });

    try {
      final id = await ref
          .read(qbankApiProvider)
          .saveExtractionCredential(
            QbankSaveExtractionCredentialRequestDto(
              label: _credentialLabelCtrl.text.trim().isEmpty
                  ? '${_provider.label} key'
                  : _credentialLabelCtrl.text.trim(),
              provider: _provider.value,
              model: model,
              apiKey: apiKey,
            ),
          );

      if (!mounted) return;
      _credentialLabelCtrl.clear();
      _credentialApiKeyCtrl.clear();
      ref.invalidate(extractionCredentialsProvider);
      setState(() {
        _savingCredential = false;
        _showCredentialForm = false;
        _credentialErr = null;
        _credentialId = id;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingCredential = false;
        _credentialErr = '$e';
      });
    }
  }

  Widget _credentialPicker(
    BuildContext context,
    ThemeData theme,
    AsyncValue<List<QbankExtractionCredentialDto>> credentialsAsync,
  ) {
    final credentials = credentialsAsync.valueOrNull ?? const [];
    final providerCredentials = credentials
        .where((credential) => credential.isActive)
        .where((credential) => credential.provider == _provider.value)
        .toList();
    final selected = _selectedCredential(providerCredentials);
    final selectedValue = selected?.id ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionLabel('API key')),
            TextButton.icon(
              onPressed: _busy || _savingCredential
                  ? null
                  : () => setState(() {
                      _showCredentialForm = !_showCredentialForm;
                      _credentialErr = null;
                    }),
              icon: const Icon(Icons.add, size: 16),
              label: Text(_showCredentialForm ? 'Hide key form' : 'Add key'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        credentialsAsync.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (e, _) => Text(
            'Could not load keys: $e',
            style: TextStyle(color: context.pal.red, fontSize: 12),
          ),
          data: (_) => DropdownButtonFormField<String>(
            initialValue: selectedValue,
            decoration: _softFieldDecoration(context),
            isExpanded: true,
            selectedItemBuilder: (context) => [
              const _DropdownSelectedText('Workflow default key'),
              ...providerCredentials.map(
                (credential) => _DropdownSelectedText(credential.label),
              ),
            ],
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(
                  'Workflow default key',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              ...providerCredentials.map(
                (credential) => DropdownMenuItem(
                  value: credential.id,
                  child: _DropdownMenuText(
                    title: credential.label,
                    subtitle: '${credential.model} / ${credential.keyPreview}',
                  ),
                ),
              ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    setState(() {
                      _credentialId = value == null || value.isEmpty
                          ? null
                          : value;
                    });
                  },
          ),
        ),
        if (_showCredentialForm) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.pal.grey100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.pal.grey200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Label', style: theme.textTheme.labelMedium),
                const SizedBox(height: 6),
                TextField(
                  controller: _credentialLabelCtrl,
                  enabled: !_savingCredential,
                  decoration: _softFieldDecoration(
                    context,
                  ).copyWith(hintText: 'e.g. Gemini key 2'),
                ),
                const SizedBox(height: 10),
                Text('API key', style: theme.textTheme.labelMedium),
                const SizedBox(height: 6),
                TextField(
                  controller: _credentialApiKeyCtrl,
                  enabled: !_savingCredential,
                  obscureText: true,
                  decoration: _softFieldDecoration(context),
                ),
                if (_credentialErr != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _credentialErr!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _savingCredential
                          ? null
                          : () => setState(() {
                              _showCredentialForm = false;
                              _credentialErr = null;
                              _credentialLabelCtrl.clear();
                              _credentialApiKeyCtrl.clear();
                            }),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: _savingCredential ? null : _saveCredential,
                      child: _savingCredential
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save key'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      color: context.pal.grey400,
    ),
  );

  Widget _field(
    String label,
    TextEditingController c, {
    String? hint,
    bool number = false,
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: c,
    keyboardType: number ? TextInputType.number : TextInputType.text,
    onChanged: onChanged,
    decoration: _softFieldDecoration(
      context,
    ).copyWith(labelText: label, hintText: hint),
  );

  InputDecoration _softFieldDecoration(BuildContext context) => InputDecoration(
    filled: true,
    fillColor: context.pal.grey100,
    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
  );
}

class _DropdownSelectedText extends StatelessWidget {
  final String text;
  const _DropdownSelectedText(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _DropdownMenuText extends StatelessWidget {
  final String title;
  final String subtitle;
  const _DropdownMenuText({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.pal.grey400,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chip widget ───────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? context.pal.indigoLight : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? context.pal.indigo : context.pal.grey200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? context.pal.indigo : context.pal.grey700,
          ),
        ),
      ),
    );
  }
}

// ── Preset card ───────────────────────────────────────────────────────────────

class _PresetCard extends StatelessWidget {
  final _LayoutPreset preset;
  final bool selected;
  final VoidCallback onTap;
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? context.pal.indigoLight : context.pal.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? context.pal.indigo : context.pal.grey200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              preset.icon,
              size: 20,
              color: selected ? context.pal.indigo : context.pal.grey600,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? context.pal.indigo
                          : context.pal.grey900,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    preset.subtitle,
                    style: TextStyle(fontSize: 11, color: context.pal.grey600),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? context.pal.indigo : context.pal.grey300,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Job detail sheet ──────────────────────────────────────────────────────────

class _JobDetailSheet extends ConsumerWidget {
  final String jobId;
  const _JobDetailSheet({required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final job = ref
        .watch(extractionJobsProvider)
        .valueOrNull
        ?.where((j) => j.id == jobId)
        .firstOrNull;
    if (job == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final examNames = ref.watch(examNamesProvider).valueOrNull ?? const {};
    final cov = (job.report?['coverage'] as Map?)?.cast<String, dynamic>();
    final missing = (cov?['missing'] as List?) ?? const [];
    final invalid = (job.report?['invalid'] as List?) ?? const [];
    final failed = (job.report?['failed_pages'] as List?) ?? const [];
    final profiles = (job.report?['page_profiles'] as List?) ?? const [];
    final plan = (job.report?['layout_plan'] as Map?)?.cast<String, dynamic>();
    final tasks = (plan?['tasks'] as List?) ?? const [];
    final pairing = (job.report?['pairing'] as Map?)?.cast<String, dynamic>();
    final paired = (pairing?['paired_qnos'] as List?) ?? const [];
    final missingByLanguage = (job.report?['missing_by_language'] as Map?)
        ?.cast<String, dynamic>();
    final models = (job.report?['models_used'] as List?) ?? const [];
    final stage = job.progress['stage']?.toString();
    final inputType = (job.report?['input_type'] ?? job.params['input_type'])
        ?.toString();
    final pageScope = job.report?['page_scope'] ?? job.params['page_scope'];
    final processedPages =
        (job.report?['processed_pages'] as List?) ?? const [];
    final skippedPages = (job.report?['skipped_pages'] as List?) ?? const [];
    String pagesText(List pages) => pages.map((p) => '$p').join(', ');
    final expected = (cov?['expected_count'] as num?)?.toInt() ?? 0;
    // Live gap from the backend contract, unlike the frozen coverage snapshot
    // from extraction time.
    final liveMissing = expected > 0
        ? ref.watch(liveMissingProvider((jobId: job.id, expected: expected)))
        : const AsyncValue<List<int>>.data(<int>[]);

    return Padding(
      padding: EdgeInsets.only(
        bottom:
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
        left: AppSpacing.pagePadding,
        right: AppSpacing.pagePadding,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: context.pal.grey200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${job.year} · ${job.paper} · Set ${job.paperSet}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      examNames[job.examSlug] ?? job.examLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.pal.grey400,
                      ),
                    ),
                  ],
                ),
              ),
              _ModeChip(isAdhoc: job.isAdhoc),
              const SizedBox(width: 6),
              _StatusChip(status: job.status),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            'Job ID: ${job.id}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.pal.grey400,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 16),
          if (stage != null && stage.isNotEmpty)
            _statRow(context, ('Stage', stage, context.pal.indigo)),
          _statRow(context, (
            'Mode',
            job.isAdhoc ? 'Adhoc page' : 'Full paper',
            null,
          )),
          if (inputType != null && inputType.isNotEmpty)
            _statRow(context, ('Input', inputType, null)),
          if (pageScope != null)
            _statRow(context, ('Page scope', '$pageScope', null)),
          if (processedPages.isNotEmpty)
            _statRow(context, (
              'Processed pages',
              pagesText(processedPages),
              null,
            )),
          if (skippedPages.isNotEmpty)
            _statRow(context, (
              'Skipped pages',
              pagesText(skippedPages),
              context.pal.amber,
            )),
          if (cov != null) ...[
            _statRow(context, () {
              final found = cov['found'];
              final exp = (cov['expected_count'] as num?)?.toInt() ?? 0;
              return ('Extracted', exp > 0 ? '$found / $exp' : '$found', null);
            }()),
            if (missing.isNotEmpty)
              _statRow(context, (
                'Missing at extraction',
                missing.join(', '),
                context.pal.amber,
              )),
            ...liveMissing.when(
              loading: () => [
                _statRow(context, ('Missing now', '…', context.pal.grey400)),
              ],
              error: (_, _) => const [],
              data: (live) {
                if (live.isEmpty) {
                  return [
                    _statRow(context, (
                      'In DB now',
                      'all $expected present',
                      const Color(0xFF16A34A),
                    )),
                  ];
                }
                // qnos gone from the DB that were present at extraction time =
                // deletions during review.
                final extractionMissing = {
                  for (final m in missing) (m as num).toInt(),
                };
                final deleted = live
                    .where((q) => !extractionMissing.contains(q))
                    .toList();
                return [
                  _statRow(context, (
                    'Missing now (in DB)',
                    live.join(', '),
                    context.pal.amber,
                  )),
                  if (deleted.isNotEmpty)
                    _statRow(context, (
                      'Deleted in review',
                      deleted.join(', '),
                      context.pal.red,
                    )),
                ];
              },
            ),
            if (invalid.isNotEmpty)
              _statRow(context, (
                'Invalid (quarantined)',
                '${invalid.length}',
                context.pal.amber,
              )),
            if (failed.isNotEmpty)
              _statRow(context, (
                'Failed pages',
                failed.map((f) => (f as Map)['page']).join(', '),
                context.pal.red,
              )),
            if (profiles.isNotEmpty)
              _statRow(context, ('Profiled pages', '${profiles.length}', null)),
            if (tasks.isNotEmpty)
              _statRow(context, ('Extraction tasks', '${tasks.length}', null)),
            if (paired.isNotEmpty)
              _statRow(context, ('Paired qnos', '${paired.length}', null)),
            if (missingByLanguage != null) ...[
              if (((missingByLanguage['en'] as List?) ?? const []).isNotEmpty)
                _statRow(context, (
                  'Missing English',
                  ((missingByLanguage['en'] as List?) ?? const []).join(', '),
                  context.pal.amber,
                )),
              if (((missingByLanguage['hi'] as List?) ?? const []).isNotEmpty)
                _statRow(context, (
                  'Missing Hindi',
                  ((missingByLanguage['hi'] as List?) ?? const []).join(', '),
                  context.pal.amber,
                )),
            ],
            if (models.isNotEmpty)
              _statRow(context, (
                'Models',
                models
                    .whereType<Map>()
                    .map((m) => '${m['provider']}:${m['model']}')
                    .join(', '),
                null,
              )),
          ] else if (job.status == 'failed') ...[
            Text(
              job.error ?? 'Failed',
              style: TextStyle(color: context.pal.red),
            ),
          ] else
            Text(
              'Waiting for the worker to report…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.pal.grey600,
              ),
            ),
          const SizedBox(height: 20),
          _RerunActions(job: job),
          const SizedBox(height: 8),
          if (job.status == 'needs_review' || job.status == 'completed')
            _PublishButton(job: job),
        ],
      ),
    );
  }

  Widget _statRow(BuildContext context, (String, String, Color?) t) {
    final (label, value, color) = t;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(color: context.pal.grey600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color ?? context.pal.grey900,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RerunActions extends ConsumerStatefulWidget {
  final ExtractionJob job;
  const _RerunActions({required this.job});

  @override
  ConsumerState<_RerunActions> createState() => _RerunActionsState();
}

class _RerunActionsState extends ConsumerState<_RerunActions> {
  bool _busy = false;
  String? _msg;

  Future<void> _run(String action) async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final newJobId = await ref
          .read(qbankApiProvider)
          .resumeExtractionJob(
            QbankResumeExtractionJobRequestDto(
              jobId: widget.job.id,
              action: action,
            ),
          );
      ref.invalidate(extractionJobsProvider);
      setState(() {
        _busy = false;
        _msg = newJobId == null ? 'Queued rerun.' : 'Queued rerun $newJobId.';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _msg = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Rerun job'),
              onPressed: _busy ? null : () => _run('rerun'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.find_replace, size: 16),
              label: const Text('Rerun missing'),
              onPressed: _busy ? null : () => _run('missing_qnos'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.compare_arrows, size: 16),
              label: const Text('Re-pair'),
              onPressed: _busy ? null : () => _run('repair_pairing'),
            ),
          ],
        ),
        if (_msg != null) ...[
          const SizedBox(height: 8),
          Text(_msg!, style: const TextStyle(fontSize: 12)),
        ],
      ],
    );
  }
}

class _PublishButton extends ConsumerStatefulWidget {
  final ExtractionJob job;
  const _PublishButton({required this.job});

  @override
  ConsumerState<_PublishButton> createState() => _PublishButtonState();
}

class _PublishButtonState extends ConsumerState<_PublishButton> {
  bool _busy = false;
  String? _msg;

  Future<void> _publish() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final questions = await ref
          .read(qbankApiProvider)
          .listDraftQuestions(
            QbankDraftQuestionsRequestDto(
              examSlug: widget.job.examSlug,
              year: widget.job.year,
              paperSlug: widget.job.paperSlug,
            ),
          );
      for (final question in questions) {
        await ref
            .read(qbankApiProvider)
            .reviewQuestion(
              QbankReviewQuestionRequestDto(
                questionId: question.id,
                action: 'publish',
              ),
            );
      }
      setState(() {
        _busy = false;
        _msg = 'Published ${questions.length} question(s).';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _msg = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
          ),
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.publish),
          label: const Text('Publish drafts'),
          onPressed: _busy ? null : _publish,
        ),
        if (_msg != null) ...[
          const SizedBox(height: 8),
          Text(_msg!, style: const TextStyle(fontSize: 12)),
        ],
      ],
    );
  }
}
