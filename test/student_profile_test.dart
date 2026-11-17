import 'package:academy_portal/screens/student_profile_screen.dart';
import 'package:academy_portal/services/student_profile_service.dart';
import 'package:academy_portal/utils/student_contact_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

StudentTestResult result(
  String subject,
  double maximum, {
  double? marks,
  bool absent = false,
}) => StudentTestResult(
  test: {
    'id': subject,
    'subject_code': subject,
    'test_no': 1,
    'test_date': '2026-11-05',
    'max_marks': maximum,
  },
  marks: marks,
  absent: absent,
);

StudentProfileData profile({bool contactColumn = false, bool admin = true}) {
  final today = studentProfileToday();
  return StudentProfileData(
    student: {
      'id': 'student-uuid',
      'name': 'Ali Ahmed',
      'status': 'enrolled',
      'stream': ['Phy', 'Chem'],
      'created_at': '2026-01-01T00:00:00Z',
      if (contactColumn) 'contact_number': null,
    },
    batch: {'name': '9th Boys', 'class_level': 9},
    attendance: [
      {
        'date': DateTime(
          today.year,
          today.month,
          1,
        ).toIso8601String().split('T').first,
        'status': 'present',
      },
      {
        'date': DateTime(
          today.year,
          today.month - 1,
          1,
        ).toIso8601String().split('T').first,
        'status': 'absent',
      },
    ],
    results: [result('Phy', 25, marks: 20), result('Chem', 50, absent: true)],
    canEditContact: admin,
  );
}

