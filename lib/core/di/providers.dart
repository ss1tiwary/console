import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/feedback/data/feedback_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (_) => Supabase.instance.client,
);

/// Current Supabase auth user. Null when signed out.
final authUserProvider = StreamProvider<User?>((ref) {
  return ref
      .watch(supabaseClientProvider)
      .auth
      .onAuthStateChange
      .map((event) => event.session?.user);
});

/// Role fetched from public.users for the signed-in user.
/// Returns null while loading / not signed in, empty string if row missing.
/// role/tier are server-authoritative — client reads only (PRINCIPLES security).
final editorRoleProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return null;

  final row = await ref
      .read(supabaseClientProvider)
      .from('users')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();
  return row?['role'] as String?;
});

final isEditorProvider = Provider<bool>((ref) {
  final role = ref.watch(editorRoleProvider).valueOrNull;
  return role == 'editor' || role == 'admin';
});

final feedbackRepositoryProvider = Provider<FeedbackRepository>(
  (ref) => FeedbackRepository(ref.watch(supabaseClientProvider)),
);
