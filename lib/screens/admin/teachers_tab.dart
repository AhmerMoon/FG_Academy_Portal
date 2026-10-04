import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_theme.dart';
import '../../services/auth_service.dart';
import '../../utils/dashboard_section_header.dart';
import '../../utils/error_state_view.dart';

class TeachersTab extends StatefulWidget {
  const TeachersTab({super.key});

  @override
  State<TeachersTab> createState() => _TeachersTabState();
}

class _TeachersTabState extends State<TeachersTab> {
  final SupabaseClient _client = Supabase.instance.client;

  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _teachers = [];

  final Map<String, List<Map<String, dynamic>>> _assignments = {};

  final Set<String> _busyIds = {};

  bool _loading = true;
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
        _client
            .from('teacher_registration_requests')
            .select(
              'id, full_name, email, '
              'subject_name, class_levels, '
              'status, requested_at',
            )
            .eq('status', 'pending')
            .order('requested_at', ascending: true),
        _client
            .from('user_profiles')
            .select(
              'user_id, email, full_name, '
              'role, is_active, created_at',
            )
            .eq('role', 'teacher')
            .order('full_name'),
        _client
            .from('teacher_assignments')
            .select(
              'teacher_id, class_level, '
              'subject_code',
            )
            .order('class_level'),
      ]);

      final pending = (results[0] as List)
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      final teachers = (results[1] as List)
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      final assignmentRows = (results[2] as List)
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      final grouped = <String, List<Map<String, dynamic>>>{};

      for (final row in assignmentRows) {
        final id = row['teacher_id']?.toString();

        if (id == null || id.isEmpty) {
          continue;
        }

        grouped.putIfAbsent(id, () => []).add(row);
      }

      if (!mounted) return;

      setState(() {
        _pending = pending;
        _teachers = teachers;

        _assignments
          ..clear()
          ..addAll(grouped);

        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('Teachers tab load error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to load teachers and access requests.';
      });
    }
  }

  void _message(String value, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        backgroundColor: error ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  List<int> _requestClasses(Map<String, dynamic> request) {
    final raw = request['class_levels'];

    if (raw is! List) {
      return [];
    }

    final values = raw
        .map((value) => int.tryParse(value.toString()))
        .whereType<int>()
        .toList();

    values.sort();

    return values;
  }

  Future<void> _approve(Map<String, dynamic> request) async {
    final id = request['id'].toString();

    if (_busyIds.contains(id)) return;

    final name = request['full_name']?.toString() ?? 'Teacher';

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Approve Teacher?'),
              content: Text(
                'Approve portal access for $name?\n\n'
                'Their selected classes and subject '
                'will become active immediately.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Approve'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _busyIds.add(id);
    });

    try {
      await _client.rpc(
        'admin_approve_teacher_request',
        params: {'p_request_id': id},
      );

      await _load();

      _message('$name has been approved.');
    } catch (e) {
      debugPrint('Teacher approval error: $e');

      _message('Teacher could not be approved.\n$e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busyIds.remove(id);
        });
      }
    }
  }

  Future<void> _reject(Map<String, dynamic> request) async {
    final id = request['id'].toString();

    if (_busyIds.contains(id)) return;

    final controller = TextEditingController();

    final reason = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reject Request?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('You may optionally enter a reason.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (reason == null || !mounted) {
      return;
    }

    setState(() {
      _busyIds.add(id);
    });

    try {
      await _client.rpc(
        'admin_reject_teacher_request',
        params: {
          'p_request_id': id,
          'p_reason': reason.isEmpty ? null : reason,
        },
      );

      await _load();

      _message('Teacher request rejected.');
    } catch (e) {
      debugPrint('Teacher rejection error: $e');

      _message('Request could not be rejected.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busyIds.remove(id);
        });
      }
    }
  }

  Future<void> _setActive(Map<String, dynamic> teacher, bool active) async {
    final id = teacher['user_id'].toString();

    if (_busyIds.contains(id)) return;

    setState(() {
      _busyIds.add(id);
    });

    try {
      await _client.rpc(
        'admin_set_portal_user_active',
        params: {'p_user_id': id, 'p_active': active},
      );

      await _load();

      _message(
        active ? 'Teacher account enabled.' : 'Teacher account disabled.',
      );
    } catch (e) {
      debugPrint('Teacher active status error: $e');

      _message('Could not change account status.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busyIds.remove(id);
        });
      }
    }
  }

  String _teacherAssignments(String teacherId) {
    final rows = _assignments[teacherId] ?? const [];

    if (rows.isEmpty) {
      return 'No teaching assignment';
    }

    return rows
        .map((row) {
          final level = row['class_level']?.toString() ?? '';

          final subject = AuthService.subjectLabel(
            row['subject_code']?.toString() ?? '',
          );

          return 'Class $level • $subject';
        })
        .join('   |   ');
  }

  Widget _pendingSection() {
    return Card(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.pending_actions_rounded,
                  color: AppTheme.fgNavyBlue,
                  size: 28,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Pending Requests (${_pending.length})',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_pending.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'No teacher access requests are pending.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              )
            else
              ..._pending.map((request) {
                final id = request['id'].toString();

                final busy = _busyIds.contains(id);

                final name = request['full_name']?.toString() ?? 'Teacher';

                final email = request['email']?.toString() ?? '';

                final subject = AuthService.subjectLabel(
                  request['subject_name']?.toString() ?? '',
                );

                final classes = _requestClasses(
                  request,
                ).map((value) => '$value').join(', ');

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.fgNavyBlue.withValues(alpha: 0.035),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: AppTheme.fgNavyBlue.withValues(alpha: 0.10),
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 690;

                      final details = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            email,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              Chip(
                                avatar: const Icon(
                                  Icons.menu_book_outlined,
                                  size: 17,
                                ),
                                label: Text(subject),
                              ),
                              Chip(
                                avatar: const Icon(
                                  Icons.school_outlined,
                                  size: 17,
                                ),
                                label: Text('Classes $classes'),
                              ),
                            ],
                          ),
                        ],
                      );

                      final actions = Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: busy ? null : () => _reject(request),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.danger,
                            ),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Reject'),
                          ),
                          ElevatedButton.icon(
                            onPressed: busy ? null : () => _approve(request),
                            icon: busy
                                ? const SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: const Text('Approve'),
                          ),
                        ],
                      );

                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            details,
                            const SizedBox(height: 13),
                            actions,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: details),
                          const SizedBox(width: 14),
                          actions,
                        ],
                      );
                    },
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _teachersSection() {
    return Card(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 25),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.co_present_rounded,
                  color: AppTheme.fgNavyBlue,
                  size: 28,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Teachers (${_teachers.length})',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_teachers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No approved teachers found.')),
              )
            else
              ..._teachers.map((teacher) {
                final id = teacher['user_id'].toString();

                final name = teacher['full_name']?.toString() ?? 'Teacher';

                final email = teacher['email']?.toString() ?? '';

                final active = teacher['is_active'] == true;

                final busy = _busyIds.contains(id);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 5,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.fgNavyBlue,
                    foregroundColor: Colors.white,
                    child: Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(email),
                        const SizedBox(height: 3),
                        Text(_teacherAssignments(id)),
                      ],
                    ),
                  ),
                  trailing: busy
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : SizedBox(
                          width: 125,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                active ? 'Active' : 'Disabled',
                                style: TextStyle(
                                  color: active
                                      ? AppTheme.success
                                      : AppTheme.danger,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Switch.adaptive(
                                value: active,
                                onChanged: (value) {
                                  _setActive(teacher, value);
                                },
                              ),
                            ],
                          ),
                        ),
                );
              }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ErrorStateView(message: _error!, onRetry: _load);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: DashboardSectionHeader(
              title: 'Teachers',
              subtitle:
                  'Approve teacher registrations and manage portal access',
              trailing: IconButton(
                tooltip: 'Refresh',
                color: Colors.white,
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _pendingSection()),
          SliverToBoxAdapter(child: _teachersSection()),
        ],
      ),
    );
  }
}
