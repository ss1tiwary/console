import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qbank_contracts/qbank_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/extraction/data/supabase_qbank_api.dart';
import '../../features/extraction/data/extraction_repository.dart';
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

final qbankApiProvider = Provider<QbankApi>(
  (ref) => SupabaseQbankApi(ref.watch(supabaseClientProvider)),
);

final extractionRepositoryProvider = Provider<ExtractionRepository>(
  (ref) => ExtractionRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(qbankApiProvider),
  ),
);
