import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/fee_models.dart';
import '../utils/student_group_helper.dart';

class NewStudentRequest {
  final String name;
  final FeeBatch batch;

  // Kept for compatibility with existing screens.
  final double defaultFee;
  final List<String> subjects;

  // New simple Add Student RPC uses this.
  final String groupCode;

  const NewStudentRequest({
    required this.name,
    required this.batch,
    required this.defaultFee,
    required this.subjects,
    required this.groupCode,
  });
}

Future<NewStudentRequest?> showAcademyAddStudentDialog({
  required BuildContext context,
  required List<FeeBatch> batches,
  required FeeBatch initialBatch,
  required String paymentMonth,
  bool lockBatch = false,

  // Compatibility with Teacher Attendance and Award Lists.
  //
  // IMPORTANT:
  // This value must NOT filter the available streams.
  // A teacher can add a student to any valid stream
  // of the selected class.
  String? requiredSubject,
}) async {
  if (batches.isEmpty) {
    return null;
  }

  FeeBatch dialogBatch = initialBatch;

  if (!batches.any((batch) => batch.id == initialBatch.id)) {
    dialogBatch = batches.first;
  }

  final nameController = TextEditingController();

  // Stream is intentionally not preselected.
  // User must explicitly choose one.
  String? selectedGroupCode;

  String? dialogError;

  double defaultFeeForClass(int classLevel) {
    if (classLevel == 9 || classLevel == 10) {
      return 5500;
    }

    if (classLevel == 11 || classLevel == 12) {
      return 6000;
    }

    return 0;
  }

  try {
    return await showDialog<NewStudentRequest>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final classLevel = dialogBatch.classLevel;

            // CRITICAL FIX:
            // Always use ALL presets for the selected class.
            //
            // Do not filter by requiredSubject.
            // Pre-Medical must remain visible even
            // when a Math/Computer teacher adds a student.
            final availableStreams = studentSubjectPresetsForClass(classLevel);

            final selectedPreset = availableStreams
                .cast<StudentSubjectPreset?>()
                .firstWhere(
                  (preset) => preset?.code == selectedGroupCode,
                  orElse: () => null,
                );

            return AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.person_add_alt_1_rounded,
                    color: AppTheme.fgNavyBlue,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Add New Student',
                      style: TextStyle(fontSize: 19),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ====================================
                    // BATCH
                    // ====================================
                    DropdownButtonFormField<String>(
                      key: ValueKey(dialogBatch.id),
                      initialValue: dialogBatch.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Batch',
                        prefixIcon: Icon(Icons.class_outlined),
                      ),
                      items: batches.map((batch) {
                        return DropdownMenuItem<String>(
                          value: batch.id,
                          child: Text(
                            batch.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: lockBatch
                          ? null
                          : (value) {
                              if (value == null) return;

                              final newBatch = batches.firstWhere(
                                (batch) => batch.id == value,
                              );

                              setDialogState(() {
                                dialogBatch = newBatch;

                                // A different class means the
                                // student must choose a new stream.
                                selectedGroupCode = null;
                                dialogError = null;
                              });
                            },
                    ),

                    const SizedBox(height: 15),

                    // ====================================
                    // STUDENT NAME
                    // ====================================
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Student Name *',
                        hintText: 'Enter full name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      onChanged: (_) {
                        if (dialogError != null) {
                          setDialogState(() {
                            dialogError = null;
                          });
                        }
                      },
                    ),

                    const SizedBox(height: 22),

                    // ====================================
                    // STREAM SELECTION
                    // ====================================
                    Row(
                      children: [
                        const Icon(
                          Icons.account_tree_outlined,
                          color: AppTheme.fgNavyBlue,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Select Stream *',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.fgNavyBlue,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Text(
                      'Class $classLevel — choose one stream',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (availableStreams.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No streams available for this class.',
                          style: TextStyle(
                            color: AppTheme.danger,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      ...availableStreams.map((preset) {
                        final selected = selectedGroupCode == preset.code;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: Material(
                            color: selected
                                ? AppTheme.fgNavyBlue.withValues(alpha: 0.07)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setDialogState(() {
                                  selectedGroupCode = preset.code;

                                  dialogError = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected
                                        ? AppTheme.fgNavyBlue
                                        : AppTheme.border,
                                    width: selected ? 1.8 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      selected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked,
                                      color: selected
                                          ? AppTheme.fgNavyBlue
                                          : AppTheme.textSecondary,
                                    ),

                                    const SizedBox(width: 12),

                                    Expanded(
                                      child: Text(
                                        preset.label,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: selected
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: selected
                                              ? AppTheme.fgNavyBlue
                                              : AppTheme.textPrimary,
                                        ),
                                      ),
                                    ),

                                    if (selected)
                                      const Icon(
                                        Icons.check_circle,
                                        color: AppTheme.success,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),

                    // ====================================
                    // INFORMATION
                    // ====================================
                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppTheme.success,
                            size: 19,
                          ),
                          SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Subjects will be assigned '
                              'automatically according to '
                              'the selected stream. '
                              'No separate subject or fee '
                              'selection is required.',
                              style: TextStyle(fontSize: 12.5, height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ====================================
                    // VALIDATION ERROR
                    // ====================================
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),

                      Text(
                        dialogError!,
                        style: const TextStyle(
                          color: AppTheme.danger,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],

                    // Teacher subject is intentionally
                    // not used to hide streams.
                    //
                    // Example:
                    // Math teacher, Class 11:
                    //
                    // FCS             -> visible
                    // Pre-Engineering -> visible
                    // Pre-Medical     -> visible
                  ],
                ),
              ),

              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),

                ElevatedButton.icon(
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add Student'),

                  onPressed: () {
                    final name = nameController.text.trim();

                    if (name.isEmpty) {
                      setDialogState(() {
                        dialogError = 'Student name is required.';
                      });
                      return;
                    }

                    if (selectedPreset == null) {
                      setDialogState(() {
                        dialogError = 'Please select a stream.';
                      });
                      return;
                    }

                    final subjects = studentSubjectsForGroup(
                      dialogBatch.classLevel,
                      selectedPreset.code,
                    );

                    if (subjects.isEmpty) {
                      setDialogState(() {
                        dialogError = 'Invalid stream selection.';
                      });
                      return;
                    }

                    final fee = defaultFeeForClass(dialogBatch.classLevel);

                    if (fee <= 0) {
                      setDialogState(() {
                        dialogError = 'Unsupported class level.';
                      });
                      return;
                    }

                    // Store all information in the
                    // request for compatibility.
                    //
                    // New RPC:
                    // portal_add_student_simple
                    // uses name, batch and groupCode.

                    Navigator.pop(
                      dialogContext,
                      NewStudentRequest(
                        name: name,
                        batch: dialogBatch,
                        defaultFee: fee,
                        subjects: List<String>.from(subjects),
                        groupCode: selectedPreset.code,
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    nameController.dispose();
  }
}
