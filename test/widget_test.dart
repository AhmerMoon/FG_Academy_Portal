import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:academy_portal/main.dart';

void main() {
  testWidgets('Startup error displays correct recovery guidance', (
    WidgetTester tester,
  ) async {
    const errorMessage =
        'App setup failed. Please check your connection and retry.';

    await tester.pumpWidget(
      const AcademyAttendanceApp(startupError: errorMessage),
    );

    await tester.pump();

    // Correct error screen should be displayed.
    expect(find.byType(StartupErrorScreen), findsOneWidget);

    expect(find.text('Startup Error'), findsOneWidget);

    // Actual error message must be visible.
    expect(find.text(errorMessage), findsOneWidget);

    // Existing app recovery instructions.
    expect(
      find.text(
        'Close and reopen the application after checking the internet connection.',
      ),
      findsOneWidget,
    );

    // Error icon should be visible.
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

    // This screen currently has no retry button.
    expect(find.text('Retry'), findsNothing);
  });
}
