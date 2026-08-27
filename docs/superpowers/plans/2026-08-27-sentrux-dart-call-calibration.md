# Sentrux Dart Call-Attribution Calibration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Windows-only, repository-owned Sentrux 0.5.7 M1 harness that measures Dart call attribution on controlled fixtures, restores the installed Dart query byte-for-byte, and never edits application code.

**Architecture:** Isolated fixtures turn aggregate call-edge counts into attributable deltas. A version-locked MCP client measures stock and staged queries; a separate watchdog process owns the named Windows mutex, a durable manifest protects the brief global-query overlay, and every mismatch fails closed.

**Tech Stack:** Dart 3.11.1, Flutter test, `dart:io`, `dart:ffi`, transitive `crypto` 3.0.7, `ffi` 2.2.0 and `win32` 5.15.0, JSON-RPC/MCP `2024-11-05`, Sentrux 0.5.7

**Spec:** `docs/superpowers/specs/2026-08-27-five-hour-hotspot-sprint-design.md`

## Global Constraints

- Create only the eight Lane A paths listed below; do not modify `lib/**`, `server/src/**`, `pubspec.yaml`, `pubspec.lock`, `.sentrux/rules.toml`, `.sentrux/baseline.json`, or RepoWise generated state.
- Treat M1 as call-attribution evidence only. Dart equality, redundancy, function NLOC, body hashes, and root quality remain invalid or informational.
- Use the literal approved Windows paths, mutex name, Sentrux version, MCP protocol, and seven hashes in this plan. Do not redirect `HOME` or `USERPROFILE` and do not install or update Sentrux.
- Abort before installed-query mutation if any unrelated `sentrux.exe` exists; never terminate it. Abort and restore if a foreign PID appears during the critical section.
- Accept Lane A only after live fixture calibration, byte-for-byte restoration, absent recovery manifest, immutable application paths, and one focused lane commit. Maximum lane time is 215 minutes.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `tool/sentrux/dart/sensor-lock.json` | Create | Frozen Sentrux/MCP identity and seven artifact hashes |
| `tool/sentrux/dart/queries/tags.scm` | Create | Staged Dart definitions, imports, calls, and type references |
| `tool/sentrux/dart/fixtures/pubspec.yaml.fixture` | Create | Dependency-free Dart 3.11 fixture package |
| `tool/sentrux/dart/fixtures/lib/main.dart.fixture` | Create | Marked positive and negative call sites |
| `tool/sentrux/dart/fixtures/lib/probe.dart.fixture` | Create | Matching definitions, dead probe, and duplicate signatures |
| `tool/src/sentrux_dart_sensor.dart` | Create | Validation, MCP, fixture, recovery, process, and evidence logic |
| `tool/calibrate_sentrux_dart.dart` | Create | Public CLI and private watchdog entry point |
| `test/architecture/sentrux_dart_sensor_test.dart` | Create | Parser, lifecycle, recovery, and live acceptance tests |

The production repository is read-only to this lane. Temporary fixture directories and the external recovery directory are runtime artifacts, not tracked files.

## Frozen Sensor Contract

`sensor-lock.json` must contain exactly:

```json
{
  "schema_version": 1,
  "sentrux_version": "0.5.7",
  "mcp_protocol_version": "2024-11-05",
  "mutex_name": "Local\\MagicMusicCRM.SentruxDartSensor.v0_5_7",
  "recovery_root": "C:\\Users\\Alinka\\AppData\\Local\\MagicMusicCRM\\sentrux-dart-sensor-recovery",
  "artifacts": [
    { "id": "sentrux_executable", "path": "C:\\Users\\Alinka\\AppData\\Local\\Programs\\Sentrux\\sentrux.exe", "sha256": "40DD2E47804BF9F006015EB742ABFE178A824F42D4A19EB00478A7D705697CAC" },
    { "id": "dart_plugin", "path": "C:\\Users\\Alinka\\.sentrux\\plugins\\dart\\plugin.toml", "sha256": "7271A5F0376CE3FF3AD81B9314F2D9355405AA3D20356A84AB3A8D1C082958F1" },
    { "id": "dart_query", "path": "C:\\Users\\Alinka\\.sentrux\\plugins\\dart\\queries\\tags.scm", "sha256": "3B70536E2303745FE31220DE09972F489E77543283EC95C95BCD01F62661FDDD" },
    { "id": "dart_grammar", "path": "C:\\Users\\Alinka\\.sentrux\\plugins\\dart\\grammars\\windows-x86_64.dll", "sha256": "482C79FEC72C93A07C38F2BDC009C0B405931F206AA0C2E50FD42E224125434B" },
    { "id": "typescript_plugin", "path": "C:\\Users\\Alinka\\.sentrux\\plugins\\typescript\\plugin.toml", "sha256": "27219129BB53AFB16D2E3D407C592B2CF3F600A42F724A6EF9974FB9CA375406" },
    { "id": "typescript_query", "path": "C:\\Users\\Alinka\\.sentrux\\plugins\\typescript\\queries\\tags.scm", "sha256": "0977EE307FBBD8E9607932763BB81446D305D37A639E7FDBA0562FC542E40BA7" },
    { "id": "typescript_grammar", "path": "C:\\Users\\Alinka\\.sentrux\\plugins\\typescript\\grammars\\windows-x86_64.dll", "sha256": "37DD6AD9E4C9458CA45A3021A95F93F11C28B231DB7BCEF890D96376464BE169" }
  ]
}
```

The complete staged query is:

```scheme
; Dart tags.scm — M1 call-attribution calibration for Sentrux 0.5.7.

(function_signature
  name: (identifier) @name) @definition.function

(class_definition
  name: (identifier) @name) @definition.class

(enum_declaration
  name: (identifier) @name) @definition.class

(mixin_declaration
  (identifier) @name) @definition.class

(import_or_export
  (library_import
    (import_specification
      (configurable_uri) @import.module))) @import

; foo() and foo<T>()
(_
  (identifier) @call.name
  .
  (selector (argument_part)) @call)

; obj.foo(), Type.foo(), and chained calls
(_
  (selector
    (unconditional_assignable_selector
      (identifier) @call.name))
  .
  (selector (argument_part)) @call)

; obj?.foo()
(_
  (selector
    (conditional_assignable_selector
      (identifier) @call.name))
  .
  (selector (argument_part)) @call)

; cascade calls
(cascade_section
  (cascade_selector (identifier) @call.name)
  .
  (argument_part) @call)
(cascade_section
  (unconditional_assignable_selector (identifier) @call.name)
  .
  (argument_part) @call)
(cascade_section
  (conditional_assignable_selector (identifier) @call.name)
  .
  (argument_part) @call)

; constructors
(new_expression
  (type_identifier) @call.name
  (arguments)) @call
(const_object_expression
  (type_identifier) @call.name
  (arguments)) @call

(type_identifier) @reference.type
```

Do not claim per-symbol names from Sentrux. Each fixture variant contains one controlled call category, so the strict aggregate call-edge delta is the observer.

`dartNonCallCapturesMatch` normalizes line endings, requires the exact four definition blocks, import block, and type-reference block once in both queries, and requires the total counts of `@definition.function`, `@definition.class`, `@import.module`, `@import`, and `@reference.type` to match. Any extra or changed non-call capture fails the staged-plugin gate.

## Exact Public Interfaces

Create these declarations in `tool/src/sentrux_dart_sensor.dart`:

