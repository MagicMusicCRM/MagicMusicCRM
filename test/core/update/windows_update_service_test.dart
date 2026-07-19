import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/update/windows_update_coordinator.dart';
import 'package:magic_music_crm/core/update/windows_update_service.dart';

const _validSha =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  group('UpdateManifest', () {
    test('parses a full manifest and normalizes blank hash', () {
      final manifest = UpdateManifest.fromJson({
        'buildNumber': 142,
        'version': '1.2.1+142',
        'url': 'https://api.magicmusiccrm.ru/downloads/app.zip',
        'sha256': _validSha,
        'notes': 'Исправления',
      });
      final blankHash = UpdateManifest.fromJson({
        'buildNumber': 1,
        'version': 'x',
        'url': 'u',
        'sha256': '   ',
      });

      expect(manifest.buildNumber, 142);
      expect(manifest.version, '1.2.1+142');
      expect(manifest.sha256, _validSha);
      expect(manifest.notes, 'Исправления');
      expect(blankHash.sha256, isNull);
    });

    test('offers only a higher build with a URL', () {
      UpdateManifest manifest(int build, {String url = 'https://x/app.zip'}) =>
          UpdateManifest(buildNumber: build, version: '', url: url);

      expect(shouldOfferUpdate(141, manifest(142)), isTrue);
      expect(shouldOfferUpdate(142, manifest(142)), isFalse);
      expect(shouldOfferUpdate(142, manifest(141)), isFalse);
      expect(shouldOfferUpdate(141, manifest(142, url: '')), isFalse);
      expect(shouldOfferUpdate(141, null), isFalse);
    });
  });

  group('update trust policy', () {
    test('accepts only HTTPS trusted manifest endpoints', () {
      expect(
        isTrustedWindowsManifestEndpoint(
          'https://api.magicmusiccrm.ru/downloads/latest-v2.json',
        ),
        isTrue,
      );
      expect(
        isTrustedWindowsManifestEndpoint(
          'https://api.phantom-net.ru/downloads/latest-v2.json',
        ),
        isFalse,
      );
      expect(
        isTrustedWindowsManifestEndpoint(
          'http://api.magicmusiccrm.ru/downloads/latest-v2.json',
        ),
        isFalse,
      );
      expect(
        isTrustedWindowsManifestEndpoint(
          'https://evil.example/downloads/latest-v2.json',
        ),
        isFalse,
      );
      expect(
        isTrustedWindowsManifestEndpoint(
          'https://api.magicmusiccrm.ru/downloads/latest.json',
        ),
        isFalse,
      );
    });

    test('requires the same trusted host and a 64-hex payload SHA', () {
      const valid = UpdateManifest(
        buildNumber: 2,
        version: '2',
        url: 'https://api.magicmusiccrm.ru/downloads/windows.zip',
        sha256: _validSha,
      );

      expect(
        isTrustedWindowsUpdateManifest(
          valid,
          trustedHost: 'api.magicmusiccrm.ru',
        ),
        isTrue,
      );
      expect(
        isTrustedWindowsUpdateManifest(
          valid,
          trustedHost: 'api.phantom-net.ru',
        ),
        isFalse,
      );
      expect(
        isTrustedWindowsUpdateManifest(
          const UpdateManifest(
            buildNumber: 2,
            version: '2',
            url: 'https://api.magicmusiccrm.ru/downloads/windows.zip',
          ),
          trustedHost: 'api.magicmusiccrm.ru',
        ),
        isFalse,
      );
    });

    test('permits only explicit loopback HTTP smoke transport', () {
      const local = UpdateManifest(
        buildNumber: 2,
        version: '2',
        url: 'http://127.0.0.1:18765/update.zip',
        sha256: _validSha,
      );

      expect(
        isTrustedWindowsUpdateManifest(
          local,
          trustedHost: '127.0.0.1',
          allowInsecureLoopback: true,
        ),
        isTrue,
      );
      expect(
        isTrustedWindowsUpdateManifest(local, trustedHost: '127.0.0.1'),
        isFalse,
      );
    });

    test('SHA-256 implementation matches standard vectors', () {
      expect(
        sha256Hex(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223'
        'b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        sha256Hex(const <int>[]),
        'e3b0c44298fc1c149afbf4c8996fb924'
        '27ae41e4649b934ca495991b7852b855',
      );
    });
  });

  test('release publisher atomically updates both manifest channels', () {
    expect(windowsUpdateManifestPath, '/downloads/latest-v2.json');

    final mainSource = File('lib/main.dart').readAsStringSync();
    expect(mainSource, contains('path: windowsUpdateManifestPath'));
    expect(mainSource, isNot(contains("path: '/downloads/latest.json'")));

    final publisher = File(
      'scripts/publish-windows-update.ps1',
    ).readAsStringSync();
    expect(
      publisher,
      contains(r"$manifestNames = @('latest.json', 'latest-v2.json')"),
    );
    expect(publisher, contains('MagicMusicCRM-\$verDash-Setup.exe'));
    expect(publisher, contains('MagicMusicCRM-\$verDash.apk'));
    expect(publisher, contains('MagicMusicCRM-\$verDash.aab'));
    expect(
      publisher,
      contains(
        r'& scp -i $SshKey $artifactPath "$Remote`:$RemoteDir/$remoteTemp"',
      ),
    );
    expect(
      publisher,
      contains(
        r'''& ssh -i $SshKey $Remote "mv -- '$RemoteDir/$remoteTemp' '$RemoteDir/$artifactName'"''',
      ),
    );
    expect(
      publisher,
      contains(
        r'& scp -i $SshKey $manifestPath "$Remote`:$RemoteDir/$remoteTemp"',
      ),
    );
    expect(
      publisher,
      contains(
        r'''& ssh -i $SshKey $Remote "mv -- '$RemoteDir/$remoteTemp' '$RemoteDir/$manifestName'"''',
      ),
    );
  });

  group('verified PowerShell launch', () {
    test('round-trips UTF-16LE EncodedCommand including Cyrillic', () {
      const source = r"$value = 'Путь с пробелом'; Write-Output $value";
      expect(decodePowerShellCommand(encodePowerShellCommand(source)), source);
    });

    test('bootstrap verifies one helper read and embedded trusted request', () {
      const helperPath = r'C:\Temp\папка с пробелом\helper.ps1';
      const requestJson =
          '{"url":"https://api.magicmusiccrm.ru/downloads/app.zip"}';
      final source = decodePowerShellCommand(
        buildEncodedUpdaterHelperCommand(
          helperPath: helperPath,
          expectedHelperSha256: _validSha,
          trustedRequestJson: requestJson,
        ),
      );

      expect(source, isNot(contains(helperPath)));
      expect(source, isNot(contains(requestJson)));
      expect(source, contains(base64Encode(utf8.encode(helperPath))));
      expect(source, contains(base64Encode(utf8.encode(requestJson))));
      expect(source, contains('[IO.File]::ReadAllBytes'));
      expect(source, contains('[ScriptBlock]::Create'));
      expect(source, contains('helper_integrity_failed'));
      expect(source, isNot(contains(r'& $helperPath')));
    });

    test('CIM broker verifies launch-command bytes before process create', () {
      const commandPath = r'C:\Temp\launch command.txt';
      final broker = buildCimBrokerScript(
        launchCommandPath: commandPath,
        expectedSha256: _validSha,
      );

      expect(broker, isNot(contains(commandPath)));
      expect(broker, contains(base64Encode(utf8.encode(commandPath))));
      expect(broker, contains('launch command integrity check failed'));
      expect(broker, contains("-ClassName 'Win32_Process'"));
      expect(broker, contains("-MethodName 'Create'"));
      expect(broker, contains('returnValue'));
      expect(broker, contains('processId'));
    });

    test('quotes Windows command-line arguments safely', () {
      expect(
        quoteWindowsCommandLineArgument(r'C:\Windows\powershell.exe'),
        r'C:\Windows\powershell.exe',
      );
      expect(
        quoteWindowsCommandLineArgument(
          r'C:\Program Files\PowerShell\powershell.exe',
        ),
        r'"C:\Program Files\PowerShell\powershell.exe"',
      );
      expect(
        quoteWindowsCommandLineArgument('C:\\Program Files\\Magic\\'),
        r'"C:\Program Files\Magic\\"',
      );
    });

    test('command line contains no raw manifest or install values', () {
      const secretUrl =
          'https://api.magicmusiccrm.ru/update.zip?token=s e c r e t';
      const installDir = r'C:\Program Files\Magic Music CRM';
      const executable = '$installDir\\magic_music_crm.exe';
      final encoded = buildEncodedUpdaterHelperCommand(
        helperPath: r'C:\Temp\helper.ps1',
        expectedHelperSha256: _validSha,
        trustedRequestJson: jsonEncode(<String, String>{
          'url': secretUrl,
          'installDir': installDir,
          'exePath': executable,
        }),
      );
      final commandLine = buildEncodedPowerShellCommandLine(
        powerShellPath: r'C:\Windows\powershell.exe',
        encodedCommand: encoded,
      );

      expect(commandLine, isNot(contains(secretUrl)));
      expect(commandLine, isNot(contains(installDir)));
      expect(commandLine, isNot(contains(executable)));
    });
  });

  group('CIM broker receipt', () {
    test('parses the last typed JSON receipt around noise', () {
      final receipt = parseCimBrokerOutput('''
WARNING: transient provider output
{"ignored":true}
{"returnValue":0,"processId":4242}
''');
      expect(receipt.returnValue, 0);
      expect(receipt.processId, 4242);
      expect(receipt.error, isNull);
    });

    test('retains errors and rejects untyped output', () {
      final receipt = parseCimBrokerOutput(
        '{"returnValue":2,"processId":0,"error":"access denied"}',
      );
      expect(receipt.error, 'access denied');
      expect(
        () => parseCimBrokerOutput('noise\n{"returnValue":"zero"}'),
        throwsFormatException,
      );
    });
  });

  group('updater handshake', () {
    Map<String, Object?> handshake({
      String type = 'ready',
      String updateId = 'run_42_abc',
      int protocolVersion = updaterProtocolVersion,
      int helperPid = 8123,
      bool elevated = false,
      String? code,
      String? message,
    }) => <String, Object?>{
      'type': type,
      'protocolVersion': protocolVersion,
      'updateId': updateId,
      'helperPid': helperPid,
      'elevated': elevated,
      'code': code,
      'message': message,
    };

    test('parses READY and FAILURE schemas', () {
      final ready = parseUpdaterHandshake(jsonEncode(handshake()));
      final failure = parseUpdaterHandshake(
        jsonEncode(
          handshake(
            type: 'failure',
            elevated: true,
            code: 'elevation_denied',
            message: 'The operation was canceled.',
          ),
        ),
      );
      expect(ready.isReady, isTrue);
      expect(failure.isReady, isFalse);
      expect(failure.code, 'elevation_denied');
      expect(
        () => parseUpdaterHandshake('{"type":"ready"}'),
        throwsFormatException,
      );
    });

    test('returns only a matching READY', () async {
      final directory = await Directory.systemTemp.createTemp(
        'mmcrm_handshake_ready_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final readyFile = File('${directory.path}\\ready.json');
      final failureFile = File('${directory.path}\\failure.json');
      await readyFile.writeAsString(jsonEncode(handshake()));

      final result = await waitForUpdaterHandshake(
        readyFile: readyFile,
        failureFile: failureFile,
        expectedUpdateId: 'run_42_abc',
        timeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 2),
      );
      expect(result.helperPid, 8123);
    });

    test('FAILURE wins over READY and remains recoverable', () async {
      final directory = await Directory.systemTemp.createTemp(
        'mmcrm_handshake_failure_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final readyFile = File('${directory.path}\\ready.json');
      final failureFile = File('${directory.path}\\failure.json');
      await readyFile.writeAsString(jsonEncode(handshake()));
      await failureFile.writeAsString(
        jsonEncode(
          handshake(
            type: 'failure',
            code: 'elevation_denied',
            message: 'UAC declined',
          ),
        ),
      );

      await expectLater(
        waitForUpdaterHandshake(
          readyFile: readyFile,
          failureFile: failureFile,
          expectedUpdateId: 'run_42_abc',
          timeout: const Duration(seconds: 1),
          pollInterval: const Duration(milliseconds: 2),
        ),
        throwsA(
          isA<WindowsUpdateLaunchException>().having(
            (error) => error.message,
            'message',
            contains('elevation_denied UAC declined'),
          ),
        ),
      );
    });

    test('rejects stale READY from another request', () async {
      final directory = await Directory.systemTemp.createTemp(
        'mmcrm_handshake_stale_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final readyFile = File('${directory.path}\\ready.json');
      final failureFile = File('${directory.path}\\failure.json');
      await readyFile.writeAsString(
        jsonEncode(handshake(updateId: 'another_update')),
      );

      await expectLater(
        waitForUpdaterHandshake(
          readyFile: readyFile,
          failureFile: failureFile,
          expectedUpdateId: 'run_42_abc',
          timeout: const Duration(seconds: 1),
          pollInterval: const Duration(milliseconds: 2),
        ),
        throwsA(isA<WindowsUpdateLaunchException>()),
      );
    });
  });

  group('process-wide updater single-flight', () {
    test('the active UI flow may acquire its nested launch lease', () async {
      var launchCalls = 0;
      final acquired = await windowsUpdateCoordinator.runFlow(() async {
        final result = await windowsUpdateCoordinator.runLaunch(() async {
          launchCalls++;
          return 42;
        });
        expect(result, 42);
      });
      expect(acquired, isTrue);
      expect(launchCalls, 1);
      expect(windowsUpdateCoordinator.isBusy, isFalse);
    });

    test('public helper entry rejects a concurrent direct launch', () async {
      final blockerStarted = Completer<void>();
      final releaseBlocker = Completer<void>();
      final blocker = windowsUpdateCoordinator.runLaunch(() async {
        blockerStarted.complete();
        await releaseBlocker.future;
      });
      await blockerStarted.future;
      final directory = await Directory.systemTemp.createTemp(
        'mmcrm_single_flight_',
      );
      try {
        await expectLater(
          launchWindowsUpdaterHelper(
            manifest: const UpdateManifest(
              buildNumber: 999,
              version: 'guard-test',
              url: 'https://api.magicmusiccrm.ru/downloads/update.zip',
              sha256: _validSha,
            ),
            trustedManifestHost: 'api.magicmusiccrm.ru',
            appPid: pid,
            exePath: Platform.resolvedExecutable,
            tempDirectory: directory,
          ),
          throwsA(isA<WindowsUpdateInProgressException>()),
        );
        expect(directory.listSync(), isEmpty);
      } finally {
        if (!releaseBlocker.isCompleted) releaseBlocker.complete();
        await blocker;
        await directory.delete(recursive: true);
      }
      expect(windowsUpdateCoordinator.isBusy, isFalse);
    });
  });

  test(
    'new app writes a matching atomic health ACK only under updater temp',
    () async {
      final temp = await Directory.systemTemp.createTemp('mmcrm_health_ack_');
      addTearDown(() => temp.delete(recursive: true));
      const updateId = 'run_123_abc';
      final runDirectory = Directory(
        '${temp.path}\\MagicMusicCRM\\updater\\$updateId',
      );
      await runDirectory.create(recursive: true);
      final ack = File('${runDirectory.path}\\health_ack.json');

      expect(
        await publishWindowsUpdateHealthAck(
          ackPath: ack.path,
          updateId: updateId,
          trustedTempDirectory: temp,
          appProcessId: 777,
        ),
        isTrue,
      );
      final decoded =
          jsonDecode(await ack.readAsString()) as Map<String, dynamic>;
      expect(decoded['type'], 'health_ack');
      expect(decoded['updateId'], updateId);
      expect(decoded['appPid'], 777);
      expect(
        await publishWindowsUpdateHealthAck(
          ackPath: '${temp.path}\\outside.json',
          updateId: updateId,
          trustedTempDirectory: temp,
        ),
        isFalse,
      );
    },
  );

  group('updaterScript security and lifecycle', () {
    test('uses a ten-minute visible staging handshake', () {
      expect(
        defaultWindowsUpdaterHandshakeTimeout,
        const Duration(minutes: 10),
      );
    });

    test(
      'trusts embedded request data and revalidates URL, SHA, and helper',
      () {
        expect(updaterScript, contains(r'$TrustedRequestBase64'));
        expect(updaterScript, isNot(contains(r'$RequestPath')));
        expect(
          updaterScript,
          isNot(contains(r'$script:Request.encodedCommand')),
        );
        expect(updaterScript, contains('Assert-TrustedRequest'));
        expect(updaterScript, contains('Update URL must use HTTPS'));
        expect(updaterScript, contains('A 64-hex payload SHA256 is required'));
        expect(updaterScript, contains('Trusted helper SHA256'));
        expect(updaterScript, contains('New-VerifiedBootstrapEncodedCommand'));
        expect(updaterScript, contains('[ScriptBlock]::Create'));
      },
    );

    test('holds an install mutex and releases it before UAC handoff', () {
      final acquire = updaterScript.indexOf('Acquire-UpdateMutex');
      final elevation = updaterScript.indexOf("Verb = 'RunAs'");
      final release = updaterScript.lastIndexOf(
        'Release-UpdateMutex',
        elevation,
      );
      expect(acquire, greaterThanOrEqualTo(0));
      expect(release, greaterThan(acquire));
      expect(elevation, greaterThan(release));
      expect(updaterScript, contains('update_already_running'));
      expect(updaterScript, contains('finally {'));
    });

    test('fully validates and stages payload before publishing READY', () {
      final download = updaterScript.indexOf('Invoke-WebRequest');
      final hash = updaterScript.indexOf("Write-Log -Stage 'hash_verified'");
      final extract = updaterScript.indexOf(
        "Write-Log -Stage 'archive_extracted'",
      );
      final structure = updaterScript.indexOf(
        'Assert-StagedPayload -SourcePath',
      );
      final snapshot = updaterScript.indexOf(
        "Write-Log -Stage 'rollback_snapshot_completed'",
      );
      final ready = updaterScript.indexOf("Write-Log -Stage 'ready'");
      final finalCancel = updaterScript.indexOf(
        r'$script:Request.cancelPath',
        snapshot,
      );

      expect(updaterScript, contains('-TimeoutSec 300'));
      expect(updaterScript, contains('-MaximumRedirection 0'));
      expect(hash, greaterThan(download));
      expect(extract, greaterThan(hash));
      expect(structure, greaterThan(extract));
      expect(snapshot, greaterThan(structure));
      expect(finalCancel, greaterThan(snapshot));
      expect(ready, greaterThan(finalCancel));
      expect(
        updaterScript,
        contains(r'[string]$script:Request.expectedExeName'),
      );
      expect(updaterScript, contains("'flutter_windows.dll'"));
      expect(updaterScript, contains(r"'data\icudtl.dat'"));
      expect(updaterScript, contains(r"'data\app.so'"));
      expect(updaterScript, contains(r"'data\flutter_assets'"));
    });

    test('ACKs takeover before swap and accepts robocopy only through 7', () {
      final ready = updaterScript.indexOf("Write-Log -Stage 'ready'");
      final acknowledged = updaterScript.indexOf(
        "Write-Log -Stage 'ready_acknowledged'",
      );
      final parentWait = updaterScript.indexOf(r'$parentDeadline');
      final copy = updaterScript.indexOf(
        r'$robocopyExitCode = Invoke-RobocopyTree',
      );
      expect(acknowledged, greaterThan(ready));
      expect(parentWait, greaterThan(acknowledged));
      expect(copy, greaterThan(parentWait));
      expect(
        updaterScript,
        contains(r'if ($robocopyExitCode -lt 0 -or $robocopyExitCode -ge 8)'),
      );
    });

    test('keeps rollback journal until matching new-app health ACK', () {
      final swap = updaterScript.indexOf("-State 'swap_started'");
      final candidate = updaterScript.indexOf(
        "Relaunch-App -Reason 'update_candidate' -RequestHealthAck \$true",
      );
      final healthWait = updaterScript.indexOf(
        'Test-MatchingHealthAck',
        candidate,
      );
      final healthAck = updaterScript.indexOf(
        "Write-Log -Stage 'health_acknowledged'",
      );
      final cleanup = updaterScript.indexOf(
        r'Remove-Item -LiteralPath $completedRunPath -Recurse',
      );

      expect(swap, greaterThanOrEqualTo(0));
      expect(candidate, greaterThan(swap));
      expect(healthWait, greaterThan(candidate));
      expect(healthAck, greaterThan(healthWait));
      expect(cleanup, greaterThan(healthAck));
      expect(updaterScript, contains('MMCRM_UPDATE_HEALTH_ACK_PATH'));
      expect(updaterScript, contains('MMCRM_UPDATE_ID'));
      expect(updaterScript, contains("Write-Log -Stage 'cleanup_deferred'"));
      expect(updaterScript, contains("-State 'rollback_completed'"));
      expect(updaterScript, contains("-Mirror \$true"));
    });

    test('redacts logs, cleans pre-READY terminals, and avoids cmd/start', () {
      expect(updaterScript, contains(r"$ErrorActionPreference = 'Stop'"));
      expect(updaterScript, contains('function Protect-SensitiveText'));
      expect(
        updaterScript,
        contains(r'message = Protect-SensitiveText $Message'),
      );
      expect(updaterScript, contains('access_token'));
      expect(updaterScript, contains(r'$1=[REDACTED]'));
      expect(updaterScript, contains(r'if (-not $script:ReadyWritten'));
      expect(updaterScript, contains(r'$parentStillRunning'));
      expect(updaterScript, contains("Write-Log -Stage 'relaunch_skipped'"));
      expect(updaterScript.toLowerCase(), isNot(contains('cmd.exe')));
      expect(updaterScript.toLowerCase(), isNot(contains('/c start')));
    });
  });
}
