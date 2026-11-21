import 'package:academy_portal/models/printable_request.dart';
import 'package:academy_portal/screens/printables_screen.dart';
import 'package:academy_portal/services/printables_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PrintableRequest request({
  String id = 'one',
  String status = 'pending',
  String teacher = 'Ali Khan',
  String title = 'Chapter 3 test',
  bool expired = false,
}) => PrintableRequest(
  id: id,
  teacherName: teacher,
  batchName: 'Class 10 A',
  subjectCode: 'Phy',
  title: title,
  testDate: DateTime(2099, 12, 5),
  copies: 32,
  notes: 'Double sided',
  fileName: 'test.pdf',
  filePath: 'teacher/$id/document.pdf',
  status: status,
  expiresAt: expired ? DateTime.utc(2000) : DateTime.utc(2100),
);

class FakePrintablesService extends PrintablesService {
  FakePrintablesService()
    : super(
        client: SupabaseClient(
          'https://example.org',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  List<PrintableRequest> rows = [request()];
  bool fail = false;
  int statusChanges = 0;
  int deleteCalls = 0;
  bool deletedAll = false;
  int? editedCopies;

  @override
  Future<int> deleteRequests({String? requestId, bool all = false}) async {
    deleteCalls++;
    deletedAll = all;
    final count = rows.where((row) => all || row.id == requestId).length;
    rows = rows.where((row) => !all && row.id != requestId).toList();
    return count;
  }

  @override
  Future<bool> updateRequest(
    PrintableRequest request, {
    required String batchId,
    required String subjectCode,
    required DateTime testDate,
    required int copies,
    required String fileName,
    Uint8List? bytes,
    required String paperType,
  }) async {
    editedCopies = copies;
    return true;
  }

  @override
  Future<List<PrintableRequest>> fetchRequests() async {
    if (fail) throw StateError('Connection unavailable');
    return rows;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChoices() async => [
    {'batch_id': 'batch-one', 'batch_name': '9th', 'subject_code': 'Phy'},
    {'batch_id': 'batch-two', 'batch_name': '10th', 'subject_code': 'Phy'},
  ];

  @override
  Future<void> setPrinted(PrintableRequest row, bool printed) async {
    statusChanges++;
    rows = [request(status: printed ? 'printed' : 'pending')];
  }
}

Future<void> showScreen(
  WidgetTester tester,
  FakePrintablesService service, {
  bool admin = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PrintablesScreen(isAdmin: admin, service: service),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('teacher edits copies without reattaching the existing file', (
    tester,
  ) async {
    final service = FakePrintablesService();
    await showScreen(tester, service);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit printable'), findsOneWidget);
    expect(find.text('32'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('test.pdf'),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextFormField), '48');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(service.editedCopies, 48);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'single deletion requires confirmation and cancel preserves the request',
    (tester) async {
      final service = FakePrintablesService();
      await showScreen(tester, service);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.deleteCalls, 0);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(service.deleteCalls, 1);
      expect(service.rows, isEmpty);
      expect(find.byTooltip('Delete all printables'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('admin Delete All includes requests outside the search filter', (
    tester,
  ) async {
    final service = FakePrintablesService()
      ..rows = [request(), request(id: 'two', title: 'Another paper')];
    await showScreen(tester, service, admin: true);
    expect(find.text('Edit'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Chapter 3');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete all printables'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete all'));
    await tester.pumpAndSettle();
    expect(service.deletedAll, isTrue);
    expect(service.rows, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('retention includes the full day after the test in Pakistan time', () {
    final expiry = printableExpiry(DateTime(2026, 12, 5));
    expect(expiry, DateTime.utc(2026, 12, 6, 19));
    expect(
      pakistanToday(expiry.subtract(const Duration(seconds: 1))),
      DateTime(2026, 12, 6),
    );
    expect(pakistanToday(expiry), DateTime(2026, 12, 7));
  });

  test('retention crosses year and leap-month boundaries correctly', () {
    expect(
      printableExpiry(DateTime(2026, 12, 31)),
      DateTime.utc(2027, 1, 1, 19),
    );
    expect(
      printableExpiry(DateTime(2028, 2, 28)),
      DateTime.utc(2028, 2, 29, 19),
    );
  });

  test('Pakistan day is independent of the device UTC day', () {
    expect(pakistanToday(DateTime.utc(2026, 12, 4, 19)), DateTime(2026, 12, 5));
    expect(
      pakistanToday(DateTime.utc(2026, 12, 4, 18, 59)),
      DateTime(2026, 12, 4),
    );
  });

  test(
    'accepts PDF and Word within size limit; rejects empty, oversized and other files',
    () {
      for (final name in ['test.pdf', 'TEST.PDF', 'paper.doc', 'paper.docx']) {
        expect(validatePrintableFile(name, printableMaxBytes), isNull);
      }
      expect(validatePrintableFile('paper.pdf', 0), isNotNull);
      expect(
        validatePrintableFile('paper.pdf', printableMaxBytes + 1),
        isNotNull,
      );
      expect(validatePrintableFile('paper.exe', 120), isNotNull);
      expect(validatePrintableFile('paper.pdf.exe', 120), isNotNull);
    },
  );

  test(
    'detects test-session filenames without misclassifying normal papers',
    () {
      expect(
        inferPrintablePaperType('Physics Test 1.docx'),
        printablePaperTestSession,
      );
      expect(
        inferPrintablePaperType('Week_06 Chemistry.pdf'),
        printablePaperTestSession,
      );
      expect(
        inferPrintablePaperType('Chapter 3 test.pdf'),
        printablePaperNormal,
      );
      expect(printableTestNumber('Math Test No. 12.docx'), 12);
    },
  );

  testWidgets(
    'teacher sees own list and submission form, without admin actions',
    (tester) async {
      final service = FakePrintablesService();
      await showScreen(tester, service);
      expect(find.text('Chapter 3 test'), findsOneWidget);
      expect(find.text('Mark printed'), findsNothing);
      await tester.tap(find.byTooltip('Submit printable'));
      await tester.pumpAndSettle();
      expect(find.text('Submit printable'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('9th'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'admin can mark printed and pending without a teacher submission button',
    (tester) async {
      final service = FakePrintablesService();
      await showScreen(tester, service, admin: true);
      expect(find.byTooltip('Submit printable'), findsNothing);
      await tester.tap(find.text('Mark printed'));
      await tester.pumpAndSettle();
      expect(service.statusChanges, 1);
      expect(find.text('Mark pending'), findsOneWidget);
      await tester.tap(find.text('Mark pending'));
      await tester.pumpAndSettle();
      expect(service.statusChanges, 2);
      expect(find.text('Mark printed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'search, status filter and expiration exclude irrelevant requests',
    (tester) async {
      final service = FakePrintablesService()
        ..rows = [
          request(),
          request(
            id: 'two',
            teacher: 'Sara Ahmed',
            title: 'Revision test',
            status: 'printed',
          ),
          request(id: 'old', title: 'Expired paper', expired: true),
        ];
      await showScreen(tester, service, admin: true);
      expect(find.text('Expired paper'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Sara');
      await tester.pumpAndSettle();
      expect(find.text('Revision test'), findsOneWidget);
      expect(find.text('Chapter 3 test'), findsNothing);
      await tester.tap(find.text('Pending (1)'));
      await tester.pumpAndSettle();
      expect(find.text('No matching requests.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('mobile list and submission dialog fit a 390-pixel screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showScreen(tester, FakePrintablesService());
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Submit printable'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Test title'), findsNothing);
    expect(find.text('Enter 1 to 5000 copies.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('load errors offer a working retry', (tester) async {
    final service = FakePrintablesService()..fail = true;
    await showScreen(tester, service);
    expect(find.text('Connection unavailable'), findsOneWidget);
    service.fail = false;
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 3 test'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
