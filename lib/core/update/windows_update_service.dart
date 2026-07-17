import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// One entry from `downloads/latest.json` describing the newest Windows build.
class UpdateManifest {
  final int buildNumber;
  final String version; // display, e.g. "1.2.1+142"
  final String url; // absolute link to the windows-x64 zip
  final String? sha256; // optional integrity check (hex, upper/lower ok)
  final String? notes;

  const UpdateManifest({
    required this.buildNumber,
    required this.version,
    required this.url,
    this.sha256,
    this.notes,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> j) => UpdateManifest(
        buildNumber: (j['buildNumber'] as num?)?.toInt() ?? 0,
        version: j['version']?.toString() ?? '',
        url: j['url']?.toString() ?? '',
        sha256: (j['sha256']?.toString().trim().isEmpty ?? true)
            ? null
            : j['sha256'].toString().trim(),
        notes: j['notes']?.toString(),
      );
}

/// Pure decision: is [manifest] a newer build than what is running, and usable?
/// Extracted so it can be unit-tested without a real HTTP round-trip.
bool shouldOfferUpdate(int currentBuild, UpdateManifest? manifest) {
  if (manifest == null) return false;
  if (manifest.url.isEmpty) return false;
  return manifest.buildNumber > currentBuild;
}

/// In-app updater for the Windows desktop build. Android/iOS update through
/// their stores; Windows has none, so the app checks a manifest we host on our
/// own server and, on the user's confirmation, hands the swap to a detached
/// PowerShell helper that waits for this process to exit, unpacks the new zip
/// over the install directory and relaunches.
class WindowsUpdateService {
  /// The build number baked in at compile time
  /// (`--dart-define=APP_BUILD_NUMBER=<pubspec build>`). 0 in dev/CI builds that
  /// don't pass it — the updater then stays disabled.
  static const int currentBuild =
      int.fromEnvironment('APP_BUILD_NUMBER', defaultValue: 0);

  final String manifestUrl;
  final Dio _dio;

  WindowsUpdateService({required this.manifestUrl, Dio? dio})
      : _dio = dio ?? Dio();

  /// Only ever active on a real, versioned Windows build.
  bool get isSupported => Platform.isWindows && currentBuild > 0;

  /// Fetches the manifest and returns it only when it describes a newer build.
  /// Any failure (offline, bad JSON, same version) resolves to null — checking
  /// for updates must never disrupt the app.
  Future<UpdateManifest?> check() async {
    if (!isSupported) return null;
    try {
      final res = await _dio.get<dynamic>(
        manifestUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: const {'Cache-Control': 'no-cache'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      final raw = res.data;
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return null;
      final manifest = UpdateManifest.fromJson(Map<String, dynamic>.from(decoded));
      return shouldOfferUpdate(currentBuild, manifest) ? manifest : null;
    } catch (_) {
      return null;
    }
  }

  /// Writes the helper script, launches it detached and quits the app so its
  /// files can be replaced. Returns only if launching the helper failed.
  Future<void> applyAndRestart(UpdateManifest manifest) async {
    if (!Platform.isWindows) return;
    final exePath = Platform.resolvedExecutable;
    final installDir = File(exePath).parent.path;
    final tempDir = await getTemporaryDirectory();
    final scriptFile = File('${tempDir.path}\\mmcrm_update.ps1');
    await scriptFile.writeAsString(updaterScript);

    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        scriptFile.path,
        '-AppPid',
        '$pid',
        '-Url',
        manifest.url,
        '-Sha256',
        manifest.sha256 ?? '',
        '-InstallDir',
        installDir,
        '-ExePath',
        exePath,
      ],
      mode: ProcessStartMode.detached,
    );

    // Give the detached helper a moment to spin up, then exit so it can take a
    // lock-free copy over our files.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    exit(0);
  }
}

/// PowerShell helper: waits for the app (by PID) to exit, downloads + verifies
/// the zip, unpacks it over the install directory (robocopy — additive, never
/// deletes user data), then relaunches. On any download/verify failure it just
/// relaunches the current version, so a bad manifest can't brick the install.
const String updaterScript = r'''
param(
  [int]$AppPid,
  [string]$Url,
  [string]$Sha256,
  [string]$InstallDir,
  [string]$ExePath
)
$ErrorActionPreference = 'SilentlyContinue'
try { Wait-Process -Id $AppPid -Timeout 120 } catch {}
Start-Sleep -Milliseconds 800

$tmp = Join-Path $env:TEMP ("mmcrm_upd_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zip = Join-Path $tmp 'update.zip'

try { Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing }
catch { Start-Process -FilePath $ExePath; exit 1 }

if ($Sha256 -ne '') {
  $h = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash
  if ($h -ne $Sha256.ToUpper()) { Start-Process -FilePath $ExePath; Remove-Item -Recurse -Force $tmp; exit 1 }
}

$ext = Join-Path $tmp 'ext'
Expand-Archive -Path $zip -DestinationPath $ext -Force

# If the zip has a single top-level folder, unpack from inside it.
$src = $ext
$dirs = @(Get-ChildItem $ext -Directory)
$files = @(Get-ChildItem $ext -File)
if ($dirs.Count -eq 1 -and $files.Count -eq 0) { $src = $dirs[0].FullName }

robocopy $src $InstallDir /E /R:3 /W:1 /NFL /NDL /NJH /NJS | Out-Null
Remove-Item -Recurse -Force $tmp
Start-Process -FilePath $ExePath
''';
