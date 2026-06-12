import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qbank_ui/qbank_ui.dart';

import '../../../core/di/providers.dart';
import '../../../core/palette.dart';
import '../../../core/spacing.dart';
import 'extraction_panel.dart' show ExtractionJob;

// ── Model ─────────────────────────────────────────────────────────────────────

class ReviewQuestion {
  final String id;
  final int? originalQno;
  final dynamic blocks;
  final dynamic options;
  final String? correctOption;
  final Map<String, dynamic>? translations;
  final Map<String, dynamic>? generationMeta;
  final bool flagged;

  const ReviewQuestion({
    required this.id,
    this.originalQno,
    this.blocks,
    this.options,
    this.correctOption,
    this.translations,
    this.generationMeta,
    required this.flagged,
  });

  factory ReviewQuestion.fromJson(Map<String, dynamic> j) {
    final meta = (j['generation_meta'] as Map?)?.cast<String, dynamic>();
    return ReviewQuestion(
      id: j['id'] as String,
      originalQno: (j['original_qno'] as num?)?.toInt(),
      blocks: j['blocks'],
      options: j['options'],
      correctOption: j['correct_option'] as String?,
      translations: (j['translations'] as Map?)?.cast<String, dynamic>(),
      generationMeta: meta,
      flagged: meta?['flagged'] == true,
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final draftQuestionsProvider = FutureProvider.autoDispose
    .family<List<ReviewQuestion>, (int, String)>((ref, key) async {
  final (year, paper) = key;
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('questions')
      .select(
          'id, original_qno, blocks, options, correct_option, translations, generation_meta, status')
      .eq('year', year)
      .eq('paper', paper)
      .eq('status', 'draft')
      .order('original_qno');
  return (rows as List)
      .map((r) => ReviewQuestion.fromJson((r as Map).cast<String, dynamic>()))
      .toList();
});

// ── Panel ─────────────────────────────────────────────────────────────────────

enum _Lang { en, hi }

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

class _ExtractionReviewPanelState
    extends ConsumerState<ExtractionReviewPanel> {
  _Lang _lang = _Lang.en;

  (int, String) get _key => (widget.job.year, widget.job.paper);

  void _refresh() => ref.invalidate(draftQuestionsProvider(_key));

  @override
  Widget build(BuildContext context) {
    final qs = ref.watch(draftQuestionsProvider(_key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          job: widget.job,
          lang: _lang,
          onLangChanged: (l) => setState(() => _lang = l),
          onRefresh: _refresh,
          onBack: widget.onBack,
          onShowStats: widget.onShowStats,
        ),
        const Divider(height: 1, color: AppPalette.grey200),
        Expanded(
          child: qs.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (questions) => questions.isEmpty
                ? _EmptyState(status: widget.job.status)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        16,
                        AppSpacing.pagePadding,
                        32),
                    itemCount: questions.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 16),
                    itemBuilder: (_, i) => _QuestionCard(
                      question: questions[i],
                      lang: _lang,
                      onApprove: (q) => _approve(q),
                      onFlag: (q, note) => _flag(q, note),
                      onDiscard: (q) => _discard(q),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _approve(ReviewQuestion q) async {
    final uid =
        ref.read(supabaseClientProvider).auth.currentUser?.id;
    await ref
        .read(supabaseClientProvider)
        .from('questions')
        .update({
          'status': 'published',
          'verified': true,
          'reviewed_by': uid,
          'reviewed_at':
              DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', q.id);
    _refresh();
  }

  Future<void> _flag(ReviewQuestion q, String note) async {
    final meta =
        Map<String, dynamic>.from(q.generationMeta ?? {});
    meta['flagged'] = true;
    if (note.isNotEmpty) meta['flag_note'] = note;
    await ref
        .read(supabaseClientProvider)
        .from('questions')
        .update({'generation_meta': meta})
        .eq('id', q.id);
    _refresh();
  }

  Future<void> _discard(ReviewQuestion q) async {
    // Double-guard: only delete drafts, never published rows.
    await ref
        .read(supabaseClientProvider)
        .from('questions')
        .delete()
        .eq('id', q.id)
        .eq('status', 'draft');
    _refresh();
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final ExtractionJob job;
  final _Lang lang;
  final ValueChanged<_Lang> onLangChanged;
  final VoidCallback onRefresh;
  final VoidCallback? onBack;
  final VoidCallback? onShowStats;
  const _Header({
    required this.job,
    required this.lang,
    required this.onLangChanged,
    required this.onRefresh,
    this.onBack,
    this.onShowStats,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: AppPalette.white,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18),
              tooltip: 'Back',
              onPressed: onBack,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                  left: onBack != null ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${job.year} · ${job.paper} · Set ${job.paperSet}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    job.examLabel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppPalette.grey400),
                  ),
                ],
              ),
            ),
          ),
          _LangPill(lang: lang, onChanged: onLangChanged),
          if (onShowStats != null)
            IconButton(
              icon: const Icon(Icons.analytics_outlined, size: 20),
              tooltip: 'Job stats & publish',
              onPressed: onShowStats,
            ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh questions',
            onPressed: onRefresh,
          ),
        ],
      ),
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
            color: AppPalette.grey300,
          ),
          const SizedBox(height: 12),
          Text(
            allDone
                ? 'All drafts reviewed.'
                : 'No draft questions yet.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppPalette.grey600),
          ),
          const SizedBox(height: 4),
          Text(
            allDone
                ? 'Nothing left to approve or discard.'
                : 'Extraction may still be in progress.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppPalette.grey400),
          ),
        ],
      ),
    );
  }
}