```dart
// ignore_for_file: depend_on_referenced_packages

final class SensorArtifactLock {
  const SensorArtifactLock({
    required this.id,
    required this.path,
    required this.sha256,
  });
  final String id;
  final String path;
  final String sha256;
}

final class SensorLock {
  const SensorLock({
    required this.schemaVersion,
    required this.sentruxVersion,
    required this.mcpProtocolVersion,
    required this.mutexName,
    required this.recoveryRoot,
    required this.artifacts,
  });
  final int schemaVersion;
  final String sentruxVersion;
  final String mcpProtocolVersion;
  final String mutexName;
  final String recoveryRoot;
  final List<SensorArtifactLock> artifacts;
  static SensorLock fromJson(Map<String, Object?> json);
}

final class SensorPaths {
  const SensorPaths({
    required this.repositoryRoot,
    required this.sentruxExecutable,
    required this.installedDartPlugin,
    required this.installedDartQuery,
    required this.stagedDartQuery,
    required this.recoveryRoot,
  });
  factory SensorPaths.approvedHost(Directory repositoryRoot, SensorLock lock);
  final Directory repositoryRoot;
  final File sentruxExecutable;
  final Directory installedDartPlugin;
  final File installedDartQuery;
  final File stagedDartQuery;
  final Directory recoveryRoot;
  File get manifestFile;
  File get backupFile;
}

final class RecoveryManifest {
  const RecoveryManifest({
    required this.schemaVersion,
    required this.sentruxVersion,
    required this.mutexName,
    required this.targetPath,
    required this.backupPath,
    required this.originalSha256,
    required this.stagedSha256,
    required this.ownerPid,
    required this.createdAtUtc,
  });
  final int schemaVersion;
  final String sentruxVersion;
  final String mutexName;
  final String targetPath;
  final String backupPath;
  final String originalSha256;
  final String stagedSha256;
  final int ownerPid;
  final DateTime createdAtUtc;
  Map<String, Object?> toJson();
  static RecoveryManifest fromJson(Map<String, Object?> json);
}

final class RootCauseMetric {
  const RootCauseMetric({required this.raw, required this.score});
  final double raw;
  final int score;
}

final class HealthSnapshot {
  const HealthSnapshot({
    required this.raw,
    required this.qualitySignal,
    required this.totalImportEdges,
    required this.crossModuleEdges,
    required this.equality,
    required this.redundancy,
  });
  final Map<String, Object?> raw;
  final int qualitySignal;
  final int totalImportEdges;
  final int crossModuleEdges;
  final RootCauseMetric equality;
  final RootCauseMetric redundancy;
  static HealthSnapshot fromMcpContent(Map<String, Object?> result);
}

final class ScanObservation {
  const ScanObservation({required this.callEdges, required this.health});
  final int callEdges;
  final HealthSnapshot health;
}

final class FixtureCase {
  const FixtureCase({
    required this.id,
    required this.enabledBlocks,
    required this.expectedCallDelta,
    required this.negative,
  });
  final String id;
  final Set<String> enabledBlocks;
  final int expectedCallDelta;
  final bool negative;
}

abstract interface class SensorProcess {
  int get pid;
  IOSink get stdin;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

typedef SensorProcessLauncher = Future<SensorProcess> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});
typedef SentruxPidReader = Future<Set<int>> Function();

final class SentruxMcpClient {
  static Future<SentruxMcpClient> start({
    required File executable,
    required String expectedVersion,
    required String expectedProtocolVersion,
    required SensorProcessLauncher launch,
  });
  factory SentruxMcpClient.forTest({
    required SensorMcpTransport transport,
    required Duration diagnosticQuietPeriod,
  });
  int get pid;
  Future<ScanObservation> scan(Directory directory);
  void abort();
  Future<void> close();
}

abstract interface class SensorWatchdogHandle {
  int get pid;
  String get normalFinishEventName;
  Future<int> get exitCode;
  void assertAlive();
  Future<void> finishNormally();
}

typedef SensorWatchdogStarter = Future<SensorWatchdogHandle> Function({
  required SensorPaths paths,
  required int parentPid,
  required SensorProcessLauncher launch,
});

final class NamedMutexWatchdog implements SensorWatchdogHandle {
  static const mutexName =
      r'Local\MagicMusicCRM.SentruxDartSensor.v0_5_7';
  static Future<NamedMutexWatchdog> start({
    required SensorPaths paths,
    required int parentPid,
    required SensorProcessLauncher launch,
  });
  int get pid;
  String get normalFinishEventName;
  Future<int> get exitCode;
  void assertAlive();
  Future<void> finishNormally();
}

abstract interface class SentruxPidWatch {
  Future<void> get violation;
  Future<void> stop();
}

typedef SentruxPidWatchStarter = Future<SentruxPidWatch> Function({
  required int ownedPid,
  required SentruxPidReader readPids,
  required Duration interval,
});

final class SequentialSentruxPidWatch implements SentruxPidWatch {
  SequentialSentruxPidWatch._({
    required this.ownedPid,
    required SentruxPidReader readPids,
    required this.interval,
  }) : _readPids = readPids;

  final int ownedPid;
  final SentruxPidReader _readPids;
  final Duration interval;
  final Completer<void> _violation = Completer<void>();
  bool _stopRequested = false;
  late final Future<void> _loop;

  static Future<SequentialSentruxPidWatch> start({
    required int ownedPid,
    required SentruxPidReader readPids,
    required Duration interval,
  }) async {
    final initial = await readPids();
    if (initial.length != 1 || !initial.contains(ownedPid)) {
      throw StateError('Initial Sentrux PID set is not exactly {$ownedPid}.');
    }
    final watch = SequentialSentruxPidWatch._(
      ownedPid: ownedPid,
      readPids: readPids,
      interval: interval,
    );
    watch._loop = watch._pollSequentially();
    return watch;
  }

  @override
  Future<void> get violation => _violation.future;

  Future<void> _pollSequentially() async {
    while (!_stopRequested) {
      await Future<void>.delayed(interval);
      if (_stopRequested) return;
      try {
        final observed = await _readPids();
        if (observed.length != 1 || !observed.contains(ownedPid)) {
          if (!_violation.isCompleted) {
            _violation.completeError(
              StateError('Unexpected Sentrux PID set: $observed.'),
              StackTrace.current,
            );
          }
          return;
        }
      } on Object catch (error, stackTrace) {
        if (!_violation.isCompleted) {
          _violation.completeError(error, stackTrace);
        }
        return;
      }
    }
  }

  @override
  Future<void> stop() async {
    _stopRequested = true;
    await _loop;
  }
}

final class CalibrationEvidence {
  const CalibrationEvidence({
    required this.stock,
    required this.staged,
    required this.duplicateSignatureClassification,
    required this.installedArtifactHashes,
    required this.recoveryMaterialPresent,
    required this.unrelatedSentruxObserved,
    required this.watchdogExitedNormally,
    this.fullRepository,
  });
  final Map<String, ScanObservation> stock;
  final Map<String, ScanObservation> staged;
  final String duplicateSignatureClassification;
  final Map<String, String> installedArtifactHashes;
  final bool recoveryMaterialPresent;
  final bool unrelatedSentruxObserved;
  final bool watchdogExitedNormally;
  final ScanObservation? fullRepository;
  Map<String, Object?> toJson();
}

final class SentruxDartSensorRunner {
  const SentruxDartSensorRunner({
    required this.paths,
    required this.lock,
    required this.launch,
    required this.readSentruxPids,
    required this.startWatchdog,
    required this.startPidWatch,
  });
  final SensorPaths paths;
  final SensorLock lock;
  final SensorProcessLauncher launch;
  final SentruxPidReader readSentruxPids;
  final SensorWatchdogStarter startWatchdog;
  final SentruxPidWatchStarter startPidWatch;
  Future<CalibrationEvidence> run({required bool includeFullRepository});
}

String sha256File(File file);
int parseBuildGraphCallEdges(Iterable<String> diagnosticLines);
bool dartNonCallCapturesMatch(String stockQuery, String stagedQuery);
String materializeFixtureTemplate(String source, Set<String> enabledBlocks);
Future<void> recoverStaleManifest(SensorPaths paths, SensorLock lock);
Future<void> validateStagedDartPlugin(
  SensorPaths paths,
  Directory scratchRoot,
);
Future<void> restoreInstalledQueryAndVerify(
  SensorPaths paths,
  SensorLock lock,
);
Future<void> deleteVerifiedRecoveryMaterial(
  SensorPaths paths,
  SensorLock lock,
);
void recoverStaleManifestSync(SensorPaths paths, SensorLock lock);
void verifyNoRecoveryMaterialAndStockTargetSync(
  SensorPaths paths,
  SensorLock lock,
);
void writeWatchdogLineSync(String line);
Future<Set<int>> readWindowsSentruxPids();
int runSensorWatchdog(List<String> arguments);
```

The public CLI has exactly two user modes:

```text
dart run tool/calibrate_sentrux_dart.dart --fixture-only
dart run tool/calibrate_sentrux_dart.dart --full-repo .
```

The parent starts the private child with the named arguments `--watchdog`, `--parent-pid`, `--finish-event`, `--lock-file`, `--manifest`, `--target`, `--backup`, and `--stock-sha256`. Values come directly from `pid`, the generated event name, the absolute `sensor-lock.json` path, `SensorPaths`, and the frozen lock. Any missing, duplicate, relative-path, or unknown argument exits 64 before starting Sentrux or reading recovery bytes.

## Exact MCP Transaction Boundary

The production transport is line-delimited JSON-RPC over one owned `sentrux.exe mcp` process. Unit tests inject this interface:

```dart
abstract interface class SensorMcpTransport {
  int get pid;
  Stream<String> get stderrLines;
  Future<Map<String, Object?>> request(
    String method,
    Map<String, Object?> params, {
    required Duration timeout,
  });
  Future<void> notify(String method, Map<String, Object?> params);
  Future<void> close({required Duration timeout});
  void abort();
}

final class OwnedTransportAbort {
  OwnedTransportAbort({
    required SensorProcess process,
    required Map<int, Completer<Map<String, Object?>>> pendingRequests,
  })  : _process = process,
        _pendingRequests = pendingRequests;

  final SensorProcess _process;
  final Map<int, Completer<Map<String, Object?>>> _pendingRequests;
  bool _aborted = false;

  void abort() {
    if (_aborted) return;
    _aborted = true;
    final error = StateError('Owned Sentrux MCP transport was aborted.');
    final stackTrace = StackTrace.current;
    final pending = _pendingRequests.values.toList(growable: false);
    _pendingRequests.clear();
    for (final request in pending) {
      if (!request.isCompleted) request.completeError(error, stackTrace);
    }
    try {
      _process.kill(ProcessSignal.sigkill);
    } on Object {
      // Pending requests are already failed; restoration must not be delayed.
    }
  }
}

final class DiagnosticInbox {
  void add(String line);
  void requireEmpty();
  Future<String> takeOne({required Duration timeout});
  Future<void> requireQuiet({required Duration duration});
}
```

