import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../services/auth_service.dart';
import '../services/github_update_service.dart';
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
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    PackageInfo? packageInfo;

    try {
      packageInfo = await PackageInfo.fromPlatform();
    } catch (e) {
      debugPrint('Package version check failed: $e');
    }

    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    GithubUpdateInfo? githubUpdate;

    // Automatically check latest GitHub release on Android.
    if (isAndroid && packageInfo != null) {
      final installedBuildNumber = int.tryParse(packageInfo.buildNumber);

      if (installedBuildNumber != null) {
        githubUpdate = await GithubUpdateService().checkForUpdate(
          installedBuildNumber,
        );
      }
    }

    if (!mounted) return;

    // Preserve existing Supabase force-update behavior.
    // No SQL changes are needed for normal GitHub updates.
    try {
      final response = await supabase
          .from('app_settings')
          .select('min_apk_version, apk_download_url')
          .eq('id', 1)
          .single();

      final requiredVersion = response['min_apk_version']?.toString() ?? '';

      final oldDownloadUrl = response['apk_download_url']?.toString() ?? '';

      if (packageInfo != null &&
          _isUpdateRequired(packageInfo.version, requiredVersion)) {
        final downloadUrl = isAndroid
            ? (githubUpdate?.apkUrl.toString() ??
                  GithubUpdateService.latestApkUrl?.toString() ??
                  oldDownloadUrl)
            : oldDownloadUrl;

        if (!mounted) return;

        _showForceUpdateDialog(downloadUrl);
        return;
      }
    } catch (e) {
      debugPrint('Supabase version check failed: $e');
    }

    // Optional update popup: Update Now or Later.
    if (githubUpdate != null && mounted) {
      final updateNow = await _showOptionalUpdateDialog(githubUpdate);

      if (!mounted) return;

      if (updateNow) {
        await _openApkDownload(githubUpdate.apkUrl.toString());

        if (!mounted) return;
      }
    }

    // Continue normal login / session restoration.
    await _restoreSessionAndProceed();
  }

  Future<void> _restoreSessionAndProceed() async {
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
      if (req[i] > curr[i]) return true;
      if (req[i] < curr[i]) return false;
    }

    return false;
  }

  List<int>? _parseVersion(String version) {
    final parts = version.split('.');

    if (parts.length < 3) {
      return null;
    }

    final result = <int>[];

    for (final part in parts.take(3)) {
      final value = int.tryParse(part);

      if (value == null) return null;

      result.add(value);
    }

    return result;
  }

  Future<bool> _showOptionalUpdateDialog(GithubUpdateInfo update) async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.system_update_alt_rounded,
            size: 40,
            color: AppTheme.fgNavyBlue,
          ),
          title: const Text(
            'New Update Available!',
            textAlign: TextAlign.center,
          ),
          content: const Text(
            'FG Academy Portal ka naya update '
            'available hai.\n\n'
            'Update Now dabane par APK download '
            'hogi. Download hone ke baad file '
            'open karke Update/Install confirm karein.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Later'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: const Text('Update Now'),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _showForceUpdateDialog(String downloadUrl) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            icon: const Icon(
              Icons.system_update_alt_rounded,
              size: 40,
              color: AppTheme.fgNavyBlue,
            ),
            title: const Text('Update Required', textAlign: TextAlign.center),
            content: const Text(
              'A newer FG Academy Portal version '
              'is required before continuing.',
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download Update'),
                onPressed: () {
                  _openApkDownload(downloadUrl);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openApkDownload(String url) async {
    final uri = Uri.tryParse(url);

    if (uri == null || uri.scheme != 'https') {
      _showDownloadError();
      return;
    }

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!opened) {
        _showDownloadError();
      }
    } catch (e) {
      debugPrint('APK download link failed: $e');
      _showDownloadError();
    }
  }

  void _showDownloadError() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open the update link. '
          'Please check your internet connection.',
        ),
        backgroundColor: AppTheme.danger,
      ),
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
