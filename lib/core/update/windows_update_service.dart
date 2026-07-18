import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'windows_update_coordinator.dart';

const int updaterProtocolVersion = 1;
const Duration defaultWindowsUpdaterHandshakeTimeout = Duration(minutes: 10);
const String windowsUpdateManifestPath = '/downloads/latest-v2.json';
const Set<String> trustedWindowsUpdateHosts = <String>{
  'api.magicmusiccrm.ru',
};

final RegExp _sha256Pattern = RegExp(r'^[A-Fa-f0-9]{64}$');

/// One entry from `downloads/latest-v2.json` describing the newest Windows build.
class UpdateManifest {
  final int buildNumber;
  final String version; // display, e.g. "1.2.1+142"
  final String url; // absolute link to the windows-x64 zip
  final String? sha256; // mandatory at the trust boundary (hex, upper/lower ok)
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
bool shouldOfferUpdate(int currentBuild, UpdateManifest? manifest) {
  if (manifest == null) return false;
  if (manifest.url.isEmpty) return false;
  return manifest.buildNumber > currentBuild;
}

bool isTrustedWindowsManifestEndpoint(String manifestUrl) {
  final uri = Uri.tryParse(manifestUrl);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.host.isEmpty ||
      (uri.hasPort && uri.port != 443) ||
      uri.path != windowsUpdateManifestPath ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    return false;
  }
  return trustedWindowsUpdateHosts.contains(uri.host.toLowerCase());
}

bool isTrustedWindowsUpdateManifest(
  UpdateManifest manifest, {
  required String trustedHost,
  bool allowInsecureLoopback = false,
}) {
  final uri = Uri.tryParse(manifest.url);
  final normalizedHost = trustedHost.toLowerCase();
  final loopbackAllowed =
      allowInsecureLoopback &&
      uri != null &&
      _isLoopbackHost(uri.host) &&
      _isLoopbackHost(normalizedHost);
  if (uri == null ||
      uri.userInfo.isNotEmpty ||
      uri.host.toLowerCase() != normalizedHost ||
      (loopbackAllowed &&
          uri.scheme.toLowerCase() != 'http' &&
          uri.scheme.toLowerCase() != 'https') ||
      (!loopbackAllowed && uri.scheme.toLowerCase() != 'https') ||
      (!loopbackAllowed &&
          !trustedWindowsUpdateHosts.contains(normalizedHost)) ||
      (uri.hasPort && !loopbackAllowed && uri.port != 443)) {
    return false;
  }
  return manifest.sha256 != null &&
      _sha256Pattern.hasMatch(manifest.sha256!.trim());
}

bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

class WindowsUpdateLaunchException implements Exception {
  const WindowsUpdateLaunchException(this.message, {this.logPath});

  final String message;
  final String? logPath;

  @override
  String toString() => logPath == null
      ? 'WindowsUpdateLaunchException: $message'
      : 'WindowsUpdateLaunchException: $message (log: $logPath)';
}

class CimBrokerReceipt {
  const CimBrokerReceipt({
    required this.returnValue,
    required this.processId,
    this.error,
  });

  final int returnValue;
  final int processId;
  final String? error;
}

class UpdaterHandshake {
  const UpdaterHandshake({
    required this.type,
    required this.protocolVersion,
    required this.updateId,
    required this.helperPid,
    required this.elevated,
    this.code,
    this.message,
  });

  final String type;
  final int protocolVersion;
  final String updateId;
  final int helperPid;
  final bool elevated;
  final String? code;
  final String? message;

  bool get isReady => type == 'ready';
}

class UpdaterLaunchSession {
  const UpdaterLaunchSession({
    required this.updateId,
    required this.brokerProcessId,
    required this.handshake,
    required this.runDirectory,
    required this.logPath,
  });

  final String updateId;
  final int brokerProcessId;
  final UpdaterHandshake handshake;
  final String runDirectory;
  final String logPath;
}

/// In-app updater for the Windows desktop build. Android/iOS update through
/// their stores. Windows hands the file swap to a PowerShell helper created by
/// `Win32_Process.Create`, which is outside launchers' kill-on-close jobs.
class WindowsUpdateService {
  static const int currentBuild = int.fromEnvironment(
    'APP_BUILD_NUMBER',
    defaultValue: 0,
  );

  final String manifestUrl;
  final Dio _dio;

  WindowsUpdateService({required this.manifestUrl, Dio? dio})
    : _dio = dio ?? Dio();

  bool get isSupported => Platform.isWindows && currentBuild > 0;

