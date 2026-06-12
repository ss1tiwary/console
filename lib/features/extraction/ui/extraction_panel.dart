import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/di/providers.dart';
import '../../../core/palette.dart';
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

  factory ExtractionJob.fromJson(Map<String, dynamic> j) => ExtractionJob(
        id: j['id'] as String,
        examSlug: j['exam_slug'] as String? ?? 'upsc_cse',
        year: (j['year'] as num).toInt(),
        paper: j['paper'] as String? ?? 'GS Paper I',
        paperSlug: j['paper_slug'] as String? ?? 'gs1',
        paperSet: j['paper_set'] as String? ?? 'A',
        pdfName: j['pdf_name'] as String?,
        status: j['status'] as String? ?? 'pending',
        progress:
            (j['progress'] as Map?)?.cast<String, dynamic>() ?? const {},
        report: (j['report'] as Map?)?.cast<String, dynamic>(),
        error: j['error'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  String get examLabel => switch (examSlug) {
        'upsc_cse'  => 'UPSC CSE',
        'ssc_cgl'   => 'SSC CGL',
        'ibps_po'   => 'IBPS PO',
        'state_psc' => 'State PSC',
        _           => examSlug.toUpperCase(),
      };
}

// ── Provider ──────────────────────────────────────────────────────────────────

final extractionJobsProvider =
    StreamProvider.autoDispose<List<ExtractionJob>>((ref) {
  return ref
      .watch(supabaseClientProvider)
      .from('extraction_jobs')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) =>
          rows.map((e) => ExtractionJob.fromJson(e)).toList());
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
            const Icon(Icons.document_scanner_outlined,
                size: 48, color: AppPalette.grey300),
            const SizedBox(height: 12),
            Text(
              'Select a job to review',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppPalette.grey400),
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
      backgroundColor: AppPalette.white,
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
      backgroundColor: AppPalette.white,
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
        Container(
          color: AppPalette.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.indigo,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('New extraction'),
            onPressed: onNewJob,
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
      color: AppPalette.white,
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
                              ? AppPalette.indigo
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
                            ? AppPalette.indigo
                            : AppPalette.grey600,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const Divider(height: 1, color: AppPalette.grey200),
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
          _sectionLabel(active.length),
          ...active.map((j) => _JobCard(
                job: j,
                isSelected: j.id == selected?.id,
                onTap: () => onSelect(j),
              )),
        ],
        if (recent.isNotEmpty) ...[
          _recentLabel(),
          ...recent.map((j) => _JobCard(
                job: j,
                isSelected: j.id == selected?.id,
                onTap: () => onSelect(j),
              )),
        ],
      ],
    );
  }

  Widget _sectionLabel(int count) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
        child: Row(children: [
          const Text('ACTIVE',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppPalette.grey400)),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppPalette.indigoLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.indigo)),
          ),
        ]),
      );

  Widget _recentLabel() => const Padding(
        padding: EdgeInsets.fromLTRB(4, 10, 4, 6),
        child: Text('RECENT',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppPalette.grey400)),
      );
}

// ── Job card ──────────────────────────────────────────────────────────────────

class _JobCard extends StatelessWidget {
  final ExtractionJob job;
  final bool isSelected;
  final VoidCallback onTap;
  const _JobCard(
      {required this.job, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          color: isSelected ? AppPalette.indigoLight : AppPalette.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                isSelected ? AppPalette.indigo : AppPalette.grey200,
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
                      job.examLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: AppPalette.grey400, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: job.status),
            ]),
            if (job.pdfName != null) ...[
              const SizedBox(height: 4),
              Text(
                job.pdfName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.grey400, fontSize: 11),
              ),
            ],
            const SizedBox(height: 10),
            if (active && total > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: done / total,
                  minHeight: 4,
                  backgroundColor: AppPalette.grey100,
                  color: AppPalette.indigo,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Page $done / $total · $qs questions',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppPalette.grey600),
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
                        ?.copyWith(color: AppPalette.grey600)),
              ]),
            ] else
              _coverageLine(theme),
          ],
        ),
      ),
    );
  }

  Widget _coverageLine(ThemeData theme) {
    final cov =
        (job.report?['coverage'] as Map?)?.cast<String, dynamic>();
    if (cov == null) {
      if (job.status == 'failed') {
        return Text(job.error ?? 'Failed',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppPalette.red));
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
            ? AppPalette.amber
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
      'pending'      => ('Queued',  AppPalette.grey600,      AppPalette.grey100),
      'running'      => ('Running', AppPalette.indigo,       AppPalette.indigoLight),
      'needs_review' => ('Review',  AppPalette.amber,        AppPalette.amberLight),
      'completed'    => ('Done',    const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
      _              => ('Failed',  AppPalette.red,          const Color(0xFFFEE2E2)),
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
              ?.copyWith(color: AppPalette.grey400)),
    );
  }
}