`LineJsonMcpTransport` creates one `OwnedTransportAbort` over its owned `SensorProcess` and live request-completer map; its `abort()` delegates directly. `SentruxMcpClient.abort()` delegates to `_transport.abort()`. Thus abort is synchronous, idempotent, never targets a discovered PID, and completes an in-flight scan immediately even if native process termination reports failure. The transport still drains its already-open pipes until process exit.

The fake-backed abort contract is executable:

```dart
test('abort fails pending request and kills only the owned process', () async {
  final process = FakeSensorProcess(pid: 41);
  final pending = <int, Completer<Map<String, Object?>>>{
    7: Completer<Map<String, Object?>>(),
  };
  final request = pending[7]!.future;
  final abort = OwnedTransportAbort(
    process: process,
    pendingRequests: pending,
  );

  abort.abort();
  abort.abort();

  await expectLater(request, throwsStateError);
  expect(process.killCalls, 1);
  expect(process.pid, 41);
  expect(pending, isEmpty);
});
```

`request` allocates a monotonically increasing positive ID, writes one JSON line, accepts only the same ID, rejects a JSON-RPC error, and returns the response `result`. `LineJsonMcpTransport` continuously drains both stdout and stderr until process exit; malformed stdout is fatal and every stderr line is still drained even when it is not a build-graph diagnostic.

`SentruxMcpClient.scan` performs two distinct MCP tool calls and preserves the complete health object:

```dart
Future<ScanObservation> scan(Directory directory) async {
  _diagnostics.requireEmpty();
  final diagnosticFuture = _diagnostics.takeOne(
    timeout: const Duration(seconds: 180),
  );
  final scanFuture = _callToolTextJson(
    'scan',
    {'path': directory.absolute.path},
    timeout: const Duration(seconds: 180),
  );
  final pair = await Future.wait<Object>([
    scanFuture,
    diagnosticFuture,
  ]).timeout(const Duration(seconds: 180));
  await _diagnostics.requireQuiet(
    duration: const Duration(milliseconds: 250),
  );
  final healthJson = await _callToolTextJson(
    'health',
    const {},
    timeout: const Duration(seconds: 30),
  );
  _diagnostics.requireEmpty();
  return ScanObservation(
    callEdges: parseBuildGraphCallEdges([pair[1] as String]),
    health: HealthSnapshot.fromMcpContent(healthJson),
  );
}

Future<Map<String, Object?>> _callToolTextJson(
  String name,
  Map<String, Object?> arguments, {
  required Duration timeout,
}) async {
  final result = await _transport.request(
    'tools/call',
    {
      'name': name,
      'arguments': arguments,
    },
    timeout: timeout,
  );
  final content = result['content'];
  if (content is! List || content.length != 1) {
    throw FormatException('$name returned invalid MCP content.');
  }
  final item = content.single;
  if (item is! Map || item['type'] != 'text' || item['text'] is! String) {
    throw FormatException('$name returned non-text MCP content.');
  }
  final decoded = jsonDecode(item['text'] as String);
  if (decoded is! Map<String, Object?>) {
    throw FormatException('$name text was not a JSON object.');
  }
  return decoded;
}
```

The 250 ms quiet window starts only after both the scan response and its first diagnostic arrive. A second diagnostic becomes pending and fails the current scan; a diagnostic that arrives between scans fails the next `requireEmpty`. Closing the client drains both pipes and requires the total accepted diagnostic count to equal the total completed scan calls.

The fake transport RED case is exact:

```dart
test('scan waits for its diagnostic then requests separate health', () async {
  final transport = ScriptedMcpTransport();
  final client = SentruxMcpClient.forTest(
    transport: transport,
    diagnosticQuietPeriod: Duration.zero,
  );
  final observationFuture = client.scan(Directory('C:\\fixture'));

  transport.completeTool(
    name: 'scan',
    textJson: {'quality_signal': 9999},
  );
  expect(transport.requestedToolNames, ['scan']);
  transport.emitStderr(
    '[build_graphs] 2 files | maps 1ms, imports 1ms, '
    'calls+inherit 1ms, total 3ms | 1 import, 7 call, 0 inherit edges',
  );
  await transport.waitForToolRequest('health');
  transport.completeTool(name: 'health', textJson: {
    'quality_signal': 5817,
    'total_import_edges': 5599,
    'cross_module_edges': 2957,
    'root_causes': {
      'equality': {'raw': 0.3487530500448399, 'score': 6512},
      'redundancy': {'raw': 0.522313862840357, 'score': 4777},
    },
  });

  final observation = await observationFuture;
  expect(observation.callEdges, 7);
  expect(observation.health.qualitySignal, 5817);
  expect(observation.health.raw['total_import_edges'], 5599);
  expect(transport.requestedToolNames, ['scan', 'health']);
});
```

`ScriptedMcpTransport` is a test-only implementation of `SensorMcpTransport`; Task 2 creates it before this test. It queues requests by tool name, completes them explicitly, and exposes stderr through a synchronous broadcast controller so the ordering above is deterministic.

## Exact Watchdog Protocol

The parent creates a unique manual-reset event by concatenating `Local\MagicMusicCRM.SentruxDartSensor.finish.`, the decimal parent PID, `.`, and 32 lowercase hexadecimal random characters. The child first creates and owns the literal mutex, then opens the parent process and finish event without yielding its native thread. Its core is:

```dart
enum WatchdogWake { normalFinish, parentExit, failed }

final class WatchdogConfig {
  const WatchdogConfig({
    required this.parentPid,
    required this.finishEventName,
    required this.paths,
    required this.lock,
  });
  final int parentPid;
  final String finishEventName;
  final SensorPaths paths;
  final SensorLock lock;
  static WatchdogConfig parse(List<String> arguments);
}
```

```dart
int runSensorWatchdog(List<String> arguments) {
  final config = WatchdogConfig.parse(arguments);
  final mutexHandle = createOwnedSensorMutex();
  if (mutexHandle == 0) return 73;
  try {
    final parentHandle = openParentForSynchronize(config.parentPid);
    if (parentHandle == 0) {
      recoverStaleManifestSync(config.paths, config.lock);
      return 74;
    }
    try {
      final finishHandle =
          openFinishEventForSynchronize(config.finishEventName);
      if (finishHandle == 0) {
        recoverStaleManifestSync(config.paths, config.lock);
        return 74;
      }
      try {
        writeWatchdogLineSync(
          jsonEncode({'watchdog': 'ready', 'pid': pid}),
        );
        final wake = waitForFinishOrParent(finishHandle, parentHandle);
        switch (wake) {
          case WatchdogWake.normalFinish:
            verifyNoRecoveryMaterialAndStockTargetSync(
              config.paths,
              config.lock,
            );
            writeWatchdogLineSync(
              jsonEncode({'watchdog': 'finished', 'pid': pid}),
            );
            return 0;
          case WatchdogWake.parentExit:
            recoverStaleManifestSync(config.paths, config.lock);
            verifyNoRecoveryMaterialAndStockTargetSync(
              config.paths,
              config.lock,
            );
            return 0;
          case WatchdogWake.failed:
            recoverStaleManifestSync(config.paths, config.lock);
            return 74;
        }
      } finally {
        closeHandle(finishHandle);
      }
    } finally {
      closeHandle(parentHandle);
    }
  } finally {
    releaseMutexChecked(mutexHandle);
    closeHandle(mutexHandle);
  }
}
```

`recoverStaleManifestSync`, target verification, and `writeWatchdogLineSync` use only synchronous file/native operations. The child performs no `await` from mutex acquisition through `ReleaseMutex`, so ownership and every recovery operation remain on the same native thread. `writeWatchdogLineSync` writes UTF-8 plus newline with checked `GetStdHandle`/`WriteFile`; readiness cannot remain buffered while `WaitForMultipleObjects` blocks.

The raw mutex wrapper checks `GetLastError` immediately after `CreateMutexW` and before any other native call:

