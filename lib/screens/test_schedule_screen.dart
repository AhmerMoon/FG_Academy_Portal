import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models/portal_user.dart';
import '../services/auth_service.dart';
import '../utils/dashboard_section_header.dart';
import 'schedule_document_preview_screen.dart';

class TestScheduleScreen extends StatefulWidget {
  final VoidCallback? onChanged;

  const TestScheduleScreen({super.key, this.onChanged});

  @override
  State<TestScheduleScreen> createState() => _TestScheduleScreenState();
}

class _TestScheduleScreenState extends State<TestScheduleScreen> {
  static const _sscOneDocumentId =
      '1LwVeUfvvaGEE8KYfamkcOwoBeZgFV6V_aN-dyv7ES7A';
  final _client = Supabase.instance.client;
  PortalUser? _user;
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  static const _labels = {
    'ssc_1': 'SSC I Test Schedule',
    'ssc_2': 'SSC II Test Schedule',
    'hssc_1': 'HSSC I Test Schedule',
    'hssc_2': 'HSSC II Test Schedule',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = _user ?? await AuthService().loadCurrentUser();
      if (user == null) throw StateError('Your account could not be loaded.');
      final rows = await Future.wait<dynamic>([
        _client.from('test_schedules').select('key,document_url,updated_at'),
        _client
            .from('test_schedule_requests')
            .select(
              'id,schedule_key,teacher_id,teacher_name,message,status,created_at',
            )
            .order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _user = user;
        _schedules = (rows[0] as List)
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _requests = (rows[1] as List)
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error =
              'Could not load schedules. Check your connection or run the schedule SQL.';
          _loading = false;
        });
      }
    }
  }

  bool _canSee(String key) {
    final user = _user;
    if (user == null) return false;
    if (user.isAdmin) return true;
    final levels = user.classLevels;
    return key.startsWith('ssc_')
        ? levels.contains(9) || levels.contains(10)
        : levels.contains(11) || levels.contains(12);
  }

  Map<String, dynamic>? _latestRequest(String key) {
    for (final request in _requests) {
      if (request['schedule_key'] == key &&
          request['teacher_id'] == _user?.userId &&
          (request['status'] == 'pending' || request['status'] == 'approved')) {
        return request;
      }
    }
    return null;
  }

  Future<void> _openDocument(
    String url, {
    bool preview = false,
    String title = 'Test Schedule',
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host != 'docs.google.com') {
      _notice('Admin needs to add a valid Google Docs link.');
      return;
    }
    // SSC I contains floating header artwork that Google Docs' embedded HTML
    // preview reflows incorrectly on narrow iPhone screens. Its exported PDF
    // is correct, so web users should view that faithful version directly.
    if (preview && kIsWeb && uri.path.contains(_sscOneDocumentId)) {
      final pdfUri = uri.replace(
        path: uri.path.replaceFirst(RegExp(r'/edit/?$'), '/export'),
        queryParameters: const {'format': 'pdf'},
      );
      try {
        final opened = await launchUrl(
          pdfUri,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank',
        );
        if (!opened) throw StateError('Could not open the schedule PDF.');
      } catch (_) {
        _notice('Could not open the schedule PDF. Try again in Safari.');
      }
      return;
    }
    if (preview) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ScheduleDocumentPreviewScreen(title: title, documentUri: uri),
        ),
      );
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('Could not open Google Docs.');
    } catch (_) {
      if (mounted) {
        _notice('Could not open Google Docs. Try again in Chrome.');
      }
    }
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<String?> _prompt(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: title.contains('link') ? 1 : 4,
          decoration: InputDecoration(
            hintText: title.contains('link')
                ? 'https://docs.google.com/document/d/.../edit'
                : 'Describe the chapter or date change',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _changeLink(String key, String old) async {
    final value = await _prompt('Edit schedule link', initial: old);
    if (value == null || value == old) return;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'docs.google.com' ||
        !uri.path.startsWith('/document/d/')) {
      _notice('Please paste a Google Docs document link.');
      return;
    }
    await _run(
      () => _client
          .from('test_schedules')
          .update({
            'document_url': value,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('key', key),
      'Schedule link updated.',
    );
  }

  Future<void> _requestEdit(String key) async {
    final message = await _prompt('Request a schedule change');
    if (message == null || message.isEmpty) return;
    await _run(
      () => _client.from('test_schedule_requests').insert({
        'schedule_key': key,
        'teacher_id': _user!.userId,
        'teacher_name': _user!.fullName,
        'message': message,
      }),
      'Request sent to admin.',
    );
  }

  Future<void> _setStatus(Map<String, dynamic> request, String status) async {
    await _run(
      () => _client
          .from('test_schedule_requests')
          .update({'status': status})
          .eq('id', request['id']),
      'Request ${status == 'approved' ? 'approved' : status}.',
    );
  }

  Future<void> _run(Future<dynamic> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      widget.onChanged?.call();
      _notice(success);
    } catch (_) {
      _notice('Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final admin = _user!.isAdmin;
    final pending = _requests
        .where((row) => row['status'] == 'pending')
        .toList();
    return Column(
      children: [
        const DashboardSectionHeader(
          title: 'Test Schedule',
          subtitle: 'View class schedules and coordinate updates',
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (admin && pending.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Change requests (${pending.length})',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          for (final request in pending) _requestTile(request),
                        ],
                      ),
                    ),
                  ),
                for (final entry in _labels.entries)
                  if (_canSee(entry.key))
                    _scheduleCard(entry.key, entry.value, admin),
                if (!admin && !_labels.keys.any(_canSee))
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'No class schedule is assigned to your account.',
                      ),
                    ),
                  ),
                if (admin) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Request history',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  for (final request in _requests.where(
                    (row) => row['status'] != 'pending',
                  ))
                    _requestTile(request),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _scheduleCard(String key, String label, bool admin) {
    final schedule = _schedules.where((row) => row['key'] == key).firstOrNull;
    final url = schedule?['document_url']?.toString() ?? '';
    final request = _latestRequest(key);
    final approved = request?['status'] == 'approved';
    final isSsc = key.startsWith('ssc');
    final accent = isSsc ? AppTheme.info : AppTheme.success;
    final level = isSsc
        ? 'Secondary | Classes 9-10'
        : 'Higher Secondary | Classes 11-12';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent.withValues(alpha: 0.14), Colors.white],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        level,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (url.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: AppTheme.success,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Ready',
                          style: TextStyle(
                            color: AppTheme.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (request != null) ...[
                  Text(
                    'Your request: ${request['status']}',
                    style: TextStyle(
                      color: approved ? AppTheme.success : AppTheme.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: url.isEmpty
                          ? null
                          : () =>
                                _openDocument(url, preview: true, title: label),
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('View Schedule'),
                    ),
                    if (admin) ...[
                      OutlinedButton.icon(
                        onPressed: url.isEmpty
                            ? null
                            : () => _openDocument(url),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit in Docs'),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _changeLink(key, url),
                        icon: const Icon(Icons.link),
                        label: const Text('Change Link'),
                      ),
                    ] else ...[
                      if (approved)
                        OutlinedButton.icon(
                          onPressed: () => _openDocument(url),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit in Docs'),
                        ),
                      if (approved && request != null)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _setStatus(request, 'completed'),
                          child: const Text('Done Editing'),
                        ),
                      if (request == null)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _requestEdit(key),
                          icon: const Icon(Icons.rate_review_outlined),
                          label: const Text('Request Editing'),
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestTile(Map<String, dynamic> request) {
    final status = request['status'].toString();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${request['teacher_name']} · ${_labels[request['schedule_key']] ?? request['schedule_key']}',
      ),
      subtitle: Text('${request['message']} · $status'),
      isThreeLine: false,
      trailing: status == 'pending'
          ? PopupMenuButton<String>(
              tooltip: 'Manage request',
              onSelected: (value) => _setStatus(request, value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'approved', child: Text('Allow Editing')),
                PopupMenuItem(
                  value: 'completed',
                  child: Text('Handled by Admin'),
                ),
                PopupMenuItem(value: 'rejected', child: Text('Reject')),
              ],
            )
          : status == 'approved'
          ? TextButton(
              onPressed: () => _setStatus(request, 'completed'),
              child: const Text('Revoke'),
            )
          : null,
    );
  }
}
