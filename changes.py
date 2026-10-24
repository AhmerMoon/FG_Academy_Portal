
from pathlib import Path
from datetime import datetime
import re
import shutil
import sys

ROOT = Path.cwd()
CHANGES = {}


def put(s, old, new, what):
    """Apply old -> new; skip if already updated."""
    n = s.count(old)

    if n == 1:
        return s.replace(old, new, 1)

    if n > 1:
        raise RuntimeError(
            f"{what}: original pattern occurs {n} times"
        )

    if new in s:
        return s

    raise RuntimeError(
        f"{what}: neither original nor updated code found"
    )


def remove(s, snippet):
    """Optional import/field: no error if already removed."""
    return s.replace(snippet, "")


def stage(filename, fn):
    path = ROOT / filename

    if not path.is_file():
        raise RuntimeError(f"Missing: {filename}")

    old = path.read_text(encoding="utf-8")

    try:
        new = fn(old)
    except Exception as e:
        raise RuntimeError(f"{filename}: {e}") from e

    if new != old:
        CHANGES[filename] = (old, new)

    print(
        ("UPDATE " if old != new else "SKIP   ")
        + filename
    )


# ============================================================
# ADMIN STUDENTS
# ============================================================

def students_tab(s):

    if "import 'archive_students_view.dart';" not in s:
        s = put(
            s,
            "import '../../widgets/add_student_dialog.dart';",
            "import '../../widgets/add_student_dialog.dart';\n"
            "import 'archive_students_view.dart';",
            "archive import",
        )

    # FIX: These imports are optional.
    # Gemini may have removed them already.
    s = remove(
        s,
        "import '../../services/fee_service.dart';\n",
    )

    s = remove(
        s,
        "import '../../utils/fee_month.dart';\n",
    )

    s = remove(
        s,
        "  final FeeService _feeService = FeeService();\n",
    )

    if "bool _archiveMode = false;" not in s:
        s = put(
            s,
            "  String? errorMessage;\n\n  @override",
            "  String? errorMessage;\n"
            "  bool _archiveMode = false;\n\n  @override",
            "archive state",
        )

    s = put(
        s,
        "supabase.from('students').select('batch_id'),",
        "supabase.from('students')"
        ".select('batch_id')"
        ".eq('is_archived', false),",
        "active counts",
    )

    if "ArchiveStudentsView(" not in s:

        s = put(
            s,
            "    return RefreshIndicator(\n"
            "      onRefresh: fetchBatches,",
            """    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Wrap(
            spacing: 10,
            children: [
              ChoiceChip(
                label: const Text('Active Batches'),
                selected: !_archiveMode,
                onSelected: (_) =>
                    setState(() => _archiveMode = false),
              ),
              ChoiceChip(
                label: const Text('Archive'),
                selected: _archiveMode,
                onSelected: (_) =>
                    setState(() => _archiveMode = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: _archiveMode
              ? ArchiveStudentsView(
                  onRestored: fetchBatches,
                )
              : RefreshIndicator(
                  onRefresh: fetchBatches,""",
            "archive selector start",
        )

        s = put(
            s,
            """        ],
      ),
    );
  }
}

// =============================================================================
// BATCH STUDENTS SCREEN""",
            """        ],
      ),
    )),
      ],
    );
  }
}

// =============================================================================
// BATCH STUDENTS SCREEN""",
            "archive selector end",
        )

    old = (
        ".select('id, name, stream, status, default_fee')\n"
        "          .eq('batch_id', widget.batchId)"
    )

    s = put(
        s,
        old + "\n          .order('name', ascending: true)",
        old
        + "\n          .eq('is_archived', false)"
        + "\n          .order('name', ascending: true)",
        "active students",
    )

    # Replace old delete method only if it exists.
    old_method = (
        "  Future<void> _deleteStudent("
        "dynamic student) async {"
    )

    if old_method in s:

        start = s.index(old_method)

        end = s.index(
            "\n  @override\n"
            "  Widget build(BuildContext context)",
            start,
        )

        archive_code = '''  Future<void> _archiveStudent(
    dynamic student,
  ) async {
    final name =
        student['name']?.toString() ?? 'Student';

    String reason = 'Left academy';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive Student?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Archive "$name"? Attendance and marks '
              'will be preserved.',
            ),
            const SizedBox(height: 14),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
              ),
              onChanged: (value) => reason = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.rpc(
        'archive_student',
        params: {
          'p_student_id': student['id'],
          'p_reason': reason.trim().isEmpty
              ? 'Left academy'
              : reason.trim(),
        },
      );

      if (!mounted) return;

      await fetchStudents();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Student archived. Historical records preserved.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Archive failed: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }
'''

        s = s[:start] + archive_code + s[end:]

    elif (
        "Future<void> _archiveStudent(" not in s
        and "rpc('archive_student'" not in s
    ):
        raise RuntimeError(
            "Cannot locate Delete or Archive method. "
            "Current file differs from uploaded snapshot."
        )

    s = s.replace(
        "tooltip: 'Delete',",
        "tooltip: 'Archive',",
    )

    s = s.replace(
        "_deleteStudent(student)",
        "_archiveStudent(student)",
    )

    s = s.replace(
        "Icons.delete_outline_rounded",
        "Icons.archive_outlined",
    )

    s = remove(
        s,
        "            '$paymentMonth fee: Unpaid',",
    )

    old_rpc = '''      await _feeService.addStudent(
        name: request.name,
        batchId: request.batch.id,
        defaultFee: request.defaultFee,
        subjects: request.subjects,
        paymentMonth: paymentMonth,
      );'''

    new_rpc = '''      await supabase.rpc(
        'portal_add_student_simple',
        params: {
          'p_name': request.name,
          'p_batch_id': request.batch.id,
          'p_group_code': request.groupCode,
        },
      );'''

    s = put(
        s,
        old_rpc,
        new_rpc,
        "Admin Add Student RPC",
    )

    s = s.replace(
        "    final paymentMonth = "
        "FeeMonth.fromDate(DateTime.now());",
        "    const paymentMonth = '';",
    )

    if "FeeService" in s or "FeeMonth" in s:
        raise RuntimeError(
            "Remaining fee-service reference. "
            "Manual review required."
        )

    return s


