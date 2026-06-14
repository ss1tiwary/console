import 'dart:math';

import 'package:resolve_theme/resolve_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    required this.progress,
    this.report,
    this.error,
    required this.createdAt,
  });

  factory ExtractionJob.fromJson(Map<String, dynamic> j) {
    final p = (j['params'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ExtractionJob(
      id: j['id'] as String,
      examSlug: p['exam_slug'] as String? ?? 'upsc_cse',
      year: (p['year'] as num?)?.toInt() ?? 0,
      paper: p['paper'] as String? ?? '',
      paperSlug: p['paper_slug'] as String? ?? '',
      paperSet: p['paper_set'] as String? ?? 'A',
      pdfName: p['pdf_name'] as String?,
      status: j['status'] as String? ?? 'pending',
      progress:
          (j['progress'] as Map?)?.cast<String, dynamic>() ?? const {},
      report: (j['report'] as Map?)?.cast<String, dynamic>(),
      error: j['error'] as String?,
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }

  String get examLabel => examSlug.replaceAll('_', ' ').toUpperCase();
}

// ── Provider ──────────────────────────────────────────────────────────────────

final extractionJobsProvider =
    StreamProvider.autoDispose<List<ExtractionJob>>((ref) {
  return ref
      .watch(supabaseClientProvider)
      .from('jobs')
      .stream(primaryKey: ['id'])
      .eq('job_type', 'extraction')
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) =>
          rows.map((e) => ExtractionJob.fromJson(e)).toList());
});

// Shared slug→short_name map used for display in cards, headers, review panel.
// Falls back to selecting just name if short_name column doesn't exist yet.
final examNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final sb = ref.read(supabaseClientProvider);
  try {
    final rows = await sb
        .from('exams')
        .select('slug, short_name, name') as List<dynamic>;
    return {
      for (final r in rows)
        r['slug'] as String:
            (r['short_name'] as String?) ?? (r['name'] as String)
    };
  } catch (_) {
    final rows =
        await sb.from('exams').select('slug, name') as List<dynamic>;
    return {for (final r in rows) r['slug'] as String: r['name'] as String};
  }
});

final _examsListProvider =
    FutureProvider.autoDispose<List<({String slug, String name})>>((ref) async {
  final sb = ref.read(supabaseClientProvider);
  try {
    final rows = await sb
        .from('exams')
        .select('slug, short_name, name')
        .eq('status', 'active')
        .order('short_name') as List<dynamic>;
    return rows
        .map((r) => (
              slug: r['slug'] as String,
              name: (r['short_name'] as String?) ?? (r['name'] as String),
            ))
        .toList();
  } catch (_) {
    final rows = await sb
        .from('exams')
        .select('slug, name')
        .eq('status', 'active')
        .order('name') as List<dynamic>;
    return rows
        .map((r) => (slug: r['slug'] as String, name: r['name'] as String))
        .toList();
  }
});

// Live missing qnos for a job — computed from the questions table so it stays
// accurate after review deletions. Keyed by (importKeyPrefix, expectedCount).
// importKeyPrefix = "{exam_slug}_{year}_{paper_slug}" (matches all qnos for the job).
final liveMissingProvider = FutureProvider.autoDispose
    .family<List<int>, ({String prefix, int expected})>((ref, args) async {
  if (args.expected <= 0) return const [];
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('questions')
      .select('original_qno')
      .like('import_key', '${args.prefix}_%') as List<dynamic>;
  final present = rows
      .map((r) => (r as Map)['original_qno'] as int? ?? 0)
      .where((n) => n > 0)
      .toSet();
  return [
    for (int i = 1; i <= args.expected; i++)
      if (!present.contains(i)) i
  ];
});

