import 'package:supabase_flutter/supabase_flutter.dart';

import 'printables_service.dart';

class DataUsageItem {
  final String key;
  final int bytes;
  final int rows;

  const DataUsageItem({
    required this.key,
    required this.bytes,
    required this.rows,
  });

  factory DataUsageItem.fromJson(Map<String, dynamic> json) => DataUsageItem(
    key: json['key']?.toString() ?? 'other',
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    rows: (json['rows'] as num?)?.toInt() ?? 0,
  );
}

class DataHealthSnapshot {
  final int databaseBytes;
  final int databaseLimitBytes;
  final int storageBytes;
  final int storageLimitBytes;
  final int storageFiles;
  final List<DataUsageItem> tables;
  final DateTime checkedAt;

  const DataHealthSnapshot({
    required this.databaseBytes,
    required this.databaseLimitBytes,
    required this.storageBytes,
    required this.storageLimitBytes,
    required this.storageFiles,
    required this.tables,
    required this.checkedAt,
  });

  double get databaseRatio => databaseLimitBytes <= 0
      ? 0
      : (databaseBytes / databaseLimitBytes).clamp(0, 1);
  double get storageRatio => storageLimitBytes <= 0
      ? 0
      : (storageBytes / storageLimitBytes).clamp(0, 1);
  bool get warning => databaseRatio >= 0.8 || storageRatio >= 0.8;
  bool get critical => databaseRatio >= 0.9 || storageRatio >= 0.9;

  factory DataHealthSnapshot.fromJson(Map<String, dynamic> json) {
    final rawTables = json['tables'] as List? ?? const [];
    final tables =
        rawTables
            .map(
              (row) => DataUsageItem.fromJson(Map<String, dynamic>.from(row)),
            )
            .toList()
          ..sort((a, b) => b.bytes.compareTo(a.bytes));
    return DataHealthSnapshot(
      databaseBytes: (json['database_bytes'] as num?)?.toInt() ?? 0,
      databaseLimitBytes:
          (json['database_limit_bytes'] as num?)?.toInt() ?? 500000000,
      storageBytes: (json['storage_bytes'] as num?)?.toInt() ?? 0,
      storageLimitBytes:
          (json['storage_limit_bytes'] as num?)?.toInt() ?? 1000000000,
      storageFiles: (json['storage_files'] as num?)?.toInt() ?? 0,
      tables: tables,
      checkedAt:
          DateTime.tryParse(json['checked_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ActivityEntry {
  final int id;
  final String actorName;
  final String action;
  final String entityType;
  final String summary;
  final DateTime createdAt;

  const ActivityEntry({
    required this.id,
    required this.actorName,
    required this.action,
    required this.entityType,
    required this.summary,
    required this.createdAt,
  });

  factory ActivityEntry.fromJson(Map<String, dynamic> json) => ActivityEntry(
    id: (json['id'] as num?)?.toInt() ?? 0,
    actorName: json['actor_name']?.toString().trim().isNotEmpty == true
        ? json['actor_name'].toString().trim()
        : 'Portal user',
    action: json['action']?.toString() ?? 'updated',
    entityType: json['entity_type']?.toString() ?? 'record',
    summary: json['summary']?.toString() ?? 'Record changed',
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

class ActivityGroup {
  final ActivityEntry latest;
  final int count;

  const ActivityGroup({required this.latest, required this.count});
}

class AdminInsightsService {
  final SupabaseClient _client;

  AdminInsightsService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<DataHealthSnapshot> fetchHealth() async {
    final result = await _client.rpc('admin_data_health');
    return DataHealthSnapshot.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<List<ActivityGroup>> fetchActivity({int limit = 100}) async {
    final rows = await _client
        .from('activity_log')
        .select('id,actor_name,action,entity_type,summary,created_at')
        .order('created_at', ascending: false)
        .limit(limit);
    return groupActivity(
      rows
          .map((row) => ActivityEntry.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
    );
  }

  Future<int> clearPreviousAttendance() async {
    final result = await _client.rpc('admin_cleanup_previous_attendance');
    return (result as num?)?.toInt() ?? 0;
  }

  Future<int> clearOldActivity({int keepDays = 30}) async {
    final result = await _client.rpc(
      'admin_cleanup_activity_log',
      params: {'p_keep_days': keepDays},
    );
    return (result as num?)?.toInt() ?? 0;
  }

  Future<int> clearExpiredPrintables() async {
    final result = await _client.rpc('prepare_expired_printable_delete');
    final rows = (result as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    for (var offset = 0; offset < rows.length; offset += 100) {
      final end = offset + 100 < rows.length ? offset + 100 : rows.length;
      final batch = rows.sublist(offset, end);
      await _client.storage
          .from(PrintablesService.bucket)
          .remove(batch.map((row) => row['file_path'].toString()).toList());
      await _client.rpc(
        'finish_printable_delete',
        params: {'p_ids': batch.map((row) => row['id'].toString()).toList()},
      );
    }
    return rows.length;
  }
}

List<ActivityGroup> groupActivity(List<ActivityEntry> entries) {
  final groups = <ActivityGroup>[];
  for (final entry in entries) {
    if (groups.isNotEmpty) {
      final previous = groups.last;
      final sameKind =
          previous.latest.actorName == entry.actorName &&
          previous.latest.action == entry.action &&
          previous.latest.entityType == entry.entityType;
      final closeInTime =
          previous.latest.createdAt.difference(entry.createdAt).abs() <=
          const Duration(minutes: 5);
      if (sameKind && closeInTime) {
        groups[groups.length - 1] = ActivityGroup(
          latest: previous.latest,
          count: previous.count + 1,
        );
        continue;
      }
    }
    groups.add(ActivityGroup(latest: entry, count: 1));
  }
  return groups;
}