// ── Paper / exam constants ────────────────────────────────────────────────────

const _kPapers = <String, (String, String)>{
  'GS I':   ('GS Paper I',   'gs1'),
  'GS II':  ('GS Paper II',  'gs2'),
  'GS III': ('GS Paper III', 'gs3'),
  'GS IV':  ('GS Paper IV',  'gs4'),
  'CSAT':   ('CSAT',         'csat'),
  'Essay':  ('Essay',        'essay'),
};

const _kExams = <String, String>{
  'UPSC CSE':  'upsc_cse',
  'SSC CGL':   'ssc_cgl',
  'IBPS PO':   'ibps_po',
  'State PSC': 'state_psc',
};

const _kSets = ['A', 'B', 'C', 'D'];

// ── New job sheet ─────────────────────────────────────────────────────────────

class _NewJobSheet extends ConsumerStatefulWidget {
  const _NewJobSheet();

  @override
  ConsumerState<_NewJobSheet> createState() => _NewJobSheetState();
}

class _NewJobSheetState extends ConsumerState<_NewJobSheet> {
  String _examKey = 'UPSC CSE';
  String _paperKey = 'GS I';
  String _set = 'A';
  final _year = TextEditingController(text: '');
  final _expected = TextEditingController(text: '100');
  final _startPage = TextEditingController(text: '3');
  final _pageStep = TextEditingController(text: '2');
  final _hindiOffset = TextEditingController(text: '-1');
  bool _hindi = true;
  bool _advExpanded = false;
  PlatformFile? _pdf;
  bool _isImage = false;
  bool _busy = false;
  String? _err;

  static const _imageExts = {'png', 'jpg', 'jpeg'};

  @override
  void dispose() {
    for (final c in [
      _year,
      _expected,
      _startPage,
      _pageStep,
      _hindiOffset
    ]) {
      c.dispose();
    }
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
          _hindi = false;
          _expected.text = '0';
        } else {
          _hindi = true;
          if (_expected.text == '0') _expected.text = '100';
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
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final sb = ref.read(supabaseClientProvider);
      final uid = sb.auth.currentUser?.id;
      final rand = Random().nextInt(1 << 32).toRadixString(16);
      final (paperName, paperSlug) = _kPapers[_paperKey]!;
      final examSlug = _kExams[_examKey]!;
      final path = '$year/${paperSlug}_${rand}_${_pdf!.name}';
      final contentType = _isImage
          ? 'image/${_pdf!.extension?.toLowerCase()}'
          : 'application/pdf';
      await sb.storage.from('pyq-uploads').uploadBinary(
            path,
            _pdf!.bytes!,
            fileOptions: FileOptions(contentType: contentType),
          );
      await sb.from('extraction_jobs').insert({
        'created_by':     uid,
        'exam_slug':      examSlug,
        'year':           year,
        'paper':          paperName,
        'paper_slug':     paperSlug,
        'paper_set':      _set,
        'pdf_path':       path,
        'pdf_name':       _pdf!.name,
        'want_hindi':     _hindi,
        'expected_count': int.tryParse(_expected.text.trim()) ?? 0,
        'start_page':     int.tryParse(_startPage.text.trim()) ?? 3,
        'page_step':      int.tryParse(_pageStep.text.trim()) ?? 2,
        'hindi_offset':   int.tryParse(_hindiOffset.text.trim()) ?? -1,
      });
      if (mounted) Navigator.pop(context);
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
                  color: AppPalette.grey200,
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
                  color: AppPalette.grey100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _pdf == null
                        ? AppPalette.grey200
                        : AppPalette.indigo,
                    width: _pdf == null ? 1 : 1.5,
                  ),
                ),
                child: Row(children: [
                  Icon(
                    _pdf == null
                        ? Icons.upload_file_outlined
                        : Icons.check_circle,
                    color: _pdf == null
                        ? AppPalette.grey400
                        : AppPalette.indigo,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pdf?.name ??
                              'Choose PDF or image (PNG / JPG)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (_pdf == null)
                          Text('PDF · PNG · JPG — max 50 MB',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppPalette.grey400)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // Exam chips
            _sectionLabel('Exam'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _kExams.keys
                  .map((k) => _Chip(
                        label: k,
                        selected: _examKey == k,
                        onTap: () => setState(() => _examKey = k),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 14),

            // Paper chips
            _sectionLabel('Paper'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _kPapers.keys
                  .map((k) => _Chip(
                        label: k,
                        selected: _paperKey == k,
                        onTap: () => setState(() => _paperKey = k),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 14),

            // Year + Set
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field('Year', _year,
                      hint: 'e.g. 2024', number: true),
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
                        children: _kSets
                            .map((s) => _Chip(
                                  label: s,
                                  selected: _set == s,
                                  onTap: () =>
                                      setState(() => _set = s),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Expected Qs + Hindi toggle
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _field('Expected Qs', _expected,
                        number: true)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('Hindi'),
                      const SizedBox(height: 6),
                      _PillToggle(
                        value: _hindi,
                        onChanged: _isImage
                            ? null
                            : (v) => setState(() => _hindi = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Advanced section
            GestureDetector(
              onTap: () =>
                  setState(() => _advExpanded = !_advExpanded),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppPalette.grey100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.tune,
                      size: 16, color: AppPalette.grey600),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Advanced layout',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppPalette.grey600)),
                  ),
                  Icon(
                    _advExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppPalette.grey400,
                  ),
                ]),
              ),
            ),
            if (_advExpanded) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _field('Start page', _startPage,
                        number: true)),
                const SizedBox(width: 10),
                Expanded(
                    child: _field('Page step', _pageStep,
                        number: true)),
                const SizedBox(width: 10),
                Expanded(
                    child: _field('Hindi offset', _hindiOffset,
                        number: true)),
              ]),
              const SizedBox(height: 6),
              Text(
                'UPSC bilingual papers: EN on odd pages (step 2 from page 3), HI at offset −1.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppPalette.grey400, fontSize: 11),
              ),
            ],

            if (_err != null) ...[
              const SizedBox(height: 12),
              Text(_err!,
                  style: const TextStyle(
                      color: AppPalette.red, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            Row(children: [
              const Spacer(),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.indigo),
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
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppPalette.grey400,
        ),
      );

  Widget _field(
    String label,
    TextEditingController c, {
    String? hint,
    bool number = false,
  }) =>
      TextField(
        controller: c,
        keyboardType:
            number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: AppPalette.grey100,
          contentPadding: const EdgeInsets.symmetric(
              vertical: 10, horizontal: 14),
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
          color: selected ? AppPalette.indigoLight : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppPalette.indigo : AppPalette.grey200,
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
                selected ? AppPalette.indigo : AppPalette.grey700,
          ),
        ),
      ),
    );
  }
}