class FakeStudentProfileService extends StudentProfileService {
  StudentProfileData data;
  String? savedContact;
  FakeStudentProfileService(this.data)
    : super(
        client: SupabaseClient(
          'https://example.org',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  @override
  Future<StudentProfileData> load(String studentId) async => data;
  @override
  Future<void> saveContact(String studentId, String? contact) async {
    savedContact = contact;
    data.student['contact_number'] = contact;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchBatches() async => [
    {'id': 'batch-nine', 'name': '9th Boys', 'class_level': 9},
    {'id': 'batch-ten', 'name': '10th Boys', 'class_level': 10},
  ];

  @override
  Future<void> saveProfile({
    required String studentId,
    required String name,
    required String batchId,
    required String status,
    required List<String> subjects,
    required String? contact,
  }) async {
    data.student.addAll({
      'name': name,
      'batch_id': batchId,
      'status': status,
      'stream': subjects,
      'contact_number': contact,
    });
  }
}

void main() {
  test('contact actions normalize Pakistani and international numbers', () {
    expect(studentWhatsAppNumber('0300 1234567'), '923001234567');
    expect(studentWhatsAppNumber('+92 (300) 123-4567'), '923001234567');
    expect(studentWhatsAppNumber('00923001234567'), '923001234567');
    expect(studentWhatsAppNumber('3001234567'), '923001234567');
    expect(studentWhatsAppNumber('+44 7700 900123'), '447700900123');
    expect(studentWhatsAppNumber('1234567'), isNull);
    expect(studentCallLink('0300 1234567')?.toString(), 'tel:03001234567');
    expect(studentCallLink('javascript:alert(1)'), isNull);
  });

  test(
    'group invites accept real invitation links/codes, not IDs or other sites',
    () {
      const code = 'AbCdEfGhIjKlMnOpQrStUv';
      expect(studentGroupInviteLink(code), 'https://chat.whatsapp.com/$code');
      expect(
        studentGroupInviteLink('https://chat.whatsapp.com/$code?mode=ac_t'),
        'https://chat.whatsapp.com/$code',
      );
      expect(studentGroupInviteLink('123456789@g.us'), isNull);
      expect(studentGroupInviteLink('https://evil.test/$code'), isNull);
      expect(
        studentGroupInviteLink('https://evil.test@chat.whatsapp.com/$code'),
        isNull,
      );
    },
  );

  testWidgets(
    'desktop profile shows its sidebar and opens call/chat/invite actions',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeStudentProfileService(profile(contactColumn: true));
      service.data.student['contact_number'] = '0300 1234567';
      service.data.batch['whatsapp_group_id'] = 'AbCdEfGhIjKlMnOpQrStUv';
      final links = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: StudentProfileScreen(
            studentId: 'student-uuid',
            service: service,
            openContactLink: (uri) async {
              links.add(uri);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('student-profile-sidebar')),
        findsOneWidget,
      );
      await tester.tap(find.text('Call'));
      await tester.pumpAndSettle();
      expect(links.last.scheme, 'tel');
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();
      expect(links.last.toString(), 'https://wa.me/923001234567');
      await tester.tap(find.text('Send group invite'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Open WhatsApp'));
      await tester.pumpAndSettle();
      expect(links.last.host, 'wa.me');
      expect(
        links.last.queryParameters['text'],
        contains('https://chat.whatsapp.com/AbCdEfGhIjKlMnOpQrStUv'),
      );
      expect(links.last.queryParameters['text'], contains('Ali Ahmed'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow phone profile keeps contact controls usable without a desktop sidebar',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeStudentProfileService(profile(contactColumn: true));
      service.data.student['contact_number'] = '03001234567';
      await tester.pumpWidget(
        MaterialApp(
          home: StudentProfileScreen(
            studentId: 'student-uuid',
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('student-profile-sidebar')),
        findsNothing,
      );
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('admin can edit student details and the initial avatar updates', (
    tester,
  ) async {
    final service = FakeStudentProfileService(profile(contactColumn: true));
    await tester.pumpWidget(
      MaterialApp(
        home: StudentProfileScreen(studentId: 'student-uuid', service: service),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.text('Edit student'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Zain Ahmed');
    await tester.enterText(find.byType(TextFormField).at(1), '0300 1234567');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(service.data.student['name'], 'Zain Ahmed');
    expect(service.data.student['contact_number'], '03001234567');
    expect(find.text('Z'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('teacher sees the avatar but cannot edit student details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StudentProfileScreen(
          studentId: 'student-uuid',
          service: FakeStudentProfileService(
            profile(contactColumn: true, admin: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.byTooltip('Edit profile'), findsNothing);
    expect(find.text('Add / edit contact number'), findsNothing);
  });
  test(
    'combined marks exclude absences and pending but include numeric zero marks',
    () {
      final totals = StudentResultTotals([
        result('Phy', 25, marks: 20),
        result('Chem', 50, absent: true),
        result('Eng', 100),
        result('Math', 10, marks: 0),
      ]);
      expect(totals.graded, 2);
      expect(totals.pending, 1);
      expect(totals.absent, 1);
      expect(totals.obtained, 20);
      expect(totals.maximum, 35);
      expect(totals.percentage, closeTo(20 / 35 * 100, 0.001));
    },
  );

  test('no entered marks produces no percentage', () {
    expect(StudentResultTotals([result('Phy', 50)]).percentage, isNull);
    expect(const StudentResultTotals([]).percentage, isNull);
  });

  test('zero-total and unmarked results are excluded from percentage', () {
    final totals = StudentResultTotals([
      result('Phy', 0, absent: true),
      result('Chem', 0, marks: 0),
      result('Eng', 50),
      result('Math', 25, absent: true),
      result('Comp', 25, marks: 0),
    ]);

    expect(totals.graded, 1);
    expect(totals.absent, 2);
    expect(totals.pending, 1);
    expect(totals.obtained, 0);
    expect(totals.maximum, 25);
    expect(totals.percentage, 0);
  });

  test('attendance month selection handles the previous year separately', () {
    final data = StudentProfileData(
      student: {},
      batch: {},
      results: [],
      canEditContact: false,
      attendance: [
        {'date': '2025-12-31', 'status': 'present'},
        {'date': '2026-01-01', 'status': 'absent'},
        {'date': '2026-12-01', 'status': 'present'},
      ],
    );
    expect(data.attendanceFor(DateTime(2025, 12)).single['date'], '2025-12-31');
    expect(data.attendanceFor(DateTime(2026, 1)).single['status'], 'absent');
  });

  testWidgets(
    'profile loads safely before the optional contact column exists',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StudentProfileScreen(
            studentId: 'student-uuid',
            service: FakeStudentProfileService(profile()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add / edit contact number'), findsNothing);
      expect(find.text('A'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('student-uuid'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('student-profile-overview')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('student-uuid'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('calendar and subject results fit a mobile screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: StudentProfileScreen(
          studentId: 'student-uuid',
          service: FakeStudentProfileService(profile()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attendance'));
    await tester.pumpAndSettle();
    expect(find.text('1 P'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Subject results'));
    await tester.tap(find.text('Subject results'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin can add contact through the single profile editor', (
    tester,
  ) async {
    final service = FakeStudentProfileService(profile(contactColumn: true));
    await tester.pumpWidget(
      MaterialApp(
        home: StudentProfileScreen(studentId: 'student-uuid', service: service),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '+92 300-1234567');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(service.data.student['contact_number'], '+923001234567');
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
