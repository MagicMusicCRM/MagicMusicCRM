import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class GithubUpdaterService {
  final String owner;
  final String repo;
  final Dio _dio;

  GithubUpdaterService({
    required this.owner,
    required this.repo,
  }) : _dio = Dio(BaseOptions(
          headers: {
            'User-Agent': 'Flutter-MagicMusicCRM-Updater',
            'Accept': 'application/vnd.github.v3+json',
          },
        ));

  /// Gets the current app version from package info.
  Future<String> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  /// Checks if a new release is available on GitHub.
  /// Returns the download URL for the APK if an update is available, null otherwise.
  Future<Map<String, dynamic>?> checkForUpdates() async {
    try {
      final response = await _dio.get(
        'https://api.github.com/repos/$owner/$repo/releases/latest',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final latestVersionTag = data['tag_name'] as String;
        final currentVersion = await getCurrentVersion();

        // Very basic simple string/version comparison
        // Assuming tag_name is like "v1.0.1" and currentVersion is "1.0.0"
        final latestVersion = latestVersionTag.replaceAll('v', '');
        
        if (_isNewerVersion(latestVersion, currentVersion)) {
          final assets = data['assets'] as List;
          for (var asset in assets) {
            final name = asset['name'] as String;
            if (name.endsWith('.apk')) {
              return {
                'version': latestVersionTag,
                'downloadUrl': asset['browser_download_url'],
              };
            }
          }
        } else {
          debugPrint('GitHub Updater: No new version found. Latest: $latestVersion, Current: $currentVersion');
        }
      }
    } catch (e) {
      debugPrint('GitHub Updater check error: $e');
    }
    return null;
  }

  /// Downloads the APK and installs it.
  Future<bool> downloadAndInstallUpdate(
    String downloadUrl, {
    Function(int received, int total)? onProgress,
  }) async {
    try {
      final savePath = await _getApkSavePath();
      
      await _dio.download(
        downloadUrl,
        savePath,
        onReceiveProgress: onProgress,
      );

      final result = await OpenFilex.open(savePath);
      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('Error downloading or installing update: $e');
      return false;
    }
  }

  Future<String> _getApkSavePath() async {
    final supportDir = await getApplicationSupportDirectory();
    final apkPath = '${supportDir.path}/update.apk';
    
    // Clean up previous update file if it exists
    final file = File(apkPath);
    if (await file.exists()) {
      await file.delete();
    }
    
    return apkPath;
  }

  bool _isNewerVersion(String latest, String current) {
    if (latest == current) return false;
    
    final latestClean = latest.split('+').first;
    final currentClean = current.split('+').first;
    
    final latestParts = latestClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts = currentClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    for (var i = 0; i < latestParts.length && i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    
    return latestParts.length > currentParts.length;
  }
}

final githubUpdaterServiceProvider = Provider<GithubUpdaterService>((ref) {
  // Hardcoded based on user prompt 'MagicMusicCRM/MagicMusicCRM'
  return GithubUpdaterService(
    owner: 'MagicMusicCRM',
    repo: 'MagicMusicCRM',
  );
});
