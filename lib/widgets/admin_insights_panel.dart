import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../services/admin_insights_service.dart';

class AdminInsightsPanel extends StatefulWidget {
  final AdminInsightsService? service;

  const AdminInsightsPanel({super.key, this.service});

  @override
  State<AdminInsightsPanel> createState() => _AdminInsightsPanelState();
}

class _AdminInsightsPanelState extends State<AdminInsightsPanel> {
  late final AdminInsightsService _service =
      widget.service ?? AdminInsightsService();
  DataHealthSnapshot? _health;
  List<ActivityGroup> _activity = const [];
  bool _loading = true;
  bool _cleaning = false;
  bool _alertShown = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<dynamic>([
        _service.fetchHealth(),
        _service.fetchActivity(),
      ]);
      if (!mounted) return;
      final health = results[0] as DataHealthSnapshot;
      setState(() {
        _health = health;
        _activity = results[1] as List<ActivityGroup>;
        _loading = false;
      });
      if (health.warning && !_alertShown) {
        _alertShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showCapacityAlert(health);
        });
      }
    } catch (error) {
      debugPrint('Admin insights error: $error');
      if (!mounted) return;
      final setupMissing =
          error is PostgrestException &&
          (error.code == '42883' || error.code == '42P01');
      setState(() {
        _loading = false;
        _error = setupMissing
            ? 'Data Health setup is pending. Run the supplied Supabase query once.'
            : 'Data Health could not be loaded. Check the connection and retry.';
      });
    }
  }

  Future<void> _showCapacityAlert(DataHealthSnapshot health) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            health.critical
                ? Icons.error_outline_rounded
                : Icons.warning_amber_rounded,
            color: health.critical ? AppTheme.danger : AppTheme.warning,
            size: 38,
          ),
          title: Text(
            health.critical
                ? 'Supabase capacity is critical'
                : 'Supabase capacity warning',
          ),
          content: Text(
            'Database: ${_percent(health.databaseRatio)} used\n'
            'File storage: ${_percent(health.storageRatio)} used\n\n'
            'Open Cleanup to remove safe old data. Current students and '
            'current result records are never removed automatically.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showCleanup();
              },
              child: const Text('Open Cleanup'),
            ),
          ],
        ),
      );

  Future<void> _showCleanup() async {
    final action = await showDialog<_CleanupAction>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Safe Data Cleanup'),
        children: [
          _cleanupOption(
            dialogContext,
            _CleanupAction.attendance,
            Icons.fact_check_outlined,
            'Previous attendance',
            'Deletes attendance before the current month only.',
          ),
          _cleanupOption(
            dialogContext,
            _CleanupAction.activity,
            Icons.history_rounded,
            'Old activity logs',
            'Keeps the latest 30 days and removes older logs.',
          ),
          _cleanupOption(
            dialogContext,
            _CleanupAction.printables,
            Icons.delete_sweep_outlined,
            'Expired printables',
            'Removes expired requests and their uploaded files.',
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    final description = switch (action) {
      _CleanupAction.attendance =>
        'attendance records before the current month',
      _CleanupAction.activity => 'activity logs older than 30 days',
      _CleanupAction.printables => 'expired printable requests and files',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm cleanup'),
        content: Text(
          'This will permanently remove $description. Current students, '
          'current-month attendance and result records remain safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cleaning = true);
    try {
      final count = switch (action) {
        _CleanupAction.attendance => await _service.clearPreviousAttendance(),
        _CleanupAction.activity => await _service.clearOldActivity(),
        _CleanupAction.printables => await _service.clearExpiredPrintables(),
      };
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cleanup complete: $count item(s) removed.'),
          backgroundColor: AppTheme.success,
        ),
      );
      await _load();
    } catch (error) {
      debugPrint('Admin cleanup error: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cleanup failed. No further data was changed.'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  Widget _cleanupOption(
    BuildContext dialogContext,
    _CleanupAction action,
    IconData icon,
    String title,
    String subtitle,
  ) => ListTile(
    leading: Icon(icon, color: AppTheme.fgNavyBlue),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle),
    onTap: () => Navigator.pop(dialogContext, action),
  );

  Future<void> _showAllActivity() => showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 15, 8, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Recent Activity',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _activity.isEmpty
                  ? const Center(child: Text('No activity recorded yet.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _activity.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) =>
                          _activityTile(_activity[index]),
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _activityTile(ActivityGroup group) {
    final entry = group.latest;
    final action = _actionLabel(entry.action);
    final detail = entry.summary.trim();
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: AppTheme.navy500.withValues(alpha: 0.11),
        foregroundColor: AppTheme.fgNavyBlue,
        child: Icon(_activityIcon(entry.entityType), size: 20),
      ),
      title: Text(
        '${entry.actorName} $action ${_entityLabel(entry.entityType)}'
        '${detail.isEmpty ? '' : ' · $detail'}'
        '${group.count > 1 ? ' (${group.count} records)' : ''}',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
      ),
      subtitle: Text(
        DateFormat('dd MMM, hh:mm a').format(entry.createdAt),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 12),
              Text('Checking Supabase health...'),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Card(
        child: ListTile(
          leading: const Icon(
            Icons.cloud_off_outlined,
            color: AppTheme.warning,
          ),
          title: const Text(
            'Data Health unavailable',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(_error!),
          trailing: IconButton(
            tooltip: 'Retry',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
      );
    }
    final health = _health!;
    final color = health.critical
        ? AppTheme.danger
        : health.warning
        ? AppTheme.warning
        : AppTheme.success;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.storage_rounded, color: color),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Supabase Data Health',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        health.critical
                            ? 'Critical — cleanup recommended now'
                            : health.warning
                            ? 'Warning — capacity is getting high'
                            : 'Healthy — plenty of capacity available',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _cleaning ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                OutlinedButton.icon(
                  onPressed: _cleaning ? null : _showCleanup,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text('Cleanup'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 620;
                final database = _usageBar(
                  title: 'Database',
                  bytes: health.databaseBytes,
                  limit: health.databaseLimitBytes,
                  ratio: health.databaseRatio,
                  subtitle: 'Free reference: 500 MB',
                );
                final storage = _usageBar(
                  title: 'File Storage',
                  bytes: health.storageBytes,
                  limit: health.storageLimitBytes,
                  ratio: health.storageRatio,
                  subtitle:
                      '${health.storageFiles} files • Free reference: 1 GB',
                );
                return wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: database),
                          const SizedBox(width: 22),
                          Expanded(child: storage),
                        ],
                      )
                    : Column(
                        children: [
                          database,
                          const SizedBox(height: 15),
                          storage,
                        ],
                      );
              },
            ),
            if (health.tables.isNotEmpty) ...[
              const SizedBox(height: 13),
              Text(
                'Largest tracked tables: ${health.tables.take(3).map((item) => '${_entityLabel(item.key)} ${_formatBytes(item.bytes)}').join(' • ')}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            const Divider(height: 27),
            Row(
              children: [
                const Icon(Icons.history_rounded, color: AppTheme.fgNavyBlue),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Recent Activity',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: _showAllActivity,
                  child: const Text('View All'),
                ),
              ],
            ),
            if (_activity.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No activity recorded yet.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              )
            else
              ..._activity.take(4).map(_activityTile),
            if (_cleaning) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _usageBar({
    required String title,
    required int bytes,
    required int limit,
    required double ratio,
    required String subtitle,
  }) {
    final color = ratio >= 0.9
        ? AppTheme.danger
        : ratio >= 0.8
        ? AppTheme.warning
        : AppTheme.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${_formatBytes(bytes)} / ${_formatBytes(limit)}',
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            color: color,
            backgroundColor: color.withValues(alpha: 0.12),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${_percent(ratio)} used • $subtitle',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
        ),
      ],
    );
  }
}

enum _CleanupAction { attendance, activity, printables }

String _formatBytes(int bytes) {
  if (bytes >= 1000000000) {
    return '${(bytes / 1000000000).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1000000) return '${(bytes / 1000000).toStringAsFixed(1)} MB';
  if (bytes >= 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
  return '$bytes B';
}

String _percent(double ratio) => '${(ratio * 100).toStringAsFixed(1)}%';

String _actionLabel(String value) => switch (value.toUpperCase()) {
  'INSERT' => 'created',
  'DELETE' => 'deleted',
  _ => 'updated',
};

String _entityLabel(String value) => switch (value) {
  'students' => 'student',
  'attendance' => 'attendance',
  'award_tests' => 'Award List test',
  'award_marks' => 'Award List marks',
  'test_session_tests' => 'Test Session test',
  'test_session_marks' => 'Test Session marks',
  'printable_requests' => 'printable',
  'activity_log' => 'activity log',
  _ => value.replaceAll('_', ' '),
};

IconData _activityIcon(String value) => switch (value) {
  'students' => Icons.person_outline_rounded,
  'attendance' => Icons.fact_check_outlined,
  'award_tests' || 'award_marks' => Icons.emoji_events_outlined,
  'test_session_tests' || 'test_session_marks' => Icons.assignment_outlined,
  'printable_requests' => Icons.print_outlined,
  _ => Icons.edit_note_rounded,
};
