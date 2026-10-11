import 'package:hive_flutter/hive_flutter.dart';

class AwardDraftStore {
  static const String _prefix = 'fg_award_draft_v1:';

  static String _key(String userId, String testId) {
    return '$_prefix$userId:$testId';
  }

  static Map<String, String> load({
    required String userId,
    required String testId,
  }) {
    final raw = Hive.box('settings').get(_key(userId, testId));

    if (raw is! Map) return {};

    return {
      for (final entry in raw.entries)
        entry.key.toString(): entry.value.toString(),
    };
  }

  static Future<void> save({
    required String userId,
    required String testId,
    required Map<String, String> marks,
  }) async {
    final box = Hive.box('settings');
    final key = _key(userId, testId);

    if (marks.isEmpty) {
      await box.delete(key);
    } else {
      await box.put(key, Map<String, String>.from(marks));
    }
  }

  static bool hasPendingDrafts(String userId) {
    final prefix = '$_prefix$userId:';
    final box = Hive.box('settings');

    for (final key in box.keys) {
      if (!key.toString().startsWith(prefix)) continue;

      final value = box.get(key);

      if (value is Map && value.isNotEmpty) {
        return true;
      }
    }

    return false;
  }
}
