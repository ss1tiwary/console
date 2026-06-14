# Resolve Console — Agent Entry Point

**Console is the internal admin surface for the whole Resolve platform** — not a feature of
PIBrief. See [`../ECOSYSTEM.md`](../ECOSYSTEM.md) for the full platform map.

It composes **P3 Question Bank** (extraction, review) and **P4 Content** (feedback, ideas)
admin operations over the shared Supabase backend. All writes are enforced server-side by RLS;
the app only reads role, never sets it.

## Architecture at a glance

```
console/
  lib/
    main.dart                 # Supabase init, ProviderScope
    app.dart                  # ConsoleApp (MaterialApp.router, ResolveTheme light/dark + themeMode)
    core/
      theme/console_theme.dart  # ThemeData + QbankTheme.standard extension
      di/providers.dart         # supabaseClient, authUser, editorRole, isEditor
      di/router.dart            # GoRouter with editor-gate redirect
    features/
      auth/ui/                  # SignInScreen (magic link), AccessDeniedScreen
      home/ui/home_screen.dart  # NavigationRail shell — filled in Phase 3
      extraction/               # (Phase 3) PYQ extraction + Phase 4 preview
      feedback/                 # (Phase 3) moved from pibrief
      relevance/                # (Phase 3) moved from pibrief
      ideas/                    # raw scratchpad (ideas table)
      stories/                  # build-ready backlog (stories table); promote idea -> story
  supabase/migrations/          # console-owned admin tables: 001_ideas, 002_stories
```

## Key invariants

- **Editor gate is the only door.** `editorRoleProvider` fetches `users.role` from Supabase
  after sign-in. If `role` is not `'editor'` or `'admin'`, the router hard-redirects to
  `/denied`. This is the one place to change the gate — don't add a second.
- **`role` is read-only.** Console reads `users.role`; it never writes it. Setting editor
  access is a Supabase dashboard / service-role operation.
- **Secrets:** `service_role` key is never in this app. Same rule as PIBrief.
- **Console owns the section-registry config** (root `decisions/0003`). Surfaces render config- and
  role-driven; the Console is where an editor toggles/relabels/reorders a surface's sections (a
  `config_options` write) and sets `visible_to` roles — no rebuild. Visibility is config (UX);
  authority is RLS (security).
- **Console owns its admin-tooling tables.** `supabase/migrations/` here is the source of
  truth for `ideas` (raw scratchpad) and `stories` (build-ready backlog) — both are Console
  concerns, not the PIBrief content pillar (ideas was moved out of pibrief). The backlog flow
  is **idea → story**: a story links its origin via `stories.source_idea_id`, and promoting an
  idea flips its status to `'promoted'` so it leaves the raw list. Same RLS model as the rest:
  `authenticated` full access, gated to editor/admin in the UI.
- **`qbank_ui` renderer is shared.** Import from `package:qbank_ui/qbank_ui.dart`; never
  copy widget code here. `ResolveTheme` (from `package:resolve_theme`) registers a brand-aware
  `QbankTheme` for light + dark, so the renderer follows the active theme out of the box.
- **Colour lives in `resolve_theme`, not here.** There is no local palette — the old
  `core/palette.dart` and `core/theme/console_theme.dart` are deleted. Read colours via
  `Theme.of(context).colorScheme.*` and `context.appColors.*`; `context.pal.*` is a legacy
  migration accessor. Rebrand/dark-tuning happens in `packages/resolve_theme` only.
- **Platform target: Android today** (builds + installs as an APK). Web + Windows are **future
  dev** (planned, not the current surface). Because Android is live, the `file_picker` compileSdk
  36 constraint **applies** — keep it set in `android/app/build.gradle.kts`.
- **Docs are part of the change** — any new feature updates this file or `../ECOSYSTEM.md` in
  the same commit (`../DOCUMENTATION.md` §10).

## Rules inherited from PRINCIPLES.md

Read [`../PRINCIPLES.md`](../PRINCIPLES.md) before writing any code. The most relevant rules:
- Single Source of Truth: shared data lives in the pillar, not copied here.
- Security logic must be API-enforced (RLS), even if the UI reflects it.
- Read code before writing. Don't invent; discover.
- Docs describe decisions, not mechanics.

## Stack

| Layer | Choice |
|---|---|
| App | Flutter (Android today; web + Windows planned) · Riverpod · GoRouter |
| Auth | Supabase magic-link OTP (same project as platform) |
| DB | Direct Supabase queries — no local drift cache needed for admin tools |
| Renderer | `packages/qbank_ui` (shared, path dep) |
| File input | `file_picker` (PDF + image) |
