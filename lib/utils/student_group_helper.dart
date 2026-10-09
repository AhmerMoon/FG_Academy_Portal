class StudentSubjectPreset {
  final String code;
  final String label;
  final List<String> subjects;

  const StudentSubjectPreset({
    required this.code,
    required this.label,
    required this.subjects,
  });
}

const List<String> _studentSubjectOrder = [
  'Phy',
  'Chem',
  'Math',
  'Eng',
  'Comp',
  'Bio',
];

String studentSubjectLabel(String code) {
  switch (code) {
    case 'Phy':
      return 'Physics';

    case 'Chem':
      return 'Chemistry';

    case 'Math':
      return 'Mathematics';

    case 'Eng':
      return 'English';

    case 'Comp':
      return 'Computer';

    case 'Bio':
      return 'Biology';

    default:
      return code;
  }
}

List<String> studentSubjectCodesForClass(int classLevel) {
  if (classLevel >= 9 && classLevel <= 12) {
    return List<String>.from(_studentSubjectOrder);
  }

  return const [];
}

int studentMaxSubjectsForClass(int classLevel) {
  if (classLevel == 9 || classLevel == 10) {
    return 5;
  }

  if (classLevel == 11 || classLevel == 12) {
    return 4;
  }

  return 0;
}

List<String> studentDefaultSubjectsForClass(int classLevel) {
  // SSC:
  // Start with the four normal/core subjects.
  // Teacher/admin can uncheck any of them for
  // partial-subject students.
  if (classLevel == 9 || classLevel == 10) {
    return const ['Phy', 'Chem', 'Math', 'Eng'];
  }

  // HSSC:
  // Physics + English checked by default,
  // exactly as requested.
  if (classLevel == 11 || classLevel == 12) {
    return const ['Phy', 'Eng'];
  }

  return const [];
}

List<StudentSubjectPreset> studentSubjectPresetsForClass(int classLevel) {
  if (classLevel == 9 || classLevel == 10) {
    return const [
      StudentSubjectPreset(
        code: 'Comp',
        label: 'Computer',
        subjects: ['Phy', 'Chem', 'Math', 'Eng', 'Comp'],
      ),
      StudentSubjectPreset(
        code: 'Bio',
        label: 'Biology',
        subjects: ['Phy', 'Chem', 'Math', 'Eng', 'Bio'],
      ),
    ];
  }

  if (classLevel == 11 || classLevel == 12) {
    return const [
      StudentSubjectPreset(
        code: 'Comp',
        label: 'FCS',
        subjects: ['Phy', 'Math', 'Eng', 'Comp'],
      ),
      StudentSubjectPreset(
        code: 'Chem',
        label: 'Pre-Engineering',
        subjects: ['Phy', 'Chem', 'Math', 'Eng'],
      ),
      StudentSubjectPreset(
        code: 'Bio',
        label: 'Pre-Medical',
        subjects: ['Phy', 'Chem', 'Eng', 'Bio'],
      ),
    ];
  }

  return const [];
}

List<String> normalizeStudentSubjects(
  int classLevel,
  Iterable<String> subjects,
) {
  final allowed = studentSubjectCodesForClass(classLevel).toSet();

  final values = subjects.where(allowed.contains).toSet();

  return _studentSubjectOrder.where(values.contains).toList();
}

String? studentSubjectSelectionError(
  int classLevel,
  Iterable<String> subjects,
) {
  final values = normalizeStudentSubjects(classLevel, subjects);

  if (values.isEmpty) {
    return 'Select at least one subject.';
  }

  final max = studentMaxSubjectsForClass(classLevel);

  if (max <= 0) {
    return 'Unsupported class level.';
  }

  if (values.length > max) {
    return 'Class $classLevel students can study maximum $max subjects.';
  }

  // Classes 9/10: Computer and Biology are alternatives.
  if (classLevel == 9 || classLevel == 10) {
    if (values.contains('Comp') && values.contains('Bio')) {
      return 'Classes 9/10 cannot have both Computer and Biology.';
    }
  }

  // Classes 11/12: enforce valid HSSC combinations.
  if (classLevel == 11 || classLevel == 12) {
    if (values.contains('Bio') && values.contains('Math')) {
      return 'Biology and Mathematics cannot be selected together.';
    }

    if (values.contains('Bio') && values.contains('Comp')) {
      return 'Biology and Computer cannot be selected together.';
    }

    if (values.contains('Comp') && values.contains('Chem')) {
      return 'Computer and Chemistry cannot be selected together.';
    }
  }

  return null;
}

bool _sameSubjectSet(Iterable<String> first, Iterable<String> second) {
  final a = first.toSet();
  final b = second.toSet();

  return a.length == b.length && a.containsAll(b);
}

// ============================================================================
// BACKWARD-COMPATIBLE HELPERS
//
// Existing code can continue to compile while presets remain convenient.
// ============================================================================

List<String> studentGroupCodesForClass(int classLevel) {
  return studentSubjectPresetsForClass(
    classLevel,
  ).map((preset) => preset.code).toList();
}

String studentGroupLabel(int classLevel, String groupCode) {
  for (final preset in studentSubjectPresetsForClass(classLevel)) {
    if (preset.code == groupCode) {
      return preset.label;
    }
  }

  return groupCode;
}

List<String> studentSubjectsForGroup(int classLevel, String groupCode) {
  for (final preset in studentSubjectPresetsForClass(classLevel)) {
    if (preset.code == groupCode) {
      return List<String>.from(preset.subjects);
    }
  }

  return const [];
}

String? inferStudentGroupCode(int classLevel, Iterable<String> subjects) {
  final normalized = normalizeStudentSubjects(classLevel, subjects);

  for (final preset in studentSubjectPresetsForClass(classLevel)) {
    if (_sameSubjectSet(normalized, preset.subjects)) {
      return preset.code;
    }
  }

  // Partial/custom student = no fake stream label.
  return null;
}
