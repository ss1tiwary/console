import 'package:flutter/material.dart';
import 'package:resolve_theme/resolve_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/spacing.dart';
import '../../../core/di/providers.dart';

/// Editorial curation (decision 0004). Search a post, then add editorial notes
/// (shown to readers) and field overrides (coalesce over the AI value). Writes
/// `annotations` / `field_overrides` under is_editor() RLS. Polymorphic by design;
/// this v1 surface targets posts.

final _searchProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, q) async {
  if (q.trim().length < 2) return const [];
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('posts')
      .select('id, title, relevance_score')
      .ilike('title', '%${q.trim()}%')
      .order('published_at', ascending: false)
      .limit(25);
  return (rows as List).map((r) => (r as Map).cast<String, dynamic>()).toList();
});

final _editorialProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, postId) async {
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('annotations')
      .select('id, kind, points')
      .eq('target_type', 'post')
      .eq('target_id', postId)
      .eq('visibility', 'editorial')
      .eq('status', 'active')
      .order('created_at');
  return (rows as List).map((r) => (r as Map).cast<String, dynamic>()).toList();
});

final _overridesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, postId) async {
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('field_overrides')
      .select('id, field, value')
      .eq('target_type', 'post')
      .eq('target_id', postId)
      .eq('status', 'active')
      .order('field');
  return (rows as List).map((r) => (r as Map).cast<String, dynamic>()).toList();
});

class CurationPanel extends ConsumerStatefulWidget {
  const CurationPanel({super.key});

  @override
  ConsumerState<CurationPanel> createState() => _CurationPanelState();
}

class _CurationPanelState extends ConsumerState<CurationPanel> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = ref.watch(_searchProvider(_q));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: context.pal.white,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Curation',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search posts by title…',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              filled: true,
              fillColor: context.pal.grey100,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ]),
      ),
      Expanded(
        child: results.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (rows) => rows.isEmpty
              ? Center(
                  child: Text(
                      _q.trim().length < 2
                          ? 'Type to search posts'
                          : 'No posts match',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: context.pal.grey400)))
              : ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return ListTile(
                      title: Text(r['title'] as String,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('relevance ${r['relevance_score']}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: context.pal.grey400)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(r['id'] as String, r['title'] as String),
                    );
                  },
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: context.pal.grey100),
                ),
        ),
      ),
    ]);
  }

  void _open(String postId, String title) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.pal.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _CurationSheet(postId: postId, title: title),
    );
  }
}

class _CurationSheet extends ConsumerWidget {
  final String postId;
  final String title;
  const _CurationSheet({required this.postId, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notes = ref.watch(_editorialProvider(postId)).valueOrNull ?? const [];
    final overrides = ref.watch(_overridesProvider(postId)).valueOrNull ?? const [];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: AppSpacing.pagePadding,
        right: AppSpacing.pagePadding,
        top: 18,
      ),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              _header(theme, "Editor's notes"),
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                      '• ${((n['points'] as List?) ?? const []).join(' · ')}',
                      style: theme.textTheme.bodyMedium),
                ),
              TextButton.icon(
                onPressed: () => _addNote(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add editorial note'),
              ),
              const SizedBox(height: 16),
              _header(theme, 'Field overrides'),
              for (final o in overrides)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('${o['field']} → ${o['value']}',
                      style: theme.textTheme.bodyMedium),
                ),
              TextButton.icon(
                onPressed: () => _addOverride(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add / update override'),
              ),
            ]),
      ),
    );
  }

  Widget _header(ThemeData theme, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1, fontWeight: FontWeight.w700)),
      );

  Future<void> _addNote(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final txt = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Editorial note'),
        content: TextField(
            controller: c,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(
                hintText: 'One point per line…', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (txt == null) return;
    final pts =
        txt.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (pts.isEmpty) return;
    final sb = ref.read(supabaseClientProvider);
    await sb.from('annotations').insert({
      'target_type': 'post',
      'target_id': postId,
      'author_id': sb.auth.currentUser?.id,
      'kind': 'note',
      'points': pts,
      'visibility': 'editorial',
    });
    ref.invalidate(_editorialProvider(postId));
  }

  Future<void> _addOverride(BuildContext context, WidgetRef ref) async {
    final fieldC = TextEditingController();
    final valC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Field override'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: fieldC,
              decoration: const InputDecoration(
                  labelText: 'Field (e.g. relevance, summary)')),
          const SizedBox(height: 10),
          TextField(
              controller: valC,
              decoration: const InputDecoration(labelText: 'Value')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || fieldC.text.trim().isEmpty) return;
    // Store numeric values as numbers, else as a string (both valid jsonb).
    final raw = valC.text.trim();
    final dynamic value = num.tryParse(raw) ?? raw;
    final sb = ref.read(supabaseClientProvider);
    await sb.from('field_overrides').upsert({
      'target_type': 'post',
      'target_id': postId,
      'field': fieldC.text.trim(),
      'value': value,
      'edited_by': sb.auth.currentUser?.id,
    }, onConflict: 'target_type,target_id,field');
    ref.invalidate(_overridesProvider(postId));
  }
}