final _papersListProvider =
    FutureProvider.autoDispose<List<({String paper, String paperSlug})>>((ref) async {
  final rows = await ref
      .read(supabaseClientProvider)
      .from('jobs')
      .select('params')
      .eq('job_type', 'extraction') as List<dynamic>;
  final seen = <String>{};
  final result = <({String paper, String paperSlug})>[];
  for (final r in rows) {
    final p = (r['params'] as Map?)?.cast<String, dynamic>() ?? {};
    final slug = p['paper_slug'] as String? ?? '';
    final paper = p['paper'] as String? ?? '';
    if (slug.isNotEmpty && seen.add(slug)) {
      result.add((paper: paper, paperSlug: slug));
    }
  }
  return result;
});

// ── Tab filter ────────────────────────────────────────────────────────────────

enum _Tab { all, queued, review, done }

extension _TabX on _Tab {
  String get label => switch (this) {
        _Tab.all    => 'All',
        _Tab.queued => 'Queued',
        _Tab.review => 'Review',
        _Tab.done   => 'Done',
      };

  bool matches(ExtractionJob j) => switch (this) {
        _Tab.all    => true,
        _Tab.queued => j.status == 'pending' || j.status == 'running',
        _Tab.review => j.status == 'needs_review',
        _Tab.done   => j.status == 'completed' || j.status == 'failed',
      };
}

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
      builder: (_, c) =>
          c.maxWidth >= 600 ? _wideLayout() : _narrowLayout(),
    );
  }

  Widget _wideLayout() {
    return Row(children: [
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
    ]);
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
            Icon(Icons.document_scanner_outlined,
                size: 48, color: context.pal.grey300),
            const SizedBox(height: 12),
            Text(
              'Select a job to review',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: context.pal.grey400),
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
            loading: () =>
                const Center(child: CircularProgressIndicator()),
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
                    borderRadius: BorderRadius.circular(10)),
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
                          color: sel
                              ? context.pal.indigo
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      t.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: sel
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: sel
                            ? context.pal.indigo
                            : context.pal.grey600,
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
  const _JobListBody(
      {required this.jobs,
      required this.selected,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final active = jobs
        .where((j) => j.status == 'pending' || j.status == 'running')
        .toList();
    final recent = jobs
        .where((j) => j.status != 'pending' && j.status != 'running')
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      children: [
        if (active.isNotEmpty) ...[
          _sectionLabel(context, active.length),
          ...active.map((j) => _JobCard(
                job: j,
                isSelected: j.id == selected?.id,
                onTap: () => onSelect(j),
              )),
        ],
        if (recent.isNotEmpty) ...[
          _recentLabel(context),
          ...recent.map((j) => _JobCard(
                job: j,
                isSelected: j.id == selected?.id,
                onTap: () => onSelect(j),
              )),
        ],
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
        child: Row(children: [
          Text('ACTIVE',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: context.pal.grey400)),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: context.pal.indigoLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: context.pal.indigo)),
          ),
        ]),
      );

  Widget _recentLabel(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(4, 10, 4, 6),
        child: Text('RECENT',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: context.pal.grey400)),
      );
}

// ── Job card ──────────────────────────────────────────────────────────────────

