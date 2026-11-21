import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../services/auth_service.dart';
import '../services/student_profile_service.dart';
import '../utils/error_state_view.dart';
import '../widgets/student_profile_edit_dialog.dart';
import '../widgets/student_profile_header.dart';
import '../utils/student_contact_links.dart';

String _number(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

class StudentProfileScreen extends StatefulWidget {
  final String studentId;
  final StudentProfileService? service;
  final Future<bool> Function(Uri)? openContactLink;
  const StudentProfileScreen({
    super.key,
    required this.studentId,
    this.service,
    this.openContactLink,
  });

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final StudentProfileService _service;
  StudentProfileData? _data;
  String? _error;
  bool _loading = true;
  bool _openingEditor = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _service = widget.service ?? StudentProfileService();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.load(widget.studentId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is StateError
              ? error.message
              : 'Could not load student profile. Please retry.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _editProfile() async {
    if (_openingEditor) return;
    setState(() => _openingEditor = true);
    try {
      final batches = (await _service.fetchBatches())
          .where(
            (b) => const [
              9,
              10,
              11,
              12,
            ].contains((b['class_level'] as num?)?.toInt()),
          )
          .toList();
      if (!mounted) return;
      if (batches.isEmpty) throw StateError('No available classes / batches.');
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StudentProfileEditDialog(
          student: _data!.student,
          batches: batches,
          service: _service,
        ),
      );
      if (saved == true && mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message
                  : 'Could not open student editor. Please retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingEditor = false);
    }
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String get _phone =>
      _data?.student['contact_number']?.toString().trim() ?? '';

  Future<bool> _launchContact(Uri uri) async {
    try {
      return await (widget.openContactLink?.call(uri) ??
          launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
            webOnlyWindowName: uri.scheme == 'tel' ? '_self' : '_blank',
          ));
    } catch (_) {
      return false;
    }
  }

  Future<void> _copyPhone() async {
    try {
      await Clipboard.setData(ClipboardData(text: _phone));
      _notice('Contact number copied.');
    } catch (_) {
      _notice('Could not copy the contact number.');
    }
  }

  Future<void> _callStudent() async {
    final uri = studentCallLink(_phone);
    if (uri == null) {
      _notice('Add a valid contact number first.');
      return;
    }
    if (!await _launchContact(uri)) {
      try {
        await Clipboard.setData(ClipboardData(text: _phone));
        _notice('No calling app is available on this device. Number copied.');
      } catch (_) {
        _notice('No calling app is available on this device.');
      }
    }
  }

  Future<void> _whatsAppStudent({String? invite}) async {
    final name = _data!.student['name']?.toString() ?? 'Student';
    final batch = _data!.batch['name']?.toString() ?? 'Academy';
    final message = invite == null
        ? null
        : 'Assalam-o-Alaikum,\n$name ke $batch academy WhatsApp group mein shamil hone ke liye ye link open karein:\n$invite';
    final uri = studentWhatsAppLink(_phone, message: message);
    if (uri == null) {
      _notice('Use a full contact number, e.g. 03001234567 or +923001234567.');
      return;
    }
    if (!await _launchContact(uri)) {
      _notice('Could not open WhatsApp. Check the app or browser settings.');
    }
  }

  Future<void> _inviteStudent() async {
    if (studentWhatsAppNumber(_phone) == null) {
      _notice('Add a full contact number before sending an invite.');
      return;
    }
    final batchId =
        _data!.student['batch_id'] ??
        _data!.batch['id'] ??
        _data!.batch['name'];
    final cacheKey = 'student_profile_group_invite_$batchId';
    final settings = Hive.isBoxOpen('settings') ? Hive.box('settings') : null;
    final saved = settings?.get(cacheKey)?.toString() ?? '';
    final group = _data!.batch['whatsapp_group_id']?.toString() ?? '';
    final controller = TextEditingController(
      text:
          studentGroupInviteLink(saved) ?? studentGroupInviteLink(group) ?? '',
    );
    final form = GlobalKey<FormState>();
    var remember = true;
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Send WhatsApp group invite'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_data!.batch['name']} · $_phone',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: controller,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'WhatsApp group invite link',
                        hintText: 'https://chat.whatsapp.com/...',
                      ),
                      validator: (value) =>
                          studentGroupInviteLink(value ?? '') == null
                          ? 'Paste a valid WhatsApp group invite link.'
                          : null,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Remember link for this batch'),
                      value: remember,
                      onChanged: (value) =>
                          update(() => remember = value ?? false),
                    ),
                    const Text(
                      'WhatsApp opens with the invite message ready. Review it and tap Send there.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              icon: const Icon(Icons.send_outlined),
              label: const Text('Open WhatsApp'),
            ),
          ],
        ),
      ),
    );
    final confirmed = await Navigator.of(context).push(route);
    if (confirmed == true && mounted) {
      final link = studentGroupInviteLink(controller.text)!;
      await _whatsAppStudent(invite: link);
      if (remember && settings != null) {
        try {
          await settings.put(cacheKey, link);
        } catch (_) {
          /* Sending does not depend on caching. */
        }
      }
    }
    await route.completed;
    controller.dispose();
  }

  bool get _canEdit =>
      _data?.canEditContact == true && _data?.student['is_archived'] != true;

  Widget _profileHeader({bool desktop = false}) => StudentProfileHeader(
    data: _data!,
    desktop: desktop,
    onEdit: _canEdit && !_openingEditor ? _editProfile : null,
    onCall: _callStudent,
    onWhatsApp: _whatsAppStudent,
    onInvite: _inviteStudent,
    onCopy: _copyPhone,
  );

  TabBar _profileTabs({bool onDark = false}) => TabBar(
    controller: _tabs,
    isScrollable: true,
    tabAlignment: TabAlignment.start,
    labelColor: onDark ? Colors.white : AppTheme.fgNavyBlue,
    unselectedLabelColor: onDark ? Colors.white70 : AppTheme.textSecondary,
    indicatorColor: onDark ? AppTheme.fgGold : AppTheme.fgNavyBlue,
    indicatorWeight: 3,
    labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
    unselectedLabelStyle: const TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 12.5,
    ),
    tabs: const [
      Tab(icon: Icon(Icons.person_outline_rounded, size: 20), text: 'Student'),
      Tab(
        icon: Icon(Icons.calendar_month_outlined, size: 20),
        text: 'Attendance',
      ),
      Tab(
        icon: Icon(Icons.analytics_outlined, size: 20),
        text: 'Combined results',
      ),
      Tab(
        icon: Icon(Icons.menu_book_outlined, size: 20),
        text: 'Subject results',
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 1000;
      final content = _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorStateView(message: _error!, onRetry: _load)
          : TabBarView(
              controller: _tabs,
              children: [
                _overview(showHeader: !desktop),
                _attendance(),
                _results(),
                _individualResults(),
              ],
            );
      return Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        appBar: AppBar(
          title: Text(
            _data?.student['name']?.toString() ?? 'Student profile',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: desktop ? null : _profileTabs(onDark: true),
        ),
        body: desktop && !_loading && _error == null
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          key: const ValueKey('student-profile-sidebar'),
                          width: 320,
                          child: ListView(
                            children: [_profileHeader(desktop: true)],
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            children: [
                              Card(
                                margin: EdgeInsets.zero,
                                child: _profileTabs(),
                              ),
                              const SizedBox(height: 8),
                              Expanded(child: content),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : content,
      );
    },
  );

  IconData _sectionIcon(String title) {
    final value = title.toLowerCase();
    if (value.contains('attendance')) return Icons.calendar_month_outlined;
    if (value.contains('daily')) return Icons.fact_check_outlined;
    if (value.contains('subject')) return Icons.menu_book_outlined;
    if (value.contains('student')) return Icons.badge_outlined;
    return Icons.analytics_outlined;
  }

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.fgNavyBlue.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _sectionIcon(title),
                  size: 20,
                  color: AppTheme.fgNavyBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget _detail(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          switch (label) {
            'Name' => Icons.person_outline,
            'UUID' => Icons.fingerprint,
            'Batch' => Icons.groups_outlined,
            'Class' => Icons.school_outlined,
            'Status' => Icons.verified_outlined,
            'Joined' => Icons.event_available_outlined,
            'Contact number' => Icons.call_outlined,
            'Percentage' || 'Overall' => Icons.trending_up,
            _ => Icons.article_outlined,
          },
          size: 18,
          color: AppTheme.textSecondary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              SelectableText(
                value == null || value.toString().isEmpty
                    ? '—'
                    : value.toString(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (label == 'UUID')
          IconButton(
            tooltip: 'Copy student UUID',
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: value?.toString() ?? ''),
              );
              _notice('Student UUID copied.');
            },
            icon: const Icon(Icons.copy_outlined, size: 16),
          ),
      ],
    ),
  );

  String _date(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? '—' : DateFormat('dd MMM yyyy').format(date);
  }

  Widget _overview({bool showHeader = true}) {
    final student = _data!.student;
    final today = studentProfileToday();
    final totals = StudentResultTotals(_data!.results);
    return ListView(
      key: const ValueKey('student-profile-overview'),
      padding: const EdgeInsets.all(16),
      children: [
        if (showHeader) _profileHeader(),
        _profileMetrics(),
        _section('Student details', [
          _detail('Name', student['name']),
          _detail('UUID', student['id']),
          _detail('Batch', _data!.batch['name']),
          _detail('Class', _data!.batch['class_level']),
          if (student['is_archived'] == true) _detail('Status', 'Archived'),
          _detail('Joined', _date(student['created_at'])),
          if (student['is_archived'] == true) ...[
            _detail('Archived', _date(student['archived_at'])),
            _detail('Reason', student['archive_reason']),
          ],
          if (_data!.canEditContact && !student.containsKey('contact_number'))
            const Text(
              'Contact field will be available after the Supabase setup.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          if (student.containsKey('default_fee'))
            _detail('Default fee', student['default_fee']),
          if (student['fee_remarks'] != null)
            _detail('Fee remarks', student['fee_remarks']),
        ]),
        _section('Subjects', [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final subject in ((student['stream'] as List?) ?? []))
                Chip(
                  avatar: const Icon(Icons.menu_book_outlined, size: 16),
                  label: Text(AuthService.subjectLabel(subject.toString())),
                ),
            ],
          ),
        ]),
        _section(
          'Attendance · ${DateFormat('MMMM yyyy').format(DateTime(today.year, today.month))}',
          [_attendanceSummary(DateTime(today.year, today.month))],
        ),
        _section('All available test results', [
          _detail('Graded tests', totals.graded),
          _detail('Absent', totals.absent),
          _detail('Not entered', totals.pending),
          _detail(
            'Overall',
            totals.percentage == null
                ? '—'
                : '${totals.percentage!.toStringAsFixed(1)}%',
          ),
        ]),
      ],
    );
  }

  Widget _profileMetrics() {
    final today = studentProfileToday();
    final totals = StudentResultTotals(_data!.results);
    final month = DateTime(today.year, today.month);
    final attendance = _data!.attendanceFor(month);
    final present = attendance.where((r) => r['status'] == 'present').length;
    final absent = attendance.where((r) => r['status'] == 'absent').length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _metricCard(
              DateFormat('MMM yyyy').format(month),
              present + absent == 0
                  ? '—'
                  : '${(present * 100 / (present + absent)).toStringAsFixed(0)}%',
              '$present P · $absent A',
              Icons.calendar_month_outlined,
              AppTheme.info,
              () => _tabs.animateTo(1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _metricCard(
              'Test results',
              totals.percentage == null
                  ? '—'
                  : '${totals.percentage!.toStringAsFixed(0)}%',
              '${totals.graded} tests',
              Icons.insights_outlined,
              AppTheme.success,
              () => _tabs.animateTo(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(
    String label,
    String value,
    String caption,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _attendanceSummary(DateTime month) {
    final rows = _data!.attendanceFor(month);
    final present = rows.where((r) => r['status'] == 'present').length;
    final absent = rows.where((r) => r['status'] == 'absent').length;
    return Wrap(
      spacing: 18,
      runSpacing: 8,
      children: [
        Text(
          'Present: $present',
          style: const TextStyle(
            color: AppTheme.success,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Absent: $absent',
          style: const TextStyle(
            color: AppTheme.danger,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Attendance: ${present + absent == 0 ? '—' : '${(present * 100 / (present + absent)).toStringAsFixed(1)}%'}',
        ),
      ],
    );
  }

  Widget _attendance() {
    final today = studentProfileToday();
    final month = DateTime(today.year, today.month);
    final rows = _data!.attendanceFor(month);
    final byDay = {
      for (final row in rows)
        DateTime.parse(row['date'].toString()).day: row['status'].toString(),
    };
    final offset = month.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section('Current month · ${DateFormat('MMMM yyyy').format(month)}', [
          _attendanceSummary(month),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final day in [
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat',
                'Sun',
              ])
                Expanded(
                  child: Center(
                    child: Text(day, style: TextStyle(fontSize: 12)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 5,
              mainAxisSpacing: 5,
              mainAxisExtent: 48,
            ),
            itemCount: offset + days,
            itemBuilder: (context, index) {
              if (index < offset) return const SizedBox.shrink();
              final day = index - offset + 1;
              final status = byDay[day];
              final color = status == 'present'
                  ? AppTheme.success
                  : status == 'absent'
                  ? AppTheme.danger
                  : AppTheme.textSecondary;
              return Tooltip(
                message: status ?? 'Not marked',
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha: status == null ? 0.04 : 0.12,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$day${status == 'present'
                        ? ' P'
                        : status == 'absent'
                        ? ' A'
                        : ''}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'P = Present · A = Absent · Uncoloured dates = not marked',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ]),
      ],
    );
  }

  Widget _individualResults() {
    final subjects = _data!.subjects;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (subjects.isEmpty)
          _section('Subject results', [
            const Text('No subject test records available.'),
          ]),
        for (final subject in subjects)
          Builder(
            builder: (_) {
              final rows = _data!.results
                  .where((result) => result.subject == subject)
                  .toList();
              final totals = StudentResultTotals(rows);
              return _section('${AuthService.subjectLabel(subject)} results', [
                _detail(
                  'Marks',
                  totals.maximum > 0
                      ? '${_number(totals.obtained)} / ${_number(totals.maximum)}'
                      : '—',
                ),
                _detail(
                  'Percentage',
                  totals.percentage == null
                      ? '—'
                      : '${totals.percentage!.toStringAsFixed(1)}%',
                ),
                _detail(
                  'Tests',
                  '${totals.graded} graded · ${totals.absent} absent · ${totals.pending} not entered',
                ),
                const Divider(height: 24),
                if (rows.isEmpty) const Text('No test records available.'),
                for (final result in rows) _testRecordCard(result),
              ]);
            },
          ),
      ],
    );
  }

  Widget _results({String? subject, bool individual = false}) {
    final rows = _data!.results
        .where((r) => !individual || r.subject == subject)
        .toList();
    final totals = StudentResultTotals(rows);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section(
          individual
              ? '${subject == null ? 'Subject' : AuthService.subjectLabel(subject)} results'
              : 'Combined results · all subjects',
          [
            _detail(
              'Marks',
              totals.maximum > 0
                  ? '${_number(totals.obtained)} / ${_number(totals.maximum)}'
                  : '—',
            ),
            _detail(
              'Percentage',
              totals.percentage == null
                  ? '—'
                  : '${totals.percentage!.toStringAsFixed(1)}%',
            ),
            _detail(
              'Tests',
              '${totals.graded} graded · ${totals.absent} absent · ${totals.pending} not entered',
            ),
            const Text(
              'Absent and unmarked tests are excluded. A saved numeric 0/X is included in the percentage.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
        if (!individual)
          _section('Subject summary', [
            for (final code in _data!.subjects)
              Builder(
                builder: (_) {
                  final summary = StudentResultTotals(
                    rows.where((r) => r.subject == code).toList(),
                  );
                  return _detail(
                    AuthService.subjectLabel(code),
                    summary.maximum <= 0
                        ? '—'
                        : '${_number(summary.obtained)} / ${_number(summary.maximum)}'
                              ' · ${summary.percentage!.toStringAsFixed(1)}%',
                  );
                },
              ),
          ]),
        _section('Individual test records', [
          if (rows.isEmpty) const Text('No test records available.'),
          if (rows.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 650) {
                  return Column(children: rows.map(_testRecordCard).toList());
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Subject')),
                      DataColumn(label: Text('Test')),
                      DataColumn(label: Text('Marks')),
                      DataColumn(label: Text('Result')),
                    ],
                    rows: rows
                        .map(
                          (r) => DataRow(
                            cells: [
                              DataCell(Text(_date(r.test['test_date']))),
                              DataCell(
                                Text(AuthService.subjectLabel(r.subject)),
                              ),
                              DataCell(Text('T${r.test['test_no']}')),
                              DataCell(
                                Text(
                                  r.absent
                                      ? 'A'
                                      : r.pending || r.maximum <= 0
                                      ? '—'
                                      : '${_number(r.obtained)} / ${_number(r.maximum)}',
                                ),
                              ),
                              DataCell(
                                Text(
                                  r.absent
                                      ? 'Absent'
                                      : r.pending
                                      ? 'Not entered'
                                      : '${(r.maximum > 0 ? r.obtained * 100 / r.maximum : 0).toStringAsFixed(1)}%',
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                );
              },
            ),
        ]),
      ],
    );
  }

  Widget _testRecordCard(StudentTestResult result) {
    final color = result.absent
        ? AppTheme.danger
        : result.pending
        ? AppTheme.textSecondary
        : AppTheme.info;
    return Container(
      key: ValueKey('student-test-${result.test['id']}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  result.absent
                      ? Icons.event_busy_outlined
                      : Icons.assignment_outlined,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${AuthService.subjectLabel(result.subject)} · T${result.test['test_no']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _date(result.test['test_date']),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    result.absent
                        ? 'A'
                        : result.pending || result.maximum <= 0
                        ? '—'
                        : '${_number(result.obtained)} / ${_number(result.maximum)}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.absent
                        ? 'Absent'
                        : result.pending
                        ? 'Not entered'
                        : '${(result.maximum > 0 ? result.obtained * 100 / result.maximum : 0).toStringAsFixed(1)}%',
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          if (!result.pending && result.maximum > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (result.obtained / result.maximum).clamp(0.0, 1.0),
                color: color,
                backgroundColor: color.withValues(alpha: 0.08),
                minHeight: 5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
