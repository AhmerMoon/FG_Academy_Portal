import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class GithubUpdateInfo {
  final int buildNumber;
  final Uri apkUrl;

  const GithubUpdateInfo({required this.buildNumber, required this.apkUrl});
}

class GithubUpdateService {
  // GitHub Actions fills this automatically during APK build.
  // No username, repository name or secret to enter manually.
  static const String _repository = String.fromEnvironment('GITHUB_REPOSITORY');

  static bool get _hasValidRepository {
    return RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(_repository);
  }

  // Permanent link which always points to the latest APK.
  static Uri? get latestApkUrl {
    if (!_hasValidRepository) return null;

    return Uri.https(
      'github.com',
      '/$_repository/releases/latest/download/'
          'FG_Academy_Portal.apk',
    );
  }

  Future<GithubUpdateInfo?> checkForUpdate(int installedBuildNumber) async {
    if (!_hasValidRepository) {
      debugPrint('GitHub update repository not configured.');
      return null;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);

    try {
      final apiUrl = Uri.https(
        'api.github.com',
        '/repos/$_repository/releases/latest',
      );

      final request = await client
          .getUrl(apiUrl)
          .timeout(const Duration(seconds: 5));

      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );

      request.headers.set(HttpHeaders.userAgentHeader, 'FG-Academy-Portal');

      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode != HttpStatus.ok) {
        debugPrint('GitHub update HTTP ${response.statusCode}');
        return null;
      }

      final responseText = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 6));

      final data = jsonDecode(responseText);

      if (data is! Map<String, dynamic>) {
        return null;
      }

      // GitHub Actions produces tags like android-10035.
      final tag = data['tag_name']?.toString() ?? '';

      final match = RegExp(r'^android-(\d+)$').firstMatch(tag);

      if (match == null) {
        return null;
      }

      final latestBuild = int.tryParse(match.group(1)!);

      if (latestBuild == null || latestBuild <= installedBuildNumber) {
        return null;
      }

      final assets = data['assets'];

      if (assets is! List) {
        return null;
      }

      for (final asset in assets) {
        if (asset is! Map) continue;

        if (asset['name'] != 'FG_Academy_Portal.apk') {
          continue;
        }

        final url = Uri.tryParse(
          asset['browser_download_url']?.toString() ?? '',
        );

        if (url == null || url.scheme != 'https' || url.host != 'github.com') {
          continue;
        }

        return GithubUpdateInfo(buildNumber: latestBuild, apkUrl: url);
      }

      return null;
    } catch (e) {
      // Weak internet must not break normal app startup.
      debugPrint('GitHub update check unavailable: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
