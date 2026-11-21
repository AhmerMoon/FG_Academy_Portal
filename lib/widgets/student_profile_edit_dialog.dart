import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../services/student_profile_service.dart';
import '../utils/student_group_helper.dart';
import 'student_subject_selector.dart';

class StudentProfileEditDialog extends StatefulWidget {
  final Map<String, dynamic> student;
  final List<Map<String, dynamic>> batches;
  final StudentProfileService service;
  const StudentProfileEditDialog({
    super.key,
    required this.student,
    required this.batches,
    required this.service,
  });

  @override
  State<StudentProfileEditDialog> createState() =>
      _StudentProfileEditDialogState();
}

class _StudentProfileEditDialogState extends State<StudentProfileEditDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late String _batchId;
  late List<String> _subjects;
  bool _saving = false;
  String? _error;

  int get _classLevel =>
      (widget.batches.firstWhere((b) => b['id'] == _batchId)['class_level']
              as num)
          .toInt();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.student['name']?.toString() ?? '',
    );
    _phone = TextEditingController(
      text: widget.student['contact_number']?.toString() ?? '',
    );
    final id = widget.student['batch_id']?.toString();
    _batchId = widget.batches.any((b) => b['id'] == id)
        ? id!
        : widget.batches.first['id'] as String;
    _subjects = normalizeStudentSubjects(
      _classLevel,
      ((widget.student['stream'] as List?) ?? []).map((s) => s.toString()),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final error = studentSubjectSelectionError(_classLevel, _subjects);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final contact = _phone.text.replaceAll(RegExp(r'[\s()\-]'), '');
      await widget.service.saveProfile(
        studentId: widget.student['id'].toString(),
        name: _name.text.trim(),
        batchId: _batchId,
        status: 'enrolled',
        subjects: _subjects,
        contact: contact.isEmpty ? null : contact,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is PostgrestException
              ? error.code == 'PGRST202'
                    ? 'Profile editing is not configured yet.'
                    : error.message
              : 'Could not save changes. Please check your connection and retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Edit student'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: AbsorbPointer(
              absorbing: _saving,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Student name',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter the student name.'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _batchId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Class / batch',
                    ),
                    items: widget.batches
                        .map(
                          (b) => DropdownMenuItem(
                            value: b['id'] as String,
                            child: Text(
                              b['name'].toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      final previousLevel = _classLevel;
                      setState(() {
                        _batchId = value;
                        if (previousLevel != _classLevel) {
                          _subjects = studentDefaultSubjectsForClass(
                            _classLevel,
                          );
                        }
                        _error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact number (optional)',
                    ),
                    validator: (value) {
                      final phone = (value ?? '').replaceAll(
                        RegExp(r'[\s()\-]'),
                        '',
                      );
                      return phone.isNotEmpty &&
                              !RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone)
                          ? 'Enter a valid contact number.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 20),
                  StudentSubjectSelector(
                    classLevel: _classLevel,
                    selectedSubjects: _subjects,
                    onChanged: (value) => setState(() {
                      _subjects = value;
                      _error = null;
                    }),
                    onValidationError: (value) =>
                        setState(() => _error = value),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppTheme.danger),
                      ),
                    ),
                  if (_saving)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving…' : 'Save changes'),
        ),
      ],
    ),
  );
}
