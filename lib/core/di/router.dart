import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:identity/identity.dart';
import '../../features/auth/ui/access_denied_screen.dart';
import '../../features/home/ui/home_screen.dart';

// ── RouterNotifier ────────────────────────────────────────────────────────────
//
// Redirect rules:
//   • Auth stream loading              → hold (avoid flicker)
//   • AppAuthGuest (no session)        → /landing (shared Google sign-in)
//   • Authenticated, not editor        → /denied
//   • Editor on /landing|/phone|/otp|/denied → /

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen(authStateProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final authAsync = _ref.read(authStateProvider);
    if (authAsync.isLoading) return null;

    final authState = authAsync.valueOrNull;
    final loc = state.matchedLocation;

    if (authState is! AppAuthAuthenticated) {
      final onAuthFlow = loc == IdentityRoutes.landing ||
          loc == IdentityRoutes.phone ||
          loc.startsWith(IdentityRoutes.otp);
      return onAuthFlow ? null : IdentityRoutes.landing;
    }

    // Authenticated — check editor gate.
    final isEditor = _ref.read(isEditorProvider);
    if (!isEditor) {
      return loc == '/denied' ? null : '/denied';
    }

    final onAuthOrDenied = loc == IdentityRoutes.landing ||
        loc == IdentityRoutes.phone ||
        loc.startsWith(IdentityRoutes.otp) ||
        loc == '/denied';
    if (onAuthOrDenied) return '/';

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
      // Shared auth flow — landing (Google sign-in), phone, OTP.
      ...identityAuthRoutes(),

      // Editor-gate denial screen (Console-specific).
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
