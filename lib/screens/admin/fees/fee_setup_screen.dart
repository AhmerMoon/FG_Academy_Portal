import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app_theme.dart';
import '../../../models/fee_models.dart';
import '../../../utils/error_state_view.dart';
import '../../../utils/fee_month.dart';

class FeeSetupScreen extends StatefulWidget {
  final VoidCallback? onDataChanged;

  const FeeSetupScreen({super.key, this.onDataChanged});

  @override
  State<FeeSetupScreen> createState() => _FeeSetupScreenState();
}

class _FeeSetupScreenState extends State<FeeSetupScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  List<String> _months = [];
  String? _selectedMonth;

  List<_DistributionConfig> _distributions = [];
  List<_FeeTeacherConfig> _teachers = [];

  final Set<String> _savingKeys = {};

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();

    _load();
  }

  String _number(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  Future<List<String>> _fetchMonths() async {
    final response = await _client
        .from('fee_summary_totals')
        .select('payment_month, month_start')
        .eq('section', 'collection')
        .eq('group_name', 'ALL')
        .order('month_start', ascending: false);

    final raw = response
        .map((row) => row['payment_month']?.toString())
        .whereType<String>();

    return FeeMonth.newestFirst(raw);
  }

  Future<void> _load({String? preferredMonth}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final months = await _fetchMonths();

      if (months.isEmpty) {
        throw StateError('No fee months are available.');
      }

      var month = preferredMonth ?? _selectedMonth;

      if (month == null || !months.contains(month)) {
        month = months.first;
      }

      await _client.rpc(
        'admin_ensure_fee_month_setup',
        params: {'p_payment_month': month},
      );

      final results = await Future.wait<dynamic>([
        _client
            .from('fee_month_distribution_settings')
            .select(
              'payment_month, level_group, '
              'teacher_percent, nts_percent, '
              'building_percent, admin_percent, '
              'organizer_percent, ecc_percent',
            )
            .eq('payment_month', month),
        _client
            .from('fee_month_teacher_assignments')
            .select(
              'payment_month, level_group, '
              'subject_code, teacher_name, '
              'display_order',
            )
            .eq('payment_month', month)
            .order('level_group')
            .order('display_order'),
      ]);

      final distributions = (results[0] as List)
          .map(
            (row) =>
                _DistributionConfig.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();

      distributions.sort((a, b) {
        int rank(String value) {
          switch (value) {
            case 'SSC':
              return 0;
            case 'HSSC':
              return 1;
            default:
              return 9;
          }
        }

        return rank(a.levelGroup).compareTo(rank(b.levelGroup));
      });

      final teachers = (results[1] as List)
          .map(
            (row) => _FeeTeacherConfig.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        _months = months;
        _selectedMonth = month;
        _distributions = distributions;
        _teachers = teachers;

        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('Fee setup load error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to load fee setup.';
      });
    }
  }

  void _message(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  Future<void> _editDistribution(_DistributionConfig config) async {
    final teacher = TextEditingController(text: _number(config.teacher));

    final nts = TextEditingController(text: _number(config.nts));

    final building = TextEditingController(text: _number(config.building));

    final admin = TextEditingController(text: _number(config.admin));

    final organizer = TextEditingController(text: _number(config.organizer));

    final ecc = TextEditingController(text: _number(config.ecc));

    String? dialogError;

    final result = await showDialog<_DistributionDraft>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double? value(TextEditingController c) {
              return double.tryParse(c.text.trim().replaceAll(',', ''));
            }

            void submit() {
              final teacherValue = value(teacher);

              final ntsValue = value(nts);

              final buildingValue = value(building);

              final adminValue = value(admin);

              final organizerValue = value(organizer);

              final eccValue = value(ecc);

              final values = [
                teacherValue,
                ntsValue,
                buildingValue,
                adminValue,
                organizerValue,
                eccValue,
              ];

              if (values.any((item) => item == null)) {
                setDialogState(() {
                  dialogError = 'Enter valid percentages in every field.';
                });

                return;
              }

              final clean = values.whereType<double>().toList();

              if (clean.any((item) => item < 0 || item > 100)) {
                setDialogState(() {
                  dialogError = 'Each percentage must be between 0 and 100.';
                });

                return;
              }

              final total = clean.fold<double>(
                0,
                (previous, item) => previous + item,
              );

              if ((total - 100).abs() > 0.001) {
                setDialogState(() {
                  dialogError =
                      'Total must be exactly 100%. Current total: ${_number(total)}%';
                });

                return;
              }

              Navigator.of(dialogContext).pop(
                _DistributionDraft(
                  teacher: teacherValue!,
                  nts: ntsValue!,
                  building: buildingValue!,
                  admin: adminValue!,
                  organizer: organizerValue!,
                  ecc: eccValue!,
                ),
              );
            }

            Widget field(String label, TextEditingController controller) {
              return TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: label, suffixText: '%'),
              );
            }

            return AlertDialog(
              title: Text('${config.levelGroup} Distribution'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Calculated financial cells remain read-only. '
                        'Only the distribution inputs are changed here.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),

                      const SizedBox(height: 16),

                      field('Teacher Share', teacher),

                      const SizedBox(height: 10),

                      field('NTS', nts),

                      const SizedBox(height: 10),

                      field('Building', building),

                      const SizedBox(height: 10),

                      field('Admin', admin),

                      const SizedBox(height: 10),

                      field('Organizer', organizer),

                      const SizedBox(height: 10),

                      field('ECC', ecc),

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
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: submit,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    teacher.dispose();
    nts.dispose();
    building.dispose();
    admin.dispose();
    organizer.dispose();
    ecc.dispose();

    if (result == null || !mounted) {
      return;
    }

    final month = _selectedMonth;

    if (month == null) return;

    final key = 'distribution-${config.levelGroup}';

    setState(() {
      _savingKeys.add(key);
    });

    try {
      await _client.rpc(
        'admin_update_fee_month_distribution',
        params: {
          'p_payment_month': month,
          'p_level_group': config.levelGroup,
          'p_teacher_percent': result.teacher,
          'p_nts_percent': result.nts,
          'p_building_percent': result.building,
          'p_admin_percent': result.admin,
          'p_organizer_percent': result.organizer,
          'p_ecc_percent': result.ecc,
        },
      );

      widget.onDataChanged?.call();

      await _load(preferredMonth: month);

      _message('${config.levelGroup} percentages updated for $month.');
    } catch (e) {
      debugPrint('Fee distribution save error: $e');

      _message('Unable to update percentages.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _savingKeys.remove(key);
        });
      }
    }
  }

  Future<void> _editTeacher(_FeeTeacherConfig teacher) async {
    final controller = TextEditingController(text: teacher.teacherName);

    String? dialogError;

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final value = controller.text.trim();

              if (value.isEmpty) {
                setDialogState(() {
                  dialogError = 'Teacher name is required.';
                });

                return;
              }

              Navigator.of(dialogContext).pop(value);
            }

            return AlertDialog(
              title: Text('${feeSubjectLabel(teacher.subjectCode)} Teacher'),
              content: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${teacher.levelGroup} • ${feeSubjectLabel(teacher.subjectCode)}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: controller,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => submit(),
                      decoration: const InputDecoration(
                        labelText: 'Teacher Name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),

                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
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
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: submit,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Name'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (name == null || !mounted) {
      return;
    }

    final month = _selectedMonth;

    if (month == null) return;

    final key = 'teacher-${teacher.levelGroup}-${teacher.subjectCode}';

    setState(() {
      _savingKeys.add(key);
    });

    try {
      await _client.rpc(
        'admin_update_fee_month_teacher_name',
        params: {
          'p_payment_month': month,
          'p_level_group': teacher.levelGroup,
          'p_subject_code': teacher.subjectCode,
          'p_teacher_name': name,
        },
      );

      widget.onDataChanged?.call();

      await _load(preferredMonth: month);

      _message('${feeSubjectLabel(teacher.subjectCode)} teacher updated.');
    } catch (e) {
      debugPrint('Fee teacher save error: $e');

      _message('Unable to update teacher name.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _savingKeys.remove(key);
        });
      }
    }
  }

  Widget _distributionCard(_DistributionConfig config) {
    final key = 'distribution-${config.levelGroup}';

    final saving = _savingKeys.contains(key);

    Widget value(String label, double number) {
      return Container(
        constraints: const BoxConstraints(minWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_number(number)}%',
              style: const TextStyle(
                color: AppTheme.fgNavyBlue,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${config.levelGroup} Distribution',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: saving ? null : () => _editDistribution(config),
                  icon: saving
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              ],
            ),

            const SizedBox(height: 13),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                value('Teacher', config.teacher),
                value('NTS', config.nts),
                value('Building', config.building),
                value('Admin', config.admin),
                value('Organizer', config.organizer),
                value('ECC', config.ecc),
              ],
            ),

            const SizedBox(height: 10),

            const Text(
              'Total: 100%',
              style: TextStyle(
                color: AppTheme.success,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teachersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Financial Report Teacher Names',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 5),

            Text(
              'These names are stored for ${_selectedMonth ?? ''} only.',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),

            const SizedBox(height: 13),

            ..._teachers.map((teacher) {
              final key =
                  'teacher-${teacher.levelGroup}-${teacher.subjectCode}';

              final saving = _savingKeys.contains(key);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceSoft,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppTheme.border),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.fgNavyBlue.withValues(
                      alpha: 0.08,
                    ),
                    foregroundColor: AppTheme.fgNavyBlue,
                    child: const Icon(Icons.school_outlined),
                  ),
                  title: Text(
                    teacher.teacherName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${teacher.levelGroup} • '
                    '${feeSubjectLabel(teacher.subjectCode)}',
                  ),
                  trailing: saving
                      ? const SizedBox(
                          width: 25,
                          height: 25,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          tooltip: 'Edit Teacher Name',
                          onPressed: () => _editTeacher(teacher),
                          icon: const Icon(Icons.edit_outlined),
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
      onRefresh: () => _load(preferredMonth: _selectedMonth),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 30),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune_rounded, color: AppTheme.fgNavyBlue),
                      SizedBox(width: 9),
                      Text(
                        'Fee Setup',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 7),

                  const Text(
                    'Edit only the input values. '
                    'Calculated fee breakdown cells remain automatic.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),

                  const SizedBox(height: 15),

                  DropdownButtonFormField<String>(
                    initialValue: _selectedMonth,
                    decoration: const InputDecoration(
                      labelText: 'Fee Month',
                      prefixIcon: Icon(Icons.calendar_month_outlined),
                    ),
                    items: _months
                        .map(
                          (month) => DropdownMenuItem(
                            value: month,
                            child: Text(month),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      _load(preferredMonth: value);
                    },
                  ),
                ],
              ),
            ),
          ),

          ..._distributions.map(_distributionCard),

          const SizedBox(height: 2),

          _teachersCard(),
        ],
      ),
    );
  }
}