```dart
typedef _CreateMutexWNative = IntPtr Function(
  Pointer<Void>,
  Int32,
  Pointer<Utf16>,
);
typedef _CreateMutexWDart = int Function(
  Pointer<Void>,
  int,
  Pointer<Utf16>,
);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();
typedef _WaitForMultipleObjectsNative = Uint32 Function(
  Uint32,
  Pointer<IntPtr>,
  Int32,
  Uint32,
);
typedef _WaitForMultipleObjectsDart = int Function(
  int,
  Pointer<IntPtr>,
  int,
  int,
);
typedef _ReleaseMutexNative = Int32 Function(IntPtr);
typedef _ReleaseMutexDart = int Function(int);

final sensorKernel32 = DynamicLibrary.open('kernel32.dll');
final createMutexW = sensorKernel32.lookupFunction<
    _CreateMutexWNative,
    _CreateMutexWDart>('CreateMutexW');
final getLastError = sensorKernel32.lookupFunction<
    _GetLastErrorNative,
    _GetLastErrorDart>('GetLastError');
final waitForMultipleObjects = sensorKernel32.lookupFunction<
    _WaitForMultipleObjectsNative,
    _WaitForMultipleObjectsDart>('WaitForMultipleObjects');
final releaseMutex = sensorKernel32.lookupFunction<
    _ReleaseMutexNative,
    _ReleaseMutexDart>('ReleaseMutex');

int createOwnedSensorMutex() {
  final name = NamedMutexWatchdog.mutexName.toNativeUtf16();
  try {
    final handle = createMutexW(nullptr, 1, name);
    final lastError = getLastError();
    if (handle == 0) {
      throw StateError('CreateMutexW failed with Win32 error $lastError.');
    }
    if (lastError == ERROR_ALREADY_EXISTS) {
      closeHandle(handle);
      return 0;
    }
    return handle;
  } finally {
    calloc.free(name);
  }
}

void releaseMutexChecked(int handle) {
  if (releaseMutex(handle) == 0) {
    final lastError = getLastError();
    throw StateError('ReleaseMutex failed with Win32 error $lastError.');
  }
}

WatchdogWake waitForFinishOrParent(int finishHandle, int parentHandle) {
  final handles = calloc<IntPtr>(2);
  try {
    handles[0] = finishHandle;
    handles[1] = parentHandle;
    final result = waitForMultipleObjects(2, handles, 0, INFINITE);
    if (result == WAIT_OBJECT_0) return WatchdogWake.normalFinish;
    if (result == WAIT_OBJECT_0 + 1) return WatchdogWake.parentExit;
    return WatchdogWake.failed;
  } finally {
    calloc.free(handles);
  }
}
```

`createMutexW`, `getLastError`, `waitForMultipleObjects`, and `releaseMutex` are raw `kernel32.dll` lookups; `closeHandle`, parent/event open helpers, and atomic replacement are thin checked wrappers. `waitForFinishOrParent` maps only `WAIT_OBJECT_0`, `WAIT_OBJECT_0 + 1`, and `WAIT_FAILED`; any other value maps to `WatchdogWake.failed`. `ReleaseMutex` is called while the child remains on the same native thread and before `CloseHandle`.

The parent accepts readiness only from the spawned PID. `assertAlive` checks the synchronously cached exit code. `finishNormally` is called only after the critical guard below is disarmed; it marks the parent state as finishing, signals the event, requires a JSON object containing only `watchdog: "finished"` and the exact spawned child PID, awaits exit 0, and closes the parent's event handle.

The whole backup/manifest/overlay/first-scan/restore/delete interval is one future guarded by the watchdog exit and sequential PID watcher. These are the exact injectable operations and guard types:

```dart
abstract interface class CriticalSectionOperations {
  Future<void> writeBackup();
  Future<void> publishManifest();
  Future<void> installOverlay();
  Future<void> restoreAndVerify();
  Future<void> deleteVerifiedRecoveryMaterial();
}

final class CriticalSectionFailure {
  const CriticalSectionFailure(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;

  Never rethrowFailure() => Error.throwWithStackTrace(error, stackTrace);
}

final class CriticalSectionOutcome<T> {
  const CriticalSectionOutcome({
    this.value,
    this.operationFailure,
    this.restorationFailure,
  });
  final T? value;
  final CriticalSectionFailure? operationFailure;
  final CriticalSectionFailure? restorationFailure;
}

final class CriticalSectionSafety {
  CriticalSectionSafety._({
    required this.failure,
    required Completer<CriticalSectionFailure> failureCompleter,
    required SentruxMcpClient patchedClient,
  })  : _failureCompleter = failureCompleter,
        _patchedClient = patchedClient;

  final Future<CriticalSectionFailure> failure;
  final Completer<CriticalSectionFailure> _failureCompleter;
  final SentruxMcpClient _patchedClient;
  CriticalSectionFailure? _observedFailure;
  bool _armed = true;

  CriticalSectionFailure? get observedFailure => _observedFailure;

  static CriticalSectionSafety arm({
    required SensorWatchdogHandle watchdog,
    required SentruxPidWatch pidWatch,
    required SentruxMcpClient patchedClient,
  }) {
    final completer = Completer<CriticalSectionFailure>();
    final safety = CriticalSectionSafety._(
      failure: completer.future,
      failureCompleter: completer,
      patchedClient: patchedClient,
    );
    unawaited(watchdog.exitCode.then<void>(
      (code) => safety._trip(
        StateError('Sensor watchdog exited unexpectedly with code $code.'),
        StackTrace.current,
      ),
      onError: (Object error, StackTrace stackTrace) =>
          safety._trip(error, stackTrace),
    ));
    unawaited(pidWatch.violation.then<void>(
      (_) => safety._trip(
        StateError('A foreign sentrux.exe PID entered the critical section.'),
        StackTrace.current,
      ),
      onError: (Object error, StackTrace stackTrace) =>
          safety._trip(error, stackTrace),
    ));
    return safety;
  }

  void _trip(Object error, StackTrace stackTrace) {
    if (!_armed || _failureCompleter.isCompleted) return;
    final failure = CriticalSectionFailure(error, stackTrace);
    _observedFailure = failure;
    _patchedClient.abort();
    _failureCompleter.complete(failure);
  }

  void throwIfTripped() => _observedFailure?.rethrowFailure();

  void disarm() => _armed = false;
}

Future<CriticalSectionOutcome<ScanObservation>> _runCriticalSection({
  required CriticalSectionOperations operations,
  required SentruxMcpClient patchedClient,
  required Directory directFixture,
  required CriticalSectionSafety safety,
}) async {
  ScanObservation? value;
  CriticalSectionFailure? operationFailure;
  CriticalSectionFailure? restorationFailure;
  try {
    safety.throwIfTripped();
    await operations.writeBackup();
    safety.throwIfTripped();
    await operations.publishManifest();
    safety.throwIfTripped();
    await operations.installOverlay();
    safety.throwIfTripped();
    value = await patchedClient.scan(directFixture);
    safety.throwIfTripped();
  } on Object catch (error, stackTrace) {
    operationFailure = CriticalSectionFailure(error, stackTrace);
  }
  try {
    await operations.restoreAndVerify();
    await operations.deleteVerifiedRecoveryMaterial();
  } on Object catch (error, stackTrace) {
    restorationFailure = CriticalSectionFailure(error, stackTrace);
  }
  return CriticalSectionOutcome<ScanObservation>(
    value: value,
    operationFailure: operationFailure,
    restorationFailure: restorationFailure,
  );
}

Future<ScanObservation> runCriticalSectionSafely({
  required CriticalSectionOperations operations,
  required SentruxMcpClient patchedClient,
  required Directory directFixture,
  required SensorWatchdogHandle watchdog,
  required SentruxPidWatch pidWatch,
}) async {
  watchdog.assertAlive();
  final safety = CriticalSectionSafety.arm(
    watchdog: watchdog,
    pidWatch: pidWatch,
    patchedClient: patchedClient,
  );
  try {
    await Future<void>.delayed(Duration.zero);
    safety.throwIfTripped();
    final section = _runCriticalSection(
      operations: operations,
      patchedClient: patchedClient,
      directFixture: directFixture,
      safety: safety,
    );
    final first = await Future.any<Object>([section, safety.failure]);
    final CriticalSectionOutcome<ScanObservation> outcome;
    CriticalSectionFailure? safetyFailure;
    if (first is CriticalSectionFailure) {
      safetyFailure = first;
      outcome = await section;
    } else {
      outcome = first as CriticalSectionOutcome<ScanObservation>;
      await Future<void>.delayed(Duration.zero);
      try {
        watchdog.assertAlive();
      } on Object catch (error, stackTrace) {
        safetyFailure = CriticalSectionFailure(error, stackTrace);
      }
      safetyFailure ??= safety.observedFailure;
    }
    outcome.restorationFailure?.rethrowFailure();
    safetyFailure?.rethrowFailure();
    outcome.operationFailure?.rethrowFailure();
    return outcome.value!;
  } finally {
    safety.disarm();
    await pidWatch.stop();
  }
}
```

