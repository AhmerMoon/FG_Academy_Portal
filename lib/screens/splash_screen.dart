import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../services/auth_service.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();

    _checkVersionAndProceed();
  }

  Future<void> _checkVersionAndProceed() async {
    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

    try {
      final packageInfo = await PackageInfo.fromPlatform();

      final response = await supabase
          .from('app_settings')
          .select(
            'min_apk_version, '
            'apk_download_url',
          )
          .eq('id', 1)
          .single();

      final requiredVersion = response['min_apk_version']?.toString() ?? '';

      final downloadUrl = response['apk_download_url']?.toString() ?? '';

      if (_isUpdateRequired(packageInfo.version, requiredVersion)) {
        _showUpdateDialog(downloadUrl);

        return;
      }
    } catch (e) {
      debugPrint('Version check failed: $e');
    }

    try {
      final portalUser = await _authService.restoreSession();

      if (!mounted) return;

      if (portalUser == null) {
        _open(const LoginScreen());

        return;
      }

      _open(DashboardScreen(userRole: portalUser.role));
    } catch (e) {
      debugPrint('Session restore failed: $e');

      if (!mounted) return;

      _open(const LoginScreen());
    }
  }

  void _open(Widget screen) {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => screen));
  }

  bool _isUpdateRequired(String current, String required) {
    final curr = _parseVersion(current);

    final req = _parseVersion(required);

    if (curr == null || req == null) {
      return false;
    }

    for (int i = 0; i < 3; i++) {
      if (req[i] > curr[i]) {
        return true;
      }

      if (req[i] < curr[i]) {
        return false;
      }
    }

    return false;
  }

  List<int>? _parseVersion(String version) {
    final parts = version.split('.');

    if (parts.length < 3) {
      return null;
    }

    final parsed = <int>[];

    for (final part in parts.take(3)) {
      final value = int.tryParse(part);

      if (value == null) {
        return null;
      }

      parsed.add(value);
    }

    return parsed;
  }

  void _showUpdateDialog(String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            icon: const Icon(
              Icons.system_update_alt_rounded,
              size: 36,
              color: AppTheme.fgNavyBlue,
            ),
            title: const Text('Update Required'),
            content: const Text(
              'A newer FG Academy Portal version is required before continuing.',
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(url);

                  if (uri == null) {
                    return;
                  }

                  try {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (e) {
                    debugPrint('Update URL error: $e');
                  }
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download Update'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/school_bg.png', fit: BoxFit.cover),

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.fgNavyBlue.withValues(alpha: 0.88),
                  const Color(0xFF061C3B).withValues(alpha: 0.93),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const Spacer(),

                Container(
                  width: 140,
                  height: 140,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppTheme.fgGold, width: 2),
                  ),
                  child: Image.asset('assets/images/app_logo_bg.png'),
                ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9)),

                const SizedBox(height: 25),

                const Text(
                  'FG Academy Portal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 5),

                const Text(
                  'Evening Coaching Classes',
                  style: TextStyle(
                    color: AppTheme.fgGold,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const Spacer(),

                const SizedBox(
                  width: 280,
                  child: LinearProgressIndicator(minHeight: 3),
                ),

                const SizedBox(height: 13),

                const Text(
                  'Securing your academy workspace…',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),

                const SizedBox(height: 18),

                const Text(
                  'Developed by Ahmer Moon Majid',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.fgGold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),

                const SizedBox(height: 3),

                const Text(
                  'ahmermoonmajid@gmail.com',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
