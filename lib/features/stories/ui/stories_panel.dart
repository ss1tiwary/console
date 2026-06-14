import 'package:flutter/material.dart';
import 'package:resolve_theme/resolve_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/spacing.dart';
import '../../../core/di/providers.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

/// One acceptance-criterion checklist row (stored as the jsonb `[{text,done}]`).
class AcceptItem {
  final String text;
  final bool done;
  const AcceptItem({required this.text, this.done = false});

  factory AcceptItem.fromJson(Map<String, dynamic> j) => AcceptItem(
        text: (j['text'] ?? '').toString(),
        done: j['done'] == true,
      );
  Map<String, dynamic> toJson() => {'text': text, 'done': done};
}

/// A build-ready backlog item. Richer than an Idea: acceptance criteria, a
/// workflow status, a size estimate, labels, and a link back to the idea it
/// was promoted from (`sourceIdeaId`).
class Story {
  final String id;
  final String appName;
  final String title;
  final String? description;
  final List<AcceptItem> acceptance;
  final String kind;
  final String priority;
  final String status;
  final String? size;
  final List<String> labels;
  final String? sourceIdeaId;
  final String? externalRef;
  final DateTime createdAt;

  const Story({
    required this.id,
    required this.appName,
    required this.title,
    this.description,
    this.acceptance = const [],
    required this.kind,
    required this.priority,
    required this.status,
    this.size,
    this.labels = const [],
    this.sourceIdeaId,
    this.externalRef,
    required this.createdAt,
  });