`SentruxMcpClient.abort` is synchronous, idempotent, no-throw, and terminates only its injected transport PID. `SentruxPidWatch.stop` is idempotent and no-throw. `throwIfTripped` runs before and after every forward operation, so a trip during a blocked backup or manifest publish prevents every later forward mutation. Cleanup deliberately ignores the trip: `restoreAndVerify` is safe before or after manifest publication, and deletion runs only after stock bytes are proven. If a safety signal wins, the runner awaits the non-throwing outcome so restore/delete finish, gives a restoration failure priority, then rejects on the safety failure. The initial and final zero-delay turns close already-completed/simultaneous signal windows. The guard is disarmed before `finishNormally`, so the acknowledged normal child exit cannot abort later scans.

## Exact Fixture Templates

`tool/sentrux/dart/fixtures/pubspec.yaml.fixture`:

```yaml
name: sentrux_dart_sensor_fixture
publish_to: none
environment:
  sdk: '>=3.11.1 <4.0.0'
```

`tool/sentrux/dart/fixtures/lib/main.dart.fixture`:

```dart
import 'probe.dart';

void main() {
// sentrux-fixture:direct
  directProbe();
// sentrux-fixture-end
// sentrux-fixture:generic
  genericProbe<int>();
// sentrux-fixture-end
// sentrux-fixture:instance
  probe.instanceProbe();
// sentrux-fixture-end
// sentrux-fixture:static
  Probe.staticProbe();
// sentrux-fixture-end
// sentrux-fixture:chained
  probe.chain.chainedProbe();
// sentrux-fixture-end
// sentrux-fixture:null_aware
  nullableProbe?.nullAwareProbe();
// sentrux-fixture-end
// sentrux-fixture:cascade_first
  probe..cascadeProbe();
// sentrux-fixture-end
// sentrux-fixture:cascade_later
  probe..cascadeField.laterCascadeProbe();
// sentrux-fixture-end
// sentrux-fixture:new_constructor
  new ExplicitProbe();
// sentrux-fixture-end
// sentrux-fixture:const_constructor
  const ConstProbe();
// sentrux-fixture-end
// sentrux-fixture:tear_off
  final tearOff = directProbe;
// sentrux-fixture-end
// sentrux-fixture:property_access
  probe.instanceProbe;
// sentrux-fixture-end
// sentrux-fixture:indexed_invocation
  callbacks[0]();
// sentrux-fixture-end
// sentrux-fixture:null_asserted_invocation
  nullableCallback!();
// sentrux-fixture-end
// sentrux-fixture:operator
  probe + probe;
// sentrux-fixture-end
// sentrux-fixture:dot_shorthand
  const ConstProbe shorthand = .new();
// sentrux-fixture-end
// sentrux-fixture:dead_attribution
  liveAlpha();
  liveBeta();
// sentrux-fixture-end
// sentrux-fixture:dead_private
  // The dead probe is declared only in probe.dart.
// sentrux-fixture-end
// sentrux-fixture:duplicate_signature
  // Duplicate build signatures are declared only in probe.dart.
// sentrux-fixture-end
}
```

`tool/sentrux/dart/fixtures/lib/probe.dart.fixture`:

```dart
// sentrux-fixture:direct
void directProbe() {}
// sentrux-fixture-end

// sentrux-fixture:generic
void genericProbe<T>() {}
// sentrux-fixture-end

// sentrux-fixture:instance
late Probe probe;
class Probe {
  void instanceProbe() {}
}
// sentrux-fixture-end

// sentrux-fixture:static
class Probe {
  static void staticProbe() {}
}
// sentrux-fixture-end

// sentrux-fixture:chained
late Probe probe;
class Probe {
  late ChainProbe chain;
}
class ChainProbe {
  void chainedProbe() {}
}
// sentrux-fixture-end

// sentrux-fixture:null_aware
late Probe? nullableProbe;
class Probe {
  void nullAwareProbe() {}
}
// sentrux-fixture-end

// sentrux-fixture:cascade_first
late Probe probe;
class Probe {
  void cascadeProbe() {}
}
// sentrux-fixture-end

// sentrux-fixture:cascade_later
late Probe probe;
class Probe {
  late CascadeProbe cascadeField;
}
class CascadeProbe {
  void laterCascadeProbe() {}
}
// sentrux-fixture-end

// sentrux-fixture:new_constructor
class ExplicitProbe {
  ExplicitProbe();
}
// sentrux-fixture-end

// sentrux-fixture:const_constructor
class ConstProbe {
  const ConstProbe();
}
// sentrux-fixture-end

// sentrux-fixture:tear_off
void directProbe() {}
// sentrux-fixture-end

// sentrux-fixture:property_access
late Probe probe;
class Probe {
  void instanceProbe() {}
}
// sentrux-fixture-end

// sentrux-fixture:indexed_invocation
late List<void Function()> callbacks;
// sentrux-fixture-end

// sentrux-fixture:null_asserted_invocation
late void Function()? nullableCallback;
// sentrux-fixture-end

// sentrux-fixture:operator
late Probe probe;
class Probe {
  Probe operator +(Probe other) => this;
}
// sentrux-fixture-end

// sentrux-fixture:dot_shorthand
class ConstProbe {
  const ConstProbe();
}
// sentrux-fixture-end

// sentrux-fixture:dead_attribution
void liveAlpha() {}
void liveBeta() {}
// sentrux-fixture-end

// sentrux-fixture:dead_private
void _deadProbe() {}
// sentrux-fixture-end

// sentrux-fixture:duplicate_signature
class BuildContext {
  const BuildContext(this.seed);
  final int seed;
}
class FirstBuilder {
  int build(BuildContext context) => context.seed;
}
class SecondBuilder {
  int build(BuildContext context) {
    return context.seed + 1;
  }
}
// sentrux-fixture-end
```

## Fixture Acceptance Matrix

| ID | Enabled marker blocks | Expected M1−M0 call delta | Classification |
|---|---|---:|---|
| `direct` | `direct` | `+1` | supported |
| `generic` | `generic` | `+1` | supported |
| `instance` | `instance` | `+1` | supported |
| `static` | `static` | `+1` | supported |
| `chained` | `chained` | `+1` | supported |
| `null_aware` | `null_aware` | `+1` | supported |
| `cascade_first` | `cascade_first` | `+1` | supported |
| `cascade_later` | `cascade_later` | `+1` | supported |
| `new_constructor` | `new_constructor` | `0` | stock behavior retained |
| `const_constructor` | `const_constructor` | `+1` | supported |
| `tear_off` | `tear_off` | `0` | negative |
| `property_access` | `property_access` | `0` | negative |
| `indexed_invocation` | `indexed_invocation` | `0` | limitation |
| `null_asserted_invocation` | `null_asserted_invocation` | `0` | limitation |
| `operator` | `operator` | `0` | limitation |
| `dot_shorthand` | `dot_shorthand` | `0` | limitation |
| `all_live` | `dead_attribution` | `+2` | controlled live functions |
| `with_dead` | `dead_attribution`, `dead_private` | `+2` | redundancy probe |
| `duplicate_signature` | `duplicate_signature` | `0` | equality invalid/signature-only |

The CLI report must also list annotations, reflection, parenthesized-result invocation such as `(factory())()`, callback invocation such as `handlers[key]()`, and `Type.named()` ambiguity as unmeasured limitations.

---

### Task 1: Freeze lock parsing, query, and fixture materialization

**Files:** Create `tool/sentrux/dart/**`, the initial parser in `tool/src/sentrux_dart_sensor.dart`, and `test/architecture/sentrux_dart_sensor_test.dart`.

**Produces:** strict `SensorLock.fromJson`, `materializeFixtureTemplate`, and the exact fixture matrix.

- [ ] **Step 1: Add the RED seven-artifact test (4 minutes).**

```dart
test('lock pins the exact seven Sentrux 0.5.7 artifacts', () {
  final json = jsonDecode(
    File('tool/sentrux/dart/sensor-lock.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final lock = SensorLock.fromJson(json);
  expect(lock.sentruxVersion, '0.5.7');
  expect(lock.mcpProtocolVersion, '2024-11-05');
  expect(lock.artifacts, hasLength(7));
  expect(
    lock.artifacts.map((artifact) => artifact.sha256),
    everyElement(matches(RegExp(r'^[0-9A-F]{64}$'))),
  );
});
```

- [ ] **Step 2: Add RED materializer failure cases (5 minutes).**

Add these compile-ready cases:

