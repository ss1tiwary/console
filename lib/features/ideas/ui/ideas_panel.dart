import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/palette.dart';
import '../../../core/spacing.dart';
import '../../../core/di/providers.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class Idea {
  final String id;
  final String appName;
  final String title;
  final String? body;
  final String? category;
  final String priority;
  final String status;
  final DateTime createdAt;

  const Idea({
    required this.id,
    required this.appName,
    required this.title,
    this.body,
    this.category,
    required this.priority,
    required this.status,
    required this.createdAt,
  });

  factory Idea.fromJson(Map<String, dynamic> j) => Idea(
        id: j['id'] as String,
        appName: j['app_name'] as String,
        title: j['title'] as String,
        body: j['body'] as String?,
        category: j['category'] as String?,
        priority: j['priority'] as String? ?? 'medium',
        status: j['status'] as String? ?? 'open',
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

// ── Provider ──────────────────────────────────────────────────────────────────

final ideasProvider =
    FutureProvider.autoDispose<List<Idea>>((ref) async {
  final data = await ref
      .watch(supabaseClientProvider)
      .from('ideas')
      .select()
      .order('created_at', ascending: false);
  return (data as List).map((e) => Idea.fromJson(e)).toList();
});

// ── Panel ─────────────────────────────────────────────────────────────────────

class IdeasPanel extends ConsumerStatefulWidget {
  const IdeasPanel({super.key});

  @override
  ConsumerState<IdeasPanel> createState() => _IdeasPanelState();
}

class _IdeasPanelState extends ConsumerState<IdeasPanel> {
  String _statusFilter = 'open';
  String? _appFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ideasAsync = ref.watch(ideasProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          color: AppPalette.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              Text('Ideas',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.indigo),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New idea'),
                onPressed: () {
                  final ideas =
                      ref.read(ideasProvider).valueOrNull ?? [];
                  final apps =
                      ideas.map((i) => i.appName).toSet().toList()
                        ..sort();
                  _showSheet(context, apps: apps);
                },
              ),
            ],
          ),
        ),
        // Body
        Expanded(
          child: ideasAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (ideas) {
              final apps =
                  ideas.map((i) => i.appName).toSet().toList()..sort();
              final filtered = ideas.where((i) {
                if (_statusFilter != 'all' &&
                    i.status != _statusFilter) {
                  return false;
                }
                if (_appFilter != null && i.appName != _appFilter) {
                  return false;
                }
                return true;
              }).toList();

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(ideasProvider),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // Status filter
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.pagePadding,
                              vertical: AppSpacing.xs),
                          children: [
                            'open',
                            'in_progress',
                            'done',
                            'dropped',
                            'all'
                          ]
                              .map((s) => _FilterChip(
                                    label: _statusLabel(s),
                                    selected: _statusFilter == s,
                                    onTap: () => setState(
                                        () => _statusFilter = s),
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                    // App filter
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
                                onTap: () =>
                                    setState(() => _appFilter = null),
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
                    // List
                    filtered.isEmpty
                        ? SliverFillRemaining(
                            child: Center(
                              child: Text('No ideas here.',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(
                                          color: AppPalette.grey400)),
                            ),
                          )
                        : SliverPadding(
                            padding:
                                const EdgeInsets.only(top: 8, bottom: 32),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (_, i) => _IdeaCard(
                                  idea: filtered[i],
                                  onTap: () => _showSheet(context,
                                      idea: filtered[i], apps: apps),
                                  onDelete: () async {
                                    await ref
                                        .read(supabaseClientProvider)
                                        .from('ideas')
                                        .delete()
                                        .eq('id', filtered[i].id);
                                    ref.invalidate(ideasProvider);
                                  },
                                ),
                                childCount: filtered.length,
                              ),
                            ),
                          ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showSheet(BuildContext context,
      {Idea? idea, required List<String> apps}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _IdeaSheet(
        idea: idea,
        existingApps: apps,
        onSaved: () {
          ref.invalidate(ideasProvider);
          Navigator.pop(context);
        },
        onDeleted: idea == null
            ? null
            : () {
                ref
                    .read(supabaseClientProvider)
                    .from('ideas')
                    .delete()
                    .eq('id', idea.id)
                    .then((_) {
                  ref.invalidate(ideasProvider);
                  Navigator.pop(context);
                });
              },
      ),
    );
  }

  String _statusLabel(String s) => switch (s) {
        'open' => 'Open',
        'in_progress' => 'In Progress',
        'done' => 'Done',
        'dropped' => 'Dropped',
        _ => 'All',
      };
}

// ── Idea card ─────────────────────────────────────────────────────────────────

