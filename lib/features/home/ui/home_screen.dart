import 'package:flutter/material.dart';
import 'package:resolve_theme/resolve_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/console_logo.dart';
import '../../dashboard/ui/dashboard_panel.dart';
import '../../extraction/ui/extraction_panel.dart';
import '../../feedback/ui/feedback_panel.dart';
import '../../ideas/ui/ideas_panel.dart';
import '../../stories/ui/stories_panel.dart';
import '../../config/ui/sections_panel.dart';
import '../../curation/ui/curation_panel.dart';
import '../../jobs/ui/jobs_panel.dart';
import '../../relevance/ui/relevance_hub_panel.dart';

// ── Destinations ───────────────────────────────────────────────────────────────

enum _Dest {
  dashboard,
  extraction,
  jobs,
  feedback,
  relevance,
  ideas,
  stories,
  sections,
  curation;

  String get label => switch (this) {
        _Dest.dashboard => 'Dashboard',
        _Dest.extraction => 'Extraction',
        _Dest.jobs       => 'Jobs',
        _Dest.feedback => 'Feedback',
        _Dest.relevance => 'Relevance',
        _Dest.ideas => 'Ideas',
        _Dest.stories => 'Backlog',
        _Dest.sections => 'Sections',
        _Dest.curation => 'Curation',
      };

  IconData get icon => switch (this) {
        _Dest.dashboard => Icons.dashboard_outlined,
        _Dest.extraction => Icons.document_scanner_outlined,
        _Dest.jobs       => Icons.monitor_heart_outlined,
        _Dest.feedback => Icons.feedback_outlined,
        _Dest.relevance => Icons.rate_review_outlined,
        _Dest.ideas => Icons.lightbulb_outline,
        _Dest.stories => Icons.view_kanban_outlined,
        _Dest.sections => Icons.view_agenda_outlined,
        _Dest.curation => Icons.edit_note_outlined,
      };

  IconData get selectedIcon => switch (this) {
        _Dest.dashboard => Icons.dashboard,
        _Dest.extraction => Icons.document_scanner,
        _Dest.jobs       => Icons.monitor_heart,
        _Dest.feedback => Icons.feedback,
        _Dest.relevance => Icons.rate_review,
        _Dest.ideas => Icons.lightbulb,
        _Dest.stories => Icons.view_kanban,
        _Dest.sections => Icons.view_agenda,
        _Dest.curation => Icons.edit_note,
      };
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _Dest _current = _Dest.dashboard;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _onSelect(_Dest dest) => setState(() => _current = dest);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) => constraints.maxWidth >= 700
          ? _wideLayout()
          : _narrowLayout(),
    );
  }

  // ── Wide (web / Windows / landscape tablet) ───────────────────────────────

  Widget _wideLayout() {
    return Scaffold(
      backgroundColor: context.pal.grey50,
      body: Row(
        children: [
          _SidebarContainer(current: _current, onSelect: _onSelect),
          Expanded(child: _panel()),
        ],
      ),
    );
  }

  // ── Narrow (Android / portrait phone) ─────────────────────────────────────

  Widget _narrowLayout() {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.pal.grey50,
      appBar: _narrowAppBar(),
      drawer: Drawer(
        width: 260,
        backgroundColor: context.pal.white,
        child: _SidebarContent(
          current: _current,
          onSelect: (d) {
            _onSelect(d);
            _scaffoldKey.currentState?.closeDrawer();
          },
        ),
      ),
      body: SafeArea(top: false, child: _panel()),
    );
  }

  PreferredSizeWidget _narrowAppBar() {
    return AppBar(
      backgroundColor: context.pal.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      title: const ConsoleLogo(size: 32),
      iconTheme: IconThemeData(color: context.pal.grey600),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(height: 0.5, color: context.pal.grey200),
      ),
    );
  }

  // ── Panel router ───────────────────────────────────────────────────────────

  Widget _panel() => switch (_current) {
        _Dest.dashboard  => const DashboardPanel(),
        _Dest.extraction => const ExtractionPanel(),
        _Dest.jobs       => const JobsPanel(),
        _Dest.feedback   => const FeedbackPanel(),
        _Dest.relevance  => const RelevanceHubPanel(),
        _Dest.ideas      => const IdeasPanel(),
        _Dest.stories    => const StoriesPanel(),
        _Dest.sections   => const SectionsPanel(),
        _Dest.curation   => const CurationPanel(),
      };
}

