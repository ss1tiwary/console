import 'package:qbank_contracts/qbank_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseQbankApi implements QbankApi {
  final SupabaseClient _client;

  const SupabaseQbankApi(this._client);

  @override
  Future<QbankQuestionDto?> getQuestion(
    String questionId, {
    String language = 'en',
  }) async {
    final data = await _client.rpc(
      'qbank_get_question_v1',
      params: {'p_question_id': questionId, 'p_language': language},
    );
    final map = _map(data);
    return map == null ? null : QbankQuestionDto.fromJson(map);
  }

  @override
  Future<QbankQuestionSearchResponseDto> searchQuestions(
    QbankQuestionSearchRequestDto request,
  ) async {
    final data = await _client.rpc(
      'qbank_search_questions_v1',
      params: {'p_request': request.toJson()},
    );
    return QbankQuestionSearchResponseDto.fromJson(_map(data) ?? const {});
  }

  @override
  Future<QbankPyqFacetsDto> getPyqFacets(String examSlug) async {
    final data = await _client.rpc(
      'qbank_get_pyq_facets_v1',
      params: {'p_exam_slug': examSlug},
    );
    return QbankPyqFacetsDto.fromJson(_map(data) ?? const {});
  }

  @override
  Future<QbankQuizSessionDto?> getQuizSession(String sessionId) async {
    final data = await _client.rpc(
      'qbank_get_quiz_session_v1',
      params: {'p_session_id': sessionId},
    );
    final map = _map(data);
    return map == null ? null : QbankQuizSessionDto.fromJson(map);
  }

  @override
  Future<List<QbankQuizSessionDto>> recentQuizSessions(
    QbankRecentQuizSessionsRequestDto request,
  ) async {
    final data = await _client.rpc(
      'qbank_recent_quiz_sessions_v1',
      params: {'p_request': request.toJson()},
    );
    return [
      for (final item in _list(_map(data)?['sessions'] ?? data))
        if (item is Map)
          QbankQuizSessionDto.fromJson(Map<String, Object?>.from(item)),
    ];
  }

  @override
  Future<List<QbankQuestionDto>> smartPracticeQuestions(
    QbankSmartPracticeRequestDto request,
  ) async {
    final data = await _client.rpc(
      'qbank_smart_practice_questions_v1',
      params: {'p_request': request.toJson()},
    );
    return [
      for (final item in _list(_map(data)?['questions'] ?? data))
        if (item is Map)
          QbankQuestionDto.fromJson(Map<String, Object?>.from(item)),
    ];
  }

  @override
  Future<QbankSubmitQuizResultResponseDto?> submitQuizResult(
    QbankSubmitQuizResultRequestDto request,
  ) async {
    final data = await _client.rpc(
      'qbank_submit_quiz_result_v1',
      params: {'p_payload': request.toJson()},
    );
    final map = _map(data);
    return map == null ? null : QbankSubmitQuizResultResponseDto.fromJson(map);
  }

  @override
  Future<List<QbankExtractionJobDto>> listExtractionJobs() async {
    final data = await _client.rpc('qbank_list_extraction_jobs_v1');
    return [
      for (final item in _list(_map(data)?['jobs'] ?? data))
        if (item is Map)
          QbankExtractionJobDto.fromJson(Map<String, Object?>.from(item)),
    ];
  }

  @override
  Future<List<QbankExtractionCredentialDto>> listExtractionCredentials() async {
    final data = await _client.rpc('qbank_list_extraction_credentials_v1');
    return [
      for (final item in _list(_map(data)?['credentials'] ?? data))
        if (item is Map)
          QbankExtractionCredentialDto.fromJson(
            Map<String, Object?>.from(item),
          ),
    ];
  }

  @override
  Future<String?> saveExtractionCredential(
    QbankSaveExtractionCredentialRequestDto request,
  ) async {
    final data = await _client.rpc(
      'qbank_save_extraction_credential_v1',
      params: {'p_payload': request.toJson()},
    );
    return _map(data)?['credentialId']?.toString();
  }

  @override
  Future<String?> createExtractionJob(
    QbankCreateExtractionJobRequestDto request,
  ) async {
    final data = await _client.rpc(
      'qbank_create_extraction_job_v1',
      params: {'p_payload': request.toJson()},
    );
    return _map(data)?['jobId']?.toString();
  }

  @override
  Future<String?> resumeExtractionJob(
    QbankResumeExtractionJobRequestDto request,
  ) async {
    final data = await _client.rpc(
      'qbank_resume_extraction_job_v1',
      params: {'p_job_id': request.jobId, 'p_action': request.action},
    );
    return _map(data)?['jobId']?.toString();
  }

  @override
  Future<void> deleteJob(String jobId) async {
    await _client.rpc('qbank_delete_job_v1', params: {'p_job_id': jobId});
  }

  @override
  Future<List<QbankQuestionDto>> listDraftQuestions(
    QbankDraftQuestionsRequestDto request,
  ) async {
    final data = await _client.rpc(
      'qbank_list_draft_questions_v1',
      params: {'p_request': request.toJson()},
    );
    return [
      for (final item in _list(_map(data)?['questions'] ?? data))
        if (item is Map)
          QbankQuestionDto.fromJson(Map<String, Object?>.from(item)),
    ];
  }

  @override
  Future<void> reviewQuestion(QbankReviewQuestionRequestDto request) async {
    await _client.rpc(
      'qbank_review_question_v1',
      params: {'p_payload': request.toJson()},
    );
  }

  @override
  Future<List<int>> getMissingQnos(QbankMissingQnosRequestDto request) async {
    final data = await _client.rpc(
      'qbank_get_missing_qnos_v1',
      params: {'p_request': request.toJson()},
    );
    return _intList(_map(data)?['missingQnos'] ?? data);
  }

  @override
  Future<List<QbankExamOptionDto>> examOptions() async {
    final data = await _client.rpc('qbank_exam_options_v1');
    return [
      for (final item in _list(_map(data)?['exams'] ?? data))
        if (item is Map)
          QbankExamOptionDto.fromJson(Map<String, Object?>.from(item)),
    ];
  }

  Map<String, Object?>? _map(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : null;

  List<Object?> _list(Object? value) =>
      value is List ? value.cast<Object?>() : const [];

  List<int> _intList(Object? value) {
    final out = <int>[];
    for (final item in _list(value)) {
      final parsed = item is int
          ? item
          : item is num
          ? item.toInt()
          : item is String
          ? int.tryParse(item)
          : null;
      if (parsed != null) out.add(parsed);
    }
    return out;
  }
}
