import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_theme.dart';

class ArchiveStudentsView extends StatefulWidget {
  final VoidCallback? onRestored;

  const ArchiveStudentsView({super.key, this.onRestored});

  @override
  State<ArchiveStudentsView> createState() => _ArchiveStudentsViewState();
}

class _ArchiveStudentsViewState extends State<ArchiveStudentsView> {
  final SupabaseClient _db = Supabase.instance.client;

  List<Map<String, dynamic>> _rows = [];
  Map<String, String> _batchNames = {};

  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _db
            .from('students')
            .select('id,name,batch_id,archived_at,archive_reason,stream')
            .eq('is_archived', true)
            .order('archived_at', ascending: false),
        _db.from('batches').select('id,name'),
      ]);

      final batches = <String, String>{};

      for (final batch in results[1] as List) {
        batches[batch['id'].toString()] = batch['name']?.toString() ?? 'Batch';
      }

      if (!mounted) return;

      setState(() {
        _rows = (results[0] as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();

        _batchNames = batches;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _batch(Map<String, dynamic> student) {
    return _batchNames[student['batch_id']?.toString()] ?? 'Unknown batch';
  }

  String _archivedDate(Map<String, dynamic> student) {
    final date = DateTime.tryParse(student['archived_at']?.toString() ?? '');

    if (date == null) return '-';

    return '${date.day.toString().padLeft(2, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.year}';
  }

  Future<void> _details(Map<String, dynamic> student) async {
    final studentId = student['id'].toString();

    try {
      final results = await Future.wait<dynamic>([
        _db
            .from('attendance')
            .select('date,status')
            .eq('student_id', studentId)
            .order('date', ascending: false),
        _db
            .from('award_marks')
            .select('test_id,marks,is_absent')
            .eq('student_id', studentId),
      ]);

      if (!mounted) return;

      final attendance = results[0] as List;
      final marks = results[1] as List;

      final present = attendance
          .where((row) => row['status'] == 'present')
          .length;

      final absent = attendance
          .where((row) => row['status'] == 'absent')
          .length;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(student['name']?.toString() ?? 'Student'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_batch(student)} · '
                      'Archived ${_archivedDate(student)}',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Historical Attendance (read-only)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 5),
                    Text('Present: $present    Absent: $absent'),
                    const SizedBox(height: 8),
                    for (final row in attendance.take(30))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text('${row['date']}: ${row['status']}'),
                      ),
                    if (attendance.length > 30)
                      Text(
                        'Showing latest 30 of '
                        '${attendance.length} records',
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'Historical Award Marks (read-only)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 5),
                    Text('Saved mark records: ${marks.length}'),
                    for (final mark in marks.take(30))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          'Test ${mark['test_id']}: '
                          '${mark['is_absent'] == true ? 'Absent' : (mark['marks'] ?? '-')}',
                        ),
                      ),
                    if (marks.length > 30)
                      Text('Showing 30 of ${marks.length} marks'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load historical records: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _restore(Map<String, dynamic> student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Restore Student?'),
          content: Text(
            'Restore "${student['name']}" '
            'to active attendance and student lists?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Restore'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _db.rpc('restore_student', params: {'p_student_id': student['id']});

      widget.onRestored?.call();

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text('Archive unavailable: $_error'));
    }

    final filtered = _rows.where((student) {
      final searchText =
          '${student['name']} '
                  '${_batch(student)} '
                  '${student['archive_reason']}'
              .toLowerCase();

      return searchText.contains(_query.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search archived students',
            ),
            onChanged: (value) {
              setState(() => _query = value);
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final student = filtered[index];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: ListTile(
                    isThreeLine: true,
                    title: Text(student['name']?.toString() ?? 'Student'),
                    subtitle: Text(
                      '${_batch(student)} · '
                      '${_archivedDate(student)}\n'
                      '${student['archive_reason'] ?? 'Left academy'}',
                    ),
                    onTap: () => _details(student),
                    trailing: IconButton(
                      tooltip: 'Restore student',
                      icon: const Icon(Icons.restore, color: AppTheme.success),
                      onPressed: () => _restore(student),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