```dart
test('fixture materializer keeps exactly one selected block', () {
  const source = '''head
// sentrux-fixture:first
first
// sentrux-fixture-end
// sentrux-fixture:second
second
// sentrux-fixture-end
tail
''';
  expect(
    materializeFixtureTemplate(source, {'second'}),
    'head\nsecond\ntail\n',
  );
});

test('fixture materializer rejects every malformed marker shape', () {
  final cases = <String, ({String source, Set<String> selected})>{
    'nested': (
      source: '// sentrux-fixture:a\n'
          '// sentrux-fixture:b\nb\n'
          '// sentrux-fixture-end\n'
          '// sentrux-fixture-end\n',
      selected: {'a'},
    ),
    'duplicate open': (
      source: '// sentrux-fixture:a\na\n'
          '// sentrux-fixture-end\n'
          '// sentrux-fixture:a\na2\n'
          '// sentrux-fixture-end\n',
      selected: {'a'},
    ),
    'missing end': (
      source: '// sentrux-fixture:a\na\n',
      selected: {'a'},
    ),
    'empty': (
      source: '// sentrux-fixture:a\n// sentrux-fixture-end\n',
      selected: {'a'},
    ),
    'unknown selection': (
      source: '// sentrux-fixture:a\na\n// sentrux-fixture-end\n',
      selected: {'missing'},
    ),
  };
  for (final entry in cases.entries) {
    expect(
      () => materializeFixtureTemplate(
        entry.value.source,
        entry.value.selected,
      ),
      throwsFormatException,
      reason: entry.key,
    );
  }
});
```

- [ ] **Step 3: Run the two RED tests (2 minutes).**

```powershell
flutter test test/architecture/sentrux_dart_sensor_test.dart --plain-name "lock pins the exact seven Sentrux 0.5.7 artifacts"
flutter test test/architecture/sentrux_dart_sensor_test.dart --plain-name "fixture materializer"
```

Expected: compilation/file failures because the implementation and fixtures do not exist.

- [ ] **Step 4: Create the exact lock and staged query (5 minutes).**

Copy the frozen JSON and Scheme blocks above. Retain the stock definition/import/type captures from the installed query unchanged around the replacement call section.

- [ ] **Step 5: Create the three marked fixture templates (5 minutes).**

Copy the three complete templates in Exact Fixture Templates byte-for-byte. `pubspec.yaml.fixture` remains exactly:

```yaml
name: sentrux_dart_sensor_fixture
publish_to: none
environment:
  sdk: '>=3.11.1 <4.0.0'
```

- [ ] **Step 6: Implement strict lock and marker parsing (5 minutes).**

Reject extra/missing keys, non-absolute paths, duplicate IDs/paths, lowercase or malformed hashes, an artifact count other than seven, and any frozen constant mismatch.

- [ ] **Step 7: Run GREEN parser tests (3 minutes).**

```powershell
flutter test test/architecture/sentrux_dart_sensor_test.dart --plain-name "lock pins the exact seven Sentrux 0.5.7 artifacts"
flutter test test/architecture/sentrux_dart_sensor_test.dart --plain-name "fixture materializer"
```

### Task 2: Implement the version-locked MCP observer

**Files:** Modify `tool/src/sentrux_dart_sensor.dart` and its architecture test.

**Produces:** `SentruxMcpClient`, strict JSON-RPC parsing, `HealthSnapshot`, and one call-edge observation per scan.

- [ ] **Step 1: Add RED diagnostic parser tests (4 minutes).**

```dart
test('parses the exact Sentrux 0.5.7 call-edge diagnostic', () {
  expect(parseBuildGraphCallEdges(const [
    '[build_graphs] 2682 files | maps 2.9ms, imports 184.1ms, '
        'calls+inherit 16.6ms, total 203.6ms | '
        '5599 import, 10476 call, 107 inherit edges',
  ]), 10476);
});

test('missing or duplicate build_graphs diagnostics fail closed', () {
  expect(() => parseBuildGraphCallEdges(const []), throwsFormatException);
  expect(
    () => parseBuildGraphCallEdges(const [
      '[build_graphs] 1 files | maps 1ms, imports 1ms, '
          'calls+inherit 1ms, total 1ms | 0 import, 1 call, 0 inherit edges',
      '[build_graphs] 1 files | maps 1ms, imports 1ms, '
          'calls+inherit 1ms, total 1ms | 0 import, 1 call, 0 inherit edges',
    ]),
    throwsFormatException,
  );
});
```

- [ ] **Step 2: Run RED diagnostic tests (2 minutes).**

```powershell
flutter test test/architecture/sentrux_dart_sensor_test.dart --plain-name "call-edge diagnostic"
flutter test test/architecture/sentrux_dart_sensor_test.dart --plain-name "diagnostics fail closed"
```

- [ ] **Step 3: Implement the anchored parser (4 minutes).**

```dart
final buildGraphsDiagnostic = RegExp(
  r'^\[build_graphs\] ([1-9][0-9]*) files \| '
  r'maps [0-9]+(?:\.[0-9]+)?ms, '
  r'imports [0-9]+(?:\.[0-9]+)?ms, '
  r'calls\+inherit [0-9]+(?:\.[0-9]+)?ms, '
  r'total [0-9]+(?:\.[0-9]+)?ms \| '
  r'([0-9]+) import, ([0-9]+) call, ([0-9]+) inherit edges$',
);
```

Feed every stderr line into `DiagnosticInbox`. `takeOne` accepts only the anchored pattern, `requireQuiet` rejects a second match, and `requireEmpty` rejects stale diagnostics before the next scan. Return capture group 3 only after the complete per-scan protocol in the Exact MCP Transaction Boundary succeeds.

- [ ] **Step 4: Create the test-only scripted MCP transport (5 minutes).**

Implement `ScriptedMcpTransport` as the exact `SensorMcpTransport` test double described above. It records `requestedToolNames`, exposes `waitForToolRequest`, completes one pending tool with one text JSON object, and can emit stderr before or after a response.

- [ ] **Step 5: Add RED initialize, split-tool, and pipe-order tests (5 minutes).**

Paste the exact split `scan`/`health` test above. Add protocol mismatch, `serverInfo.version` mismatch, malformed JSON, wrong response ID, missing text content, timeout, duplicate diagnostic, diagnostic-after-response, stale diagnostic, and unexpected process exit cases.

- [ ] **Step 6: Implement the line JSON transport and request router (5 minutes).**

Create `LineJsonMcpTransport`; continuously drain stdout/stderr, allocate IDs, route responses by exact ID, reject duplicate/unknown IDs, and abort only the process it launched. Do not parse health in the transport.

- [ ] **Step 7: Implement version-locked initialization (4 minutes).**

Send:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"magicmusiccrm-sentrux-dart-sensor","version":"1"}}}
```

Then send `notifications/initialized`. Require response protocol `2024-11-05` and `serverInfo.version == "0.5.7"` before exposing the client.

- [ ] **Step 8: Implement separate scan and health calls (5 minutes).**

Implement the exact `scan` and `_callToolTextJson` bodies above. `HealthSnapshot.fromMcpContent` requires and preserves `quality_signal`, `total_import_edges`, `cross_module_edges`, and the full `root_causes` object in `raw`; it extracts equality/redundancy without dropping other fields.

- [ ] **Step 9: Run the complete MCP unit group GREEN (4 minutes).**

```powershell
flutter test test/architecture/sentrux_dart_sensor_test.dart --plain-name "SentruxMcpClient"
flutter test test/architecture/sentrux_dart_sensor_test.dart --plain-name "build_graphs"
```

### Task 3: Implement durable recovery and process exclusion

**Files:** Modify `tool/src/sentrux_dart_sensor.dart`, create `tool/calibrate_sentrux_dart.dart`, and extend the test.

**Produces:** validatable recovery manifest, write-through atomic replacement, watchdog-owned mutex, and fail-closed PID watcher.

- [ ] **Step 1: Add RED stale-recovery tests (5 minutes).**

Test valid staged bytes restoring from a pinned-hash backup, malformed manifest preserving every byte, wrong backup hash preserving every file, stock target cleaning a valid stale manifest, stock target cleaning a verified orphan backup, and every non-stock orphan combination failing closed without deletion.

The central RED case is:

```dart
test('stale staged query restores from a verified durable manifest', () async {
  final setup = await RecoveryTestSetup.create(
    targetBytes: const [2],
    backupBytes: const [1],
  );
  addTearDown(setup.dispose);
  setup.writeManifest(
    originalSha256: sha256.convert([1]).toString().toUpperCase(),
    stagedSha256: sha256.convert([2]).toString().toUpperCase(),
  );

  await recoverStaleManifest(setup.paths, setup.lock);

  expect(setup.target.readAsBytesSync(), [1]);
  expect(setup.paths.manifestFile.existsSync(), isFalse);
  expect(setup.paths.backupFile.existsSync(), isFalse);
});
```

`RecoveryTestSetup` is created in this step with temporary literal target/backup paths, an injected matching `SensorLock`, `writeManifest`, and idempotent recursive disposal.

- [ ] **Step 2: Run the recovery group RED (2 minutes).**

```powershell
flutter test test/architecture/sentrux_dart_sensor_test.dart --plain-name "recovery"
```

- [ ] **Step 3: Implement `RecoveryManifest` validation (5 minutes).**

Persist `manifest.json` and `stock-tags.scm.bin` beneath the frozen recovery root. Require schema 1, Sentrux 0.5.7, the literal mutex, literal target/backup paths, stock hash, staged hash, positive owner PID, and UTC timestamp.

- [ ] **Step 4: Implement durable atomic replacement (5 minutes).**

Flush backup bytes, write and flush `manifest.json.tmp`, then publish with `MoveFileExW(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)`. For overlay and restore, write a flushed temporary file beside the installed target and atomically replace the target; never move the tracked staged query or the only recovery backup. A backup without a manifest is deleted only when the target and backup both verify as stock; every other orphan combination is preserved and fails closed.

- [ ] **Step 5: Add RED watchdog/mutex/liveness tests (5 minutes).**

Cover lock conflict, parent death restoration, normal completion acknowledgement, a second watchdog acquiring after the first exits, normal completion refusing while recovery material remains, child exit while backup is blocked, child exit after overlay, and child exit while restoration is blocked:

```dart
test('safety trip during backup prevents manifest overlay and scan', () async {
  final harness = await FakeCalibrationHarness.create(
    blockBackupUntilReleased: true,
  );
  addTearDown(harness.dispose);
  final run = harness.runner.run(includeFullRepository: false);
  await harness.waitForEvent('backup-started');

  harness.watchdogProcess.completeExit(90);
  await harness.waitForEvent('patched-process-aborted');
  harness.releaseBackup();

  await expectLater(run, throwsStateError);
  expect(harness.events, isNot(contains('manifest')));
  expect(harness.events, isNot(contains('overlay')));
  expect(harness.patchedScanCalls, 0);
  expect(harness.target.readAsBytesSync(), harness.stockBytes);
  expect(harness.paths.manifestFile.existsSync(), isFalse);
  expect(harness.paths.backupFile.existsSync(), isFalse);
});

