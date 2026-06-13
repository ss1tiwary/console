import 'package:flutter/material.dart';
import 'package:resolve_theme/resolve_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class _PostScores {
  final int pSyllabus;
  final int pPyqResonance;
  final int pFactualYield;
  final int pStaticCreation;
  final int pConfusability;
  final int mSyllabus;
  final int mPyqResonance;
  final int mAnalytical;
  final int mSignificance;
  final int mExampleValue;
  final int shelfLife;

  int get aiPrelims =>
      pSyllabus + pPyqResonance + pFactualYield + pStaticCreation + pConfusability;
  int get aiMains =>
      mSyllabus + mPyqResonance + mAnalytical + mSignificance + mExampleValue;
  int get aiRelevance => aiPrelims > aiMains ? aiPrelims : aiMains;

  const _PostScores({
    required this.pSyllabus,
    required this.pPyqResonance,
    required this.pFactualYield,
    required this.pStaticCreation,
    required this.pConfusability,
    required this.mSyllabus,
    required this.mPyqResonance,
    required this.mAnalytical,
    required this.mSignificance,
    required this.mExampleValue,
    required this.shelfLife,
  });

  factory _PostScores.fromRow(Map<String, dynamic> row) => _PostScores(
        pSyllabus: (row['p_syllabus'] as num?)?.toInt() ?? 0,
        pPyqResonance: (row['p_pyq_resonance'] as num?)?.toInt() ?? 0,
        pFactualYield: (row['p_factual_yield'] as num?)?.toInt() ?? 0,
        pStaticCreation:
            (row['p_static_creation'] as num?)?.toInt() ?? 0,
        pConfusability:
            (row['p_confusability'] as num?)?.toInt() ?? 0,
        mSyllabus: (row['m_syllabus'] as num?)?.toInt() ?? 0,
        mPyqResonance: (row['m_pyq_resonance'] as num?)?.toInt() ?? 0,
        mAnalytical: (row['m_analytical'] as num?)?.toInt() ?? 0,
        mSignificance: (row['m_significance'] as num?)?.toInt() ?? 0,
        mExampleValue: (row['m_example_value'] as num?)?.toInt() ?? 0,
        shelfLife: (row['shelf_life'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'p_syllabus': pSyllabus,
        'p_pyq_resonance': pPyqResonance,
        'p_factual_yield': pFactualYield,
        'p_static_creation': pStaticCreation,
        'p_confusability': pConfusability,
        'm_syllabus': mSyllabus,
        'm_pyq_resonance': mPyqResonance,
        'm_analytical': mAnalytical,
        'm_significance': mSignificance,
        'm_example_value': mExampleValue,
        'shelf_life': shelfLife,
      };
}

// ── Provider ──────────────────────────────────────────────────────────────────

final _postScoresProvider = FutureProvider.family<
    ({_PostScores ai, _PostScores? human, String? justification}),
    String>((ref, postId) async {
  final sb = ref.watch(supabaseClientProvider);
  final postRows = await sb
      .from('posts')
      .select('p_syllabus, p_pyq_resonance, p_factual_yield, '
          'p_static_creation, p_confusability, m_syllabus, '
          'm_pyq_resonance, m_analytical, m_significance, '
          'm_example_value, shelf_life')
      .eq('id', postId)
      .limit(1);
  if (postRows.isEmpty) throw Exception('Post not found');
  final ai = _PostScores.fromRow(postRows.first);

  final uid = sb.auth.currentUser?.id;
  _PostScores? human;
  String? justification;
  if (uid != null) {
    final revRows = await sb
        .from('relevance_reviews')
        .select('human_scores, justification')
        .eq('post_id', postId)
        .eq('reviewer_id', uid)
        .limit(1);
    if (revRows.isNotEmpty) {
      final r = revRows.first;
      final hs = r['human_scores'] as Map<String, dynamic>? ?? {};
      if (hs.isNotEmpty) human = _PostScores.fromRow(hs);
      justification = r['justification'] as String?;
    }
  }
  return (ai: ai, human: human, justification: justification);
});

// ── Screen ────────────────────────────────────────────────────────────────────

/// Relevance re-score form. Shows AI scores; reviewer assigns parallel values.
/// `onDone` is called after a successful save (or can be used to close a dialog).
class RelevanceReviewScreen extends ConsumerStatefulWidget {
  final String postId;
  final String postTitle;
  final VoidCallback onDone;
  const RelevanceReviewScreen({
    super.key,
    required this.postId,
    required this.postTitle,
    required this.onDone,
  });

  @override
  ConsumerState<RelevanceReviewScreen> createState() =>
      _RelevanceReviewScreenState();
}

class _RelevanceReviewScreenState
    extends ConsumerState<RelevanceReviewScreen> {
  late int _hPSyllabus,
      _hPPyq,
      _hPFactual,
      _hPStatic,
      _hPConfus;
  late int _hMSyllabus,
      _hMPyq,
      _hMAnalytical,
      _hMSignificance,
      _hMExample;
  late int _hShelfLife;
  final _justController = TextEditingController();
  bool _initialised = false;
  bool _saving = false;

  @override
  void dispose() {
    _justController.dispose();
    super.dispose();
  }

  void _initialise(
      _PostScores ai, _PostScores? human, String? justification) {
    if (_initialised) return;
    final h = human ?? ai;
    _hPSyllabus = h.pSyllabus;
    _hPPyq = h.pPyqResonance;
    _hPFactual = h.pFactualYield;
    _hPStatic = h.pStaticCreation;
    _hPConfus = h.pConfusability;
    _hMSyllabus = h.mSyllabus;
    _hMPyq = h.mPyqResonance;
    _hMAnalytical = h.mAnalytical;
    _hMSignificance = h.mSignificance;
    _hMExample = h.mExampleValue;
    _hShelfLife = h.shelfLife;
    _justController.text = justification ?? '';
    _initialised = true;
  }

  int get _humanPrelims =>
      _hPSyllabus + _hPPyq + _hPFactual + _hPStatic + _hPConfus;
  int get _humanMains =>
      _hMSyllabus + _hMPyq + _hMAnalytical + _hMSignificance + _hMExample;
  int get _humanRelevance =>
      _humanPrelims > _humanMains ? _humanPrelims : _humanMains;

  Future<void> _save(_PostScores ai) async {
    setState(() => _saving = true);
    try {
      final sb = ref.read(supabaseClientProvider);
      final uid = sb.auth.currentUser?.id;
      if (uid == null) throw Exception('Not authenticated');

      final humanScores = _PostScores(
        pSyllabus: _hPSyllabus,
        pPyqResonance: _hPPyq,
        pFactualYield: _hPFactual,
        pStaticCreation: _hPStatic,
        pConfusability: _hPConfus,
        mSyllabus: _hMSyllabus,
        mPyqResonance: _hMPyq,
        mAnalytical: _hMAnalytical,
        mSignificance: _hMSignificance,
        mExampleValue: _hMExample,
        shelfLife: _hShelfLife,
      );

      await sb.from('relevance_reviews').upsert({
        'post_id': widget.postId,
        'reviewer_id': uid,
        'ai_scores': ai.toJson(),
        'human_scores': humanScores.toJson(),
        'human_prelims': _humanPrelims,
        'human_mains': _humanMains,
        'human_relevance': _humanRelevance,
        'justification': _justController.text.trim().isEmpty
            ? null
            : _justController.text.trim(),
      }, onConflict: 'post_id,reviewer_id');

      ref.invalidate(_postScoresProvider(widget.postId));
      widget.onDone();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: context.pal.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scoresAsync =
        ref.watch(_postScoresProvider(widget.postId));

    return scoresAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) =>
          Center(child: Text('Could not load scores.\n$e')),
      data: (data) {
        _initialise(data.ai, data.human, data.justification);
        return _buildBody(context, theme, data.ai);
      },
    );
  }

  Widget _buildBody(
      BuildContext context, ThemeData theme, _PostScores ai) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.postTitle,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _TotalsBanner(
          aiPrelims: ai.aiPrelims,
          aiMains: ai.aiMains,
          aiRelevance: ai.aiRelevance,
          humanPrelims: _humanPrelims,
          humanMains: _humanMains,
          humanRelevance: _humanRelevance,
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GroupLabel('Prelims Track', context.pal.indigo),
              const SizedBox(height: 4),
              _DimRow(
                label: 'Syllabus match',
                hint: 'Derived (read-only)',
                maxVal: 25,
                aiVal: ai.pSyllabus,
                humanVal: _hPSyllabus,
                readOnly: true,
                onChanged: (_) {},
              ),
              _DimRow(
                label: 'PYQ resonance',
                hint: 'Past Prelims echo',
                maxVal: 15,
                aiVal: ai.pPyqResonance,
                humanVal: _hPPyq,
                onChanged: (v) => setState(() => _hPPyq = v),
              ),
              _DimRow(
                label: 'Factual yield',
                hint: 'MCQ-ready facts',
                maxVal: 20,
                aiVal: ai.pFactualYield,
                humanVal: _hPFactual,
                onChanged: (v) =>
                    setState(() => _hPFactual = v),
              ),
              _DimRow(
                label: 'Static creation',
                hint: 'New permanent fact',
                maxVal: 15,
                aiVal: ai.pStaticCreation,
                humanVal: _hPStatic,
                onChanged: (v) =>
                    setState(() => _hPStatic = v),
              ),
              _DimRow(
                label: 'Confusability',
                hint: 'Good MCQ distractors',
                maxVal: 10,
                aiVal: ai.pConfusability,
                humanVal: _hPConfus,
                onChanged: (v) =>
                    setState(() => _hPConfus = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GroupLabel('Mains Track', context.pal.green),
              const SizedBox(height: 4),
              _DimRow(
                label: 'Syllabus match',
                hint: 'Derived (read-only)',
                maxVal: 25,
                aiVal: ai.mSyllabus,
                humanVal: _hMSyllabus,
                readOnly: true,
                onChanged: (_) {},
              ),
              _DimRow(
                label: 'PYQ resonance',
                hint: 'Past Mains echo',
                maxVal: 15,
                aiVal: ai.mPyqResonance,
                humanVal: _hMPyq,
                onChanged: (v) => setState(() => _hMPyq = v),
              ),
              _DimRow(
                label: 'Analytical depth',
                hint: 'Debate / tensions',
                maxVal: 20,
                aiVal: ai.mAnalytical,
                humanVal: _hMAnalytical,
                onChanged: (v) =>
                    setState(() => _hMAnalytical = v),
              ),
              _DimRow(
                label: 'Significance',
                hint: 'National impact scale',
                maxVal: 15,
                aiVal: ai.mSignificance,
                humanVal: _hMSignificance,
                onChanged: (v) =>
                    setState(() => _hMSignificance = v),
              ),
              _DimRow(
                label: 'Example value',
                hint: 'Quotable case study',
                maxVal: 10,
                aiVal: ai.mExampleValue,
                humanVal: _hMExample,
                onChanged: (v) =>
                    setState(() => _hMExample = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GroupLabel('Shelf Life', context.pal.amber),
              const SizedBox(height: 12),
              _ShelfLifeRow(
                aiVal: ai.shelfLife,
                humanVal: _hShelfLife,
                onChanged: (v) =>
                    setState(() => _hShelfLife = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GroupLabel('Justification', context.pal.grey600),
              const SizedBox(height: 10),
              TextField(
                controller: _justController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText:
                      'Why does your score differ from the AI?',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: widget.onDone,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : () => _save(ai),
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2))
                  : const Text('Save Review'),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Totals banner ─────────────────────────────────────────────────────────────

class _TotalsBanner extends StatelessWidget {
  final int aiPrelims, aiMains, aiRelevance;
  final int humanPrelims, humanMains, humanRelevance;
  const _TotalsBanner({
    required this.aiPrelims,
    required this.aiMains,
    required this.aiRelevance,
    required this.humanPrelims,
    required this.humanMains,
    required this.humanRelevance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.pal.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.pal.grey200),
      ),
      child: Row(children: [
        _TotalCol('PRELIMS', aiPrelims, humanPrelims),
        _divider(context),
        _TotalCol('MAINS', aiMains, humanMains),
        _divider(context),
        _TotalCol('RELEVANCE', aiRelevance, humanRelevance,
            highlight: true),
      ]),
    );
  }

  Widget _divider(BuildContext context) => Container(
        width: 1,
        height: 40,
        margin:
            const EdgeInsets.symmetric(horizontal: 12),
        color: context.pal.grey200,
      );
}

class _TotalCol extends StatelessWidget {
  final String label;
  final int ai, human;
  final bool highlight;
  const _TotalCol(this.label, this.ai, this.human,
      {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final diff = human - ai;
    final diffColor = diff > 0
        ? context.pal.green
        : diff < 0
            ? context.pal.red
            : context.pal.grey400;
    return Expanded(
      child: Column(children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: context.pal.grey400)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$human',
              style: TextStyle(
                  fontSize: highlight ? 22 : 18,
                  fontWeight: FontWeight.w800,
                  color: highlight
                      ? context.pal.indigo
                      : context.pal.grey900),
            ),
            const SizedBox(width: 4),
            Text('/ $ai',
                style: TextStyle(
                    fontSize: 11,
                    color: context.pal.grey400)),
          ],
        ),
        if (diff != 0)
          Text(
            diff > 0 ? '+$diff' : '$diff',
            style: TextStyle(
                fontSize: 11,
                color: diffColor,
                fontWeight: FontWeight.w600),
          ),
      ]),
    );
  }
}

// ── Dimension row ─────────────────────────────────────────────────────────────

class _DimRow extends StatelessWidget {
  final String label;
  final String hint;
  final int maxVal;
  final int aiVal;
  final int humanVal;
  final bool readOnly;
  final ValueChanged<int> onChanged;

  const _DimRow({
    required this.label,
    required this.hint,
    required this.maxVal,
    required this.aiVal,
    required this.humanVal,
    required this.onChanged,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: readOnly
                              ? context.pal.grey400
                              : context.pal.grey900)),
                  Text(hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: context.pal.grey400,
                          fontSize: 11)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: context.pal.grey100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('AI: $aiVal / $maxVal',
                  style: TextStyle(
                      fontSize: 11,
                      color: context.pal.grey600,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              child: Text('$humanVal',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: readOnly
                          ? context.pal.grey400
                          : context.pal.indigo)),
            ),
          ]),
          if (!readOnly) ...[
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(
                        enabledThumbRadius: 7),
                overlayShape:
                    const RoundSliderOverlayShape(
                        overlayRadius: 14),
                activeTrackColor: context.pal.indigo,
                thumbColor: context.pal.indigo,
                overlayColor: context.pal.indigoLight,
                inactiveTrackColor: context.pal.grey200,
              ),
              child: Slider(
                value: humanVal.toDouble(),
                min: 0,
                max: maxVal.toDouble(),
                divisions: maxVal,
                label: '$humanVal',
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
          ],
          Divider(height: 1, color: context.pal.grey100),
        ],
      ),
    );
  }
}

