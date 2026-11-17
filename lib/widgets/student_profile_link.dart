import 'package:flutter/material.dart';

import '../screens/student_profile_screen.dart';

class StudentProfileLink extends StatelessWidget {
  final String studentId;
  final String name;
  final TextStyle? style;

  const StudentProfileLink({
    super.key,
    required this.studentId,
    required this.name,
    this.style,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Open student profile',
    child: InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StudentProfileScreen(studentId: studentId),
        ),
      ),
      child: Text(name, style: style),
    ),
  );
}