# ============================================================
# TEACHER ATTENDANCE
# ============================================================

def teacher(s):

    if "import '../widgets/add_student_dialog.dart';" not in s:
        s = put(
            s,
            "import '../app_theme.dart';",
            "import '../app_theme.dart';\n"
            "import '../models/fee_models.dart';\n"
            "import '../widgets/add_student_dialog.dart';",
            "teacher imports",
        )

    # Preserve other subject helper imports.

    old = (
        ".select('id, name, stream')\n"
        "            .eq('batch_id', widget.batchId)"
    )

    s = put(
        s,
        old + "\n            .order('name', ascending: true)",
        old
        + "\n            .eq('is_archived', false)"
        + "\n            .order('name', ascending: true)",
        "teacher active student query",
    )

    start = s.index(
        "  Future<void> _openAddStudentDialog() async {"
    )

    end = s.index(
        "\n  Future<void> _addNewStudent(",
        start,
    )

    current_method = s[start:end]

    if "showAcademyAddStudentDialog(" not in current_method:

        method = '''  Future<void> _openAddStudentDialog() async {
    if (_isAddingStudent) return;

    final level = _classLevel;

    if (level == null) {
      _showMessage(
        'Class information unavailable.',
        error: true,
      );
      return;
    }

    final batch = FeeBatch(
      id: widget.batchId,
      name: widget.batchName,
      classLevel: level,
    );

    final request = await showAcademyAddStudentDialog(
      context: context,
      batches: [batch],
      initialBatch: batch,
      paymentMonth: '',
      lockBatch: true,
      requiredSubject: _teacherSubjectCode,
    );

    if (!mounted || request == null) return;

    await _addNewStudent(
      _NewAttendanceStudentDraft(
        name: request.name,
        subjects: request.subjects,
        groupCode: request.groupCode,
      ),
    );
  }
'''

        s = s[:start] + method + s[end:]

    old_rpc = '''        'portal_add_student_from_attendance_v2',
        params: {
          'p_name': request.name,
          'p_batch_id': widget.batchId,
          'p_subjects': request.subjects,
        },'''

    new_rpc = '''        'portal_add_student_simple',
        params: {
          'p_name': request.name,
          'p_batch_id': widget.batchId,
          'p_group_code': request.groupCode,
        },'''

    s = put(
        s,
        old_rpc,
        new_rpc,
        "teacher Add Student RPC",
    )

    s = s.replace(
        "Today attendance is Present and "
        "current month fee is Unpaid.",
        "Today attendance is Present.",
    )

    if "final String groupCode;" not in s:

        s = put(
            s,
            "  final List<String> subjects;\n\n"
            "  const _NewAttendanceStudentDraft({",
            "  final List<String> subjects;\n"
            "  final String groupCode;\n\n"
            "  const _NewAttendanceStudentDraft({",
            "teacher draft groupCode field",
        )

        s = put(
            s,
            "    required this.subjects,\n"
            "  });\n}",
            "    required this.subjects,\n"
            "    required this.groupCode,\n"
            "  });\n}",
            "teacher draft groupCode constructor",
        )

    return s


