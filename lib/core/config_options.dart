import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'di/providers.dart';

/// Platform config dropdown/enum values, pulled from the shared `config_options`
/// table (question-bank migration 013, seeded by 014). Adding an option = INSERT
/// a row there; no app release. Falls back to a built-in default only when the
/// table is empty/unreachable (e.g. pre-seed), so the UI is never broken.
///
/// Read with `ref.watch(configOptionsProvider('question_subject'))`.
final configOptionsProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, category) async {
  try {
    final rows = await ref
        .watch(supabaseClientProvider)
        .from('config_options')
        .select('value, sort_order')
        .eq('category', category)
        .eq('scope', 'global')
        .eq('active', true)
        .order('sort_order');
    final list =
        (rows as List).map((r) => (r as Map)['value'] as String).toList();
    if (list.isNotEmpty) return list;
  } catch (_) {
    // fall through to the built-in default
  }
  return defaultConfigOptions[category] ?? const <String>[];
});

/// Built-in fallback lists — only used if the DB table can't be read. The table
/// is the source of truth; keep these minimal and in sync with the 014 seed.
const defaultConfigOptions = <String, List<String>>{
  'question_subject': [
    'Ancient History', 'Medieval History', 'Modern History', 'Art and Culture',
    'Geography', 'Polity', 'Governance', 'Economy', 'International Relations',
    'Science and Technology', 'Environment and Ecology', 'Society',
    'Internal Security', 'Ethics', 'Disaster Management', 'Current Affairs',
  ],
  'paper_set': ['A', 'B', 'C', 'D'],
};
