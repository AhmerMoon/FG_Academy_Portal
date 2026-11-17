import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/printable_request.dart';

class PrintablesService {
  final SupabaseClient _client;
  static const bucket = 'test-printables';
  PrintablesService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<PrintableRequest>> fetchRequests() async {
    final rows = await _client
        .from('printable_requests')
        .select()
        .neq('status', 'uploading')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('test_date')
        .order('created_at');
    return rows.map(PrintableRequest.fromJson).toList();
  }

  Future<List<Map<String, dynamic>>> fetchChoices() async {
    final result = await _client.rpc('printable_submission_choices');
    return (result as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> submit({
    required String batchId,
    required String subjectCode,
    required String title,
    required DateTime testDate,
    required int copies,
    required String notes,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final reservation = await _upload(
      batchId: batchId,
      subjectCode: subjectCode,
      title: title,
      testDate: testDate,
      copies: copies,
      notes: notes,
      fileName: fileName,
      bytes: bytes,
    );
    await _client.rpc(
      'finalize_printable_request',
      params: {'p_request_id': reservation['id']},
    );
  }

  Future<Map<String, dynamic>> _upload({
    required String batchId,
    required String subjectCode,
    required String title,
    required DateTime testDate,
    required int copies,
    required String notes,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final error = validatePrintableFile(fileName, bytes.length);
    if (error != null) throw ArgumentError(error);
    final params = <String, dynamic>{
      'p_batch_id': batchId,
      'p_subject_code': subjectCode,
      'p_title': title.trim(),
      'p_test_date': testDate.toIso8601String().split('T').first,
      'p_copies': copies,
      'p_notes': notes.trim(),
      'p_file_name': fileName,
      'p_file_size': bytes.length,
    };
    final reservation = Map<String, dynamic>.from(
      await _client.rpc('reserve_printable_request', params: params) as Map,
    );
    await _client.storage
        .from(bucket)
        .uploadBinary(
          reservation['file_path'] as String,
          bytes,
          fileOptions: FileOptions(
            contentType: printableMimeType(fileName),
            upsert: false,
          ),
        );
    return reservation;
  }

  /// A replacement uploads separately. The server switches files only after
  /// upload succeeds, so a failed upload leaves the original request intact.
  Future<bool> updateRequest(
    PrintableRequest request, {
    required String batchId,
    required String subjectCode,
    required DateTime testDate,
    required int copies,
    required String fileName,
    Uint8List? bytes,
  }) async {
    Map<String, dynamic>? replacement;
    if (bytes != null) {
      replacement = await _upload(
        batchId: batchId,
        subjectCode: subjectCode,
        title: fileName.length > 120 ? fileName.substring(0, 120) : fileName,
        testDate: testDate,
        copies: copies,
        notes: request.notes,
        fileName: fileName,
        bytes: bytes,
      );
    }
    await _client.rpc(
      'edit_printable_request',
      params: {
        'p_request_id': request.id,
        'p_batch_id': batchId,
        'p_subject_code': subjectCode,
        'p_test_date': testDate.toIso8601String().split('T').first,
        'p_copies': copies,
        'p_upload_id': replacement?['id'],
      },
    );
    if (replacement != null) {
      try {
        await deleteRequests(requestId: replacement['id'] as String);
      } catch (_) {
        // The edit already committed. Report cleanup separately, never claim
        // that the edit failed or delete the newly selected attachment.
        return false;
      }
    }
    return true;
  }

  Future<int> deleteRequests({String? requestId, bool all = false}) async {
    final result = await _client.rpc(
      'prepare_printable_delete',
      params: {'p_request_id': requestId, 'p_all': all},
    );
    final rows = (result as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (var offset = 0; offset < rows.length; offset += 100) {
      final end = offset + 100 < rows.length ? offset + 100 : rows.length;
      final batch = rows.sublist(offset, end);
      await _client.storage
          .from(bucket)
          .remove(batch.map((row) => row['file_path'] as String).toList());
      await _client.rpc(
        'finish_printable_delete',
        params: {'p_ids': batch.map((row) => row['id'] as String).toList()},
      );
    }
    return rows.length;
  }

  Future<Uint8List> download(PrintableRequest request) async {
    if (request.isExpired) {
      throw StateError('This printable has expired. Refresh the list.');
    }
    return _client.storage.from(bucket).download(request.filePath);
  }

  Future<void> setPrinted(PrintableRequest request, bool printed) async {
    await _client.rpc(
      'admin_set_printable_printed',
      params: {'p_request_id': request.id, 'p_printed': printed},
    );
  }
}