// ── Shelf life ────────────────────────────────────────────────────────────────

class _ShelfLifeRow extends StatelessWidget {
  final int aiVal;
  final int humanVal;
  final ValueChanged<int> onChanged;
  const _ShelfLifeRow(
      {required this.aiVal,
      required this.humanVal,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const opts = [
      (0, 'Transient', 'Monthly figure'),
      (5, 'This cycle', 'This exam year'),
      (10, 'Permanent', 'New body / act'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: context.pal.grey100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('AI: $aiVal',
                style: TextStyle(
                    fontSize: 11,
                    color: context.pal.grey600,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(
          children: opts.map((o) {
            final (val, label, _) = o;
            final selected = humanVal == val;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(val),
                child: Container(
                  margin: EdgeInsets.only(right: val != 10 ? 8 : 0),
                  padding:
                      const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? context.pal.indigo
                        : context.pal.grey100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$label\n($val)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? context.pal.white
                          : context.pal.grey600,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          opts
              .firstWhere((o) => o.$1 == humanVal)
              .$3,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: context.pal.grey400),
        ),
      ],
    );
  }
}

// ── Shared primitives ─────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.pal.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.pal.grey200),
        ),
        child: child,
      );
}

class _GroupLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _GroupLabel(this.text, this.color);
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(text.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(
                    color: color,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700)),
      ]);
}
