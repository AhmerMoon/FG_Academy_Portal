import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../models/printable_request.dart';
import '../services/auth_service.dart';
import '../services/docx_space_saver.dart';
import '../services/printables_service.dart';
import '../utils/dashboard_section_header.dart';
import '../utils/error_state_view.dart';
import '../utils/printable_file_actions.dart';

String _printableError(Object error) {
  if (error is PostgrestException) {
    if (error.code == 'PGRST202' ||
        error.code == 'PGRST205' ||
        error.code == '42P01') {
      return 'Printables setup is not available yet. Please contact the administrator.';
    }
    if (error.code == 'P0001') return error.message;
    return 'Could not save request (${error.code ?? 'server'}): ${error.message}';
  }
  if (error is StorageException) {
    if (error.statusCode == '401') {
      return 'Your session expired. Sign in again and retry.';
    }
    if (error.statusCode == '403') {
      return 'File access denied (403). Contact the administrator.';
    }
    if (error.statusCode == '413') {
      return 'The selected file exceeds the upload size limit.';
    }
    final message = error.message.length > 200
        ? error.message.substring(0, 200)
        : error.message;
    return 'File upload failed (${error.statusCode ?? 'connection'}): $message';
  }
  if (error is AuthException) return 'Please sign in again: ${error.message}';
  if (error is ArgumentError) return error.message.toString();
  if (error is StateError) return error.message;
  return 'Could not complete the request. Check your connection and try again.';
}

class PrintablesScreen extends StatefulWidget {
  final bool isAdmin;
  final PrintablesService? service;
  final VoidCallback? onChanged;
  const PrintablesScreen({
    super.key,
    required this.isAdmin,
    this.service,
    this.onChanged,
  });

  @override
  State<PrintablesScreen> createState() => _PrintablesScreenState();
}

