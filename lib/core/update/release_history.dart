import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import 'windows_update_service.dart';

const String releaseHistoryAssetPath = 'assets/release_history.json';
const String releaseHistoryDownloadPath = '/downloads/release-history.json';

class AppReleaseNote {
  const AppReleaseNote({
    required this.version,
    required this.buildNumber,
    required this.date,
    required this.title,
    required this.summary,
    required this.changes,
  });

  final String version;
  final int? buildNumber;
  final String date;
  final String title;
  final String summary;
  final List<String> changes;

  factory AppReleaseNote.fromJson(Map<String, dynamic> json) {
    final changes = (json['changes'] as List<dynamic>? ?? const [])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final note = AppReleaseNote(
      version: json['version']?.toString().trim() ?? '',
      buildNumber: (json['buildNumber'] as num?)?.toInt(),
      date: json['date']?.toString().trim() ?? '',
      title: json['title']?.toString().trim() ?? '',
      summary: json['summary']?.toString().trim() ?? '',
      changes: changes,
    );
    if (note.version.isEmpty ||
        (note.buildNumber != null && note.buildNumber! <= 0) ||
        note.date.isEmpty ||
        note.title.isEmpty ||
        note.summary.isEmpty ||
        note.changes.isEmpty) {
      throw const FormatException('Incomplete release history entry.');
    }
    return note;
  }
}

List<AppReleaseNote> parseReleaseHistory(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('Release history must be an object.');
  }
  final releases = decoded['releases'];
  if (releases is! List || releases.isEmpty) {
    throw const FormatException('Release history is empty.');
  }

  final result = <AppReleaseNote>[];
  final builds = <int>{};
  var previousBuild = 1 << 30;
  for (final value in releases) {
    if (value is! Map) {
      throw const FormatException('Release history entry must be an object.');
    }
    final note = AppReleaseNote.fromJson(Map<String, dynamic>.from(value));
    final buildNumber = note.buildNumber;
    if (buildNumber != null) {
      if (!builds.add(buildNumber)) {
        throw const FormatException(
          'Release history contains duplicate builds.',
        );
      }
      if (buildNumber >= previousBuild) {
        throw const FormatException(
          'Release history must be ordered from newest to oldest.',
        );
      }
      previousBuild = buildNumber;
    }
    result.add(note);
  }
  return List.unmodifiable(result);
}

String releaseHistoryUrlForApi(String apiBaseUrl) {
  final base = Uri.parse(apiBaseUrl);
  return Uri(
    scheme: base.scheme.isEmpty ? 'https' : base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: releaseHistoryDownloadPath,
  ).toString();
}

bool isTrustedReleaseHistoryEndpoint(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.userInfo.isEmpty &&
      uri.host.isNotEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      trustedWindowsUpdateHosts.contains(uri.host.toLowerCase()) &&
      uri.path == releaseHistoryDownloadPath &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty;
}

class ReleaseHistoryRepository {
  ReleaseHistoryRepository({Dio? dio, AssetBundle? bundle, this.remoteUrl})
    : _dio = dio ?? Dio(),
      _bundle = bundle ?? rootBundle;

  final Dio _dio;
  final AssetBundle _bundle;
  final String? remoteUrl;

  Future<List<AppReleaseNote>> load() async {
    final url = remoteUrl;
    if (url != null && isTrustedReleaseHistoryEndpoint(url)) {
      try {
        final response = await _dio.get<dynamic>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (status) => status == 200,
            headers: const {
              'Cache-Control': 'no-cache, no-store',
              'Pragma': 'no-cache',
            },
            receiveTimeout: const Duration(seconds: 10),
            sendTimeout: const Duration(seconds: 10),
          ),
        );
        final raw = response.data;
        if (raw is String) return parseReleaseHistory(raw);
      } catch (_) {
        // The bundled history keeps the section usable while offline.
      }
    }
    return loadBundled();
  }

  Future<List<AppReleaseNote>> loadBundled() async {
    final raw = await _bundle.loadString(releaseHistoryAssetPath);
    return parseReleaseHistory(raw);
  }
}

class InstalledAppVersion {
  const InstalledAppVersion({required this.version, required this.buildNumber});

  final String version;
  final int buildNumber;

  String get shortVersion => version.split('+').first;
}

Future<InstalledAppVersion> loadInstalledAppVersion({
  ReleaseHistoryRepository? repository,
  int currentBuild = WindowsUpdateService.currentBuild,
}) async {
  final history = await (repository ?? ReleaseHistoryRepository())
      .loadBundled();
  if (currentBuild > 0) {
    for (final release in history) {
      if (release.buildNumber == currentBuild) {
        return InstalledAppVersion(
          version: release.version,
          buildNumber: release.buildNumber!,
        );
      }
    }
    return InstalledAppVersion(
      version: 'Сборка $currentBuild',
      buildNumber: currentBuild,
    );
  }
  final latest = history.first;
  return InstalledAppVersion(
    version: latest.version,
    buildNumber: latest.buildNumber ?? 0,
  );
}
