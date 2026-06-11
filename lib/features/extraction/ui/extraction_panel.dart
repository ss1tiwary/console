import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/di/providers.dart';
import '../../../core/palette.dart';
import '../../../core/spacing.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class ExtractionJob {
  final String id;
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
    required this.year,
    required this.paper,
    required this.paperSlug,
    required this.paperSet,
    required this.pdfName,
    required this.status,
    required this.progress,
    required this.report,
    required this.error,
    required this.createdAt,
  });

  factory ExtractionJob.fromJson(Map<String, dynamic> j) =>
      ExtractionJob(
        id: j['id'] as String,
        year: (j['year'] as num).toInt(),
        paper: j['paper'] as String? ?? 'GS Paper I',
        paperSlug: j['paper_slug'] as String? ?? 'gs1',
        paperSet: j['paper_set'] as String? ?? 'A',
        pdfName: j['pdf_name'] as String?,
        status: j['status'] as String? ?? 'pending',
        progress:
            (j['progress'] as Map?)?.cast<String, dynamic>() ??
                const {},
        report:
            (j['report'] as Map?)?.cast<String, dynamic>(),
        error: j['error'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
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

// ── Panel ─────────────────────────────────────────────────────────────────────

class ExtractionPanel extends ConsumerWidget {
  const ExtractionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final jobsAsync = ref.watch(extractionJobsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          color: AppPalette.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Text('PYQ Extraction',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.indigo),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('New paper'),
                onPressed: () => _showNewJobSheet(context, ref),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppPalette.grey200),
        // Body
        Expanded(
          child: jobsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (jobs) => jobs.isEmpty
                ? Center(
                    child: Text(
                      'No extraction jobs yet.\nTap "New paper" to start.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppPalette.grey400),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        12,
                        AppSpacing.pagePadding,
                        32),
                    itemCount: jobs.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) => _JobCard(
                      job: jobs[i],
                      onTap: () =>
                          _showJobDetail(context, ref, jobs[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _showNewJobSheet(BuildContext context, WidgetRef ref) {
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

  void _showJobDetail(
      BuildContext context, WidgetRef ref, ExtractionJob job) {
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
}

// ── Job card ──────────────────────────────────────────────────────────────────

class _JobCard extends StatelessWidget {
  final ExtractionJob job;
  final VoidCallback onTap;
  const _JobCard({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total =
        (job.progress['pages_total'] as num?)?.toInt() ?? 0;
    final done =
        (job.progress['pages_done'] as num?)?.toInt() ?? 0;
    final qs =
        (job.progress['questions_extracted'] as num?)?.toInt() ?? 0;
    final running =
        job.status == 'running' || job.status == 'pending';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppPalette.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.grey200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  '${job.year} · ${job.paper} · Set ${job.paperSet}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _StatusChip(status: job.status),
            ]),
            if (job.pdfName != null) ...[
              const SizedBox(height: 3),
              Text(
                job.pdfName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.grey400, fontSize: 11),
              ),
            ],
            const SizedBox(height: 10),
            if (running && total > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? null : done / total,
                  minHeight: 6,
                  backgroundColor: AppPalette.grey100,
                  color: AppPalette.indigo,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Page $done / $total · $qs questions so far',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppPalette.grey600),
              ),
            ] else if (running) ...[
              Row(children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Queued — waiting for the worker…',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppPalette.grey600),
                ),
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
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppPalette.red));
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
      'pending' => ('Queued', AppPalette.grey600, AppPalette.grey100),
      'running' =>
        ('Running', AppPalette.indigo, AppPalette.indigoLight),
      'needs_review' =>
        ('Needs review', AppPalette.amber, AppPalette.amberLight),
      'completed' =>
        ('Complete', const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
      _ => ('Failed', AppPalette.red, const Color(0xFFFEE2E2)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}

// ── New job sheet ─────────────────────────────────────────────────────────────

class _NewJobSheet extends ConsumerStatefulWidget {
  const _NewJobSheet();
  @override
  ConsumerState<_NewJobSheet> createState() => _NewJobSheetState();
}

class _NewJobSheetState extends ConsumerState<_NewJobSheet> {
  final _year = TextEditingController(text: '');
  final _paper = TextEditingController(text: 'GS Paper I');
  final _slug = TextEditingController(text: 'gs1');
  final _set = TextEditingController(text: 'A');
  final _expected = TextEditingController(text: '100');
  bool _hindi = true;

  PlatformFile? _pdf;
  bool _isImage = false;
  bool _busy = false;
  String? _err;

  static const _imageExtensions = {'png', 'jpg', 'jpeg'};

  @override
  void dispose() {
    for (final c in [_year, _paper, _slug, _set, _expected]) {
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
      final isImage = _imageExtensions.contains(ext);
      setState(() {
        _pdf = file;
        _isImage = isImage;
        if (isImage) {
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
      final path =
          '$year/${_slug.text.trim()}_${rand}_${_pdf!.name}';
      final contentType = _isImage
          ? 'image/${_pdf!.extension?.toLowerCase()}'
          : 'application/pdf';
      await sb.storage.from('pyq-uploads').uploadBinary(
            path,
            _pdf!.bytes!,
            fileOptions: FileOptions(contentType: contentType),
          );
      await sb.from('extraction_jobs').insert({
        'created_by': uid,
        'year': year,
        'paper': _paper.text.trim(),
        'paper_slug': _slug.text.trim(),
        'paper_set': _set.text.trim(),
        'pdf_path': path,
        'pdf_name': _pdf!.name,
        'want_hindi': _hindi,
        'expected_count':
            int.tryParse(_expected.text.trim()) ?? 0,
        if (_isImage) 'start_page': 1,
        if (_isImage) 'page_step': 1,
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
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _pdf?.name ??
                        'Choose PDF or image (PNG / JPG)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _field('Year', _year,
                    hint: 'e.g. 2025', number: true)),
            const SizedBox(width: 12),
            Expanded(child: _field('Set', _set)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 2, child: _field('Paper', _paper)),
            const SizedBox(width: 12),
            Expanded(child: _field('Slug', _slug, hint: 'gs1')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _field('Expected Qs', _expected,
                    number: true)),
            const SizedBox(width: 12),
            Expanded(
              child: Row(children: [
                Switch(
                  value: _hindi,
                  activeThumbColor: AppPalette.indigo,
                  onChanged: (v) => setState(() => _hindi = v),
                ),
                const Text('Hindi'),
              ]),
            ),
          ]),
          if (_err != null) ...[
            const SizedBox(height: 12),
            Text(_err!,
                style: TextStyle(
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
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.indigo),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white))
                  : const Text('Upload & queue'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
          {String? hint, bool number = false}) =>
      TextField(
        controller: c,
        keyboardType:
            number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: AppPalette.grey100,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      );
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
    final invalid = (job.report?['invalid'] as List?) ?? const [];
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
              child: Text(
                '${job.year} · ${job.paper} · Set ${job.paperSet}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            _StatusChip(status: job.status),
          ]),
          const SizedBox(height: 4),
          SelectableText('Job id: ${job.id}',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.grey400, fontSize: 11)),
          const SizedBox(height: 16),
          if (cov != null) ...[
            _statRow('Extracted', () {
              final found = cov['found'];
              final exp =
                  (cov['expected_count'] as num?)?.toInt() ?? 0;
              return exp > 0 ? '$found / $exp' : '$found';
            }()),
            if (missing.isNotEmpty)
              _statRow('Missing qnos', missing.join(', '),
                  color: AppPalette.amber),
            if (invalid.isNotEmpty)
              _statRow('Invalid (quarantined)',
                  '${invalid.length}',
                  color: AppPalette.amber),
            if (failed.isNotEmpty)
              _statRow(
                  'Failed pages',
                  failed
                      .map((f) => (f as Map)['page'])
                      .join(', '),
                  color: AppPalette.red),
          ] else if (job.status == 'failed') ...[
            Text(job.error ?? 'Failed',
                style: TextStyle(color: AppPalette.red)),
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

  Widget _statRow(String label, String value, {Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
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
          ],
        ),
      );
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
