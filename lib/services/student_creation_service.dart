import 'package:supabase_flutter/supabase_flutter.dart';

class StudentCreationService {
  StudentCreationService([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<void> create({
    required String name,
    required String batchId,
    required String groupCode,
    String? contact,
  }) async {
    try {
      await _client.rpc(
        'portal_add_student_with_contact',
        params: {
          'p_name': name,
          'p_batch_id': batchId,
          'p_group_code': groupCode,
          'p_contact': contact,
        },
      );
    } on PostgrestException catch (error) {
      final missingFunction =
          error.code == 'PGRST202' ||
          error.code == '42883' ||
          error.message.contains('portal_add_student_with_contact');
      if (!missingFunction) rethrow;

      await _client.rpc(
        'portal_add_student_simple',
        params: {
          'p_name': name,
          'p_batch_id': batchId,
          'p_group_code': groupCode,
        },
      );
    }
  }
}
