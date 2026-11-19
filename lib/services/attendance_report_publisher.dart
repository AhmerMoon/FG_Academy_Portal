import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceReportPublisher {
  AttendanceReportPublisher([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String> publish({
    required String batchId,
    required Uint8List pngBytes,
  }) async {
    final batch = await _client
        .from('batches')
        .select('attendance_report_token')
        .eq('id', batchId)
        .single();
    final token = batch['attendance_report_token']?.toString();
    if (token == null || token.isEmpty) {
      throw StateError('Attendance report link is not configured.');
    }

    final path = '$token/latest.png';
    await _client.storage
        .from('attendance-reports')
        .uploadBinary(
          path,
          pngBytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/png',
            cacheControl: '60',
          ),
        );

    final baseUrl = _client.storage
        .from('attendance-reports')
        .getPublicUrl(path);
    return '$baseUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }
}
