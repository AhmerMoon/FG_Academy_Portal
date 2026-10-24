import 'package:flutter/foundation.dart';

class GithubUpdateInfo {
  final int buildNumber;
  final Uri apkUrl;

  const GithubUpdateInfo({required this.buildNumber, required this.apkUrl});
}

/// Web stub — GitHub update checks are not supported on web.
/// The app simply skips update checking on web/Vercel.
class GithubUpdateService {
  static Uri? get latestApkUrl => null;

  Future<GithubUpdateInfo?> checkForUpdate(int installedBuildNumber) async {
    debugPrint('GitHub update check skipped on web.');
    return null;
  }
}
