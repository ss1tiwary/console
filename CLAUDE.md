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
    app.dart                  # ConsoleApp (MaterialApp.router, ConsoleTheme)
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
      ideas/                    # (Phase 3) moved from pibrief
```

## Key invariants

- **Editor gate is the only door.** `editorRoleProvider` fetches `users.role` from Supabase
  after sign-in. If `role` is not `'editor'` or `'admin'`, the router hard-redirects to
  `/denied`. This is the one place to change the gate — don't add a second.
- **`role` is read-only.** Console reads `users.role`; it never writes it. Setting editor
  access is a Supabase dashboard / service-role operation.
- **Secrets:** `service_role` key is never in this app. Same rule as PIBrief.
- **`qbank_ui` renderer is shared.** Import from `package:qbank_ui/qbank_ui.dart`; never
  copy widget code here. `ConsoleTheme.light` registers `QbankTheme.standard` so the renderer
  works out of the box.
- **Platform targets: web + Windows only.** No Android/iOS. `file_picker` compileSdk 36
  constraint never applies here.
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
| App | Flutter (web + Windows) · Riverpod · GoRouter |
| Auth | Supabase magic-link OTP (same project as platform) |
| DB | Direct Supabase queries — no local drift cache needed for admin tools |
| Renderer | `packages/qbank_ui` (shared, path dep) |
| File input | `file_picker` (PDF + image) |