// ── Pill toggle (On / Off) ────────────────────────────────────────────────────

class _PillToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _PillToggle({required this.value, required this.onChanged});

  Widget _seg(String label, bool active, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: active ? AppPalette.indigoLight : Colors.transparent,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AppPalette.indigo : AppPalette.grey600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onChanged == null ? 0.45 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppPalette.grey200),
          borderRadius: BorderRadius.circular(999),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _seg('Off', !value,
                  onChanged != null ? () => onChanged!(false) : null),
              _seg('On', value,
                  onChanged != null ? () => onChanged!(true) : null),
            ],
          ),
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
    final cov =
        (job.report?['coverage'] as Map?)?.cast<String, dynamic>();
    final missing = (cov?['missing'] as List?) ?? const [];
    final invalid =
        (job.report?['invalid'] as List?) ?? const [];
    final failed =
        (job.report?['failed_pages'] as List?) ?? const [];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
                color: AppPalette.grey200,
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
                  Text(job.examLabel,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppPalette.grey400)),
                ],
              ),
            ),
            _StatusChip(status: job.status),
          ]),
          const SizedBox(height: 4),
          SelectableText('Job ID: ${job.id}',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.grey400, fontSize: 11)),
          const SizedBox(height: 16),
          if (cov != null) ...[
            _statRow(() {
              final found = cov['found'];
              final exp =
                  (cov['expected_count'] as num?)?.toInt() ?? 0;
              return ('Extracted',
                  exp > 0 ? '$found / $exp' : '$found', null);
            }()),
            if (missing.isNotEmpty)
              _statRow(('Missing qnos', missing.join(', '),
                  AppPalette.amber)),
            if (invalid.isNotEmpty)
              _statRow(('Invalid (quarantined)',
                  '${invalid.length}', AppPalette.amber)),
            if (failed.isNotEmpty)
              _statRow(('Failed pages',
                  failed
                      .map((f) => (f as Map)['page'])
                      .join(', '),
                  AppPalette.red)),
          ] else if (job.status == 'failed') ...[
            Text(job.error ?? 'Failed',
                style:
                    const TextStyle(color: AppPalette.red)),
          ] else
            Text('Waiting for the worker to report…',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppPalette.grey600)),
          const SizedBox(height: 20),
          if (job.status == 'needs_review' ||
              job.status == 'completed')
            _PublishButton(job: job),
        ],
      ),
    );
  }

  Widget _statRow((String, String, Color?) t) {
    final (label, value, color) = t;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 140,
          child: Text(label,
              style: const TextStyle(
                  color: AppPalette.grey600, fontSize: 13)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color ?? AppPalette.grey900,
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