test('watchdog death after ready restores and rejects the run', () async {
  final harness = await FakeCalibrationHarness.create();
  addTearDown(harness.dispose);
  final run = harness.runner.run(includeFullRepository: false);
  await harness.waitForEvent('overlay');

  harness.watchdogProcess.completeExit(91);

  await expectLater(run, throwsStateError);
  expect(harness.target.readAsBytesSync(), harness.stockBytes);
  expect(harness.paths.manifestFile.existsSync(), isFalse);
  expect(harness.paths.backupFile.existsSync(), isFalse);
  expect(harness.patchedProcess.killed, isTrue);
});

test('watchdog death during restore still restores before rejection', () async {
  final harness = await FakeCalibrationHarness.create(
    blockRestoreUntilReleased: true,
  );
  addTearDown(harness.dispose);
  final run = harness.runner.run(includeFullRepository: false);
  await harness.waitForEvent('restore-started');

  harness.watchdogProcess.completeExit(92);
  await harness.waitForEvent('patched-process-aborted');
  harness.releaseRestore();

  await expectLater(run, throwsStateError);
  expect(harness.target.readAsBytesSync(), harness.stockBytes);
  expect(harness.paths.manifestFile.existsSync(), isFalse);
  expect(harness.paths.backupFile.existsSync(), isFalse);
  expect(harness.patchedProcess.killed, isTrue);
});
```

- [ ] **Step 6: Implement checked native handle wrappers (5 minutes).**

Implement raw FFI for `CreateMutexW`, `GetLastError`, `WaitForMultipleObjects`, and `ReleaseMutex`; wrap `OpenProcess`, `OpenEventW`, `CreateEventW`, `SetEvent`, `CloseHandle`, `WriteFile`, and `MoveFileExW` with zero/`WAIT_FAILED` checks. Add the immediate `ERROR_ALREADY_EXISTS` branch and checked same-thread release shown above.

- [ ] **Step 7: Implement the child wait branches (5 minutes).**

Implement the exact `runSensorWatchdog` body above. Readiness is emitted only after the event, parent handle, and owned mutex are valid. Parent/event open failure attempts verified stale recovery before exit; normal finish acknowledges only stock/no-recovery state; parent death restores and verifies.

- [ ] **Step 8: Implement the parent watchdog handle (5 minutes).**

Generate the unique event, spawn the current Dart executable/CLI with named private arguments, require the ready PID, expose the single cached `exitCode` future and `assertAlive`, and require finished acknowledgement plus exit 0 in `finishNormally`. Do not create an always-failing exit wrapper; `CriticalSectionSafety` owns the scoped interpretation of exit.

- [ ] **Step 9: Add RED PID parsing and watcher tests (4 minutes).**

Parse only rows matching `^"sentrux\.exe","([0-9]+)",` from:

```dart
Process.run(
  'tasklist.exe',
  const ['/FI', 'IMAGENAME eq sentrux.exe', '/FO', 'CSV', '/NH'],
  runInShell: false,
);
```

Any nonzero exit or quoted nonmatching row fails closed. Test the concrete sequential watcher with deterministic readers:

```dart
test('Sentrux PID watch rejects a later foreign PID and stops', () async {
  final snapshots = <Set<int>>[
    {41},
    {41, 99},
  ];
  Future<Set<int>> readPids() async => snapshots.removeAt(0);
  final watch = await SequentialSentruxPidWatch.start(
    ownedPid: 41,
    readPids: readPids,
    interval: Duration.zero,
  );

  await expectLater(watch.violation, throwsStateError);
  await watch.stop();
  expect(snapshots, isEmpty);
});

