import 'package:flutter/material.dart';
import 'package:resolve_theme/resolve_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qbank_ui/qbank_ui.dart';

import '../../../core/config_options.dart';
import '../../../core/di/providers.dart';
import '../../../core/spacing.dart';
import 'extraction_panel.dart' show ExtractionJob, examNamesProvider;

// ── Model ─────────────────────────────────────────────────────────────────────

class ReviewQuestion {
  final String id;
  final int? originalQno;
  final dynamic blocks;
  final dynamic options;
  final String? correctOption;
  final String? subject;
  final Map<String, dynamic>? translations;
  final Map<String, dynamic>? generationMeta;
  final bool flagged;
  final String? flagNote;

  const ReviewQuestion({
    required this.id,
    this.originalQno,
    this.blocks,
    this.options,
    this.correctOption,
    this.subject,
    this.translations,
    this.generationMeta,
    required this.flagged,
    this.flagNote,
  });

  factory ReviewQuestion.fromJson(Map<String, dynamic> j) {
    final meta = (j['generation_meta'] as Map?)?.cast<String, dynamic>();
    return ReviewQuestion(
      id: j['id'] as String,
      originalQno: (j['original_qno'] as num?)?.toInt(),
      blocks: j['blocks'],
      options: j['options'],
      correctOption: j['correct_option'] as String?,
      subject: j['subject'] as String?,
      translations: (j['translations'] as Map?)?.cast<String, dynamic>(),
      generationMeta: meta,
      flagged: meta?['flagged'] == true,
      flagNote: meta?['flag_note'] as String?,
    );
  }

  ReviewQuestion copyWith({
    int? originalQno,
    String? correctOption,
    String? subject,
    bool? flagged,
    String? flagNote,
    Map<String, dynamic>? generationMeta,
  }) =>
      ReviewQuestion(
        id: id,
        originalQno: originalQno ?? this.originalQno,
        blocks: blocks,
        options: options,
        correctOption: correctOption ?? this.correctOption,
        subject: subject ?? this.subject,
        translations: translations,
        generationMeta: generationMeta ?? this.generationMeta,
        flagged: flagged ?? this.flagged,
        flagNote: flagNote ?? this.flagNote,
      );
}

// Config dropdown values come from the shared `config_options` table via
// configOptionsProvider (see core/config_options.dart).

// ── Provider ──────────────────────────────────────────────────────────────────

final draftQuestionsProvider = FutureProvider.autoDispose
    .family<List<ReviewQuestion>, (int, String)>((ref, key) async {
  final (year, paper) = key;
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('questions')
      .select(
          'id, original_qno, blocks, options, correct_option, subject, translations, generation_meta, status')
      .eq('year', year)
      .eq('paper', paper)
      .eq('status', 'draft')
      .order('original_qno');
  return (rows as List)
      .map((r) => ReviewQuestion.fromJson((r as Map).cast<String, dynamic>()))
      .toList();
});

// ── Panel ─────────────────────────────────────────────────────────────────────

enum _Lang { both, en, hi }

class ExtractionReviewPanel extends ConsumerStatefulWidget {
  final ExtractionJob job;
  final VoidCallback? onBack;
  final VoidCallback? onShowStats;
  const ExtractionReviewPanel(
      {super.key, required this.job, this.onBack, this.onShowStats});

  @override
  ConsumerState<ExtractionReviewPanel> createState() =>
      _ExtractionReviewPanelState();
}

class _ExtractionReviewPanelState extends ConsumerState<ExtractionReviewPanel> {
  _Lang _lang = _Lang.both;

  /// Local working copy. The provider is the source of truth on (re)load, but
  /// once seeded we mutate this list optimistically so actions feel instant and
  /// don't trigger a full re-fetch + list rebuild on every tap.
  List<ReviewQuestion>? _items;

  (int, String) get _key => (widget.job.year, widget.job.paper);

