import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/fee_models.dart';
import '../utils/student_group_helper.dart';
import 'student_subject_selector.dart';

class NewStudentRequest {
  final String name;
  final FeeBatch batch;
  final double defaultFee;
  final List<String> subjects;

  const NewStudentRequest({
    required this.name,
    required this.batch,
    required this.defaultFee,
    required this.subjects,
  });
}

Future<NewStudentRequest?> showAcademyAddStudentDialog({
  required BuildContext context,
  required List<FeeBatch> batches,
  required FeeBatch initialBatch,
  required String paymentMonth,
  bool lockBatch = false,
}) async {
  FeeBatch dialogBatch = initialBatch;

  final nameController = TextEditingController();
  final feeController = TextEditingController(
    text: dialogBatch.classLevel <= 10 ? '5500' : '6000',
  );

  var selectedSubjects = List<String>.from(
    studentDefaultSubjectsForClass(dialogBatch.classLevel),
  );

  String? dialogError;

  try {
    return await showDialog<NewStudentRequest>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              title: const Row(
                children: [
                  Icon(Icons.person_add_alt_1, color: AppTheme.fgNavyBlue),
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
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(dialogBatch.id),
                      initialValue: dialogBatch.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Batch',
                        prefixIcon: Icon(Icons.class_outlined),
                      ),
                      items: batches.map((batch) {
                        return DropdownMenuItem(
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

                                feeController.text = newBatch.classLevel <= 10
                                    ? '5500'
                                    : '6000';

                                selectedSubjects = List<String>.from(
                                  studentDefaultSubjectsForClass(
                                    newBatch.classLevel,
                                  ),
                                );

                                dialogError = null;
                              });
                            },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Student Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: feeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Default Monthly Fee',
                        prefixText: 'Rs ',
                        helperText: dialogBatch.classLevel <= 10
                            ? 'SSC suggested fee: Rs 5,500'
                            : 'HSSC suggested fee: Rs 6,000',
                      ),
                    ),
                    const SizedBox(height: 20),
                    StudentSubjectSelector(
                      classLevel: dialogBatch.classLevel,
                      selectedSubjects: selectedSubjects,
                      onChanged: (subjects) {
                        setDialogState(() {
                          selectedSubjects = subjects;
                          dialogError = null;
                        });
                      },
                      onValidationError: (message) {
                        setDialogState(() {
                          dialogError = message;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'On save: student will be created, '
                        'today attendance will be Present, '
                        'and $paymentMonth fee will start as Unpaid.',
                        style: const TextStyle(fontSize: 12.5, height: 1.45),
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        style: const TextStyle(
                          color: AppTheme.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add Student'),
                  onPressed: () {
                    final name = nameController.text.trim();

                    final fee = double.tryParse(feeController.text.trim());

                    if (name.isEmpty) {
                      setDialogState(() {
                        dialogError = 'Student name is required.';
                      });
                      return;
                    }

                    if (fee == null || fee <= 0) {
                      setDialogState(() {
                        dialogError = 'Enter a valid default fee.';
                      });
                      return;
                    }

                    final validation = studentSubjectSelectionError(
                      dialogBatch.classLevel,
                      selectedSubjects,
                    );

                    if (validation != null) {
                      setDialogState(() {
                        dialogError = validation;
                      });
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      NewStudentRequest(
                        name: name,
                        batch: dialogBatch,
                        defaultFee: fee,
                        subjects: List<String>.from(selectedSubjects),
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
    feeController.dispose();
  }
}