test('Sentrux PID watch rejects a foreign PID before mutation', () async {
  await expectLater(
    SequentialSentruxPidWatch.start(
      ownedPid: 41,
      readPids: () async => {41, 99},
      interval: const Duration(milliseconds: 100),
    ),
    throwsStateError,
  );
});
```

- [ ] **Step 10: Implement the 100 ms sequential PID watcher (4 minutes).**

Before mutation require an empty PID set. After the patched client starts, allow only its PID. Implement `SentruxPidWatchStarter` as one sequential 100 ms polling loop whose `violation` completes on any read failure or unexpected PID, and whose idempotent `stop` waits for the active read before returning. The exact scoped guard below races it through backup, manifest, overlay, cache-priming scan, restore, verification, and recovery-file deletion.

- [ ] **Step 11: Run recovery/watchdog/process groups GREEN (5 minutes).**

```powershell
flutter test test/architecture/sentrux_dart_sensor_test.dart --plain-name "recovery"
flutter test test/architecture/sentrux_dart_sensor_test.dart --plain-name "watchdog"
flutter test test/architecture/sentrux_dart_sensor_test.dart --plain-name "Sentrux PID"
```

### Task 4: Orchestrate stock and staged fixture scans

**Files:** Modify the sensor library, CLI, and architecture test.

**Produces:** `--fixture-only`, `--full-repo .`, JSON evidence, exact fixture predicates, and immediate installed-query restoration.

- [ ] **Step 1: Add RED lifecycle-order test (5 minutes).**

Require this exact event order from injected fakes:

```text
watchdog-ready -> recover-stale -> validate-seven -> materialize-fixtures
-> validate-staged-plugin -> stock-start -> stock-scans -> stock-stop
-> validate-seven -> patched-start -> patched-synchronized -> watcher-start
-> critical-safety-armed -> backup -> manifest -> overlay
-> first-patched-scan -> restore
-> verify-stock-query -> delete-recovery -> critical-safety-disarm -> watcher-stop
-> remaining-patched-scans -> optional-full-repository-scan
-> patched-stop -> validate-seven -> watchdog-finish
```

- [ ] **Step 2: Run the lifecycle test RED (2 minutes).**

```powershell
flutter test test/architecture/sentrux_dart_sensor_test.dart --plain-name "restores immediately after the first patched scan"
```

- [ ] **Step 3: Implement fixture materialization and plugin validation (5 minutes).**

Create one temporary package per matrix row. Copy the installed Dart plugin to a separate temporary directory, replace only its query, and execute:

```dart
final validation = await Process.run(
  paths.sentruxExecutable.path,
  ['plugin', 'validate', temporaryPlugin.absolute.path],
  runInShell: false,
);
if (validation.exitCode != 0) {
  throw StateError(
    'Staged Dart plugin validation failed: ${validation.stderr}',
  );
}
```

Verify all seven installed hashes again; the temporary plugin is the only validation target.

- [ ] **Step 4: Implement stock scans in one fresh MCP process (5 minutes).**

Initialize stock Sentrux once, scan every isolated fixture, pair each call count with health, then close the process and verify all seven hashes again.

- [ ] **Step 5: Implement the patched cache-priming critical section (5 minutes).**

Start a second MCP process and wait for initialize so startup sync is complete. Start the sequential PID watch, then call the exact `runCriticalSectionSafely` helper from the watchdog contract. It arms both safety inputs before `operations.writeBackup`, publishes backup then manifest then staged query, scans `direct` once to cache the staged query, and keeps the guard armed until stock verification and recovery-file deletion finish. Only `patchedClient.abort()` may terminate a process, and it owns exactly the injected patched MCP PID.

```dart
final pidWatch = await startPidWatch(
  ownedPid: patchedClient.pid,
  readPids: readSentruxPids,
  interval: const Duration(milliseconds: 100),
);
firstPatchedObservation = await runCriticalSectionSafely(
  operations: FileCriticalSectionOperations(paths: paths, lock: lock),
  patchedClient: patchedClient,
  directFixture: directFixture,
  watchdog: watchdog,
  pidWatch: pidWatch,
);
```

`FileCriticalSectionOperations` implements the five exact injectable methods above using durable atomic replacement. The helper captures operation errors instead of throwing before restoration, waits for the full outcome after either safety signal, preserves the original operation error when restoration succeeds, and replaces it with the restoration error when stock bytes cannot be proven.

- [ ] **Step 6: Implement remaining scans and derived failure classification (5 minutes).**

Require every matrix delta exactly and `with_dead.redundancy.raw > all_live.redundancy.raw`. Derive, rather than hardcode, the known duplicate-signature classification:

```dart
String classifyDuplicateSignatureFailure({
  required ScanObservation stock,
  required ScanObservation staged,
  required List<int> firstBodyBytes,
  required List<int> secondBodyBytes,
  required bool definitionCapturesUnchanged,
}) {
  if (!definitionCapturesUnchanged) {
    throw StateError('M1 changed Dart definition captures.');
  }
  if (
    sha256.convert(firstBodyBytes).toString() ==
    sha256.convert(secondBodyBytes).toString()
  ) {
    throw StateError('Duplicate-signature fixture bodies are not distinct.');
  }
  if (
    staged.health.equality.raw != stock.health.equality.raw ||
    staged.health.equality.score != stock.health.equality.score
  ) {
    throw StateError('M1 unexpectedly changed signature-only equality.');
  }
  return 'invalid_signature_only';
}
```

`definitionCapturesUnchanged` is true only when the staged definition/import/type Scheme blocks byte-normalize to the pinned stock blocks and the staged edit is confined to the call block. Do not convert this result into a root quality gate.

- [ ] **Step 7: Implement CLI argument and evidence output (4 minutes).**

Accept only `--fixture-only`, `--full-repo` followed by one path token, or the named private watchdog arguments. Resolve the full-repository path against the current directory and require an existing directory. Emit one JSON object to stdout; diagnostics and failures go to stderr with nonzero exit.

- [ ] **Step 8: Run all fake-backed tests GREEN (5 minutes).**

```powershell
flutter test test/architecture/sentrux_dart_sensor_test.dart
dart analyze tool
```

### Task 5: Run live Lane A acceptance and commit

**Files:** No new paths. Amend only the eight owned paths when a live test exposes a defect.

**Produces:** one accepted or omitted Lane A and one cherry-pickable commit when accepted.

- [ ] **Step 1: Run one recovery-aware fixture invocation (5 minutes).**

```powershell
$recoveryRoot = "C:\Users\Alinka\AppData\Local\MagicMusicCRM\sentrux-dart-sensor-recovery"
$manifestPath = Join-Path $recoveryRoot 'manifest.json'
$backupPath = Join-Path $recoveryRoot 'stock-tags.scm.bin'
$fixtureEvidenceJson = & dart run tool/calibrate_sentrux_dart.dart --fixture-only
$fixtureExit = $LASTEXITCODE
$queryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (
  'C:\Users\Alinka\.sentrux\plugins\dart\queries\tags.scm'
)).Hash
$unsafeRecoveryState =
  (Test-Path -LiteralPath $manifestPath) -or
  (Test-Path -LiteralPath $backupPath) -or
  $queryHash -ne '3B70536E2303745FE31220DE09972F489E77543283EC95C95BCD01F62661FDDD'
if ($unsafeRecoveryState) {
  throw 'Lane A blocked: preserve unresolved recovery material and installed bytes'
}
if ($fixtureExit -ne 0) {
  Write-Output 'Lane A OMIT: the single recovery-aware live invocation failed safely'
  return
}
$fixtureEvidence = $fixtureEvidenceJson | ConvertFrom-Json
```

This is the first and only external preflight invocation: argument validation loads the frozen lock, starts the watchdog so it owns the mutex, performs validated stale-manifest or verified orphan-backup recovery inside that same invocation, validates all seven hashes, and only then runs its internal process preflight. A safe nonzero result omits Lane A; unresolved recovery bytes block it. Never kill a process.

- [ ] **Step 2: Validate captured fixture evidence (2 minutes).**

```powershell
$fixtureEvidence.stock.PSObject.Properties.Count
$fixtureEvidence.staged.PSObject.Properties.Count
$fixtureEvidence.duplicate_signature_classification
$fixtureEvidence.recovery_material_present
$fixtureEvidence.unrelated_sentrux_observed
$fixtureEvidence.watchdog_exited_normally
```

Expected: all matrix deltas exact, seven final hashes exact, `duplicate_signature_classification` is derived as `invalid_signature_only`, `recovery_material_present` is false, `unrelated_sentrux_observed` is false, and `watchdog_exited_normally` is true.

- [ ] **Step 3: Run the full-repository diagnostic (5 minutes).**

```powershell
dart run tool/calibrate_sentrux_dart.dart --full-repo .
```

Expected: an M1 diagnostic is emitted with no root-quality threshold. If a new foreign process appears, the runner restores and rejects the run.

- [ ] **Step 4: Verify immutable paths and external restoration (4 minutes).**

```powershell
$laneBase = (git merge-base HEAD main).Trim()
git diff --exit-code $laneBase -- lib server/src .sentrux/rules.toml .sentrux/baseline.json pubspec.yaml pubspec.lock
if (
  (Test-Path -LiteralPath "C:\Users\Alinka\AppData\Local\MagicMusicCRM\sentrux-dart-sensor-recovery\manifest.json") -or
  (Test-Path -LiteralPath "C:\Users\Alinka\AppData\Local\MagicMusicCRM\sentrux-dart-sensor-recovery\stock-tags.scm.bin")
) {
  throw "Recovery material remains"
}
$dartQueryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath "C:\Users\Alinka\.sentrux\plugins\dart\queries\tags.scm").Hash
if ($dartQueryHash -ne "3B70536E2303745FE31220DE09972F489E77543283EC95C95BCD01F62661FDDD") {
  throw "Installed Dart query was not restored"
}
$createdMutex = $false
$mutexProbe = [System.Threading.Mutex]::new(
  $true,
  'Local\MagicMusicCRM.SentruxDartSensor.v0_5_7',
  [ref]$createdMutex
)
try {
  if (-not $createdMutex) { throw 'Sensor mutex remains owned' }
  $mutexProbe.ReleaseMutex()
} finally {
  $mutexProbe.Dispose()
}
```

- [ ] **Step 5: Run final local gates (5 minutes).**

```powershell
flutter test test/architecture/sentrux_dart_sensor_test.dart
dart analyze tool
git diff --check
git status --short
```

Expected: tests and analyzer pass; status lists only the eight Lane A paths.

- [ ] **Step 6: Commit the accepted lane (3 minutes).**

```powershell
git add -- tool/sentrux/dart tool/src/sentrux_dart_sensor.dart tool/calibrate_sentrux_dart.dart test/architecture/sentrux_dart_sensor_test.dart
git diff --cached --check
git commit -m "test(architecture): calibrate Dart Sentrux calls"
```

Expected: one focused commit and a clean Lane A worktree.

## Coordinator Acceptance

- [ ] **Step 1: Re-run fixture-only calibration after cherry-pick (5 minutes).**

The coordinator must first confirm no unrelated Sentrux process and no concurrent stock scan. If the precondition cannot be met, omit Lane A from integration even if its fake-backed tests pass.

- [ ] **Step 2: Verify seven hashes and recovery absence again (3 minutes).**

Read every path from `sensor-lock.json`, recompute SHA-256, require exact equality, require both `manifest.json` and `stock-tags.scm.bin` absent, and acquire/release a probe of `Local\MagicMusicCRM.SentruxDartSensor.v0_5_7` with `createdNew == true`.

- [ ] **Step 3: Run repository scope and rule checks (4 minutes).**

```powershell
git diff --check
sentrux check .
git status --short --branch
```

Expected: Sentrux rules 2/2 pass and no production path changed by Lane A. Do not run the legacy baseline gate and do not claim a Dart health-score improvement.

## Rollback

Before reverting Lane A, require the installed Dart query hash to be the frozen stock hash, both recovery files to be absent, and the named mutex probe to succeed. Then revert the exact `$integratedLaneA` captured by orchestration; it removes only the eight owned paths. If a valid manifest exists, run the CLI so startup recovery executes before its foreign-process preflight. If manifest or backup validation fails, preserve both files and restore only from bytes matching the frozen stock SHA-256.
