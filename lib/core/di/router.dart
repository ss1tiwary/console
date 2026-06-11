import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers.dart';
import '../../features/auth/ui/sign_in_screen.dart';
import '../../features/auth/ui/access_denied_screen.dart';
import '../../features/home/ui/home_screen.dart';

// ── RouterNotifier ────────────────────────────────────────────────────────────
//
// Redirect rules:
//   • Not signed in           → /sign-in
//   • Signed in, not editor   → /denied
//   • Editor on /sign-in or /denied → /
//   • Everything else: pass through

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen(authUserProvider, (_, _) => notifyListeners());
    _ref.listen(editorRoleProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final authAsync = _ref.read(authUserProvider);
    if (authAsync.isLoading) return null;

    final user = authAsync.valueOrNull;
    if (user == null) {
      return state.matchedLocation == '/sign-in' ? null : '/sign-in';
    }

    final roleAsync = _ref.read(editorRoleProvider);
    if (roleAsync.isLoading) return null;

    final role = roleAsync.valueOrNull;
    final isEditor = role == 'editor' || role == 'admin';

    if (!isEditor) {
      return state.matchedLocation == '/denied' ? null : '/denied';
    }

    if (state.matchedLocation == '/sign-in' ||
        state.matchedLocation == '/denied') {
      return '/';
    }
    return null;
  }
}

// ── Router provider ───────────────────────────────────────────────────────────

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(
        path: '/sign-in',
        builder: (_, _) => const SignInScreen(),
      ),
      GoRoute(
        path: '/denied',
        builder: (_, _) => const AccessDeniedScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (_, _) => const HomeScreen(),
      ),
    ],
  );
});
