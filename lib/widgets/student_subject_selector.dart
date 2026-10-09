import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/student_group_helper.dart';

class StudentSubjectSelector extends StatelessWidget {
  final int classLevel;

  final List<String> selectedSubjects;

  final ValueChanged<List<String>> onChanged;

  final ValueChanged<String>? onValidationError;

  const StudentSubjectSelector({
    super.key,
    required this.classLevel,
    required this.selectedSubjects,
    required this.onChanged,
    this.onValidationError,
  });

  bool _sameSet(Iterable<String> a, Iterable<String> b) {
    final first = a.toSet();
    final second = b.toSet();

    return first.length == second.length && first.containsAll(second);
  }

  void _toggleSubject(String code, bool selected) {
    final next = selectedSubjects.toSet();

    if (selected) {
      // SSC: Computer and Biology remain alternatives.
      // Selecting one automatically removes the other.
      if (classLevel == 9 || classLevel == 10) {
        if (code == 'Comp') {
          next.remove('Bio');
        }

        if (code == 'Bio') {
          next.remove('Comp');
        }
      }

      next.add(code);

      // Prevent invalid HSSC combinations
      // and exceeding the maximum subjects.
      final validation = studentSubjectSelectionError(classLevel, next);

      if (validation != null) {
        onValidationError?.call(validation);
        return;
      }
    } else {
      // Allow unchecking subjects, including
      // when a student studies only selected subjects.
      next.remove(code);
    }

    onChanged(normalizeStudentSubjects(classLevel, next));
  }

  @override
  Widget build(BuildContext context) {
    final allowed = studentSubjectCodesForClass(classLevel);

    final presets = studentSubjectPresetsForClass(classLevel);

    final max = studentMaxSubjectsForClass(classLevel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Subjects',
                style: TextStyle(
                  color: AppTheme.fgNavyBlue,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.fgNavyBlue.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${selectedSubjects.length} / $max',
                style: const TextStyle(
                  color: AppTheme.fgNavyBlue,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 5),

        const Text(
          'Presets are optional. Select a preset for speed, then change any checkbox if this student studies fewer or different subjects.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),

        if (presets.isNotEmpty) ...[
          const SizedBox(height: 13),

          const Text(
            'Quick Presets',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 7),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presets.map((preset) {
              final selected = _sameSet(selectedSubjects, preset.subjects);

              return ChoiceChip(
                selected: selected,
                avatar: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.auto_awesome_rounded,
                  size: 17,
                ),
                label: Text(
                  preset.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onSelected: (_) {
                  onChanged(List<String>.from(preset.subjects));
                },
              );
            }).toList(),
          ),
        ],

        const SizedBox(height: 16),

        ...allowed.map((code) {
          final checked = selectedSubjects.contains(code);

          final isHssc = classLevel == 11 || classLevel == 12;

          // An unchecked subject is disabled if selecting
          // it would create an invalid HSSC combination
          // or exceed the 4-subject limit.
          final blocked =
              isHssc &&
              !checked &&
              studentSubjectSelectionError(classLevel, [
                    ...selectedSubjects,
                    code,
                  ]) !=
                  null;

          return CheckboxListTile(
            value: checked,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppTheme.fgNavyBlue,
            title: Text(
              studentSubjectLabel(code),
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            onChanged: blocked
                ? null
                : (value) {
                    _toggleSubject(code, value ?? false);
                  },
          );
        }),

        const SizedBox(height: 4),

        Text(
          classLevel <= 10
              ? 'SSC: maximum 5 subjects. Computer and Biology cannot both be selected.'
              : 'HSSC: maximum 4 subjects. Biology cannot combine with Math or Computer. Computer cannot combine with Chemistry. Invalid options are disabled.',
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