# ============================================================
# AWARD LISTS
# ============================================================

def awards(s):

    if "import '../widgets/add_student_dialog.dart';" not in s:

        s = put(
            s,
            "import '../models/fee_models.dart';",
            "import '../models/fee_models.dart';\n"
            "import '../widgets/add_student_dialog.dart';",
            "award imports",
        )

    old = (
        ".select('id, name, stream')\n"
        "            .eq('batch_id', batchId)"
    )

    s = put(
        s,
        old + "\n            .order('name', ascending: true)",
        old
        + "\n            .eq('is_archived', false)"
        + "\n            .order('name', ascending: true)",
        "award active student query",
    )

    start = s.index(
        "  Future<void> _addStudentFromAwards() async {"
    )

    end = s.index(
        "\n  Future<void> _editAwardStudent(",
        start,
    )

    if "showAcademyAddStudentDialog(" not in s[start:end]:

        method = '''  Future<void> _addStudentFromAwards() async {
    if (_addingStudent || _saving) return;

    final batchId = _selectedBatchId;
    final subject = _selectedSubject;
    final level = _selectedClassLevel;

    if (
      batchId == null ||
      subject == null ||
      level <= 0
    ) {
      _showMessage(
        'Select batch and subject first.',
        error: true,
      );
      return;
    }

    final batch = FeeBatch(
      id: batchId,
      name: _selectedBatch?['name']?.toString() ?? 'Batch',
      classLevel: level,
    );

    final request = await showAcademyAddStudentDialog(
      context: context,
      batches: [batch],
      initialBatch: batch,
      paymentMonth: '',
      lockBatch: true,
      requiredSubject: subject,
    );

    if (!mounted || request == null) return;

    setState(() => _addingStudent = true);

    try {
      await _persistMarkDrafts();

      await _supabase.rpc(
        'portal_add_student_simple',
        params: {
          'p_name': request.name,
          'p_batch_id': batchId,
          'p_group_code': request.groupCode,
        },
      );

      if (!mounted) return;

      await _loadTestStudents();

      _showMessage(
        '${request.name} added successfully. '
        'Existing marks preserved.',
      );
    } catch (e) {
      debugPrint('Award Add Student error: $e');

      _showMessage(
        'Student could not be added.\\n$e',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _addingStudent = false);
      }
    }
  }
'''

        s = s[:start] + method + s[end:]

    return s


# ============================================================
# ADMIN ATTENDANCE
# ============================================================

def admin_attendance(s):

    s = put(
        s,
        "supabase.from('students').select('batch_id'),",
        "supabase.from('students')"
        ".select('id, batch_id')"
        ".eq('is_archived', false),",
        "attendance active students",
    )

    s = put(
        s,
        ".select('batch_id, status')",
        ".select('batch_id, student_id, status')",
        "attendance row columns",
    )

    s = put(
        s,
        "      final attendanceRows = results[2];\n\n"
        "      final total",
        "      final attendanceRows = results[2];\n"
        "      final activeIds = studentRows"
        ".map((s) => s['id'].toString()).toSet();\n\n"
        "      final total",
        "active IDs",
    )

    s = put(
        s,
        "      for (final row in attendanceRows) {\n"
        "        final id = row['batch_id']?.toString();",
        "      for (final row in attendanceRows) {\n"
        "        if (!activeIds.contains("
        "row['student_id']?.toString())) continue;\n"
        "        final id = row['batch_id']?.toString();",
        "attendance active counts",
    )

    old = (
        ".select('id, name')\n"
        "            .eq('batch_id', widget.batchId)"
    )

    s = put(
        s,
        old + "\n            .order('name', ascending: true)",
        old
        + "\n            .eq('is_archived', false)"
        + "\n            .order('name', ascending: true)",
        "admin edit attendance query",
    )

    return s


