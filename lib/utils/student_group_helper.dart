List<String> studentGroupCodesForClass(int classLevel) {
  if (classLevel <= 10) {
    return const ['Comp', 'Bio'];
  }

  return const ['Comp', 'Chem', 'Bio'];
}

String studentGroupLabel(int classLevel, String groupCode) {
  if (classLevel <= 10) {
    switch (groupCode) {
      case 'Comp':
        return 'Computer';

      case 'Bio':
        return 'Biology';

      default:
        return groupCode;
    }
  }

  switch (groupCode) {
    case 'Comp':
      return 'FCS';

    case 'Chem':
      return 'Pre-Engineering';

    case 'Bio':
      return 'Pre-Medical';

    default:
      return groupCode;
  }
}

List<String> studentSubjectsForGroup(int classLevel, String groupCode) {
  if (classLevel <= 10) {
    switch (groupCode) {
      case 'Comp':
        return const ['Phy', 'Chem', 'Math', 'Eng', 'Comp'];

      case 'Bio':
        return const ['Phy', 'Chem', 'Math', 'Eng', 'Bio'];

      default:
        return const [];
    }
  }

  switch (groupCode) {
    // FCS
    case 'Comp':
      return const ['Phy', 'Math', 'Eng', 'Comp'];

    // Pre-Engineering
    case 'Chem':
      return const ['Phy', 'Chem', 'Math', 'Eng'];

    // Pre-Medical
    case 'Bio':
      return const ['Phy', 'Chem', 'Eng', 'Bio'];

    default:
      return const [];
  }
}

String? inferStudentGroupCode(int classLevel, Iterable<String> subjects) {
  final values = subjects.toSet();

  if (classLevel <= 10) {
    if (values.contains('Comp')) {
      return 'Comp';
    }

    if (values.contains('Bio')) {
      return 'Bio';
    }

    return null;
  }

  // Important order:
  // Pre-Med contains both Biology AND Chemistry,
  // so Biology must be checked before Chemistry.
  if (values.contains('Comp')) {
    return 'Comp';
  }

  if (values.contains('Bio')) {
    return 'Bio';
  }

  if (values.contains('Chem')) {
    return 'Chem';
  }

  return null;
}
