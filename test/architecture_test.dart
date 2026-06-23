// Architecture guard — PRINCIPLES #10 (feature-flow layering) + #12 (dumb client).
//
// The UI layer (lib/features/*/ui/) must never touch Supabase/the DB directly. DB access
// lives only in feature `data/` adapters behind a repository port.
//
// Console predates this rule: the panels below still query Supabase inline. They are
// GRANDFATHERED so the guard can land green and stop *new* violations today. The allowlist
// must only ever shrink — as each panel is refactored to Controller -> UseCase -> Port,
// delete its line. A NEW file under ui/ that touches Supabase fails the test. Goal: empty.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Known pre-rule violators. NEVER add to this list — only remove as panels are migrated.
const _grandfathered = <String>{
  'lib/features/dashboard/ui/dashboard_panel.dart',
  'lib/features/jobs/ui/jobs_panel.dart',
  'lib/features/home/ui/home_screen.dart',
  'lib/features/curation/ui/curation_panel.dart',
  'lib/features/config/ui/sections_panel.dart',
  'lib/features/ideas/ui/ideas_panel.dart',
  'lib/features/auth/ui/access_denied_screen.dart',
  'lib/features/relevance/ui/relevance_hub_panel.dart',
  'lib/features/stories/ui/stories_panel.dart',
  'lib/features/relevance/ui/relevance_review_screen.dart',
};

void main() {
  final forbidden = <RegExp>[
    RegExp(r'package:supabase_flutter'),
    RegExp(r'Supabase\.instance'),
    RegExp(r'supabaseClientProvider'),
    RegExp(r"\.from\('"), // Supabase table query: .from('questions')
    RegExp(r'\.rpc\('),
    RegExp(r'\.storage\.from\('),
  ];

  bool touchesDb(File f) {
    final text = f.readAsStringSync();
    return forbidden.any((p) => p.hasMatch(text));
  }

  String rel(File f) => f.path.replaceAll(r'\', '/');

  test('no NEW Supabase/DB access in lib/features/*/ui/', () {
    final newViolations = [
      for (final f in _uiDartFiles())
        if (touchesDb(f) && !_grandfathered.contains(rel(f))) rel(f),
    ];

    expect(
      newViolations,
      isEmpty,
      reason:
          'New UI file calls Supabase directly (PRINCIPLES #10/#12). '
          'Use a feature data/ adapter behind a repository port — do not add to the '
          'grandfather allowlist.\n${newViolations.join('\n')}',
    );
  });

  test('grandfather allowlist only shrinks (no stale entries)', () {
    final stillExist = _uiDartFiles().map(rel).toSet();
    final drained = _grandfathered.where((p) {
      final f = File(p);
      return !stillExist.contains(rel(f)) || !touchesDb(f);
    }).toList();

    expect(
      drained,
      isEmpty,
      reason:
          'These allowlist entries no longer violate (or are gone) — '
          'remove them from _grandfathered:\n${drained.join('\n')}',
    );
  });
}

Iterable<File> _uiDartFiles() sync* {
  final features = Directory('lib/features');
  if (!features.existsSync()) return;
  for (final entity in features.listSync()) {
    if (entity is! Directory) continue;
    final ui = Directory('${entity.path}/ui');
    if (!ui.existsSync()) continue;
    yield* ui
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
  }
}