// ── Sidebar container (desktop) ────────────────────────────────────────────────

class _SidebarContainer extends StatelessWidget {
  final _Dest current;
  final ValueChanged<_Dest> onSelect;
  const _SidebarContainer(
      {required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: context.pal.white,
        border: Border(right: BorderSide(color: context.pal.grey200)),
      ),
      child: _SidebarContent(current: current, onSelect: onSelect),
    );
  }
}

// ── Sidebar content (shared between fixed sidebar and Drawer) ──────────────────

class _SidebarContent extends ConsumerWidget {
  final _Dest current;
  final ValueChanged<_Dest> onSelect;
  const _SidebarContent(
      {required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = Supabase.instance.client.auth.currentUser;
    final displayName = user?.userMetadata?['full_name'] as String? ??
        user?.userMetadata?['name'] as String?;
    final email = user?.email ?? '';
    final avatarUrl = user?.userMetadata?['avatar_url'] as String?;

    return SafeArea(
      top: false,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header. Align keeps the square logo at its intrinsic size — the parent
        // Column is CrossAxisAlignment.stretch, which would otherwise force the
        // logo to full drawer width and BoxFit.cover would crop it.
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConsoleLogo(size: 36),
          ),
        ),
        Divider(height: 1, color: context.pal.grey100),
        const SizedBox(height: 8),
        // Section label
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Text(
            'MENU',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: context.pal.grey400,
            ),
          ),
        ),
        // Nav items
        for (final dest in _Dest.values)
          _NavItem(
            dest: dest,
            selected: current == dest,
            onTap: () => onSelect(dest),
          ),
        const Spacer(),
        Divider(height: 1, color: context.pal.grey100),
        // User footer
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          child: Row(children: [
            _Avatar(url: avatarUrl, name: displayName ?? email),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (displayName != null)
                    Text(
                      displayName,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.pal.grey900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    email,
                    style: TextStyle(
                        fontSize: 11, color: context.pal.grey400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(_themeIcon(ref.watch(themeModeProvider)), size: 16),
              tooltip: 'Appearance',
              color: context.pal.grey400,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => _cycleThemeMode(ref),
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, size: 16),
              tooltip: 'Sign out',
              color: context.pal.grey400,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () =>
                  Supabase.instance.client.auth.signOut(),
            ),
          ]),
        ),
      ],
    ));
  }
}

// ── Theme-mode toggle (cycles light → dark → system) ───────────────────────────

IconData _themeIcon(ThemeMode m) => switch (m) {
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.system => Icons.brightness_auto_outlined,
    };

void _cycleThemeMode(WidgetRef ref) {
  final current = ref.read(themeModeProvider);
  final next = switch (current) {
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.system,
    ThemeMode.system => ThemeMode.light,
  };
  ref.read(themeModeProvider.notifier).set(next);
}

// ── Nav item ───────────────────────────────────────────────────────────────────

class _NavItem extends StatefulWidget {
  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem(
      {required this.dest, required this.selected, required this.onTap});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: sel
                ? context.pal.indigo
                : _hovered
                    ? context.pal.grey100
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(
              sel ? widget.dest.selectedIcon : widget.dest.icon,
              size: 18,
              color: sel ? context.pal.white : context.pal.grey600,
            ),
            const SizedBox(width: 10),
            Text(
              widget.dest.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    sel ? FontWeight.w600 : FontWeight.w400,
                color: sel ? context.pal.white : context.pal.grey700,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Avatar ─────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  const _Avatar({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundImage: NetworkImage(url!),
        backgroundColor: context.pal.grey100,
      );
    }
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 16,
      backgroundColor: context.pal.indigoLight,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: context.pal.indigo,
        ),
      ),
    );
  }
}
