import 'package:flutter/material.dart';
import 'package:resolve_theme/resolve_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/spacing.dart';
import '../../../core/di/providers.dart';
import '../../../core/config_options.dart';

/// Section-registry editor (decision 0003). Lets an editor toggle / reorder /
/// relabel / role-gate the post-detail sections — writes `config_options`
/// (category 'ui_section', scope 'pibrief.post_detail'); the app re-reads with no
/// rebuild. Visibility set here is UX; RLS remains the real authority.
const _scope = 'pibrief.post_detail';

final _sectionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('config_options')
      .select('id, value, label, label_i18n, sort_order, active, metadata')
      .eq('category', 'ui_section')
      .eq('scope', _scope)
      .order('sort_order');
  return (rows as List).map((r) => (r as Map).cast<String, dynamic>()).toList();
});

class SectionsPanel extends ConsumerWidget {
  const SectionsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(_sectionsProvider);
    final roles = ref.watch(configOptionsProvider('role')).valueOrNull ??
        const ['aspirant', 'editor', 'admin'];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: context.pal.white,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Row(children: [
          Text('Post sections',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => ref.invalidate(_sectionsProvider),
          ),
        ]),
      ),
      Expanded(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (rows) => _List(rows: rows, roles: roles),
        ),
      ),
    ]);
  }
}

class _List extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> rows;
  final List<String> roles;
  const _List({required this.rows, required this.roles});

  @override
  ConsumerState<_List> createState() => _ListState();
}

class _ListState extends ConsumerState<_List> {
  late List<Map<String, dynamic>> _rows;

  @override
  void initState() {
    super.initState();
    _rows = [...widget.rows];
  }

  @override
  void didUpdateWidget(_List old) {
    super.didUpdateWidget(old);
    _rows = [...widget.rows];
  }

  Future<void> _patch(String id, Map<String, dynamic> values) async {
    await ref
        .read(supabaseClientProvider)
        .from('config_options')
        .update(values)
        .eq('id', id);
  }

  Future<void> _onReorder(int oldI, int newI) async {
    setState(() {
      if (newI > oldI) newI -= 1;
      final item = _rows.removeAt(oldI);
      _rows.insert(newI, item);
    });
    // Persist new order as 10,20,30… so future inserts can slot between.
    for (var i = 0; i < _rows.length; i++) {
      final want = (i + 1) * 10;
      if (_rows[i]['sort_order'] != want) {
        _rows[i]['sort_order'] = want;
        await _patch(_rows[i]['id'] as String, {'sort_order': want});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pagePadding, vertical: 8),
      itemCount: _rows.length,
      onReorder: _onReorder,
      itemBuilder: (context, i) {
        final r = _rows[i];
        return _SectionTile(
          key: ValueKey(r['id']),
          row: r,
          roles: widget.roles,
          onToggle: (v) async {
            setState(() => r['active'] = v);
            await _patch(r['id'] as String, {'active': v});
          },
          onRoles: (visibleTo) async {
            final meta = Map<String, dynamic>.from(
                (r['metadata'] as Map?)?.cast<String, dynamic>() ?? {});
            meta['visible_to'] = visibleTo;
            setState(() => r['metadata'] = meta);
            await _patch(r['id'] as String, {'metadata': meta});
          },
          onLabel: (label, hi) async {
            final i18n = Map<String, dynamic>.from(
                (r['label_i18n'] as Map?)?.cast<String, dynamic>() ?? {});
            if (hi.trim().isEmpty) {
              i18n.remove('hi');
            } else {
              i18n['hi'] = hi.trim();
            }
            setState(() {
              r['label'] = label;
              r['label_i18n'] = i18n;
            });
            await _patch(r['id'] as String, {'label': label, 'label_i18n': i18n});
          },
        );
      },
    );
  }
}

class _SectionTile extends StatefulWidget {
  final Map<String, dynamic> row;
  final List<String> roles;
  final ValueChanged<bool> onToggle;
  final ValueChanged<List<String>> onRoles;
  final void Function(String label, String hi) onLabel;

  const _SectionTile({
    super.key,
    required this.row,
    required this.roles,
    required this.onToggle,
    required this.onRoles,
    required this.onLabel,
  });

  @override
  State<_SectionTile> createState() => _SectionTileState();
}

class _SectionTileState extends State<_SectionTile> {
  bool _expanded = false;

  List<String> get _visibleTo {
    final meta = (widget.row['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
    return ((meta['visible_to'] as List?) ?? widget.roles)
        .map((e) => e.toString())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.row;
    final active = r['active'] == true;
    final label = (r['label'] as String?) ?? (r['value'] as String);
    final hi = ((r['label_i18n'] as Map?)?['hi'] as String?) ?? '';
    final visible = _visibleTo;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: context.pal.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _expanded ? context.pal.indigo : context.pal.grey200),
      ),
      child: Column(children: [
        Row(children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(Icons.drag_indicator, color: context.pal.grey400),
          ),
          Expanded(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
              title: Opacity(
                opacity: active ? 1 : 0.5,
                child: Text(label,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              subtitle: Text(
                '${r['value']}  ·  ${visible.join(', ')}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: context.pal.grey400, fontSize: 11),
              ),
              onTap: () => setState(() => _expanded = !_expanded),
            ),
          ),
          Switch(value: active, onChanged: widget.onToggle),
          const SizedBox(width: 6),
        ]),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('VISIBLE TO',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: context.pal.grey400,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final role in widget.roles)
                    FilterChip(
                      label: Text(role),
                      selected: visible.contains(role),
                      onSelected: (sel) {
                        final next = [...visible];
                        if (sel) {
                          if (!next.contains(role)) next.add(role);
                        } else {
                          next.remove(role);
                        }
                        widget.onRoles(next);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit, size: 15),
                label: const Text('Edit label'),
                onPressed: () => _editLabel(context, label, hi),
              ),
            ]),
          ),
      ]),
    );
  }

  Future<void> _editLabel(BuildContext context, String label, String hi) async {
    final l = TextEditingController(text: label);
    final h = TextEditingController(text: hi);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Edit label'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: l,
              decoration: const InputDecoration(labelText: 'Label (English)')),
          const SizedBox(height: 10),
          TextField(
              controller: h,
              decoration: const InputDecoration(labelText: 'Label (हिन्दी)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) widget.onLabel(l.text.trim(), h.text);
  }
}