  factory Story.fromJson(Map<String, dynamic> j) => Story(
        id: j['id'] as String,
        appName: j['app_name'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        acceptance: ((j['acceptance'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => AcceptItem.fromJson(e.cast<String, dynamic>()))
            .toList(),
        kind: j['kind'] as String? ?? 'feature',
        priority: j['priority'] as String? ?? 'medium',
        status: j['status'] as String? ?? 'backlog',
        size: j['size'] as String?,
        labels: ((j['labels'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        sourceIdeaId: j['source_idea_id'] as String?,
        externalRef: j['external_ref'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

// ── Constants ───────────────────────────────────────────────────────────────

const kStoryKinds = ['feature', 'bug', 'chore', 'refactor', 'spike', 'design'];
const kStoryPriorities = ['low', 'medium', 'high', 'urgent'];
const kStoryStatuses = [
  'backlog', 'ready', 'in_progress', 'blocked', 'in_review', 'done', 'dropped'
];
const kStorySizes = ['xs', 's', 'm', 'l', 'xl'];

// Section order: active work first, then queued, then closed.
const _statusOrder = [
  'in_progress', 'blocked', 'in_review', 'ready', 'backlog', 'done', 'dropped'
];

String storyStatusLabel(String s) => switch (s) {
      'in_progress' => 'In progress',
      'in_review' => 'In review',
      _ => '${s[0].toUpperCase()}${s.substring(1)}',
    };

// ── Provider ──────────────────────────────────────────────────────────────────

final storiesProvider = FutureProvider.autoDispose<List<Story>>((ref) async {
  final data = await ref
      .watch(supabaseClientProvider)
      .from('stories')
      .select()
      .order('created_at', ascending: false);
  return (data as List).map((e) => Story.fromJson(e)).toList();
});

// ── Panel ─────────────────────────────────────────────────────────────────────

class StoriesPanel extends ConsumerStatefulWidget {
  const StoriesPanel({super.key});

  @override
  ConsumerState<StoriesPanel> createState() => _StoriesPanelState();
}

class _StoriesPanelState extends ConsumerState<StoriesPanel> {
  String _statusFilter = 'all';
  String? _appFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(storiesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: context.pal.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(children: [
            Text('Backlog',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            FilledButton.icon(
              style:
                  FilledButton.styleFrom(backgroundColor: context.pal.indigo),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New story'),
              onPressed: () {
                final apps = _knownApps();
                _showSheet(context, apps: apps);
              },
            ),
          ]),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (stories) {
              final apps = _knownApps(stories);
              final filtered = stories.where((s) {
                if (_statusFilter != 'all' && s.status != _statusFilter) {
                  return false;
                }
                if (_appFilter != null && s.appName != _appFilter) {
                  return false;
                }
                return true;
              }).toList();

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(storiesProvider),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.pagePadding,
                              vertical: AppSpacing.xs),
                          children: ['all', ...kStoryStatuses]
                              .map((s) => _FilterChip(
                                    label: s == 'all'
                                        ? 'All'
                                        : storyStatusLabel(s),
                                    selected: _statusFilter == s,
                                    onTap: () =>
                                        setState(() => _statusFilter = s),
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                    if (apps.length > 1)
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 40,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.pagePadding),
                            children: [
                              _FilterChip(
                                label: 'All apps',
                                selected: _appFilter == null,
                                onTap: () => setState(() => _appFilter = null),
                                small: true,
                              ),
                              ...apps.map((a) => _FilterChip(
                                    label: a,
                                    selected: _appFilter == a,
                                    onTap: () =>
                                        setState(() => _appFilter = a),
                                    small: true,
                                  )),
                            ],
                          ),
                        ),
                      ),
                    if (filtered.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Text('No stories here.',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: context.pal.grey400)),
                        ),
                      )
                    else
                      ..._buildSections(context, filtered, apps),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<String> _knownApps([List<Story>? stories]) {
    final src = stories ?? ref.read(storiesProvider).valueOrNull ?? const [];
    return src.map((s) => s.appName).toSet().toList()..sort();
  }

  // Grouped sections by status (active work first). A single section when a
  // specific status filter is active.
  List<Widget> _buildSections(
      BuildContext context, List<Story> filtered, List<String> apps) {
    final theme = Theme.of(context);
    final byStatus = <String, List<Story>>{};
    for (final s in filtered) {
      byStatus.putIfAbsent(s.status, () => []).add(s);
    }
    final order = [
      for (final st in _statusOrder)
        if (byStatus.containsKey(st)) st
    ];
    final sections = <Widget>[];
    for (final st in order) {
      final items = byStatus[st]!;
      sections.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding, 12, AppSpacing.pagePadding, 4),
          child: Row(children: [
            Text(storyStatusLabel(st),
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: context.pal.grey600)),
            const SizedBox(width: 6),
            Text('${items.length}',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: context.pal.grey400)),
          ]),
        ),
      ));
      sections.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => _StoryCard(
            story: items[i],
            onTap: () => _showSheet(context, story: items[i], apps: apps),
          ),
          childCount: items.length,
        ),
      ));
    }
    return sections;
  }

  void _showSheet(BuildContext context,
      {Story? story, required List<String> apps}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.pal.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StorySheet(
        story: story,
        existingApps: apps,
        onSaved: () {
          ref.invalidate(storiesProvider);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ── Story card ─────────────────────────────────────────────────────────────────

class _StoryCard extends StatelessWidget {
  final Story story;
  final VoidCallback onTap;
  const _StoryCard({required this.story, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = story.acceptance.where((a) => a.done).length;
    final total = story.acceptance.length;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pagePadding, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.pal.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.pal.grey200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(story.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, height: 1.3)),
              ),
              const SizedBox(width: 8),
              _priorityDot(context, story.priority),
            ]),
            if (story.description != null &&
                story.description!.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(story.description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: context.pal.grey600, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
            if (total > 0) ...[
              const SizedBox(height: 9),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: done / total,
                      minHeight: 4,
                      backgroundColor: context.pal.grey200,
                      valueColor: const AlwaysStoppedAnimation(
                          Color(0xFF16A34A)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text('$done/$total',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: context.pal.grey400, fontSize: 11)),
              ]),
            ],
            const SizedBox(height: 9),
            Wrap(spacing: 5, runSpacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _chip(story.appName, context.pal.white, context.pal.indigo),
              _kindChip(context, story.kind),
              _statusChip(context, story.status),
              if (story.size != null)
                _chip(story.size!.toUpperCase(), context.pal.grey600,
                    context.pal.grey100),
              for (final l in story.labels)
                _chip(l, context.pal.grey600, context.pal.grey100),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              if (story.sourceIdeaId != null) ...[
                Icon(Icons.lightbulb_outline,
                    size: 12, color: context.pal.grey400),
                const SizedBox(width: 3),
                Text('from idea',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: context.pal.grey400, fontSize: 11)),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              Text(_dateLabel(story.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: context.pal.grey400, fontSize: 11)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _priorityDot(BuildContext context, String p) {
    final color = switch (p) {
      'urgent' => const Color(0xFFDC2626),
      'high' => context.pal.amber,
      'medium' => context.pal.grey600,
      _ => context.pal.grey400,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _chip(String label, Color text, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: text)),
      );

  Widget _kindChip(BuildContext context, String kind) {
    final icon = switch (kind) {
      'bug' => Icons.bug_report_outlined,
      'chore' => Icons.build_outlined,
      'refactor' => Icons.recycling,
      'spike' => Icons.science_outlined,
      'design' => Icons.palette_outlined,
      _ => Icons.star_outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: context.pal.indigoLight,
          borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: context.pal.indigo),
        const SizedBox(width: 3),
        Text(kind,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: context.pal.indigo)),
      ]),
    );
  }

  Widget _statusChip(BuildContext context, String s) {
    final (color, bg) = switch (s) {
      'ready' => (context.pal.indigo, context.pal.indigoLight),
      'in_progress' => (context.pal.amber, context.pal.amberLight),
      'blocked' => (context.pal.red, const Color(0xFFFEE2E2)),
      'in_review' => (const Color(0xFF7C3AED), const Color(0xFFEDE9FE)),
      'done' => (const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
      _ => (context.pal.grey600, context.pal.grey100),
    };
    return _chip(storyStatusLabel(s), color, bg);
  }

  String _dateLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return '1d ago';
    if (diff < 30) return '${diff}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Add / Edit / Promote sheet ─────────────────────────────────────────────────

/// Editor for a story. Public so the ideas panel can open it to *promote* an
/// idea: pass `sourceIdeaId` + prefill values; on a successful insert the idea
/// is flipped to status 'promoted'.
class StorySheet extends ConsumerStatefulWidget {
  final Story? story;
  final List<String> existingApps;
  final VoidCallback onSaved;
  // Promotion prefill (used when creating from an idea).
  final String? sourceIdeaId;
  final String? initialApp;
  final String? initialTitle;
  final String? initialDescription;
  final String? initialKind;
  final String? initialPriority;

  const StorySheet({
    super.key,
    this.story,
    required this.existingApps,
    required this.onSaved,
    this.sourceIdeaId,
    this.initialApp,
    this.initialTitle,
    this.initialDescription,
    this.initialKind,
    this.initialPriority,
  });

  @override
  ConsumerState<StorySheet> createState() => _StorySheetState();
}

class _StorySheetState extends ConsumerState<StorySheet> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late final TextEditingController _appName;
  late final TextEditingController _labels;
  late final TextEditingController _externalRef;
  late String _kind;
  late String _priority;
  late String _status;
  String? _size;
  late List<_AcceptRow> _accept;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.story;
    _title = TextEditingController(text: s?.title ?? widget.initialTitle ?? '');
    _desc = TextEditingController(
        text: s?.description ?? widget.initialDescription ?? '');
    _appName = TextEditingController(
        text: s?.appName ??
            widget.initialApp ??
            (widget.existingApps.isNotEmpty
                ? widget.existingApps.first
                : ''));
    _labels = TextEditingController(text: (s?.labels ?? const []).join(', '));
    _externalRef = TextEditingController(text: s?.externalRef ?? '');
    _kind = s?.kind ?? widget.initialKind ?? 'feature';
    _priority = s?.priority ?? widget.initialPriority ?? 'medium';
    _status = s?.status ?? 'backlog';
    _size = s?.size;
    _accept = (s?.acceptance ?? const [])
        .map((a) => _AcceptRow(
            controller: TextEditingController(text: a.text), done: a.done))
        .toList();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _appName.dispose();
    _labels.dispose();
    _externalRef.dispose();
    for (final r in _accept) {
      r.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _appName.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final sb = ref.read(supabaseClientProvider);

    final acceptance = [
      for (final r in _accept)
        if (r.controller.text.trim().isNotEmpty)
          AcceptItem(text: r.controller.text.trim(), done: r.done).toJson()
    ];
    final labels = _labels.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final payload = <String, dynamic>{
      'app_name': _appName.text.trim(),
      'title': _title.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'acceptance': acceptance,
      'kind': _kind,
      'priority': _priority,
      'status': _status,
      'size': _size,
      'labels': labels,
      'external_ref':
          _externalRef.text.trim().isEmpty ? null : _externalRef.text.trim(),
    };
    // Stamp lifecycle timestamps from the status transition.
    if (_status == 'in_progress') payload['started_at'] = _nowIso();
    if (_status == 'done') payload['completed_at'] = _nowIso();

    if (widget.story == null) {
      if (widget.sourceIdeaId != null) {
        payload['source_idea_id'] = widget.sourceIdeaId;
      }
      await sb.from('stories').insert(payload);
      // Promotion: mark the originating idea so it leaves the raw list.
      if (widget.sourceIdeaId != null) {
        await sb
            .from('ideas')
            .update({'status': 'promoted'}).eq('id', widget.sourceIdeaId!);
      }
    } else {
      await sb.from('stories').update(payload).eq('id', widget.story!.id);
    }
    if (mounted) widget.onSaved();
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  Future<void> _delete() async {
    if (widget.story == null) return;
    await ref
        .read(supabaseClientProvider)
        .from('stories')
        .delete()
        .eq('id', widget.story!.id);
    if (mounted) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.story != null;
    final isPromote = widget.sourceIdeaId != null;

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
                  color: context.pal.grey200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
                isEdit
                    ? 'Edit story'
                    : isPromote
                        ? 'Promote to story'
                        : 'New story',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            _field('App', _appName,
                hint: 'e.g. console', suggestions: widget.existingApps),
            const SizedBox(height: 12),
            _field('Title', _title, hint: 'Imperative — "Add backlog board"'),
            const SizedBox(height: 12),
            TextField(
                controller: _desc,
                maxLines: 3,
                decoration: _decoration('Description (optional)')),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: _DropdownField(
                  label: 'Kind',
                  value: _kind,
                  items: kStoryKinds,
                  onChanged: (v) => setState(() => _kind = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DropdownField(
                  label: 'Priority',
                  value: _priority,
                  items: kStoryPriorities,
                  onChanged: (v) => setState(() => _priority = v),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _DropdownField(
                  label: 'Status',
                  value: _status,
                  items: kStoryStatuses,
                  labelFor: storyStatusLabel,
                  onChanged: (v) => setState(() => _status = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DropdownField(
                  label: 'Size',
                  value: _size ?? 'none',
                  items: const ['none', ...kStorySizes],
                  onChanged: (v) =>
                      setState(() => _size = v == 'none' ? null : v),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Acceptance criteria',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: context.pal.grey600)),
            const SizedBox(height: 4),
            ..._accept.asMap().entries.map((e) => _acceptRow(e.key, e.value)),
            TextButton.icon(
              onPressed: () => setState(() => _accept
                  .add(_AcceptRow(controller: TextEditingController()))),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add criterion'),
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
            const SizedBox(height: 12),
            _field('Labels', _labels, hint: 'comma, separated'),
            const SizedBox(height: 12),
            _field('Link (optional)', _externalRef, hint: 'GitHub issue / PR'),
            const SizedBox(height: 20),
            Row(children: [
              if (isEdit) ...[
                IconButton(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  color: context.pal.red,
                ),
                const Spacer(),
              ] else
                const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: context.pal.indigo),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(isEdit ? 'Save' : (isPromote ? 'Promote' : 'Add')),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _acceptRow(int index, _AcceptRow row) {
    return Row(children: [
      Checkbox(
        value: row.done,
        visualDensity: VisualDensity.compact,
        onChanged: (v) => setState(() => row.done = v ?? false),
      ),
      Expanded(
        child: TextField(
          controller: row.controller,
          style: TextStyle(
            fontSize: 14,
            decoration: row.done ? TextDecoration.lineThrough : null,
            color: row.done ? context.pal.grey400 : null,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Done when…',
            border: InputBorder.none,
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.close, size: 16),
        color: context.pal.grey400,
        visualDensity: VisualDensity.compact,
        onPressed: () => setState(() {
          _accept.removeAt(index).controller.dispose();
        }),
      ),
    ]);
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, List<String>? suggestions}) {
    if (suggestions != null && suggestions.isNotEmpty) {
      return Autocomplete<String>(
        initialValue: TextEditingValue(text: ctrl.text),
        optionsBuilder: (v) => suggestions
            .where((s) => s.toLowerCase().contains(v.text.toLowerCase())),
        fieldViewBuilder: (_, c, focus, onSubmit) {
          c.text = ctrl.text;
          return TextField(
            controller: c,
            focusNode: focus,
            onChanged: (v) => ctrl.text = v,
            onEditingComplete: onSubmit,
            decoration: _decoration(hint ?? label),
          );
        },
        onSelected: (v) => setState(() => ctrl.text = v),
      );
    }
    return TextField(controller: ctrl, decoration: _decoration(hint ?? label));
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: context.pal.grey100,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );
}

class _AcceptRow {
  final TextEditingController controller;
  bool done;
  _AcceptRow({required this.controller, this.done = false});
}

// ── Shared small widgets ────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool small;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: EdgeInsets.symmetric(
            horizontal: small ? 10 : 14, vertical: small ? 4 : 6),
        decoration: BoxDecoration(
          color: selected ? context.pal.indigo : context.pal.white,
          borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
          border: Border.all(
              color: selected ? context.pal.indigo : context.pal.grey200),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? context.pal.white : context.pal.grey600,
            fontSize: small ? 12 : 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final void Function(String) onChanged;
  final String Function(String)? labelFor;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelFor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: context.pal.grey600)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.pal.grey100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: items
                  .map((i) => DropdownMenuItem(
                      value: i,
                      child: Text(
                          labelFor?.call(i) ?? _capitalize(i),
                          style: const TextStyle(fontSize: 14))))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  String _capitalize(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) =>
          w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
