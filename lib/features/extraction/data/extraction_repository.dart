import 'dart:math';
import 'dart:typed_data';

import 'package:qbank_contracts/qbank_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExtractionRepository {
  final SupabaseClient _client;
  final QbankApi _api;

  const ExtractionRepository(this._client, this._api);

  Future<String?> uploadAndCreateJob({
    required String examSlug,
    required int year,
    required String paper,
    required String paperSlug,
    required String paperSet,
    required String fileName,
    required String? fileExtension,
    required Uint8List bytes,
    required bool isImage,
    required String mode,
    required int pageScope,
    required String layout,
    required bool wantHindi,
    required int expectedCount,
    required int startPage,
    required int endPage,
    required int pageStep,
    required int hindiOffset,
    required String modelProvider,
    required String modelName,
    required String? credentialId,
  }) async {
    final rand = Random().nextInt(1 << 32).toRadixString(16);
    final path = '$year/${paperSlug}_${rand}_$fileName';
    final ext = fileExtension?.toLowerCase();
    final contentType = isImage
        ? (ext == 'png' ? 'image/png' : 'image/jpeg')
        : 'application/pdf';

    await _client.storage
        .from('pyq-uploads')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );

    return _api.createExtractionJob(
      QbankCreateExtractionJobRequestDto(
        examSlug: examSlug,
        year: year,
        paperSlug: paperSlug,
        params: {
          'paper': paper,
          'paper_set': paperSet,
          'layout': layout,
          'mode': mode,
          'input_type': isImage ? 'image' : 'pdf',
          if (pageScope > 0) 'page_scope': pageScope,
          'pdf_path': path,
          'pdf_name': fileName,
          'want_hindi': wantHindi,
          'expected_count': expectedCount,
          'start_page': startPage,
          if (endPage > 0) 'end_page': endPage,
          'page_step': pageStep,
          'hindi_offset': hindiOffset,
          'model_provider': modelProvider,
          'model': modelName,
          if (credentialId != null && credentialId.isNotEmpty)
            'credential_id': credentialId,
        },
      ),
    );
  }
}
