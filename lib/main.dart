import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app_theme.dart';
import 'constants.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Hive.openBox('offline_attendance');
  await Hive.openBox('settings'); // Auth session save rakhne ke liye

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  runApp(const AcademyAttendanceApp());
}

class AcademyAttendanceApp extends StatelessWidget {
  const AcademyAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FG Academy Portal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.officialTheme,
      home: const SplashScreen(),
    );
  }
}