class _IdeaCard extends StatelessWidget {
  final Idea idea;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _IdeaCard(
      {required this.idea, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pagePadding, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppPalette.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.grey200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(idea.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, height: 1.3)),
              ),
              const SizedBox(width: 8),
              _priorityDot(idea.priority),
            ]),
            if (idea.body != null && idea.body!.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(idea.body!,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: AppPalette.grey600, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 9),
            Row(children: [
              _chip(
                  idea.appName, AppPalette.indigo, AppPalette.indigoLight),
              if (idea.category != null) ...[
                const SizedBox(width: 5),
                _chip(idea.category!, AppPalette.grey600,
                    AppPalette.grey100),
              ],
              const SizedBox(width: 5),
              _statusChip(idea.status),
              const Spacer(),
              Text(
                _dateLabel(idea.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.grey400, fontSize: 11),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _priorityDot(String p) {
    final color = switch (p) {
      'high' => const Color(0xFFDC2626),
      'medium' => AppPalette.amber,
      _ => AppPalette.grey400,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _chip(String label, Color text, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: text)),
      );

  Widget _statusChip(String s) {
    final (label, color, bg) = switch (s) {
      'open' => ('Open', AppPalette.indigo, AppPalette.indigoLight),
      'in_progress' =>
        ('In Progress', AppPalette.amber, AppPalette.amberLight),
      'done' =>
        ('Done', const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
      _ => ('Dropped', AppPalette.grey600, AppPalette.grey100),
    };
    return _chip(label, color, bg);
  }

  String _dateLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return '1d ago';
    if (diff < 30) return '${diff}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Add / Edit sheet ──────────────────────────────────────────────────────────

class _IdeaSheet extends ConsumerStatefulWidget {
  final Idea? idea;
  final List<String> existingApps;
  final VoidCallback onSaved;
  final VoidCallback? onDeleted;

  const _IdeaSheet({
    this.idea,
    required this.existingApps,
    required this.onSaved,
    this.onDeleted,
  });

  @override
  ConsumerState<_IdeaSheet> createState() => _IdeaSheetState();
}

class _IdeaSheetState extends ConsumerState<_IdeaSheet> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _appName;
  late String _category;
  late String _priority;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.idea?.title ?? '');
    _body = TextEditingController(text: widget.idea?.body ?? '');
    _appName = TextEditingController(
        text: widget.idea?.appName ??
            (widget.existingApps.isNotEmpty
                ? widget.existingApps.first
                : ''));
    _category = widget.idea?.category ?? 'feature';
    _priority = widget.idea?.priority ?? 'medium';
    _status = widget.idea?.status ?? 'open';
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _appName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _appName.text.trim().isEmpty) {
      return;
    }
    setState(() => _saving = true);
    final payload = {
      'app_name': _appName.text.trim(),
      'title': _title.text.trim(),
      'body': _body.text.trim().isEmpty ? null : _body.text.trim(),
      'category': _category,
      'priority': _priority,
      'status': _status,
    };
    if (widget.idea == null) {
      await ref.read(supabaseClientProvider).from('ideas').insert(payload);
    } else {
      await ref
          .read(supabaseClientProvider)
          .from('ideas')
          .update(payload)
          .eq('id', widget.idea!.id);
    }
    if (mounted) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.idea != null;

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
          Text(isEdit ? 'Edit Idea' : 'New Idea',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          _field('App', _appName,
              hint: 'e.g. pibrief',
              suggestions: widget.existingApps),
          const SizedBox(height: 12),
          _field('Title', _title, hint: 'What\'s the idea?'),
          const SizedBox(height: 12),
          TextField(
              controller: _body,
              maxLines: 3,
              decoration: _decoration('Details (optional)')),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _DropdownField(
                label: 'Category',
                value: _category,
                items: const [
                  'feature', 'bug', 'content', 'design', 'data', 'other'
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DropdownField(
                label: 'Priority',
                value: _priority,
                items: const ['low', 'medium', 'high'],
                onChanged: (v) => setState(() => _priority = v),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (isEdit)
            _DropdownField(
              label: 'Status',
              value: _status,
              items: const ['open', 'in_progress', 'done', 'dropped'],
              onChanged: (v) => setState(() => _status = v),
            ),
          const SizedBox(height: 20),
          Row(children: [
            if (isEdit && widget.onDeleted != null) ...[
              IconButton(
                onPressed: widget.onDeleted,
                icon: const Icon(Icons.delete_outline),
                color: AppPalette.red,
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
                  backgroundColor: AppPalette.indigo),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white))
                  : Text(isEdit ? 'Save' : 'Add'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, List<String>? suggestions}) {
    if (suggestions != null && suggestions.isNotEmpty) {
      return Autocomplete<String>(
        initialValue: TextEditingValue(text: ctrl.text),
        optionsBuilder: (v) => suggestions
            .where((s) =>
                s.toLowerCase().contains(v.text.toLowerCase())),
        fieldViewBuilder: (_, c, focus, onSubmit) {
          ctrl.text = c.text;
          return TextField(
            controller: c,
            focusNode: focus,
            onEditingComplete: onSubmit,
            decoration: _decoration(hint ?? label),
          );
        },
        onSelected: (v) => setState(() => ctrl.text = v),
      );
    }
    return TextField(
        controller: ctrl, decoration: _decoration(hint ?? label));
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppPalette.grey100,
        contentPadding: const EdgeInsets.symmetric(
            vertical: 10, horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

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
          color: selected ? AppPalette.indigo : AppPalette.white,
          borderRadius:
              BorderRadius.circular(AppSpacing.chipRadius),
          border: Border.all(
              color: selected
                  ? AppPalette.indigo
                  : AppPalette.grey200),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppPalette.white : AppPalette.grey600,
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

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
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
                ?.copyWith(color: AppPalette.grey600)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppPalette.grey100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: items
                  .map((i) => DropdownMenuItem(
                      value: i,
                      child: Text(_capitalize(i),
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