  Future<UpdateManifest?> check() async {
    if (!isSupported) return null;
    if (!isTrustedWindowsManifestEndpoint(manifestUrl)) return null;
    try {
      final res = await _dio.get<dynamic>(
        manifestUrl,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (status) => status == 200,
          headers: const {'Cache-Control': 'no-cache'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      final raw = res.data;
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return null;
      final manifest = UpdateManifest.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      final trustedHost = Uri.parse(manifestUrl).host;
      if (!isTrustedWindowsUpdateManifest(manifest, trustedHost: trustedHost)) {
        return null;
      }
      return shouldOfferUpdate(currentBuild, manifest) ? manifest : null;
    } catch (_) {
      return null;
    }
  }

  /// Starts and handshakes with the out-of-job helper. The app exits only after
  /// a matching READY message. Broker/UAC/helper failures throw, so the caller
  /// can close its progress UI while this process remains usable.
  Future<void> applyAndRestart(UpdateManifest manifest) async {
    if (!Platform.isWindows) return;

    final tempDir = await getTemporaryDirectory();
    final manifestEndpoint = Uri.tryParse(manifestUrl);
    final updateUri = Uri.tryParse(manifest.url);
    final trustedHost =
        manifestEndpoint != null &&
            trustedWindowsUpdateHosts.contains(
              manifestEndpoint.host.toLowerCase(),
            )
        ? manifestEndpoint.host
        : updateUri?.host ?? '';
    await launchWindowsUpdaterHelper(
      manifest: manifest,
      trustedManifestHost: trustedHost,
      appPid: pid,
      exePath: Platform.resolvedExecutable,
      tempDirectory: tempDir,
    );

    exit(0);
  }
}

/// Creates the unique updater files, asks a short synchronous CIM broker to
/// create the helper, and waits for READY or FAILURE. Kept separate from
/// [WindowsUpdateService.applyAndRestart] so the real lifecycle can be smoked
/// against a harmless executable in a temporary install directory.
Future<UpdaterLaunchSession> launchWindowsUpdaterHelper({
  required UpdateManifest manifest,
  required String trustedManifestHost,
  required int appPid,
  required String exePath,
  required Directory tempDirectory,
  bool allowInsecureLoopbackForTesting = false,
  Duration brokerTimeout = const Duration(seconds: 10),
  Duration handshakeTimeout = defaultWindowsUpdaterHandshakeTimeout,
  Duration handshakePollInterval = const Duration(milliseconds: 100),
}) {
  return windowsUpdateCoordinator.runLaunch(
    () => _launchWindowsUpdaterHelperUncoordinated(
      manifest: manifest,
      trustedManifestHost: trustedManifestHost,
      appPid: appPid,
      exePath: exePath,
      tempDirectory: tempDirectory,
      allowInsecureLoopbackForTesting: allowInsecureLoopbackForTesting,
      brokerTimeout: brokerTimeout,
      handshakeTimeout: handshakeTimeout,
      handshakePollInterval: handshakePollInterval,
    ),
  );
}

Future<UpdaterLaunchSession> _launchWindowsUpdaterHelperUncoordinated({
  required UpdateManifest manifest,
  required String trustedManifestHost,
  required int appPid,
  required String exePath,
  required Directory tempDirectory,
  required bool allowInsecureLoopbackForTesting,
  required Duration brokerTimeout,
  required Duration handshakeTimeout,
  required Duration handshakePollInterval,
}) async {
  if (!isTrustedWindowsUpdateManifest(
    manifest,
    trustedHost: trustedManifestHost,
    allowInsecureLoopback: allowInsecureLoopbackForTesting,
  )) {
    throw const WindowsUpdateLaunchException(
      'Update manifest URL or mandatory SHA-256 is not trusted.',
    );
  }
  if (!Platform.isWindows) {
    throw const WindowsUpdateLaunchException(
      'Windows updater was requested on a non-Windows platform.',
    );
  }

  final powerShellPath = resolveWindowsPowerShellPath();
  if (!File(powerShellPath).existsSync()) {
    throw WindowsUpdateLaunchException(
      'Windows PowerShell was not found at $powerShellPath.',
    );
  }

  final updaterRoot = Directory(
    '${tempDirectory.path}${Platform.pathSeparator}MagicMusicCRM'
    '${Platform.pathSeparator}updater',
  );
  await updaterRoot.create(recursive: true);
  final runDirectory = await updaterRoot.createTemp('run_${appPid}_');
  final updateId = runDirectory.path.split(Platform.pathSeparator).last;
  final helperFile = File(
    '${runDirectory.path}${Platform.pathSeparator}helper.ps1',
  );
  final requestFile = File(
    '${runDirectory.path}${Platform.pathSeparator}request.json',
  );
  final launchCommandFile = File(
    '${runDirectory.path}${Platform.pathSeparator}launch_command.txt',
  );
  final readyFile = File(
    '${runDirectory.path}${Platform.pathSeparator}ready.json',
  );
  final failureFile = File(
    '${runDirectory.path}${Platform.pathSeparator}failure.json',
  );
  final acknowledgementFile = File(
    '${runDirectory.path}${Platform.pathSeparator}ack.json',
  );
  final cancellationFile = File(
    '${runDirectory.path}${Platform.pathSeparator}cancel.json',
  );
  final healthAcknowledgementFile = File(
    '${runDirectory.path}${Platform.pathSeparator}health_ack.json',
  );
  final workDirectory = Directory(
    '${runDirectory.path}${Platform.pathSeparator}payload',
  );
  final logFile = File(
    '${updaterRoot.path}${Platform.pathSeparator}mmcrm_update.jsonl',
  );
  final installDir = File(exePath).parent.path;

  await helperFile.writeAsString(updaterScript, flush: true);
  final helperBytes = await helperFile.readAsBytes();
  final helperSha256 = sha256Hex(helperBytes);
  final mutexDigest = sha256Hex(
    utf8.encode(installDir.toLowerCase().replaceAll('/', r'\')),
  ).substring(0, 32);
  final request = <String, dynamic>{
    'protocolVersion': updaterProtocolVersion,
    'updateId': updateId,
    'appPid': appPid,
    'buildNumber': manifest.buildNumber,
    'version': manifest.version,
    'url': manifest.url,
    'sha256': manifest.sha256!.trim(),
    'trustedHost': trustedManifestHost.toLowerCase(),
    'allowInsecureLoopback': allowInsecureLoopbackForTesting,
    'installDir': installDir,
    'exePath': exePath,
    'expectedExeName': File(exePath).uri.pathSegments.last,
    'readyPath': readyFile.path,
    'failurePath': failureFile.path,
    'ackPath': acknowledgementFile.path,
    'cancelPath': cancellationFile.path,
    'healthAckPath': healthAcknowledgementFile.path,
    'workPath': workDirectory.path,
    'rollbackPath': '${workDirectory.path}${Platform.pathSeparator}rollback',
    'recoveryJournalPath':
        '${workDirectory.path}${Platform.pathSeparator}recovery.json',
    'logPath': logFile.path,
    'powerShellPath': powerShellPath,
    'helperSha256': helperSha256,
    'mutexName': 'Local\\MagicMusicCRM.Update.$mutexDigest',
  };
  final trustedRequestJson = jsonEncode(request);
  await requestFile.writeAsString(trustedRequestJson, flush: true);
  final encodedHelperCommand = buildEncodedUpdaterHelperCommand(
    helperPath: helperFile.path,
    expectedHelperSha256: helperSha256,
    trustedRequestJson: trustedRequestJson,
  );

  final helperCommandLine = buildEncodedPowerShellCommandLine(
    powerShellPath: powerShellPath,
    encodedCommand: encodedHelperCommand,
  );
  await launchCommandFile.writeAsString(helperCommandLine, flush: true);
  final launchCommandSha256 = sha256Hex(await launchCommandFile.readAsBytes());
  final brokerCommand = encodePowerShellCommand(
    buildCimBrokerScript(
      launchCommandPath: launchCommandFile.path,
      expectedSha256: launchCommandSha256,
    ),
  );
  late CimBrokerReceipt receipt;
  late UpdaterHandshake handshake;
  try {
    receipt = await runCimBroker(
      powerShellPath: powerShellPath,
      encodedBrokerCommand: brokerCommand,
      timeout: brokerTimeout,
      logPath: logFile.path,
    );
    handshake = await waitForUpdaterHandshake(
      readyFile: readyFile,
      failureFile: failureFile,
      expectedUpdateId: updateId,
      timeout: handshakeTimeout,
      pollInterval: handshakePollInterval,
      logPath: logFile.path,
    );
    await _writeUpdaterControlFile(
      acknowledgementFile,
      type: 'ack',
      updateId: updateId,
    );
  } catch (_) {
    try {
      await _writeUpdaterControlFile(
        cancellationFile,
        type: 'cancel',
        updateId: updateId,
      );
    } catch (_) {
      // Preserve the original broker/handshake failure for the UI.
    }
    rethrow;
  }

  return UpdaterLaunchSession(
    updateId: updateId,
    brokerProcessId: receipt.processId,
    handshake: handshake,
    runDirectory: runDirectory.path,
    logPath: logFile.path,
  );
}

Future<void> _writeUpdaterControlFile(
  File destination, {
  required String type,
  required String updateId,
}) async {
  final temporary = File('${destination.path}.$pid.tmp');
  await temporary.writeAsString(
    jsonEncode(<String, Object>{
      'type': type,
      'protocolVersion': updaterProtocolVersion,
      'updateId': updateId,
      'appPid': pid,
      'timestampUtc': DateTime.now().toUtc().toIso8601String(),
    }),
    flush: true,
  );
  await temporary.rename(destination.path);
}

Future<bool> publishWindowsUpdateHealthAck({
  required String ackPath,
  required String updateId,
  Directory? trustedTempDirectory,
  int? appProcessId,
}) async {
  if (!RegExp(r'^run_\d+_[A-Za-z0-9]+$').hasMatch(updateId)) return false;
  try {
    final trustedRoot = Directory(
      '${(trustedTempDirectory ?? Directory.systemTemp).absolute.path}'
      '${Platform.pathSeparator}MagicMusicCRM${Platform.pathSeparator}updater',
    ).absolute.uri.normalizePath();
    final acknowledgement = File(ackPath).absolute;
    final acknowledgementUri = acknowledgement.uri.normalizePath();
    if (!acknowledgementUri.toString().toLowerCase().startsWith(
          trustedRoot.toString().toLowerCase(),
        ) ||
        acknowledgement.uri.pathSegments.isEmpty ||
        acknowledgement.uri.pathSegments.last != 'health_ack.json' ||
        acknowledgement.parent.uri.pathSegments
                .where((segment) => segment.isNotEmpty)
                .last !=
            updateId ||
        !await acknowledgement.parent.exists()) {
      return false;
    }

    final temporary = File(
      '${acknowledgement.path}.${appProcessId ?? pid}.tmp',
    );
    await temporary.writeAsString(
      jsonEncode(<String, Object>{
        'type': 'health_ack',
        'protocolVersion': updaterProtocolVersion,
        'updateId': updateId,
        'appPid': appProcessId ?? pid,
        'timestampUtc': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    await temporary.rename(acknowledgement.path);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> publishWindowsUpdateHealthAckFromEnvironment() {
  final ackPath = Platform.environment['MMCRM_UPDATE_HEALTH_ACK_PATH'] ?? '';
  final updateId = Platform.environment['MMCRM_UPDATE_ID'] ?? '';
  if (ackPath.isEmpty || updateId.isEmpty) return Future<bool>.value(false);
  return publishWindowsUpdateHealthAck(ackPath: ackPath, updateId: updateId);
}

String resolveWindowsPowerShellPath() {
  final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  return '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
}

/// PowerShell's `-EncodedCommand` format is UTF-16LE followed by Base64.
String encodePowerShellCommand(String source) {
  final bytes = <int>[];
  for (final unit in source.codeUnits) {
    bytes
      ..add(unit & 0xff)
      ..add((unit >> 8) & 0xff);
  }
  return base64Encode(bytes);
}

String decodePowerShellCommand(String encoded) {
  final bytes = base64Decode(encoded);
  if (bytes.length.isOdd) {
    throw const FormatException('PowerShell command has odd UTF-16LE length.');
  }
  final units = <int>[];
  for (var i = 0; i < bytes.length; i += 2) {
    units.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(units);
}

String _utf8Base64(String value) => base64Encode(utf8.encode(value));

String sha256Hex(List<int> input) {
  const mask = 0xffffffff;
  const initial = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  const roundConstants = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  final message = <int>[...input.map((byte) => byte & 0xff), 0x80];
  while (message.length % 64 != 56) {
    message.add(0);
  }
  final bitLength = input.length * 8;
  for (var shift = 56; shift >= 0; shift -= 8) {
    message.add((bitLength >> shift) & 0xff);
  }

  final hash = List<int>.from(initial);
  final words = List<int>.filled(64, 0);
  for (var offset = 0; offset < message.length; offset += 64) {
    for (var i = 0; i < 16; i++) {
      final index = offset + i * 4;
      words[i] =
          ((message[index] << 24) |
              (message[index + 1] << 16) |
              (message[index + 2] << 8) |
              message[index + 3]) &
          mask;
    }
    for (var i = 16; i < 64; i++) {
      final s0 =
          _rotateRight(words[i - 15], 7) ^
          _rotateRight(words[i - 15], 18) ^
          (words[i - 15] >>> 3);
      final s1 =
          _rotateRight(words[i - 2], 17) ^
          _rotateRight(words[i - 2], 19) ^
          (words[i - 2] >>> 10);
      words[i] = (words[i - 16] + s0 + words[i - 7] + s1) & mask;
    }

    var a = hash[0];
    var b = hash[1];
    var c = hash[2];
    var d = hash[3];
    var e = hash[4];
    var f = hash[5];
    var g = hash[6];
    var h = hash[7];
    for (var i = 0; i < 64; i++) {
      final upperSigma1 =
          _rotateRight(e, 6) ^ _rotateRight(e, 11) ^ _rotateRight(e, 25);
      final choose = (e & f) ^ ((~e) & g);
      final temporary1 =
          (h + upperSigma1 + choose + roundConstants[i] + words[i]) & mask;
      final upperSigma0 =
          _rotateRight(a, 2) ^ _rotateRight(a, 13) ^ _rotateRight(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temporary2 = (upperSigma0 + majority) & mask;
      h = g;
      g = f;
      f = e;
      e = (d + temporary1) & mask;
      d = c;
      c = b;
      b = a;
      a = (temporary1 + temporary2) & mask;
    }
    hash[0] = (hash[0] + a) & mask;
    hash[1] = (hash[1] + b) & mask;
    hash[2] = (hash[2] + c) & mask;
    hash[3] = (hash[3] + d) & mask;
    hash[4] = (hash[4] + e) & mask;
    hash[5] = (hash[5] + f) & mask;
    hash[6] = (hash[6] + g) & mask;
    hash[7] = (hash[7] + h) & mask;
  }
  return hash.map((word) => word.toRadixString(16).padLeft(8, '0')).join();
}

int _rotateRight(int value, int count) {
  return ((value >>> count) | (value << (32 - count))) & 0xffffffff;
}

/// Carries only Base64 data and the expected helper hash. The bootstrap reads
/// helper bytes once, verifies them, and executes the verified in-memory text;
/// mutable request.json is retained for forensics but never trusted at runtime.
String buildEncodedUpdaterHelperCommand({
  required String helperPath,
  required String expectedHelperSha256,
  required String trustedRequestJson,
}) {
  if (!_sha256Pattern.hasMatch(expectedHelperSha256)) {
    throw const FormatException('Expected helper SHA-256 is invalid.');
  }
  final helper = _utf8Base64(helperPath);
  final request = _utf8Base64(trustedRequestJson);
  final source =
      '''
\$ErrorActionPreference = 'Stop'
\$ProgressPreference = 'SilentlyContinue'
\$utf8 = New-Object System.Text.UTF8Encoding(\$false, \$true)
\$trustedRequestBase64 = '$request'
\$requestJson = \$utf8.GetString([Convert]::FromBase64String(\$trustedRequestBase64))
\$request = \$requestJson | ConvertFrom-Json
function Publish-BootstrapFailure {
  try {
    \$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    \$principal = New-Object Security.Principal.WindowsPrincipal(\$identity)
    \$payload = [ordered]@{
      type = 'failure'
      protocolVersion = 1
      updateId = [string]\$request.updateId
      helperPid = \$PID
      elevated = \$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
      code = 'helper_integrity_failed'
      message = 'Updater bootstrap integrity validation failed.'
      timestampUtc = [DateTime]::UtcNow.ToString('o')
    }
    \$json = \$payload | ConvertTo-Json -Compress
    \$temporaryPath = ([string]\$request.failurePath) + '.' + \$PID + '.tmp'
    [IO.File]::WriteAllText(\$temporaryPath, \$json, (New-Object Text.UTF8Encoding(\$false)))
    Move-Item -LiteralPath \$temporaryPath -Destination ([string]\$request.failurePath) -Force
  } catch {}
}
try {
  \$helperPath = \$utf8.GetString([Convert]::FromBase64String('$helper'))
  \$helperBytes = [IO.File]::ReadAllBytes(\$helperPath)
  \$sha = [Security.Cryptography.SHA256]::Create()
  try { \$actualHash = (\$sha.ComputeHash(\$helperBytes) | ForEach-Object { \$_.ToString('x2') }) -join '' }
  finally { \$sha.Dispose() }
  if (-not [string]::Equals(\$actualHash, '$expectedHelperSha256', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Updater helper integrity check failed.'
  }
  \$helperSource = \$utf8.GetString(\$helperBytes)
  \$scriptBlock = [ScriptBlock]::Create(\$helperSource)
  & \$scriptBlock -TrustedRequestBase64 \$trustedRequestBase64 -ExpectedHelperSha256 '$expectedHelperSha256' -HelperPath \$helperPath
} catch {
  Publish-BootstrapFailure
  exit 31
}
''';
  return encodePowerShellCommand(source);
}

String buildEncodedPowerShellCommandLine({
  required String powerShellPath,
  required String encodedCommand,
}) {
  return [
    quoteWindowsCommandLineArgument(powerShellPath),
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-EncodedCommand',
    encodedCommand,
  ].join(' ');
}

/// Quotes one argument according to the Windows CommandLineToArgvW convention.
String quoteWindowsCommandLineArgument(String value) {
  if (value.isEmpty) return '""';
  if (!RegExp(r'[\s"]').hasMatch(value)) return value;

  final result = StringBuffer('"');
  var backslashes = 0;
  for (final unit in value.codeUnits) {
    if (unit == 0x5c) {
      backslashes++;
      continue;
    }
    if (unit == 0x22) {
      result.write(_repeatBackslash(backslashes * 2 + 1));
      result.write('"');
      backslashes = 0;
      continue;
    }
    result.write(_repeatBackslash(backslashes));
    result.writeCharCode(unit);
    backslashes = 0;
  }
  result.write(_repeatBackslash(backslashes * 2));
  result.write('"');
  return result.toString();
}

String _repeatBackslash(int count) => List.filled(count, '\\').join();

/// The broker itself contains only a Base64 command line, so no updater URL or
/// filesystem path is interpreted as PowerShell source.
String buildCimBrokerScript({
  required String launchCommandPath,
  required String expectedSha256,
}) {
  if (!_sha256Pattern.hasMatch(expectedSha256)) {
    throw const FormatException('Expected launch command SHA-256 is invalid.');
  }
  final commandPath = _utf8Base64(launchCommandPath);
  return '''
\$ErrorActionPreference = 'Stop'
\$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding(\$false)
try {
  \$commandPath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$commandPath'))
  \$commandBytes = [IO.File]::ReadAllBytes(\$commandPath)
  \$sha = [Security.Cryptography.SHA256]::Create()
  try { \$actualHash = (\$sha.ComputeHash(\$commandBytes) | ForEach-Object { \$_.ToString('x2') }) -join '' }
  finally { \$sha.Dispose() }
  if (-not [string]::Equals(\$actualHash, '$expectedSha256', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Updater launch command integrity check failed.'
  }
  \$commandLine = (New-Object Text.UTF8Encoding(\$false, \$true)).GetString(\$commandBytes)
  \$result = Invoke-CimMethod -Namespace 'root/cimv2' -ClassName 'Win32_Process' -MethodName 'Create' -Arguments @{ CommandLine = \$commandLine }
  \$payload = [ordered]@{ returnValue = [int]\$result.ReturnValue; processId = [int]\$result.ProcessId }
  [Console]::Out.WriteLine((\$payload | ConvertTo-Json -Compress))
  if ([int]\$result.ReturnValue -ne 0 -or [int]\$result.ProcessId -le 0) { exit 41 }
} catch {
  \$payload = [ordered]@{ returnValue = -1; processId = 0; error = \$_.Exception.Message }
  [Console]::Out.WriteLine((\$payload | ConvertTo-Json -Compress))
  exit 42
}
''';
}

Future<CimBrokerReceipt> runCimBroker({
  required String powerShellPath,
  required String encodedBrokerCommand,
  required Duration timeout,
  String? logPath,
}) async {
  final process = await Process.start(powerShellPath, [
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-EncodedCommand',
    encodedBrokerCommand,
  ], mode: ProcessStartMode.normal);
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();

  late int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () => -1,
    );
    final stdoutText = await _finishProcessOutput(stdoutFuture);
    final stderrText = await _finishProcessOutput(stderrFuture);
    throw WindowsUpdateLaunchException(
      'CIM updater broker timed out after ${timeout.inSeconds}s. '
      'stdout=${_oneLine(stdoutText)} stderr=${_oneLine(stderrText)}',
      logPath: logPath,
    );
  }

  final stdoutText = await _finishProcessOutput(stdoutFuture);
  final stderrText = await _finishProcessOutput(stderrFuture);
  CimBrokerReceipt receipt;
  try {
    receipt = parseCimBrokerOutput(stdoutText);
  } on FormatException catch (error) {
    throw WindowsUpdateLaunchException(
      'CIM updater broker returned an invalid receipt: $error. '
      'stdout=${_oneLine(stdoutText)} stderr=${_oneLine(stderrText)}',
      logPath: logPath,
    );
  }
  if (exitCode != 0 || receipt.returnValue != 0 || receipt.processId <= 0) {
    throw WindowsUpdateLaunchException(
      'CIM updater broker failed: exit=$exitCode, '
      'returnValue=${receipt.returnValue}, pid=${receipt.processId}, '
      'error=${receipt.error ?? _oneLine(stderrText)}.',
      logPath: logPath,
    );
  }
  return receipt;
}

Future<String> _finishProcessOutput(Future<String> output) async {
  try {
    return await output.timeout(const Duration(seconds: 2));
  } catch (_) {
    return '';
  }
}

String _oneLine(String value) {
  final text = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  return text.length <= 500 ? text : '${text.substring(0, 500)}…';
}

CimBrokerReceipt parseCimBrokerOutput(String stdoutText) {
  for (final line in const LineSplitter().convert(stdoutText).reversed) {
    final candidate = line.trim().replaceFirst('\ufeff', '');
    if (!candidate.startsWith('{')) continue;
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is! Map) continue;
      final map = Map<String, dynamic>.from(decoded);
      final returnValue = (map['returnValue'] as num?)?.toInt();
      final processId = (map['processId'] as num?)?.toInt();
      if (returnValue == null || processId == null) continue;
      return CimBrokerReceipt(
        returnValue: returnValue,
        processId: processId,
        error: map['error']?.toString(),
      );
    } catch (_) {
      // PowerShell may emit progress records around the single JSON receipt.
    }
  }
  throw const FormatException('No JSON broker receipt was found.');
}

UpdaterHandshake parseUpdaterHandshake(String contents) {
  final decoded = jsonDecode(contents.replaceFirst('\ufeff', ''));
  if (decoded is! Map) {
    throw const FormatException('Updater handshake is not a JSON object.');
  }
  final map = Map<String, dynamic>.from(decoded);
  final type = map['type']?.toString() ?? '';
  final protocol = (map['protocolVersion'] as num?)?.toInt();
  final updateId = map['updateId']?.toString() ?? '';
  final helperPid = (map['helperPid'] as num?)?.toInt();
  final elevated = map['elevated'];
  if ((type != 'ready' && type != 'failure') ||
      protocol == null ||
      updateId.isEmpty ||
      helperPid == null ||
      helperPid <= 0 ||
      elevated is! bool) {
    throw const FormatException('Updater handshake has an invalid schema.');
  }
  return UpdaterHandshake(
    type: type,
    protocolVersion: protocol,
    updateId: updateId,
    helperPid: helperPid,
    elevated: elevated,
    code: map['code']?.toString(),
    message: map['message']?.toString(),
  );
}

Future<UpdaterHandshake> waitForUpdaterHandshake({
  required File readyFile,
  required File failureFile,
  required String expectedUpdateId,
  required Duration timeout,
  Duration pollInterval = const Duration(milliseconds: 100),
  String? logPath,
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    if (await failureFile.exists()) {
      final failure = await _readAndValidateHandshake(
        failureFile,
        expectedUpdateId: expectedUpdateId,
        expectedType: 'failure',
        logPath: logPath,
      );
      throw WindowsUpdateLaunchException(
        'Updater helper failed before takeover: '
                '${failure.code ?? 'unknown'} ${failure.message ?? ''}'
            .trim(),
        logPath: logPath,
      );
    }
    if (await readyFile.exists()) {
      return _readAndValidateHandshake(
        readyFile,
        expectedUpdateId: expectedUpdateId,
        expectedType: 'ready',
        logPath: logPath,
      );
    }
    await Future<void>.delayed(pollInterval);
  }
  throw WindowsUpdateLaunchException(
    'Updater helper did not publish READY or FAILURE within '
    '${timeout.inSeconds}s.',
    logPath: logPath,
  );
}

Future<UpdaterHandshake> _readAndValidateHandshake(
  File file, {
  required String expectedUpdateId,
  required String expectedType,
  String? logPath,
}) async {
  try {
    final handshake = parseUpdaterHandshake(await file.readAsString());
    if (handshake.protocolVersion != updaterProtocolVersion ||
        handshake.updateId != expectedUpdateId ||
        handshake.type != expectedType) {
      throw const FormatException('Updater handshake does not match request.');
    }
    return handshake;
  } on WindowsUpdateLaunchException {
    rethrow;
  } catch (error) {
    throw WindowsUpdateLaunchException(
      'Invalid updater $expectedType handshake: $error',
      logPath: logPath,
    );
  }
}

/// PowerShell helper protocol:
/// integrity-verified embedded request -> READY/FAILURE JSON, plus append-only
/// JSONL diagnostics. request.json is forensic-only and is never trusted.
/// A non-writable Program Files installation is elevated interactively before
/// READY; declining UAC produces FAILURE while the Flutter process stays open.
const String updaterScript = r'''
param(
  [Parameter(Mandatory = $true)][string]$TrustedRequestBase64,
  [Parameter(Mandatory = $true)][string]$ExpectedHelperSha256,
  [Parameter(Mandatory = $true)][string]$HelperPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:Request = $null
$script:ReadyWritten = $false
$script:IsElevated = $false
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:UpdateMutex = $null
$script:MutexOwned = $false
$script:OldAppRelaunched = $false

function Write-AtomicJson([string]$Path, $Payload) {
  $json = $Payload | ConvertTo-Json -Depth 8 -Compress
  $temporaryPath = "$Path.$PID.tmp"
  [IO.File]::WriteAllText($temporaryPath, $json, $script:Utf8NoBom)
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Protect-SensitiveText($Value) {
  if ($null -eq $Value) { return '' }
  $text = [string]$Value
  if ($null -ne $script:Request) {
    foreach ($secret in @([string]$script:Request.url)) {
      if (-not [string]::IsNullOrWhiteSpace($secret)) {
        $text = $text.Replace($secret, '[REDACTED]')
      }
    }
  }
  return [regex]::Replace(
    $text,
    '(?i)\b(token|access_token|auth|key|api_key|signature|sig|secret|code)=([^&\s]+)',
    '$1=[REDACTED]'
  )
}

function Write-Log([string]$Stage, [string]$Message = '', $Data = $null) {
  if ($null -eq $script:Request) { return }
  try {
    $record = [ordered]@{
      timestampUtc = [DateTime]::UtcNow.ToString('o')
      protocolVersion = 1
      updateId = [string]$script:Request.updateId
      pid = $PID
      elevated = $script:IsElevated
      stage = $Stage
      message = Protect-SensitiveText $Message
    }
    if ($null -ne $Data) { $record.data = $Data }
    $line = ($record | ConvertTo-Json -Depth 8 -Compress) + [Environment]::NewLine
    [IO.File]::AppendAllText([string]$script:Request.logPath, $line, $script:Utf8NoBom)
  } catch {}
}

function Write-Failure([string]$Code, [string]$Message) {
  if ($null -eq $script:Request) { return }
  $payload = [ordered]@{
    type = 'failure'
    protocolVersion = 1
    updateId = [string]$script:Request.updateId
    helperPid = $PID
    elevated = $script:IsElevated
    code = $Code
    message = Protect-SensitiveText $Message
    timestampUtc = [DateTime]::UtcNow.ToString('o')
  }
  Write-AtomicJson -Path ([string]$script:Request.failurePath) -Payload $payload
}

function Test-CurrentProcessElevated {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-InstallDirectoryWritable {
  $probePath = Join-Path ([string]$script:Request.installDir) ('.mmcrm_update_probe_' + [string]$script:Request.updateId)
  try {
    [IO.File]::WriteAllText($probePath, 'probe', $script:Utf8NoBom)
    Remove-Item -LiteralPath $probePath -Force
    return $true
  } catch {
    try { Remove-Item -LiteralPath $probePath -Force -ErrorAction Ignore } catch {}
    return $false
  }
}

function Test-MatchingControlFile([string]$Path, [string]$ExpectedType) {
  if (-not [IO.File]::Exists($Path)) { return $false }
  try {
    $control = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    return (
      [int]$control.protocolVersion -eq 1 -and
      [string]$control.updateId -eq [string]$script:Request.updateId -and
      [string]$control.type -eq $ExpectedType
    )
  } catch {
    Write-Log -Stage 'invalid_control_file' -Message $_.Exception.Message -Data @{ type = $ExpectedType }
    return $false
  }
}

function Assert-TrustedRequest {
  if ([int]$script:Request.protocolVersion -ne 1) { throw 'Unsupported updater protocol version.' }
  if ([string]::IsNullOrWhiteSpace([string]$script:Request.updateId)) { throw 'Missing updateId.' }
  if (-not ([string]$script:Request.sha256 -match '^[A-Fa-f0-9]{64}$')) { throw 'A 64-hex payload SHA256 is required.' }
  if (-not ([string]$ExpectedHelperSha256 -match '^[A-Fa-f0-9]{64}$')) { throw 'Expected helper SHA256 is invalid.' }
  if (-not [string]::Equals([string]$script:Request.helperSha256, [string]$ExpectedHelperSha256, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Trusted helper SHA256 does not match the request.'
  }
  if (-not ([string]$script:Request.mutexName -match '^Local\\MagicMusicCRM\.Update\.[a-f0-9]{32}$')) {
    throw 'Install mutex name is invalid.'
  }
  if (-not [string]::Equals(
    [string]$script:Request.expectedExeName,
    [IO.Path]::GetFileName([string]$script:Request.exePath),
    [StringComparison]::OrdinalIgnoreCase
  )) { throw 'Expected executable name is invalid.' }

  $updateUri = $null
  if (-not [Uri]::TryCreate([string]$script:Request.url, [UriKind]::Absolute, [ref]$updateUri)) {
    throw 'Update URL is invalid.'
  }
  $trustedHost = ([string]$script:Request.trustedHost).ToLowerInvariant()
  if (-not [string]::Equals($updateUri.DnsSafeHost, $trustedHost, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Update URL host does not match the trusted manifest host.'
  }
  $allowLoopback = [bool]$script:Request.allowInsecureLoopback
  if ($allowLoopback) {
    if (-not $updateUri.IsLoopback -or @('http', 'https') -notcontains $updateUri.Scheme.ToLowerInvariant()) {
      throw 'Insecure updater transport is restricted to loopback smoke tests.'
    }
  } else {
    if ($updateUri.Scheme -ne 'https') { throw 'Update URL must use HTTPS.' }
    if (@('api.magicmusiccrm.ru') -notcontains $trustedHost) {
      throw 'Update URL host is not trusted.'
    }
    if (-not $updateUri.IsDefaultPort -and $updateUri.Port -ne 443) { throw 'Update URL port is not trusted.' }
  }
}

function Acquire-UpdateMutex {
  try {
    $script:UpdateMutex = New-Object System.Threading.Mutex($false, ([string]$script:Request.mutexName))
    try {
      $script:MutexOwned = $script:UpdateMutex.WaitOne(0)
    } catch [Threading.AbandonedMutexException] {
      $script:MutexOwned = $true
    }
    if (-not $script:MutexOwned) {
      $script:UpdateMutex.Dispose()
      $script:UpdateMutex = $null
    }
    return $script:MutexOwned
  } catch {
    Write-Log -Stage 'mutex_failed' -Message $_.Exception.Message
    return $false
  }
}

function Release-UpdateMutex {
  if ($script:MutexOwned -and $null -ne $script:UpdateMutex) {
    try { $script:UpdateMutex.ReleaseMutex() } catch {}
  }
  if ($null -ne $script:UpdateMutex) {
    try { $script:UpdateMutex.Dispose() } catch {}
  }
  $script:MutexOwned = $false
  $script:UpdateMutex = $null
}

function New-VerifiedBootstrapEncodedCommand {
  $helperPathBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$HelperPath))
  $template = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$trustedRequestBase64 = '__TRUSTED_REQUEST_BASE64__'
$requestJson = $utf8.GetString([Convert]::FromBase64String($trustedRequestBase64))
$request = $requestJson | ConvertFrom-Json
function Publish-BootstrapFailure {
  try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $payload = [ordered]@{
      type = 'failure'; protocolVersion = 1; updateId = [string]$request.updateId
      helperPid = $PID
      elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
      code = 'helper_integrity_failed'; message = 'Updater bootstrap integrity validation failed.'
      timestampUtc = [DateTime]::UtcNow.ToString('o')
    }
    $json = $payload | ConvertTo-Json -Compress
    $temporaryPath = ([string]$request.failurePath) + '.' + $PID + '.tmp'
    [IO.File]::WriteAllText($temporaryPath, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporaryPath -Destination ([string]$request.failurePath) -Force
  } catch {}
}
try {
  $helperPath = $utf8.GetString([Convert]::FromBase64String('__HELPER_PATH_BASE64__'))
  $helperBytes = [IO.File]::ReadAllBytes($helperPath)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $actualHash = ($sha.ComputeHash($helperBytes) | ForEach-Object { $_.ToString('x2') }) -join '' }
  finally { $sha.Dispose() }
  if (-not [string]::Equals($actualHash, '__EXPECTED_HELPER_SHA256__', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Updater helper integrity check failed.'
  }
  $helperSource = $utf8.GetString($helperBytes)
  $scriptBlock = [ScriptBlock]::Create($helperSource)
  & $scriptBlock -TrustedRequestBase64 $trustedRequestBase64 -ExpectedHelperSha256 '__EXPECTED_HELPER_SHA256__' -HelperPath $helperPath
} catch {
  Publish-BootstrapFailure
  exit 31
}
'@
  $bootstrapSource = $template.Replace('__TRUSTED_REQUEST_BASE64__', [string]$TrustedRequestBase64)
  $bootstrapSource = $bootstrapSource.Replace('__HELPER_PATH_BASE64__', $helperPathBase64)
  $bootstrapSource = $bootstrapSource.Replace('__EXPECTED_HELPER_SHA256__', [string]$ExpectedHelperSha256)
  return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootstrapSource))
}

function Assert-StagedPayload([string]$SourcePath) {
  $requiredFiles = @(
    [string]$script:Request.expectedExeName,
    'flutter_windows.dll',
    'data\icudtl.dat',
    'data\app.so'
  )
  foreach ($relativePath in $requiredFiles) {
    $candidate = Join-Path $SourcePath $relativePath
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      throw "Staged payload is missing required file: $relativePath"
    }
  }
  $flutterAssets = Join-Path $SourcePath 'data\flutter_assets'
  if (-not (Test-Path -LiteralPath $flutterAssets -PathType Container)) {
    throw 'Staged payload is missing data\flutter_assets.'
  }
  Write-Log -Stage 'payload_structure_verified'
}

function Write-RecoveryJournal([string]$State, [string]$Message = '') {
  $journal = [ordered]@{
    protocolVersion = 1
    updateId = [string]$script:Request.updateId
    state = $State
    message = Protect-SensitiveText $Message
    installDir = [string]$script:Request.installDir
    rollbackPath = [string]$script:Request.rollbackPath
    exePath = [string]$script:Request.exePath
    healthAckPath = [string]$script:Request.healthAckPath
    timestampUtc = [DateTime]::UtcNow.ToString('o')
  }
  Write-AtomicJson -Path ([string]$script:Request.recoveryJournalPath) -Payload $journal
}

function Test-MatchingHealthAck([int]$ExpectedPid) {
  $path = [string]$script:Request.healthAckPath
  if (-not [IO.File]::Exists($path)) { return $false }
  try {
    $ack = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    return (
      [int]$ack.protocolVersion -eq 1 -and
      [string]$ack.type -eq 'health_ack' -and
      [string]$ack.updateId -eq [string]$script:Request.updateId -and
      [int]$ack.appPid -eq $ExpectedPid
    )
  } catch {
    Write-Log -Stage 'invalid_health_ack' -Message $_.Exception.Message
    return $false
  }
}

function Invoke-RobocopyTree([string]$Source, [string]$Destination, [bool]$Mirror = $false) {
  $copyMode = if ($Mirror) { '/MIR' } else { '/E' }
  & robocopy.exe $Source $Destination $copyMode /XJ /R:3 /W:1 /NFL /NDL /NJH /NJS | Out-Null
  return [int]$LASTEXITCODE
}

function Relaunch-App([string]$Reason, [bool]$RequestHealthAck = $false) {
  Write-Log -Stage 'relaunch_started' -Message $Reason
  $previousAckPath = [Environment]::GetEnvironmentVariable('MMCRM_UPDATE_HEALTH_ACK_PATH', 'Process')
  $previousUpdateId = [Environment]::GetEnvironmentVariable('MMCRM_UPDATE_ID', 'Process')
  try {
    if ($RequestHealthAck) {
      [Environment]::SetEnvironmentVariable('MMCRM_UPDATE_HEALTH_ACK_PATH', [string]$script:Request.healthAckPath, 'Process')
      [Environment]::SetEnvironmentVariable('MMCRM_UPDATE_ID', [string]$script:Request.updateId, 'Process')
    } else {
      [Environment]::SetEnvironmentVariable('MMCRM_UPDATE_HEALTH_ACK_PATH', $null, 'Process')
      [Environment]::SetEnvironmentVariable('MMCRM_UPDATE_ID', $null, 'Process')
    }
    return Start-Process -FilePath ([string]$script:Request.exePath) -WorkingDirectory ([string]$script:Request.installDir) -PassThru
  } finally {
    [Environment]::SetEnvironmentVariable('MMCRM_UPDATE_HEALTH_ACK_PATH', $previousAckPath, 'Process')
    [Environment]::SetEnvironmentVariable('MMCRM_UPDATE_ID', $previousUpdateId, 'Process')
  }
}

try {
  $rawRequest = $script:Utf8NoBom.GetString([Convert]::FromBase64String($TrustedRequestBase64))
  $script:Request = $rawRequest | ConvertFrom-Json
  Assert-TrustedRequest
  $script:IsElevated = Test-CurrentProcessElevated

  Write-Log -Stage 'helper_started' -Data @{
    appPid = [int]$script:Request.appPid
    helperPid = $PID
    version = [string]$script:Request.version
  }

  if (-not (Acquire-UpdateMutex)) {
    Write-Log -Stage 'update_already_running' -Message 'Another updater owns this installation.'
    Write-Failure -Code 'update_already_running' -Message 'Another update is already running.'
    exit 24
  }

  if (Test-MatchingControlFile -Path ([string]$script:Request.cancelPath) -ExpectedType 'cancel') {
    Write-Log -Stage 'launch_cancelled' -Message 'The application cancelled updater launch before READY.'
    Write-Failure -Code 'launch_cancelled' -Message 'Updater launch was cancelled.'
    exit 22
  }

  if (-not (Test-InstallDirectoryWritable)) {
    if (-not $script:IsElevated) {
      Write-Log -Stage 'elevation_required' -Message 'Install directory is not writable.'
      try {
        $elevationEncodedCommand = New-VerifiedBootstrapEncodedCommand
        # The elevated process must acquire its own mutex. Release this handle
        # before UAC so no deadlock spans the integrity-verified handoff.
        Release-UpdateMutex
        $startArguments = @{
          FilePath = [string]$script:Request.powerShellPath
          Verb = 'RunAs'
          WindowStyle = 'Hidden'
          ArgumentList = @(
            '-NoLogo', '-NoProfile', '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-EncodedCommand', $elevationEncodedCommand
          )
          PassThru = $true
          ErrorAction = 'Stop'
        }
        $elevatedProcess = Start-Process @startArguments
        Write-Log -Stage 'elevation_spawned' -Data @{ elevatedPid = $elevatedProcess.Id }
        exit 0
      } catch {
        Write-Log -Stage 'elevation_denied' -Message $_.Exception.Message
        Write-Failure -Code 'elevation_denied' -Message $_.Exception.Message
        exit 20
      }
    }

    Write-Log -Stage 'install_not_writable' -Message 'Elevated helper still cannot write the install directory.'
    Write-Failure -Code 'install_not_writable' -Message 'Install directory is not writable.'
    exit 21
  }

  Write-Log -Stage 'install_dir_writable'

  # Keep Flutter and its persistent progress overlay alive while every slow or
  # fallible preparation step runs. READY means only process stop + file swap
  # remain.
  $workPath = [string]$script:Request.workPath
  New-Item -ItemType Directory -Force -Path $workPath | Out-Null
  $zipPath = Join-Path $workPath 'update.zip'
  Write-Log -Stage 'download_started'
  Invoke-WebRequest -Uri ([string]$script:Request.url) -OutFile $zipPath -UseBasicParsing -TimeoutSec 300 -MaximumRedirection 0 -ErrorAction Stop
  Write-Log -Stage 'download_completed' -Data @{ bytes = (Get-Item -LiteralPath $zipPath).Length }

  $expectedHash = ([string]$script:Request.sha256).Trim()
  $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash
  if ($actualHash -ne $expectedHash.ToUpperInvariant()) {
    throw "SHA256 mismatch: got $actualHash"
  }
  Write-Log -Stage 'hash_verified'

  $extractPath = Join-Path $workPath 'extracted'
  Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force -ErrorAction Stop
  Write-Log -Stage 'archive_extracted'

  $sourcePath = $extractPath
  $directories = @(Get-ChildItem -LiteralPath $extractPath -Directory)
  $files = @(Get-ChildItem -LiteralPath $extractPath -File)
  if ($directories.Count -eq 1 -and $files.Count -eq 0) {
    $sourcePath = $directories[0].FullName
  }
  Assert-StagedPayload -SourcePath $sourcePath

  $rollbackPath = [string]$script:Request.rollbackPath
  $snapshotExitCode = Invoke-RobocopyTree -Source ([string]$script:Request.installDir) -Destination $rollbackPath
  Write-Log -Stage 'rollback_snapshot_completed' -Data @{ exitCode = $snapshotExitCode }
  if ($snapshotExitCode -lt 0 -or $snapshotExitCode -ge 8) {
    throw "rollback snapshot failed with robocopy exit code $snapshotExitCode"
  }
  Write-RecoveryJournal -State 'payload_staged' -Message 'Payload and rollback snapshot are ready.'

  # A UAC decision or a slow download may outlive the app-side handshake
  # timeout. Never publish a late READY after the app cancelled this run.
  if (Test-MatchingControlFile -Path ([string]$script:Request.cancelPath) -ExpectedType 'cancel') {
    Write-Log -Stage 'launch_cancelled' -Message 'The application cancelled updater launch while staging.'
    Write-Failure -Code 'launch_cancelled' -Message 'Updater launch was cancelled.'
    exit 22
  }

  $ready = [ordered]@{
    type = 'ready'
    protocolVersion = 1
    updateId = [string]$script:Request.updateId
    helperPid = $PID
    elevated = $script:IsElevated
    timestampUtc = [DateTime]::UtcNow.ToString('o')
  }
  Write-AtomicJson -Path ([string]$script:Request.readyPath) -Payload $ready
  Write-Log -Stage 'ready'

  $ackDeadline = [DateTime]::UtcNow.AddSeconds(120)
  while (-not (Test-MatchingControlFile -Path ([string]$script:Request.ackPath) -ExpectedType 'ack')) {
    if (Test-MatchingControlFile -Path ([string]$script:Request.cancelPath) -ExpectedType 'cancel') {
      Remove-Item -LiteralPath ([string]$script:Request.readyPath) -Force -ErrorAction Ignore
      Write-Log -Stage 'launch_cancelled' -Message 'The application cancelled updater launch after READY.'
      Write-Failure -Code 'launch_cancelled' -Message 'Updater launch was cancelled.'
      exit 22
    }
    if ([DateTime]::UtcNow -ge $ackDeadline) {
      Remove-Item -LiteralPath ([string]$script:Request.readyPath) -Force -ErrorAction Ignore
      Write-Log -Stage 'ack_timeout' -Message 'The application did not acknowledge READY.'
      Write-Failure -Code 'ack_timeout' -Message 'The application did not acknowledge updater takeover.'
      exit 23
    }
    Start-Sleep -Milliseconds 50
  }
  $script:ReadyWritten = $true
  Write-Log -Stage 'ready_acknowledged'

  $parentDeadline = [DateTime]::UtcNow.AddSeconds(120)
  while ($null -ne (Get-Process -Id ([int]$script:Request.appPid) -ErrorAction Ignore)) {
    if ([DateTime]::UtcNow -ge $parentDeadline) {
      throw 'Timed out waiting for the application process to exit.'
    }
    Start-Sleep -Milliseconds 250
  }
  Write-Log -Stage 'parent_exited'
  Start-Sleep -Milliseconds 800

  Write-RecoveryJournal -State 'swap_started' -Message 'Replacing the installation tree.'
  $robocopyExitCode = Invoke-RobocopyTree -Source $sourcePath -Destination ([string]$script:Request.installDir)
  Write-Log -Stage 'robocopy_completed' -Data @{ exitCode = $robocopyExitCode }
  if ($robocopyExitCode -lt 0 -or $robocopyExitCode -ge 8) {
    Write-Log -Stage 'rollback_started' -Message 'Payload copy failed; restoring the pre-update snapshot.'
    $rollbackExitCode = Invoke-RobocopyTree -Source $rollbackPath -Destination ([string]$script:Request.installDir) -Mirror $true
    Write-Log -Stage 'rollback_completed' -Data @{ exitCode = $rollbackExitCode }
    if ($rollbackExitCode -lt 0 -or $rollbackExitCode -ge 8) {
      Write-RecoveryJournal -State 'rollback_failed' -Message "Rollback robocopy exit code $rollbackExitCode."
      throw "robocopy failed with exit code $robocopyExitCode; rollback also failed with exit code $rollbackExitCode"
    }
    Write-RecoveryJournal -State 'rollback_completed' -Message 'Payload copy failed; previous installation restored.'
    throw "robocopy failed with exit code $robocopyExitCode; previous installation restored"
  }

  Write-RecoveryJournal -State 'awaiting_health_ack' -Message 'New application started; waiting for first-frame ACK.'
  $newApp = Relaunch-App -Reason 'update_candidate' -RequestHealthAck $true
  Write-Log -Stage 'health_wait_started' -Data @{ appPid = $newApp.Id }
  $healthDeadline = [DateTime]::UtcNow.AddSeconds(45)
  $healthConfirmed = $false
  while ([DateTime]::UtcNow -lt $healthDeadline) {
    if (Test-MatchingHealthAck -ExpectedPid $newApp.Id) {
      $healthConfirmed = $true
      break
    }
    if ($newApp.HasExited) { break }
    Start-Sleep -Milliseconds 250
  }

  if (-not $healthConfirmed) {
    Write-Log -Stage 'health_check_failed' -Message 'New application exited or did not acknowledge startup.'
    if (-not $newApp.HasExited) {
      Stop-Process -Id $newApp.Id -Force -ErrorAction Ignore
      try { $newApp.WaitForExit(5000) } catch {}
    }
    Write-Log -Stage 'rollback_started' -Message 'New application health check failed.'
    $healthRollbackExitCode = Invoke-RobocopyTree -Source $rollbackPath -Destination ([string]$script:Request.installDir) -Mirror $true
    Write-Log -Stage 'rollback_completed' -Data @{ exitCode = $healthRollbackExitCode }
    if ($healthRollbackExitCode -lt 0 -or $healthRollbackExitCode -ge 8) {
      Write-RecoveryJournal -State 'rollback_failed' -Message "Health rollback robocopy exit code $healthRollbackExitCode."
      throw "new application health check failed; rollback failed with exit code $healthRollbackExitCode"
    }
    Write-RecoveryJournal -State 'rollback_completed' -Message 'New application health check failed; previous installation restored.'
    Relaunch-App -Reason 'health_check_rollback' | Out-Null
    $script:OldAppRelaunched = $true
    throw 'new application health check failed; previous installation restored'
  }

  Write-Log -Stage 'health_acknowledged' -Data @{ appPid = $newApp.Id }
  Write-RecoveryJournal -State 'healthy' -Message 'New application acknowledged startup.'
  Write-Log -Stage 'completed'
  # The log lives outside the per-run directory. Once the candidate is healthy,
  # discard the trusted request, helper, handshakes, payload and rollback copy.
  # Cleanup is best-effort and must never relaunch/roll back a healthy build.
  $completedRunPath = Split-Path -Parent $workPath
  try {
    Remove-Item -LiteralPath $completedRunPath -Recurse -Force -ErrorAction Stop
  } catch {
    Write-Log -Stage 'cleanup_deferred' -Message $_.Exception.Message
  }
  exit 0
} catch {
  $failureMessage = $_.Exception.Message
  Write-Log -Stage 'failed' -Message $failureMessage
  try { Write-Failure -Code 'helper_failed' -Message $failureMessage } catch {}
  if ($script:ReadyWritten -and -not $script:OldAppRelaunched) {
    $parentStillRunning = $null -ne (Get-Process -Id ([int]$script:Request.appPid) -ErrorAction Ignore)
    if ($parentStillRunning) {
      # A takeover timeout happened before the swap. The original UI is still
      # alive, so launching it again would create a duplicate CRM process.
      Write-Log -Stage 'relaunch_skipped' -Message 'Original application is still running.'
    } else {
      try { Relaunch-App -Reason 'update_failed' | Out-Null } catch { Write-Log -Stage 'relaunch_failed' -Message $_.Exception.Message }
    }
  }
  exit 1
} finally {
  if (-not $script:ReadyWritten -and $null -ne $script:Request) {
    try {
      $terminalWorkPath = [string]$script:Request.workPath
      if (-not [string]::IsNullOrWhiteSpace($terminalWorkPath) -and (Test-Path -LiteralPath $terminalWorkPath)) {
        Remove-Item -LiteralPath $terminalWorkPath -Recurse -Force -ErrorAction Ignore
      }
    } catch {}
  }
  Release-UpdateMutex
}
''';
