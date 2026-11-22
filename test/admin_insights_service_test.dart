import 'package:academy_portal/services/admin_insights_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses health usage and sorts largest tables first', () {
    final health = DataHealthSnapshot.fromJson({
      'database_bytes': 450,
      'database_limit_bytes': 500,
      'storage_bytes': 200,
      'storage_limit_bytes': 1000,
      'storage_files': 3,
      'checked_at': '2026-11-22T10:00:00Z',
      'tables': [
        {'key': 'students', 'bytes': 20, 'rows': 100},
        {'key': 'attendance', 'bytes': 80, 'rows': 900},
      ],
    });

    expect(health.databaseRatio, 0.9);
    expect(health.storageRatio, 0.2);
    expect(health.critical, isTrue);
    expect(health.tables.first.key, 'attendance');
  });

  test('groups consecutive activity by actor, action and entity', () {
    final now = DateTime(2026, 11, 22, 10);
    final groups = groupActivity([
      ActivityEntry(
        id: 2,
        actorName: 'Sir Ali',
        action: 'UPDATE',
        entityType: 'attendance',
        summary: 'Present',
        createdAt: now,
      ),
      ActivityEntry(
        id: 1,
        actorName: 'Sir Ali',
        action: 'UPDATE',
        entityType: 'attendance',
        summary: 'Absent',
        createdAt: now.subtract(const Duration(minutes: 1)),
      ),
      ActivityEntry(
        id: 3,
        actorName: 'Admin',
        action: 'UPDATE',
        entityType: 'students',
        summary: 'Student A',
        createdAt: now.subtract(const Duration(minutes: 2)),
      ),
    ]);

    expect(groups, hasLength(2));
    expect(groups.first.count, 2);
    expect(groups.last.latest.entityType, 'students');
  });
}