// ── Question card ─────────────────────────────────────────────────────────────

class _QuestionCard extends StatefulWidget {
  final ReviewQuestion question;
  final _Lang lang;
  final Future<void> Function(ReviewQuestion q) onApprove;
  final Future<void> Function(ReviewQuestion q, String note) onFlag;
  final Future<void> Function(ReviewQuestion q) onDiscard;

  const _QuestionCard({
    required this.question,
    required this.lang,
    required this.onApprove,
    required this.onFlag,
    required this.onDiscard,
  });

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

enum _CardOp { none, approving, flagging, discarding }

class _QuestionCardState extends State<_QuestionCard> {
  _CardOp _op = _CardOp.none;

  bool get _busy => _op != _CardOp.none;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.question;
    final doc =
        QuestionDocument.tryFromRow(q.blocks, q.options);
    final hiData =
        (q.translations?['hi'] as Map?)?.cast<String, dynamic>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: q.flagged ? AppPalette.amber : AppPalette.grey200,
          width: q.flagged ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (q.originalQno != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppPalette.grey100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Q ${q.originalQno}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppPalette.grey700)),
                ),
              if (q.flagged) ...[
                const SizedBox(width: 8),
                _FlagChip(note: q.generationMeta?['flag_note'] as String?),
              ],
              const Spacer(),
              if (q.correctOption != null)
                Text(
                  'Ans: ${q.correctOption}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppPalette.grey600),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.lang == _Lang.hi && hiData != null)
            _HindiView(hiData: hiData)
          else if (doc != null) ...[
            QuestionDocumentView(doc.blocks),
            const SizedBox(height: 12),
            _OptionsPreview(
                doc: doc, correctOption: q.correctOption),
          ] else
            Text(
              'No block document — legacy row.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppPalette.grey400),
            ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppPalette.grey100),
          const SizedBox(height: 10),
          Row(
            children: [
              _ActionButton(
                label: 'Approve',
                icon: Icons.check_circle_outline,
                color: AppPalette.green,
                busy: _op == _CardOp.approving,
                disabled: _busy,
                onPressed: () async {
                  setState(() => _op = _CardOp.approving);
                  await widget.onApprove(q);
                },
              ),
              const SizedBox(width: 8),
              _ActionButton(
                label: 'Flag',
                icon: Icons.flag_outlined,
                color: AppPalette.amber,
                busy: _op == _CardOp.flagging,
                disabled: _busy,
                onPressed: () => _showFlagDialog(context),
              ),
              const Spacer(),
              _ActionButton(
                label: 'Discard',
                icon: Icons.delete_outline,
                color: AppPalette.red,
                busy: _op == _CardOp.discarding,
                disabled: _busy,
                onPressed: () => _showDiscardDialog(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showFlagDialog(BuildContext context) {
    final ctrl = TextEditingController(
      text: widget.question.generationMeta?['flag_note'] as String? ?? '',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Flag question'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'Note — e.g. "OCR error in statement 2"',
          ),
          autofocus: true,
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppPalette.amber),
            onPressed: () async {
              final note = ctrl.text.trim();
              Navigator.pop(ctx);
              setState(() => _op = _CardOp.flagging);
              await widget.onFlag(widget.question, note);
            },
            child: const Text('Flag'),
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
            style:
                FilledButton.styleFrom(backgroundColor: AppPalette.red),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _op = _CardOp.discarding);
              await widget.onDiscard(widget.question);
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}

// ── Flag chip ─────────────────────────────────────────────────────────────────

class _FlagChip extends StatelessWidget {
  final String? note;
  const _FlagChip({this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppPalette.amberLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        note != null && note!.isNotEmpty ? 'Flagged: $note' : 'Flagged',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.amber, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ── Hindi plain-text view ─────────────────────────────────────────────────────

class _HindiView extends StatelessWidget {
  final Map<String, dynamic> hiData;
  const _HindiView({required this.hiData});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stem = hiData['stem'] as String? ?? '';
    final statements =
        (hiData['statements'] as List?)?.map((s) => '$s').toList() ??
            const <String>[];
    final opts = hiData['options'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stem.isNotEmpty)
          Text(stem,
              style: theme.textTheme.titleMedium
                  ?.copyWith(height: 1.6)),
        if (statements.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...statements.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 26,
                          child: Text('${e.key + 1}.',
                              style: theme.textTheme.bodyMedium)),
                      Expanded(
                          child: Text(e.value,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(height: 1.5))),
                    ],
                  ),
                ),
              ),
        ],
        if (opts is Map) ...[
          const SizedBox(height: 10),
          ...((opts['options'] as List?) ?? const []).map((o) {
            if (o is! Map) return const SizedBox.shrink();
            final key = o['key'] as String? ?? '';
            final text = o['text'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      width: 26,
                      child: Text('$key.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.w700))),
                  Expanded(
                      child: Text(text,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.5))),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}

// ── Options preview (answer revealed, non-interactive) ───────────────────────

class _OptionsPreview extends StatelessWidget {
  final QuestionDocument doc;
  final String? correctOption;
  const _OptionsPreview(
      {required this.doc, required this.correctOption});

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

  Widget _seg(_Lang l, String label) {
    final active = lang == l;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(l),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppPalette.grey200),
        borderRadius: BorderRadius.circular(999),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [_seg(_Lang.en, 'EN'), _seg(_Lang.hi, 'हिं')],
        ),
      ),
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool busy;
  final bool disabled;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.busy,
    required this.disabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10),
      ),
      icon: busy
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: color))
          : Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      onPressed: (disabled || busy) ? null : onPressed,
    );
  }
}
