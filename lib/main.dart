import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'constants.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? startupError;

  try {
    await Hive.initFlutter();

    if (!Hive.isBoxOpen('settings')) {
      await Hive.openBox('settings');
    }

    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Card(
            margin: const EdgeInsets.all(22),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.09),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      color: AppTheme.danger,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Startup Error',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Close and reopen the application after checking the internet connection.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