class _PrintablesScreenState extends State<PrintablesScreen>
    with WidgetsBindingObserver {
  late final PrintablesService _service;
  final _search = TextEditingController();
  List<PrintableRequest> _requests = [];
  final _busy = <String>{};
  Timer? _timer;
  bool _loading = true;
  bool _refreshing = false;
  bool _openingForm = false;
  bool _deletingAll = false;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PrintablesService();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final rows = await _service.fetchRequests();
      if (!mounted) return;
      setState(() {
        _requests = rows;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _printableError(error);
      });
    } finally {
      _refreshing = false;
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<String> _downloadFolders(PrintableRequest request) {
    final root = request.isTestSession ? 'Test Session' : 'Normal Tests';
    final folders = <String>[
      root,
      request.batchName,
      AuthService.subjectLabel(request.subjectCode),
    ];
    if (request.isTestSession) {
      final number = printableTestNumber(request.fileName);
      folders.add(
        number == null
            ? DateFormat('yyyy-MM-dd').format(request.testDate)
            : 'Test $number',
      );
    } else {
      folders.add(DateFormat('yyyy-MM-dd').format(request.testDate));
    }
    return folders;
  }

  Future<void> _newRequest([PrintableRequest? editing]) async {
    if (_openingForm) return;
    setState(() => _openingForm = true);
    try {
      final choices = await _service.fetchChoices();
      if (!mounted) return;
      if (choices.isEmpty) {
        _message(
          'No assigned classes and subjects are available. Contact the administrator.',
        );
        return;
      }
      setState(() => _openingForm = false);
      var cleanupComplete = true;
      final submitted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SubmissionDialog(
          service: _service,
          choices: choices,
          editing: editing,
          onCleanupPending: () => cleanupComplete = false,
        ),
      );
      if (submitted == true) {
        widget.onChanged?.call();
        _message(
          editing == null
              ? 'Printable submitted. The administrator can now see your request.'
              : cleanupComplete
              ? 'Printable updated and marked Pending.'
              : 'Printable updated. Old file removal failed; admin can retry Delete All.',
        );
        await _load();
      }
    } catch (error) {
      _message(_printableError(error));
    } finally {
      if (mounted) setState(() => _openingForm = false);
    }
  }

  Future<void> _delete({PrintableRequest? request}) async {
    final all = request == null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(all ? 'Delete all printables?' : 'Delete printable?'),
        content: Text(
          all
              ? 'All submitted printables and their files will be permanently deleted, including those outside your current filter.'
              : '${request.title}\n\nThe request and its file will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: Text(all ? 'Delete all' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      if (all) {
        _deletingAll = true;
      } else {
        _busy.add(request.id);
      }
    });
    try {
      final count = await _service.deleteRequests(
        requestId: request?.id,
        all: all,
      );
      _message('$count printable(s) deleted with their files.');
    } catch (error) {
      _message('${_printableError(error)} Delete can be retried safely.');
    } finally {
      if (mounted) {
        widget.onChanged?.call();
        setState(() {
          _deletingAll = false;
          _busy.remove(request?.id);
        });
        await _load();
      }
    }
  }

  Future<void> _action(PrintableRequest request, String action) async {
    setState(() => _busy.add(request.id));
    try {
      if (action == 'status') {
        await _service.setPrinted(request, !request.isPrinted);
        widget.onChanged?.call();
        await _load();
      } else {
        final bytes = await _service.download(request);
        if (!mounted) return;
        if (action == 'download') {
          final saved = await savePrintable(
            bytes,
            request.fileName,
            printableMimeType(request.fileName),
            folders: _downloadFolders(request),
          );
          if (saved) {
            _message(
              kIsWeb
                  ? 'Download started.'
                  : 'File saved. On Windows it is in Academy Portal Data / Printables.',
            );
          }
        } else if (request.isPdf) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _PrintablePdfPreview(
                request: request,
                bytes: bytes,
                isAdmin: widget.isAdmin,
              ),
            ),
          );
        } else {
          final isDocx = printableExtension(request.fileName) == 'docx';
          if (isDocx) {
            final compacted = await compactDocx(bytes, request.fileName);
            await openPrintableWord(
              compacted.bytes,
              compacted.fileName,
              printableMimeType(compacted.fileName),
            );
            _message(
              compacted.wasCompacted
                  ? 'Space-saved copy created from a ${compacted.detectedPages}-page paper: '
                        '${compacted.optionGroupsCompacted} option group(s) arranged, '
                        '${compacted.blankLinesRemoved} extra blank line(s) removed. Review it in Word before printing ${request.copies} copies.'
                  : 'This paper is already detected as one page, so it was opened unchanged.',
            );
          } else {
            await openPrintableWord(
              bytes,
              request.fileName,
              printableMimeType(request.fileName),
            );
            _message(
              'Legacy DOC opened unchanged. Save it as DOCX in Word to use automatic space saving.',
            );
          }
        }
      }
    } catch (error) {
      _message(_printableError(error));
    } finally {
      if (mounted) setState(() => _busy.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final active = _requests.where((r) => !r.isExpired).toList();
    final visible = active
        .where(
          (r) =>
              (_filter == 'all' || r.status == _filter) &&
              '${r.title} ${r.teacherName} ${r.batchName} ${AuthService.subjectLabel(r.subjectCode)} ${DateFormat('dd MMM yyyy').format(r.testDate)}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return Column(
      children: [
        DashboardSectionHeader(
          title: 'Printables',
          subtitle: widget.isAdmin
              ? 'Test papers and print requests'
              : 'Submit test papers for printing',
          trailing: IconButton(
            onPressed: () => _load(),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search printables',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
              ),
              if (!widget.isAdmin) ...[
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _openingForm ? null : _newRequest,
                  tooltip: 'Submit printable',
                  icon: _openingForm
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded),
                ),
              ],
              if (widget.isAdmin)
                IconButton(
                  tooltip: 'Delete all printables',
                  onPressed: _deletingAll || _busy.isNotEmpty
                      ? null
                      : () => _delete(),
                  color: AppTheme.danger,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
            ],
          ),
        ),
        if (_deletingAll) const LinearProgressIndicator(),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final entry in {
                'all': 'All',
                'pending': 'Pending',
                'printed': 'Printed',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      '${entry.value} (${active.where((r) => entry.key == 'all' || r.status == entry.key).length})',
                    ),
                    selected: _filter == entry.key,
                    onSelected: (_) => setState(() => _filter = entry.key),
                  ),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Text(
            'Files stay available through the day after the test (Pakistan time). PDF is recommended for direct printing.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? ErrorStateView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 24),
                    itemCount: visible.isEmpty ? 1 : visible.length,
                    itemBuilder: (context, index) {
                      if (visible.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(36),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.print_outlined,
                                size: 48,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                query.isNotEmpty || _filter != 'all'
                                    ? 'No matching requests.'
                                    : widget.isAdmin
                                    ? 'No print requests yet.'
                                    : 'Tap + to submit your first test paper.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }
                      return _requestCard(visible[index]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _requestCard(PrintableRequest request) {
    final busy = _deletingAll || _busy.contains(request.id);
    final deleting = request.status == 'deleting';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  request.isPdf
                      ? Icons.picture_as_pdf_outlined
                      : Icons.description_outlined,
                  color: AppTheme.fgNavyBlue,
                  size: 30,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${request.batchName} · ${AuthService.subjectLabel(request.subjectCode)}',
                      ),
                      Text(
                        request.teacherName,
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Chip(
                  label: Text(
                    deleting
                        ? 'Delete pending'
                        : request.isPrinted
                        ? 'Printed'
                        : 'Pending',
                  ),
                  avatar: Icon(
                    request.isPrinted
                        ? Icons.check_circle_outline
                        : Icons.schedule,
                    size: 17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                Text(
                  'Test: ${DateFormat('EEE, dd MMM yyyy').format(request.testDate)}',
                ),
                Text(
                  '${request.copies} copies',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    request.isTestSession ? 'Test Session' : 'Normal Test',
                  ),
                  avatar: Icon(
                    request.isTestSession
                        ? Icons.event_note_rounded
                        : Icons.assignment_outlined,
                    size: 17,
                  ),
                ),
              ],
            ),
            if (request.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(request.notes),
              ),
            const SizedBox(height: 8),
            Text(
              request.fileName,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            Text(
              'Available until ${DateFormat('dd MMM yyyy, h:mm a').format(request.expiresAt.add(const Duration(hours: 5)).subtract(const Duration(minutes: 1)))} PKT',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            if (busy) const LinearProgressIndicator(),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: busy || deleting
                      ? null
                      : () => _action(request, 'download'),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download'),
                ),
                TextButton.icon(
                  onPressed: busy || deleting
                      ? null
                      : () => _action(request, 'print'),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(
                    request.isPdf
                        ? 'Preview / Print'
                        : kIsWeb
                        ? printableExtension(request.fileName) == 'docx'
                              ? 'Compact / Download'
                              : 'Download to print'
                        : printableExtension(request.fileName) == 'docx'
                        ? 'Compact / Open in Word'
                        : 'Open in Word',
                  ),
                ),
                if (widget.isAdmin)
                  TextButton.icon(
                    onPressed: busy || deleting
                        ? null
                        : () => _action(request, 'status'),
                    icon: Icon(
                      request.isPrinted
                          ? Icons.undo_rounded
                          : Icons.check_circle_outline,
                    ),
                    label: Text(
                      request.isPrinted ? 'Mark pending' : 'Mark printed',
                    ),
                  ),
                if (!widget.isAdmin)
                  TextButton.icon(
                    onPressed: busy || deleting
                        ? null
                        : () => _newRequest(request),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                TextButton.icon(
                  onPressed: busy ? null : () => _delete(request: request),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(deleting ? 'Retry delete' : 'Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrintablePdfPreview extends StatelessWidget {
  final PrintableRequest request;
  final Uint8List bytes;
  final bool isAdmin;
  const _PrintablePdfPreview({
    required this.request,
    required this.bytes,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(request.title)),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Requested: ${request.copies} copies. Set the copy count in the print dialog.'
            '${isAdmin ? ' After printing, return to the list and mark this request Printed.' : ''}',
          ),
        ),
        Expanded(
          child: PdfPreview(
            build: (_) async => bytes,
            pdfFileName: request.fileName,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            dynamicLayout: false,
            allowSharing: false,
          ),
        ),
      ],
    ),
  );
}

class _SubmissionDialog extends StatefulWidget {
  final PrintablesService service;
  final List<Map<String, dynamic>> choices;
  final PrintableRequest? editing;
  final VoidCallback? onCleanupPending;
  const _SubmissionDialog({
    required this.service,
    required this.choices,
    this.editing,
    this.onCleanupPending,
  });

  @override
  State<_SubmissionDialog> createState() => _SubmissionDialogState();
}

class _SubmissionDialogState extends State<_SubmissionDialog> {
  final _form = GlobalKey<FormState>();
  final _copies = TextEditingController();
  int _choice = 0;
  DateTime _date = pakistanToday().add(const Duration(days: 1));
  Uint8List? _bytes;
  String? _fileName;
  String? _error;
  bool _submitting = false;
  bool _picking = false;
  String _paperType = printablePaperNormal;
  bool _paperTypeTouched = false;

  @override
  void initState() {
    super.initState();
    final request = widget.editing;
    if (request != null) {
      _copies.text = request.copies.toString();
      _date = request.testDate;
      _fileName = request.fileName;
      _paperType = request.paperType;
      _paperTypeTouched = true;
      final classLevel = RegExp(r'\d+').firstMatch(request.batchName)?.group(0);
      final index = widget.choices.indexWhere(
        (choice) =>
            choice['subject_code'] == request.subjectCode &&
            RegExp(
                  r'\d+',
                ).firstMatch(choice['batch_name'] as String)?.group(0) ==
                classLevel,
      );
      if (index >= 0) _choice = index;
    }
  }

  @override
  void dispose() {
    _copies.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final file = await pickPrintableFile();
      if (file == null || !mounted) return;
      final size = await file.length();
      if (size == null) {
        throw StateError(
          'Could not read the selected file. Choose a local copy.',
        );
      }
      final error = validatePrintableFile(file.name, size);
      if (error != null) throw ArgumentError(error);
      final bytes = await file.readAsBytes();
      final bytesError = validatePrintableFile(file.name, bytes.length);
      if (bytesError != null) throw ArgumentError(bytesError);
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _bytes = bytes;
        if (!_paperTypeTouched) {
          _paperType = inferPrintablePaperType(file.name);
        }
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _printableError(error));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_bytes == null && widget.editing == null) {
      setState(() => _error = 'Attach your test paper first.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final choice = widget.choices[_choice];
      if (widget.editing != null) {
        final cleaned = await widget.service.updateRequest(
          widget.editing!,
          batchId: choice['batch_id'] as String,
          subjectCode: choice['subject_code'] as String,
          testDate: _date,
          copies: int.parse(_copies.text.trim()),
          fileName: _fileName!,
          bytes: _bytes,
          paperType: _paperType,
        );
        if (!cleaned) widget.onCleanupPending?.call();
      } else {
        await widget.service.submit(
          batchId: choice['batch_id'] as String,
          subjectCode: choice['subject_code'] as String,
          title: _fileName!.length > 120
              ? _fileName!.substring(0, 120)
              : _fileName!,
          testDate: _date,
          copies: int.parse(_copies.text.trim()),
          notes: '',
          fileName: _fileName!,
          paperType: _paperType,
          bytes: _bytes!,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '${_printableError(error)} If the connection dropped during submission, check your list before trying again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: AlertDialog(
      title: Text(
        widget.editing == null ? 'Submit printable' : 'Edit printable',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Subject'),
                  child: Text(
                    AuthService.subjectLabel(
                      widget.choices[_choice]['subject_code'] as String,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _choice,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Class',
                    helperText:
                        'Both boys and girls; enter total copies below.',
                  ),
                  items: [
                    for (var i = 0; i < widget.choices.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          widget.choices[i]['batch_name'] as String,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _choice = value!),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _submitting
                      ? null
                      : () async {
                          final today = pakistanToday();
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _date.isBefore(today) ? today : _date,
                            firstDate: today,
                            lastDate: today.add(const Duration(days: 366)),
                          );
                          if (date != null && mounted) {
                            setState(() => _date = date);
                          }
                        },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(
                    'Test: ${DateFormat('EEE, dd MMM yyyy').format(_date)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _copies,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Number of copies',
                  ),
                  validator: (value) {
                    final count = int.tryParse(value?.trim() ?? '');
                    return count == null || count < 1 || count > 5000
                        ? 'Enter 1 to 5000 copies.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Paper type',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Normal Test'),
                        value: _paperType == printablePaperNormal,
                        onChanged: _submitting
                            ? null
                            : (_) => setState(() {
                                _paperType = printablePaperNormal;
                                _paperTypeTouched = true;
                              }),
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Test Session'),
                        value: _paperType == printablePaperTestSession,
                        onChanged: _submitting
                            ? null
                            : (_) => setState(() {
                                _paperType = printablePaperTestSession;
                                _paperTypeTouched = true;
                              }),
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Choose one. If untouched, names such as “Test 1” or “Week 1” are detected automatically.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _submitting || _picking ? null : _pick,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(
                    _picking
                        ? 'Reading file…'
                        : _fileName == null
                        ? 'Attach PDF / Word (max 20 MB)'
                        : 'Replace file',
                  ),
                ),
                if (_fileName != null)
                  Text(
                    _fileName!,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'PDF supports printing inside the app. Word files open in a compatible app for printing.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Available through ${DateFormat('dd MMM yyyy').format(printableExpiry(_date).add(const Duration(hours: 5)).subtract(const Duration(days: 1)))}. Files are then automatically removed.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppTheme.danger),
                    ),
                  ),
                if (_submitting)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submitting || _picking ? null : _submit,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: Text(
            _submitting
                ? 'Saving…'
                : widget.editing == null
                ? 'Submit'
                : 'Save changes',
          ),
        ),
      ],
    ),
  );
}
