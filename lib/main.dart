import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app_theme.dart';
import 'constants.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? startupError;
  try {
    await Hive.initFlutter();
    await Hive.openBox('offline_attendance');
    await Hive.openBox('settings'); // Auth session save rakhne ke liye

    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  } catch (e) {
    startupError = 'App setup failed. Please check your connection and retry.';
    debugPrint('Startup error: $e');
  }

  runApp(AcademyAttendanceApp(startupError: startupError));
}

class AcademyAttendanceApp extends StatelessWidget {
  final String? startupError;

  const AcademyAttendanceApp({super.key, this.startupError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FG Academy Portal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.officialTheme,
      home: startupError == null
          ? const SplashScreen()
          : StartupErrorScreen(message: startupError!),
    );
  }
}

class StartupErrorScreen extends StatelessWidget {
  final String message;

  const StartupErrorScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => main(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
