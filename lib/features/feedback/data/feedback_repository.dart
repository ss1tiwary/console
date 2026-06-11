import 'package:supabase_flutter/supabase_flutter.dart';
import 'feedback_model.dart';

class FeedbackRepository {
  FeedbackRepository(this._supabase);
  final SupabaseClient _supabase;

  Future<List<AdminFeedbackItem>> getAllFeedback({String? filterStatus}) async {
    const cols = 'id, target_type, target_id, target_label, user_id, '
        'feedback_type, note, status, created_at';
    final rows = filterStatus != null
        ? await _supabase
            .from('content_feedback')
            .select(cols)
            .eq('status', filterStatus)
            .order('created_at', ascending: false)
        : await _supabase
            .from('content_feedback')
            .select(cols)
            .order('status', ascending: true)
            .order('created_at', ascending: false);
    return rows.map((r) => AdminFeedbackItem(
          id: r['id'] as String,
          targetType:
              ContentTargetType.fromValue(r['target_type'] as String),
          targetId: r['target_id'] as String,
          targetLabel: (r['target_label'] as String?) ?? '(untitled)',
          userId: r['user_id'] as String,
          feedbackType:
              FeedbackType.fromValue(r['feedback_type'] as String),
          note: r['note'] as String?,
          status: r['status'] as String? ?? 'pending',
          createdAt: DateTime.parse(r['created_at'] as String),
        )).toList();
  }

  Future<void> updateStatus(String feedbackId, String status) async {
    await _supabase
        .from('content_feedback')
        .update({'status': status})
        .eq('id', feedbackId);
  }

  Future<void> deleteById(String feedbackId) async {
    await _supabase
        .from('content_feedback')
        .delete()
        .eq('id', feedbackId);
  }
}
