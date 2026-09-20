import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const gold = Color(0xFFD4AF37);
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkVersionAndProceed();
  }

  Future<void> _checkVersionAndProceed() async {
    // Splash animation ke liye thora wait
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    try {
      // 1. Get current app version from pubspec.yaml
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // 2. Get required version from Supabase
      final response = await supabase
          .from('app_settings')
          .select('min_apk_version, apk_download_url')
          .eq('id', 1)
          .single();

      final requiredVersion = response['min_apk_version'] as String;
      final downloadUrl = response['apk_download_url'] as String;

      // 3. Compare versions (e.g. "1.0.0" vs "1.0.1")
      if (_isUpdateRequired(currentVersion, requiredVersion)) {
        _showUpdateDialog(downloadUrl);
        return; // Stop flow here
      }
    } catch (e) {
      debugPrint('Version check failed: $e');
      // No internet ya Supabase error aaye toh default login flow chalao
    }

    // 4. Normal Auth Flow
    final settingsBox = Hive.box('settings');
    final isLoggedIn = settingsBox.get('isLoggedIn', defaultValue: false);
    final role = settingsBox.get('role', defaultValue: 'teacher');

    final Widget nextScreen = isLoggedIn
        ? DashboardScreen(userRole: role)
        : const LoginScreen();

    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => nextScreen));
    }
  }

  bool _isUpdateRequired(String current, String required) {
    List<int> curr = current.split('.').map(int.parse).toList();
    List<int> req = required.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      if (req[i] > curr[i]) return true;
      if (req[i] < curr[i]) return false;
    }
    return false;
  }

  void _showUpdateDialog(String url) {
    showDialog(
      context: context,
      barrierDismissible:
          false, // Force update (user popup close nahi kar sakta)
      builder: (context) => PopScope(
        canPop: false, // Android back button disable
        child: AlertDialog(
          title: const Text('Update Required'),
          content: const Text(
            'App ka naya version aa chuka hai. Attendance aur portal theek se use karne ke liye app ko foran update karein.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('Download Update'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/school_bg.png'),
            fit: BoxFit.cover,
            opacity: 0.25,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/app_logo.png', width: 180)
                  .animate()
                  .fadeIn(duration: 900.ms)
                  .scale(
                    begin: const Offset(0.7, 0.7),
                    end: const Offset(1, 1),
                    duration: 900.ms,
                    curve: Curves.easeOutBack,
                  ),
              const SizedBox(height: 24),
              const Text(
                    'Evening Coaching Classes',
                    style: TextStyle(
                      color: gold,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 500.ms, duration: 700.ms)
                  .slideY(
                    begin: 1,
                    end: 0,
                    delay: 500.ms,
                    duration: 700.ms,
                    curve: Curves.easeOut,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