class _JobCard extends ConsumerWidget {
  final ExtractionJob job;
  final bool isSelected;
  final VoidCallback onTap;
  const _JobCard(
      {required this.job, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final examNames = ref.watch(examNamesProvider).valueOrNull ?? const {};
    final total =
        (job.progress['pages_total'] as num?)?.toInt() ?? 0;
    final done =
        (job.progress['pages_done'] as num?)?.toInt() ?? 0;
    final qs =
        (job.progress['questions_extracted'] as num?)?.toInt() ?? 0;
    final active =
        job.status == 'running' || job.status == 'pending';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? context.pal.indigoLight : context.pal.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                isSelected ? context.pal.indigo : context.pal.grey200,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${job.year} · ${job.paper} · Set ${job.paperSet}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      examNames[job.examSlug] ?? job.examLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: context.pal.grey400, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: job.status),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    size: 18, color: context.pal.grey400),
                padding: EdgeInsets.zero,
                tooltip: 'Job actions',
                onSelected: (v) {
                  if (v == 'delete') _confirmDelete(context, ref);
                },
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline,
                          size: 18, color: context.pal.red),
                      const SizedBox(width: 8),
                      const Text('Delete job'),
                    ]),
                  ),
                ],
              ),
            ]),
            if (job.pdfName != null) ...[
              const SizedBox(height: 4),
              Text(
                job.pdfName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: context.pal.grey400, fontSize: 11),
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
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: context.pal.grey600),
              ),
            ] else if (active) ...[
              Row(children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('Queued — waiting for worker…',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: context.pal.grey600)),
              ]),
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
              child: const Text('Cancel')),
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
      // The .stream() provider removes the card automatically. Requires the
      // jobs_editor_delete RLS policy (question-bank migration 012).
      await ref
          .read(supabaseClientProvider)
          .from('jobs')
          .delete()
          .eq('id', job.id);
      messenger.showSnackBar(const SnackBar(content: Text('Job deleted')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Widget _coverageLine(BuildContext context, ThemeData theme) {
    final cov =
        (job.report?['coverage'] as Map?)?.cast<String, dynamic>();
    if (cov == null) {
      if (job.status == 'failed') {
        return Text(job.error ?? 'Failed',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: context.pal.red));
      }
      return const SizedBox.shrink();
    }
    final found = (cov['found'] as num?)?.toInt() ?? 0;
    final expected =
        (cov['expected_count'] as num?)?.toInt() ?? 0;
    final missing = (cov['missing'] as List?)?.length ?? 0;
    final countLabel =
        expected > 0 ? '$found / $expected' : '$found';
    return Text(
      '$countLabel extracted'
      '${missing > 0 ? ' · $missing missing' : ' · complete'}',
      style: theme.textTheme.bodySmall?.copyWith(
        color: missing > 0
            ? context.pal.amber
            : const Color(0xFF16A34A),
        fontWeight: FontWeight.w600,
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
      'pending'      => ('Queued',  context.pal.grey600,      context.pal.grey100),
      'running'      => ('Running', context.pal.indigo,       context.pal.indigoLight),
      'needs_review' => ('Review',  context.pal.amber,        context.pal.amberLight),
      'completed'    => ('Done',    const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
      _              => ('Failed',  context.pal.red,          const Color(0xFFFEE2E2)),
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

// ── Empty list ─────────────────────────────────────────────────────────────────

class _EmptyList extends StatelessWidget {
  final _Tab tab;
  const _EmptyList({required this.tab});

  @override
  Widget build(BuildContext context) {
    final msg = switch (tab) {
      _Tab.queued => 'No queued jobs.',
      _Tab.review => 'Nothing needs review.',
      _Tab.done   => 'No completed jobs yet.',
      _Tab.all    => 'No jobs yet.\nTap New extraction to start.',
    };
    return Center(
      child: Text(msg,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: context.pal.grey400)),
    );
  }
}

// ── Paper / exam constants ────────────────────────────────────────────────────


// ── Layout presets ────────────────────────────────────────────────────────────
// A preset is the human-facing choice; it maps to the worker contract's `layout`
// value + the page knobs (start_page / page_step / hindi_offset) so the user never
// has to reason about raw page numbers. See question-bank/extract_worker.py.

enum _LayoutPreset { upscPagePair, samePage, englishOnly }

extension _LayoutPresetX on _LayoutPreset {
  String get title => switch (this) {
        _LayoutPreset.upscPagePair => 'UPSC bilingual',
        _LayoutPreset.samePage     => 'Bilingual · same page',
        _LayoutPreset.englishOnly   => 'English only',
      };

  String get subtitle => switch (this) {
        _LayoutPreset.upscPagePair => 'Hindi printed on a separate page',
        _LayoutPreset.samePage     => 'English + Hindi in one page (2 columns)',
        _LayoutPreset.englishOnly   => 'No Hindi extraction',
      };

  IconData get icon => switch (this) {
        _LayoutPreset.upscPagePair => Icons.auto_stories_outlined,
        _LayoutPreset.samePage     => Icons.vertical_split_outlined,
        _LayoutPreset.englishOnly   => Icons.subject,
      };

  // What gets written to extraction_jobs.layout.
  String get dbValue => switch (this) {
        _LayoutPreset.upscPagePair => 'page_pair',
        _LayoutPreset.samePage     => 'same_page',
        _LayoutPreset.englishOnly   => 'single',
      };

  bool get wantHindi => this != _LayoutPreset.englishOnly;

  // Default page knobs for a PDF. Images always override to 1 / 1 / 0.
  (int start, int step, int offset) get pdfDefaults => switch (this) {
        _LayoutPreset.upscPagePair => (3, 2, -1),
        _LayoutPreset.samePage     => (1, 1, 0),
        _LayoutPreset.englishOnly   => (1, 1, 0),
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
  _LayoutPreset _preset = _LayoutPreset.upscPagePair;
  final _year = TextEditingController(text: '');
  final _expected = TextEditingController(text: '100');
  final _paperCtrl = TextEditingController();
  int _startPage = 3;
  int _pageStep = 2;
  int _hindiOffset = -1;
  PlatformFile? _pdf;
  bool _isImage = false;
  bool _busy = false;
  String? _err;

  static const _imageExts = {'png', 'jpg', 'jpeg'};

  List<_LayoutPreset> get _availablePresets => _isImage
      ? const [_LayoutPreset.samePage, _LayoutPreset.englishOnly]
      : _LayoutPreset.values;

  void _applyPreset(_LayoutPreset p) {
    final (start, step, offset) = p.pdfDefaults;
    setState(() {
      _preset = p;
      _startPage = _isImage ? 1 : start;
      _pageStep  = _isImage ? 1 : step;
      _hindiOffset = _isImage ? 0 : offset;
    });
  }

  String _slugify(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  @override
  void dispose() {
    _year.dispose();
    _expected.dispose();
    _paperCtrl.dispose();
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
        if (isImg) {
          _expected.text = '0';
          final p = _availablePresets.contains(_preset)
              ? _preset
              : _LayoutPreset.samePage;
          _preset = p;
          _startPage = 1; _pageStep = 1; _hindiOffset = 0;
        } else {
          if (_expected.text == '0') _expected.text = '100';
          _applyPreset(_preset);
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
    final paper = (_paper?.isNotEmpty == true) ? _paper! : _paperCtrl.text.trim();
    if (paper.isEmpty) {
      setState(() => _err = 'Enter a paper name.');
      return;
    }
    final paperSlug = _paperSlug ?? _slugify(paper);
    setState(() { _busy = true; _err = null; });
    try {
      final sb = ref.read(supabaseClientProvider);
      final uid = sb.auth.currentUser?.id;
      final rand = Random().nextInt(1 << 32).toRadixString(16);
      final path = '$year/${paperSlug}_${rand}_${_pdf!.name}';
      final contentType = _isImage
          ? 'image/${_pdf!.extension?.toLowerCase()}'
          : 'application/pdf';
      await sb.storage.from('pyq-uploads').uploadBinary(
            path,
            _pdf!.bytes!,
            fileOptions: FileOptions(contentType: contentType),
          );
      await sb.from('jobs').insert({
        'job_type':     'extraction',
        'triggered_by': 'admin',
        'created_by':   uid,
        'params': {
          'exam_slug':      _examSlug,
          'year':           year,
          'paper':          paper,
          'paper_slug':     paperSlug,
          'paper_set':      _set,
          'layout':         _preset.dbValue,
          'pdf_path':       path,
          'pdf_name':       _pdf!.name,
          'want_hindi':     _preset.wantHindi,
          'expected_count': int.tryParse(_expected.text.trim()) ?? 0,
          'start_page':     _startPage,
          'page_step':      _pageStep,
          'hindi_offset':   _hindiOffset,
        },
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job queued — waiting for worker')),
        );
      }
    } catch (e) {
      setState(() { _busy = false; _err = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final examsAsync = ref.watch(_examsListProvider);
    final papersAsync = ref.watch(_papersListProvider);
    final sets = ref.watch(configOptionsProvider('paper_set')).valueOrNull ??
        defaultConfigOptions['paper_set']!;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom +
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
            Text('New extraction',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
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
                    color: _pdf == null ? context.pal.grey200 : context.pal.indigo,
                    width: _pdf == null ? 1 : 1.5,
                  ),
                ),
                child: Row(children: [
                  Icon(
                    _pdf == null ? Icons.upload_file_outlined : Icons.check_circle,
                    color: _pdf == null ? context.pal.grey400 : context.pal.indigo,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pdf?.name ?? 'Choose PDF or image (PNG / JPG)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (_pdf == null)
                          Text('PDF · PNG · JPG — max 50 MB',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: context.pal.grey400)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // Exam dropdown (loaded from DB)
            examsAsync.when(
              loading: () => const SizedBox(
                height: 48,
                child: LinearProgressIndicator(minHeight: 2),
              ),
              error: (e, _) => Text('Could not load exams: $e',
                  style: TextStyle(color: context.pal.red, fontSize: 12)),
              data: (exams) => DropdownButtonFormField<String>(
                initialValue: _examSlug,
                decoration: InputDecoration(
                  labelText: 'Exam',
                  filled: true,
                  fillColor: context.pal.grey100,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                hint: const Text('Select exam'),
                isExpanded: true,
                items: exams
                    .map((e) => DropdownMenuItem(
                          value: e.slug,
                          child: Text(e.name, overflow: TextOverflow.ellipsis),
                        ))
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
                        .map((p) => _Chip(
                              label: p.paper,
                              selected: _paperSlug == p.paperSlug,
                              onTap: () => setState(() {
                                _paper = p.paper;
                                _paperSlug = p.paperSlug;
                                _paperCtrl.text = p.paper;
                              }),
                            ))
                        .toList(),
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
            _field('Paper name', _paperCtrl,
                hint: 'e.g. GS Paper I',
                onChanged: (v) => setState(() {
                      _paper = v;
                      _paperSlug = null;
                    })),
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
                            .map((s) => _Chip(
                                  label: s,
                                  selected: _set == s,
                                  onTap: () => setState(() => _set = s),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Layout preset
            _sectionLabel('Layout'),
            const SizedBox(height: 8),
            ..._availablePresets.map((p) => _PresetCard(
                  preset: p,
                  selected: _preset == p,
                  onTap: () => _applyPreset(p),
                )),
            const SizedBox(height: 14),

            _field('Expected questions', _expected, number: true),

            if (_err != null) ...[
              const SizedBox(height: 12),
              Text(_err!,
                  style: TextStyle(color: context.pal.red, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            Row(children: [
              const Spacer(),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: context.pal.indigo),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_outlined, size: 16),
                label: const Text('Upload & queue'),
                onPressed: _busy ? null : _submit,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: context.pal.grey400,
        ),
      );

  Widget _field(
    String label,
    TextEditingController c, {
    String? hint,
    bool number = false,
    ValueChanged<String>? onChanged,
  }) =>
      TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: context.pal.grey100,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      );
}

// ── Chip widget ───────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
            color:
                selected ? context.pal.indigo : context.pal.grey700,
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
  const _PresetCard(
      {required this.preset,
      required this.selected,
      required this.onTap});

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
        child: Row(children: [
          Icon(preset.icon,
              size: 20,
              color: selected ? context.pal.indigo : context.pal.grey600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preset.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? context.pal.indigo
                          : context.pal.grey900,
                    )),
                const SizedBox(height: 1),
                Text(preset.subtitle,
                    style: TextStyle(
                        fontSize: 11, color: context.pal.grey600)),
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
        ]),
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
    final cov =
        (job.report?['coverage'] as Map?)?.cast<String, dynamic>();
    final missing = (cov?['missing'] as List?) ?? const [];
    final invalid =
        (job.report?['invalid'] as List?) ?? const [];
    final failed =
        (job.report?['failed_pages'] as List?) ?? const [];
    final expected =
        (cov?['expected_count'] as num?)?.toInt() ?? 0;
    // Live gap from the questions table — reflects review deletions, unlike the
    // frozen report.coverage.missing snapshot from extraction time.
    final liveMissing = expected > 0
        ? ref.watch(liveMissingProvider((
            prefix: '${job.examSlug}_${job.year}_${job.paperSlug}',
            expected: expected,
          )))
        : const AsyncValue<List<int>>.data(<int>[]);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom +
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
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${job.year} · ${job.paper} · Set ${job.paperSet}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(examNames[job.examSlug] ?? job.examLabel,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: context.pal.grey400)),
                ],
              ),
            ),
            _StatusChip(status: job.status),
          ]),
          const SizedBox(height: 4),
          SelectableText('Job ID: ${job.id}',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: context.pal.grey400, fontSize: 11)),
          const SizedBox(height: 16),
          if (cov != null) ...[
            _statRow(context, () {
              final found = cov['found'];
              final exp =
                  (cov['expected_count'] as num?)?.toInt() ?? 0;
              return ('Extracted',
                  exp > 0 ? '$found / $exp' : '$found', null);
            }()),
            if (missing.isNotEmpty)
              _statRow(context, ('Missing at extraction',
                  missing.join(', '), context.pal.amber)),
            ...liveMissing.when(
              loading: () => [
                _statRow(context, ('Missing now', '…', context.pal.grey400)),
              ],
              error: (_, _) => const [],
              data: (live) {
                if (live.isEmpty) {
                  return [
                    _statRow(context, ('In DB now',
                        'all $expected present', const Color(0xFF16A34A))),
                  ];
                }
                // qnos gone from the DB that were present at extraction time =
                // deletions during review.
                final extractionMissing = {
                  for (final m in missing) (m as num).toInt()
                };
                final deleted = live
                    .where((q) => !extractionMissing.contains(q))
                    .toList();
                return [
                  _statRow(context, ('Missing now (in DB)',
                      live.join(', '), context.pal.amber)),
                  if (deleted.isNotEmpty)
                    _statRow(context, ('Deleted in review',
                        deleted.join(', '), context.pal.red)),
                ];
              },
            ),
            if (invalid.isNotEmpty)
              _statRow(context, ('Invalid (quarantined)',
                  '${invalid.length}', context.pal.amber)),
            if (failed.isNotEmpty)
              _statRow(context, ('Failed pages',
                  failed
                      .map((f) => (f as Map)['page'])
                      .join(', '),
                  context.pal.red)),
          ] else if (job.status == 'failed') ...[
            Text(job.error ?? 'Failed',
                style:
                    TextStyle(color: context.pal.red)),
          ] else
            Text('Waiting for the worker to report…',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: context.pal.grey600)),
          const SizedBox(height: 20),
          if (job.status == 'needs_review' ||
              job.status == 'completed')
            _PublishButton(job: job),
        ],
      ),
    );
  }

  Widget _statRow(BuildContext context, (String, String, Color?) t) {
    final (label, value, color) = t;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 140,
          child: Text(label,
              style: TextStyle(
                  color: context.pal.grey600, fontSize: 13)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color ?? context.pal.grey900,
                  fontSize: 13)),
        ),
      ]),
    );
  }
}

class _PublishButton extends ConsumerStatefulWidget {
  final ExtractionJob job;
  const _PublishButton({required this.job});

  @override
  ConsumerState<_PublishButton> createState() =>
      _PublishButtonState();
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
      final rows = await ref
          .read(supabaseClientProvider)
          .from('questions')
          .update({'status': 'published'})
          .eq('year', widget.job.year)
          .eq('paper', widget.job.paper)
          .eq('status', 'draft')
          .select('id');
      setState(() {
        _busy = false;
        _msg = 'Published ${(rows as List).length} question(s).';
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
              backgroundColor: const Color(0xFF16A34A)),
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
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
