class PortalAssignment {
  final int classLevel;
  final String subjectCode;

  const PortalAssignment({required this.classLevel, required this.subjectCode});

  factory PortalAssignment.fromJson(Map<String, dynamic> json) {
    return PortalAssignment(
      classLevel: (json['class_level'] as num).toInt(),
      subjectCode: json['subject_code'].toString(),
    );
  }

  String get subjectLabel {
    switch (subjectCode) {
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
        return subjectCode;
    }
  }

  String get displayText => 'Class $classLevel • $subjectLabel';
}

class PortalUser {
  final String userId;
  final String email;
  final String fullName;
  final String role;
  final bool mustChangePassword;
  final bool isActive;
  final List<PortalAssignment> assignments;

  const PortalUser({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
    required this.mustChangePassword,
    required this.isActive,
    required this.assignments,
  });

  bool get isAdmin => role == 'admin';

  bool get isTeacher => role == 'teacher';

  List<int> get classLevels {
    final values = assignments
        .map((assignment) => assignment.classLevel)
        .toSet()
        .toList();

    values.sort();

    return values;
  }

  List<String> get subjectCodes {
    return assignments
        .map((assignment) => assignment.subjectCode)
        .toSet()
        .toList();
  }

  String get assignmentSummary {
    if (isAdmin) {
      return 'Full academy access';
    }

    if (assignments.isEmpty) {
      return 'No teaching assignment';
    }

    final subjects = assignments
        .map((assignment) => assignment.subjectLabel)
        .toSet()
        .join(', ');

    final classes = classLevels.join(', ');

    return '$subjects • Classes $classes';
  }
}