# ============================================================
# STUDENT QUERY FILTERING
# ============================================================

def simple_filter(s):

    pattern = (
        r"\.from\('students'\)\s*"
        r"\.select\([^)]*\)\s*"
        r"\.eq\('batch_id',\s*[^)]+\)"
    )

    matches = list(re.finditer(pattern, s))

    if len(matches) != 1:
        raise RuntimeError(
            "Expected exactly 1 batch student query, "
            f"found {len(matches)}"
        )

    match = matches[0]

    following = s[match.end():match.end() + 95]

    if ".eq('is_archived', false)" in following:
        return s

    return (
        s[:match.end()]
        + "\n          .eq('is_archived', false)"
        + s[match.end():]
    )


def counts(s):
    return put(
        s,
        "supabase.from('students').select('batch_id'),",
        "supabase.from('students')"
        ".select('batch_id')"
        ".eq('is_archived', false),",
        "batch count students",
    )


def dashboard(s):
    return put(
        s,
        "supabase.from('students')"
        ".select('id, batch_id'),",
        "supabase.from('students')"
        ".select('id, batch_id')"
        ".eq('is_archived', false),",
        "dashboard student counts",
    )


# ============================================================
# PREFLIGHT + BACKUP + APPLY
# ============================================================

def main():

    if not (ROOT / "pubspec.yaml").is_file():
        raise RuntimeError(
            "Run from Flutter project root "
            "containing pubspec.yaml"
        )

    required_files = [
        "lib/widgets/add_student_dialog.dart",
        "lib/screens/admin/archive_students_view.dart",
    ]

    for relative in required_files:
        if not (ROOT / relative).is_file():
            raise RuntimeError(
                "First create/replace UI file: " + relative
            )

    dialog_path = (
        ROOT / "lib/widgets/add_student_dialog.dart"
    )

    dialog = dialog_path.read_text(
        encoding="utf-8"
    )

    if (
        "groupCode" not in dialog
        or "requiredSubject" not in dialog
    ):
        raise RuntimeError(
            "Add Student dialog is not the "
            "compact Stream version yet"
        )

    work = [
        (
            "lib/screens/admin/students_tab.dart",
            students_tab,
        ),
        (
            "lib/screens/student_screen.dart",
            teacher,
        ),
        (
            "lib/screens/award_lists_screen.dart",
            awards,
        ),
        (
            "lib/screens/admin/admin_attendance_tab.dart",
            admin_attendance,
        ),
        (
            "lib/screens/dashboard_screen.dart",
            dashboard,
        ),
        (
            "lib/screens/admin/batches_tab.dart",
            counts,
        ),
        (
            "lib/screens/teacher_batches_screen.dart",
            counts,
        ),
        (
            "lib/screens/teacher_attendance_history_screen.dart",
            simple_filter,
        ),
        (
            "lib/services/award_progress_service.dart",
            simple_filter,
        ),
        (
            "lib/services/award_share_service.dart",
            simple_filter,
        ),
    ]

    # ALL modifications are prepared in memory first.
    for filename, transform in work:
        stage(filename, transform)

    print(
        f"\nPreflight successful: "
        f"{len(CHANGES)} files require changes."
    )

    # Testing mode never writes source files.
    if "--check" in sys.argv:
        print(
            "CHECK MODE - no project files modified."
        )
        return

    if not CHANGES:
        print("Nothing to update.")
        return

    # Backup every existing file before writing.
    stamp = datetime.now().strftime(
        "%Y%m%d_%H%M%S"
    )

    backup_folder = (
        ROOT / f"flutter_archive_backup_{stamp}"
    )

    for filename in CHANGES:
        destination = backup_folder / filename

        destination.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        shutil.copy2(
            ROOT / filename,
            destination,
        )

    for filename, (_, new_content) in CHANGES.items():
        (ROOT / filename).write_text(
            new_content,
            encoding="utf-8",
        )

    print(
        f"Wrote {len(CHANGES)} files. "
        f"Backup: {backup_folder}"
    )

    print(
        "Next: dart format, flutter analyze, "
        "flutter test. No deployment yet."
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("STOPPED SAFELY:", error)
        sys.exit(1)