class _DistributionConfig {
  final String levelGroup;

  final double teacher;
  final double nts;
  final double building;
  final double admin;
  final double organizer;
  final double ecc;

  const _DistributionConfig({
    required this.levelGroup,
    required this.teacher,
    required this.nts,
    required this.building,
    required this.admin,
    required this.organizer,
    required this.ecc,
  });

  factory _DistributionConfig.fromJson(Map<String, dynamic> json) {
    double n(String key) => (json[key] as num?)?.toDouble() ?? 0;

    return _DistributionConfig(
      levelGroup: json['level_group']?.toString() ?? '',
      teacher: n('teacher_percent'),
      nts: n('nts_percent'),
      building: n('building_percent'),
      admin: n('admin_percent'),
      organizer: n('organizer_percent'),
      ecc: n('ecc_percent'),
    );
  }
}

class _DistributionDraft {
  final double teacher;
  final double nts;
  final double building;
  final double admin;
  final double organizer;
  final double ecc;

  const _DistributionDraft({
    required this.teacher,
    required this.nts,
    required this.building,
    required this.admin,
    required this.organizer,
    required this.ecc,
  });
}

class _FeeTeacherConfig {
  final String levelGroup;
  final String subjectCode;
  final String teacherName;
  final int displayOrder;

  const _FeeTeacherConfig({
    required this.levelGroup,
    required this.subjectCode,
    required this.teacherName,
    required this.displayOrder,
  });

  factory _FeeTeacherConfig.fromJson(Map<String, dynamic> json) {
    return _FeeTeacherConfig(
      levelGroup: json['level_group']?.toString() ?? '',
      subjectCode: json['subject_code']?.toString() ?? '',
      teacherName: json['teacher_name']?.toString() ?? '',
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 99,
    );
  }
}
