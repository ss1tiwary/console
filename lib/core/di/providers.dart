import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/feedback/data/feedback_repository.dart';

// Auth state, editor gate, and auth adapter come from the shared identity
// kernel. Console's router and UI read these directly.
export 'package:identity/identity.dart'
    show
        authStateProvider,
        isEditorProvider,
        isLoggedInProvider,
        authAdapterProvider,
        authConfigProvider,
        AppAuthState,
        AppAuthLoading,
        AppAuthAuthenticated,
        AppAuthGuest,
        AppAuthUser;

final supabaseClientProvider = Provider<SupabaseClient>(
  (_) => Supabase.instance.client,
);

final feedbackRepositoryProvider = Provider<FeedbackRepository>(
  (ref) => FeedbackRepository(ref.watch(supabaseClientProvider)),
);