  void _refresh() {
    setState(() => _items = null);
    ref.invalidate(draftQuestionsProvider(_key));
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? context.pal.red : context.pal.grey900,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    // Seed / re-seed the local list whenever the provider emits fresh data.
    ref.listen(draftQuestionsProvider(_key), (_, next) {
      next.whenData((data) {
        if (mounted) setState(() => _items = List.of(data));
      });
    });
    final async = ref.watch(draftQuestionsProvider(_key));
    final items = _items;
    // DB-driven subject list (migration 013); built-in default until it loads.
    final subjects = ref.watch(configOptionsProvider('question_subject')).valueOrNull ??
        defaultConfigOptions['question_subject']!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          job: widget.job,
          lang: _lang,
          count: items?.length,
          flaggedCount: items?.where((q) => q.flagged).length ?? 0,
          onLangChanged: (l) => setState(() => _lang = l),
          onRefresh: _refresh,
          onBack: widget.onBack,
          onShowStats: widget.onShowStats,
        ),
        Divider(height: 1, color: context.pal.grey200),
        Expanded(
          child: items == null
              ? async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (_) =>
                      const Center(child: CircularProgressIndicator()),
                )
              : items.isEmpty
                  ? _EmptyState(status: widget.job.status)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.pagePadding, 16, AppSpacing.pagePadding, 32),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 16),
                      itemBuilder: (_, i) => _QuestionCard(
                        key: ValueKey(items[i].id),
                        question: items[i],
                        job: widget.job,
                        lang: _lang,
                        subjects: subjects,
                        onApprove: () => _approve(items[i]),
                        onFlag: (note) => _flag(items[i], note),
                        onDiscard: () => _discard(items[i]),
                        onSubject: (s) => _setSubject(items[i], s),
                        onAnswer: (a) => _setAnswer(items[i], a),
                        onQno: (n) => _setQno(items[i], n),
                      ),
                    ),
        ),
      ],
    );
  }

  Future<void> _approve(ReviewQuestion q) async {
    setState(() => _items!.removeWhere((x) => x.id == q.id));
    try {
      final uid = ref.read(supabaseClientProvider).auth.currentUser?.id;
      await ref.read(supabaseClientProvider).from('questions').update({
        'status': 'published',
        'verified': true,
        'reviewed_by': uid,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', q.id);
      _snack('Approved Q${q.originalQno ?? ''} — published');
    } catch (e) {
      _snack('Approve failed: $e', error: true);
      _refresh();
    }
  }

  Future<void> _flag(ReviewQuestion q, String note) async {
    final meta = Map<String, dynamic>.from(q.generationMeta ?? {});
    meta['flagged'] = true;
    if (note.isNotEmpty) {
      meta['flag_note'] = note;
    } else {
      meta.remove('flag_note');
    }
    // Optimistic in-place update — card stays, banner appears immediately.
    setState(() {
      final i = _items!.indexWhere((x) => x.id == q.id);
      if (i >= 0) {
        _items![i] = q.copyWith(
            flagged: true,
            flagNote: note.isEmpty ? null : note,
            generationMeta: meta);
      }
    });
    try {
      await ref
          .read(supabaseClientProvider)
          .from('questions')
          .update({'generation_meta': meta}).eq('id', q.id);
      _snack('Flag saved');
    } catch (e) {
      _snack('Flag failed: $e', error: true);
      _refresh();
    }
  }

  Future<void> _discard(ReviewQuestion q) async {
    setState(() => _items!.removeWhere((x) => x.id == q.id));
    try {
      await ref
          .read(supabaseClientProvider)
          .from('questions')
          .delete()
          .eq('id', q.id)
          .eq('status', 'draft');
      _snack('Discarded Q${q.originalQno ?? ''}');
    } catch (e) {
      _snack('Discard failed: $e', error: true);
      _refresh();
    }
  }

  // ── Inline field overrides (subject / answer / qno) ─────────────────────────
  // Each preserves the AI's original value in generation_meta the first time it's
  // changed, so `*_extracted ≠ final` is a queryable extraction-error signal for
  // prompt refinement. The card stays put (unlike approve/discard).

  void _replaceItem(ReviewQuestion q) {
    final i = _items!.indexWhere((x) => x.id == q.id);
    if (i >= 0) _items![i] = q;
  }

  Future<void> _override(
      ReviewQuestion q, String column, String extractedKey, Object? extractedVal,
      Object? newVal, ReviewQuestion updated) async {
    final meta = Map<String, dynamic>.from(q.generationMeta ?? {});
    meta.putIfAbsent(extractedKey, () => extractedVal);
    setState(() => _replaceItem(updated.copyWith(generationMeta: meta)));
    try {
      await ref.read(supabaseClientProvider).from('questions').update(
          {column: newVal, 'generation_meta': meta}).eq('id', q.id);
    } catch (e) {
      _snack('Save failed: $e', error: true);
      _refresh();
    }
  }

  Future<void> _setSubject(ReviewQuestion q, String subject) => _override(
      q, 'subject', 'subject_extracted', q.subject, subject,
      q.copyWith(subject: subject));

  Future<void> _setAnswer(ReviewQuestion q, String opt) => _override(
      q, 'correct_option', 'correct_option_extracted', q.correctOption, opt,
      q.copyWith(correctOption: opt));

  Future<void> _setQno(ReviewQuestion q, int qno) => _override(
      q, 'original_qno', 'original_qno_extracted', q.originalQno, qno,
      q.copyWith(originalQno: qno));
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  final ExtractionJob job;
  final _Lang lang;
  final int? count;
  final int flaggedCount;
  final ValueChanged<_Lang> onLangChanged;
  final VoidCallback onRefresh;
  final VoidCallback? onBack;
  final VoidCallback? onShowStats;
  const _Header({
    required this.job,
    required this.lang,
    required this.count,
    required this.flaggedCount,
    required this.onLangChanged,
    required this.onRefresh,
    this.onBack,
    this.onShowStats,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final examNames = ref.watch(examNamesProvider).valueOrNull ?? const {};
    final exam = examNames[job.examSlug] ?? job.examLabel;
    // Build the title from only the parts that are actually set — an unset
    // draft has year 0 / empty paper / empty set, which would otherwise render
    // as a scattered "0 ·  · Set " skeleton with the count pills floating.
    final titleParts = <String>[
      if (job.year > 0) '${job.year}',
      if (job.paper.trim().isNotEmpty) job.paper,
      if (job.paperSet.trim().isNotEmpty) 'Set ${job.paperSet}',
    ];
    final titleStr = titleParts.isEmpty ? exam : titleParts.join(' · ');
    final showExamSubtitle = titleParts.isNotEmpty;
    // Two tiers: 7 controls can't share one ~360px row (squeezes the title to
    // nothing). Tier 1 = identity + occasional actions; tier 2 = status chips +
    // language toggle. Title gets full width on tier 1; chips align with the
    // toggle on tier 2.
    return Container(
      color: context.pal.white,
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Tier 1: back · title/exam · stats · refresh ───────────────────
          Row(
            children: [
              if (onBack != null)
                IconButton(
                  icon:
                      const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  tooltip: 'Back',
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                )
              else
                const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleStr,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showExamSubtitle)
                      Text(
                        exam,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: context.pal.grey400),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (onShowStats != null)
                IconButton(
                  icon: const Icon(Icons.analytics_outlined, size: 20),
                  tooltip: 'Job stats & publish',
                  onPressed: onShowStats,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 36),
                ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh questions',
                onPressed: onRefresh,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 40, minHeight: 36),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ── Tier 2: status chips ······ language toggle ──────────────────
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                if (count != null) ...[
                  _CountPill(label: '$count draft${count == 1 ? '' : 's'}'),
                  const SizedBox(width: 6),
                ],
                if (flaggedCount > 0)
                  _CountPill(
                    label: '$flaggedCount flagged',
                    color: context.pal.amber,
                    bg: context.pal.amberLight,
                  ),
                const Spacer(),
                _LangPill(lang: lang, onChanged: onLangChanged),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? bg;
  const _CountPill({
    required this.label,
    this.color,
    this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: bg ?? context.pal.grey100,
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color ?? context.pal.grey600)),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String status;
  const _EmptyState({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDone = status == 'completed' || status == 'needs_review';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            allDone
                ? Icons.check_circle_outline
                : Icons.hourglass_empty_outlined,
            size: 48,
            color: context.pal.grey300,
          ),
          const SizedBox(height: 12),
          Text(
            allDone ? 'All drafts reviewed.' : 'No draft questions yet.',
            style:
                theme.textTheme.bodyMedium?.copyWith(color: context.pal.grey600),
          ),
          const SizedBox(height: 4),
          Text(
            allDone
                ? 'Nothing left to approve or discard.'
                : 'Extraction may still be in progress.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: context.pal.grey400),
          ),
        ],
      ),
    );
  }
}

// ── Question card ─────────────────────────────────────────────────────────────

class _QuestionCard extends StatelessWidget {
  final ReviewQuestion question;
  final ExtractionJob job;
  final _Lang lang;
  final List<String> subjects;
  final VoidCallback onApprove;
  final ValueChanged<String> onFlag;
  final VoidCallback onDiscard;
  final ValueChanged<String> onSubject;
  final ValueChanged<String> onAnswer;
  final ValueChanged<int> onQno;

  const _QuestionCard({
    super.key,
    required this.question,
    required this.job,
    required this.lang,
    required this.subjects,
    required this.onApprove,
    required this.onFlag,
    required this.onDiscard,
    required this.onSubject,
    required this.onAnswer,
    required this.onQno,
  });

  // Small context chip (Q / Set / year / paper / subject), mirroring PIBrief's
  // question-card chips so reviewers see the same metadata at a glance.
  Widget _ctxChip(BuildContext context, ThemeData theme, String label,
      {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent ? context.pal.indigoLight : context.pal.grey100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: accent ? context.pal.indigo : context.pal.grey600)),
    );
  }

  // ── Override box: correct subject / answer / qno before approving ──────────
  Widget _overrideBox(BuildContext context, ThemeData theme) {
    final q = question;
    final extractedSubj = q.generationMeta?['subject_extracted'] as String?;
    final subjEdited = extractedSubj != null && extractedSubj != q.subject;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.pal.grey50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.pal.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('REVIEW · CORRECT BEFORE APPROVE',
              style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: context.pal.amber)),
          const SizedBox(height: 10),
          _overrideRow(
            context,
            theme,
            'Subject',
            aiHint: subjEdited ? 'AI: $extractedSubj' : null,
            child: InkWell(
              onTap: () => _pickSubject(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: subjEdited
                      ? context.pal.amberLight
                      : context.pal.white,
                  border: Border.all(
                      color: subjEdited
                          ? context.pal.amber
                          : context.pal.grey300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    (q.subject?.trim().isNotEmpty ?? false)
                        ? q.subject!
                        : 'Set subject',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: (q.subject?.trim().isNotEmpty ?? false)
                            ? context.pal.grey900
                            : context.pal.grey400),
                  ),
                  Icon(Icons.arrow_drop_down,
                      size: 18, color: context.pal.grey600),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _overrideRow(
            context,
            theme,
            'Answer',
            child: _AnswerSelector(
                selected: q.correctOption, onSelect: onAnswer),
          ),
          const SizedBox(height: 8),
          _overrideRow(
            context,
            theme,
            'Question no.',
            child: InkWell(
              onTap: () => _editQno(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: context.pal.white,
                  border: Border.all(color: context.pal.grey300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(q.originalQno?.toString() ?? '—',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overrideRow(BuildContext context, ThemeData theme, String label,
      {String? aiHint, required Widget child}) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: context.pal.grey700)),
        ),
        if (aiHint != null) ...[
          Text(aiHint,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: context.pal.grey400)),
          const SizedBox(width: 8),
        ],
        child,
      ],
    );
  }

  void _pickSubject(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Subject',
                  style: Theme.of(sheet)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            for (final s in subjects)
              ListTile(
                title: Text(s),
                trailing: s == question.subject
                    ? Icon(Icons.check, color: context.pal.indigo)
                    : null,
                onTap: () {
                  if (s != question.subject) onSubject(s);
                  Navigator.of(sheet).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editQno(BuildContext context) async {
    final ctrl =
        TextEditingController(text: question.originalQno?.toString() ?? '');
    final res = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Question number'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'e.g. 11'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text.trim());
              Navigator.pop(d, n);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (res != null && res != question.originalQno) onQno(res);
  }

  // Renders one language's block document + options, or an empty-state line.
  List<Widget> _section(BuildContext context, ThemeData theme,
      QuestionDocument? d, String? correctOption, String emptyMsg) {
    if (d == null) {
      return [
        Text(emptyMsg,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: context.pal.grey400)),
      ];
    }
    return [
      QuestionDocumentView(d.blocks),
      const SizedBox(height: 12),
      _OptionsPreview(doc: d, correctOption: correctOption),
    ];
  }

  // "हिंदी" label + rule separating the stacked English and Hindi views.
  Widget _hindiLabel(BuildContext context, ThemeData theme) => Row(
        children: [
          Text('हिंदी',
              style: theme.textTheme.labelSmall?.copyWith(
                  color: context.pal.grey600,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: context.pal.grey200, height: 1)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = question;
    final doc = QuestionDocument.tryFromRow(q.blocks, q.options);
    final hiData = (q.translations?['hi'] as Map?)?.cast<String, dynamic>();
    // Hindi is stored as the SAME {blocks, options} block-document as English
    // (see prompts_extract.py) — so render it through the shared renderer too,
    // not a flat stem/statements view (which only ever found `options`).
    final hiDoc = hiData == null
        ? null
        : QuestionDocument.tryFromRow(hiData['blocks'], hiData['options']);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.pal.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: q.flagged ? context.pal.amber : context.pal.grey200,
          width: q.flagged ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Flag banner — full-width strip at top, the proper home for the note.
          if (q.flagged)
            _FlagBanner(
              note: q.flagNote,
              onEdit: () => _showFlagDialog(context),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Read-only identity chips (subject + answer now live in the
                // editable override box below).
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (q.originalQno != null)
                      _ctxChip(context, theme, 'Q ${q.originalQno}',
                          accent: true),
                    if (job.paperSet.trim().isNotEmpty)
                      _ctxChip(context, theme, 'Set ${job.paperSet}'),
                    if (job.year > 0)
                      _ctxChip(context, theme, 'PYQ ${job.year}'),
                    if (job.paper.trim().isNotEmpty)
                      _ctxChip(context, theme, job.paper),
                  ],
                ),
                const SizedBox(height: 12),
                _overrideBox(context, theme),
                const SizedBox(height: 14),
                // ── EN + HI stacked (default), or one focused via the toggle ──
                // English shown for Both and EN.
                if (lang != _Lang.hi)
                  ..._section(context, theme, doc, q.correctOption,
                      'No block document — legacy row.'),
                // Hindi divider, only in Both when a Hindi doc exists.
                if (lang == _Lang.both && hiDoc != null) ...[
                  const SizedBox(height: 18),
                  _hindiLabel(context, theme),
                  const SizedBox(height: 12),
                ],
                // Hindi shown for Both (if present) and HI.
                if (lang == _Lang.hi ||
                    (lang == _Lang.both && hiDoc != null))
                  ..._section(context, theme, hiDoc, q.correctOption,
                      'No Hindi translation captured for this question.'),
                const SizedBox(height: 16),
                Divider(height: 1, color: context.pal.grey100),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: context.pal.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Approve'),
                        onPressed: onApprove,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            q.flagged ? context.pal.amber : context.pal.grey700,
                        side: BorderSide(
                            color: q.flagged
                                ? context.pal.amber
                                : context.pal.grey300),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      icon: Icon(
                          q.flagged ? Icons.flag : Icons.flag_outlined,
                          size: 16),
                      label: Text(q.flagged ? 'Edit flag' : 'Flag'),
                      onPressed: () => _showFlagDialog(context),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: context.pal.red,
                      tooltip: 'Discard draft',
                      style: IconButton.styleFrom(
                        side: BorderSide(color: context.pal.grey300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.all(10),
                      ),
                      onPressed: () => _showDiscardDialog(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFlagDialog(BuildContext context) {
    final ctrl = TextEditingController(text: question.flagNote ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(question.flagged ? 'Edit flag note' : 'Flag question'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saved to the question for later correction. The draft stays in '
              'the list — flagging does not remove it.',
              style: Theme.of(ctx)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: context.pal.grey600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Note',
                hintText: 'e.g. OCR error in statement 2',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          if (question.flagged)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                onFlag(''); // clears note but keeps flagged; see _flag
              },
              child: const Text('Clear note'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.pal.amber),
            onPressed: () {
              final note = ctrl.text.trim();
              Navigator.pop(ctx);
              onFlag(note);
            },
            child: const Text('Save flag'),
          ),
        ],
      ),
    );
  }

  void _showDiscardDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard draft?'),
        content: const Text(
          'This permanently deletes the draft. '
          'Only discard duplicates or irrecoverable extraction errors.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.pal.red),
            onPressed: () {
              Navigator.pop(ctx);
              onDiscard();
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}

// ── Flag banner ───────────────────────────────────────────────────────────────

class _FlagBanner extends StatelessWidget {
  final String? note;
  final VoidCallback onEdit;
  const _FlagBanner({required this.note, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasNote = note != null && note!.isNotEmpty;
    return Material(
      color: context.pal.amberLight,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.flag, size: 16, color: context.pal.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Flagged for correction',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: context.pal.amber,
                            fontWeight: FontWeight.w700)),
                    if (hasNote) ...[
                      const SizedBox(height: 2),
                      Text(note!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: context.pal.grey800)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.edit_outlined,
                  size: 15, color: context.pal.amber.withValues(alpha: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Answer selector (a/b/c/d) for the override box ───────────────────────────

class _AnswerSelector extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const _AnswerSelector({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const keys = ['a', 'b', 'c', 'd'];
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.pal.grey300),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final k in keys)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(k),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                color:
                    selected == k ? context.pal.indigo : context.pal.white,
                child: Text(k,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected == k
                            ? context.pal.white
                            : context.pal.grey600)),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Options preview (answer revealed, non-interactive) ───────────────────────

class _OptionsPreview extends StatelessWidget {
  final QuestionDocument doc;
  final String? correctOption;
  const _OptionsPreview({required this.doc, required this.correctOption});

  @override
  Widget build(BuildContext context) {
    bool isCorrect(String k) => k == correctOption;
    switch (doc.options.style) {
      case OptionsStyle.codeGrid:
        return CodeGridOptions(
          columns: doc.options.columns,
          options: doc.options.options,
          selectedOption: null,
          revealed: correctOption != null,
          isCorrect: isCorrect,
          onSelect: null,
        );
      case OptionsStyle.pairs:
        return PairOptions(
          columns: doc.options.columns,
          options: doc.options.options,
          selectedOption: null,
          revealed: correctOption != null,
          isCorrect: isCorrect,
          onSelect: null,
        );
      case OptionsStyle.list:
        return DocOptionList(
          options: doc.options.options,
          selectedOption: null,
          revealed: correctOption != null,
          isCorrect: isCorrect,
          onSelect: null,
        );
    }
  }
}

// ── Language pill (PIBrief-style EN / हिं) ────────────────────────────────────

class _LangPill extends StatelessWidget {
  final _Lang lang;
  final ValueChanged<_Lang> onChanged;
  const _LangPill({required this.lang, required this.onChanged});

  Widget _seg(BuildContext context, _Lang l, String label) {
    final active = lang == l;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(l),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        color: active ? context.pal.indigoLight : Colors.transparent,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? context.pal.indigo : context.pal.grey600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.pal.grey200),
        borderRadius: BorderRadius.circular(999),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _seg(context, _Lang.both, 'Both'),
            _seg(context, _Lang.en, 'EN'),
            _seg(context, _Lang.hi, 'हिं'),
          ],
        ),
      ),
    );
  }
}
