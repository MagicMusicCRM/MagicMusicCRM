import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/update/windows_update_service.dart';

void main() {
  for (final mode in ['healthy', 'rollback', 'bad-hash', 'missing-payload']) {
    test(
      'real updater helper $mode',
      () async {
        final base = Directory(
          Platform.environment['UPDATER_AUDIT_OUTPUT']!,
        ).absolute;
        final fixture = Directory('${base.path}/$mode');
        await fixture.create(recursive: true);
        final install = Directory('${fixture.path}/install');
        await install.create();
        final payload = Directory('${fixture.path}/candidate');
        await payload.create();
        final temp = Directory('${fixture.path}/temp');
        await temp.create();
        // The product helper may mirror/delete only these disposable fixture trees.
        for (final dir in [install, payload, temp])
          expect(
            dir.resolveSymbolicLinksSync().toLowerCase().startsWith(
              '${base.resolveSymbolicLinksSync().toLowerCase()}${Platform.pathSeparator}',
            ),
            true,
          );
        const name = 'audit_update_fixture.exe';
        Future<File> compile(Directory dir, String kind) async {
          final source = File('${dir.path}/fixture.cs');
          source.writeAsStringSync(
            r'''
using System;using System.IO;using System.Diagnostics;using System.Threading;using System.Reflection;
class Fixture { [STAThread] static void Main() {
 string kind="__KIND__";string here=Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
 File.WriteAllText(Path.Combine(here,kind+".pid"),Process.GetCurrentProcess().Id.ToString());
 if(kind=="crash")return;
 string ack=Environment.GetEnvironmentVariable("MMCRM_UPDATE_HEALTH_ACK_PATH");
 string id=Environment.GetEnvironmentVariable("MMCRM_UPDATE_ID");
 if(kind=="healthy"&&!String.IsNullOrEmpty(ack))File.WriteAllText(ack,"{\"protocolVersion\":1,\"type\":\"health_ack\",\"updateId\":\""+id+"\",\"appPid\":"+Process.GetCurrentProcess().Id+"}");
 Thread.Sleep(90000);
}}
'''
                .replaceAll('__KIND__', kind),
          );
          final exe = File('${dir.path}/$name');
          final result = await Process.run(
            r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
            ['/nologo', '/target:winexe', '/out:$name', 'fixture.cs'],
            workingDirectory: dir.path,
          );
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
          return exe;
        }

        final old = await compile(install, 'old'),
            candidate = await compile(
              payload,
              mode == 'rollback' ? 'crash' : 'healthy',
            );
        final oldHash = sha256Hex(await old.readAsBytes()),
            newHash = sha256Hex(await candidate.readAsBytes());
        final archive = Archive();
        void add(String name, List<int> bytes) =>
            archive.addFile(ArchiveFile(name, bytes.length, bytes));
        add(name, await candidate.readAsBytes());
        for (final file in [
          'flutter_windows.dll',
          'data/icudtl.dat',
          'data/flutter_assets/AssetManifest.bin',
          'new-marker.txt',
          if (mode != 'missing-payload') 'data/app.so',
        ])
          add(file, utf8.encode('synthetic $mode'));
        final zip = ZipEncoder().encode(archive);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var downloads = 0;
        server.listen((r) async {
          downloads++;
          r.response.headers.contentType = ContentType('application', 'zip');
          r.response.contentLength = zip.length;
          r.response.add(zip);
          await r.response.close();
        });
        final parent = await Process.start(
          old.path,
          [],
          workingDirectory: install.path,
        );
        final evidence = <String, dynamic>{
          'mode': mode,
          'oldHash': oldHash,
          'candidateHash': newHash,
          'fixtureRoot': fixture.path,
          'startedAt': DateTime.now().toIso8601String(),
        };
        try {
          final manifest = UpdateManifest(
            buildNumber: 221,
            version: '1.5.41+221',
            url: 'http://127.0.0.1:${server.port}/payload.zip',
            sha256: mode == 'bad-hash' ? '0' * 64 : sha256Hex(zip),
            notes: 'Synthetic updater audit',
          );
          if (mode == 'bad-hash' || mode == 'missing-payload') {
            Object? failure;
            try {
              await launchWindowsUpdaterHelper(
                manifest: manifest,
                trustedManifestHost: '127.0.0.1',
                appPid: parent.pid,
                exePath: old.path,
                tempDirectory: temp,
                allowInsecureLoopbackForTesting: true,
                handshakeTimeout: const Duration(seconds: 50),
              );
            } catch (e) {
              failure = e;
            }
            expect(failure, isNotNull);
            evidence['rejection'] = failure.toString();
            expect(sha256Hex(await old.readAsBytes()), oldHash);
            expect(File('${install.path}/new-marker.txt').existsSync(), false);
          } else {
            final session = await launchWindowsUpdaterHelper(
              manifest: manifest,
              trustedManifestHost: '127.0.0.1',
              appPid: parent.pid,
              exePath: old.path,
              tempDirectory: temp,
              allowInsecureLoopbackForTesting: true,
              handshakeTimeout: const Duration(seconds: 50),
            );
            evidence['updateId'] = session.updateId;
            evidence['ready'] = true;
            evidence['helperPid'] = session.handshake.helperPid;
            expect(
              sha256Hex(await old.readAsBytes()),
              oldHash,
              reason: 'READY must precede replacement',
            );
            parent.kill();
            await parent.exitCode;
            List<Map<String, dynamic>> logs() =>
                File(session.logPath).existsSync()
                ? File(session.logPath)
                      .readAsLinesSync()
                      .where((s) => s.trim().isNotEmpty)
                      .map((s) => jsonDecode(s) as Map<String, dynamic>)
                      .where((r) => r['updateId'] == session.updateId)
                      .toList()
                : [];
            final deadline = DateTime.now().add(const Duration(seconds: 65));
            final terminal = mode == 'healthy' ? 'completed' : 'failed';
            while (DateTime.now().isBefore(deadline) &&
                !logs().any((r) => r['stage'] == terminal))
              await Future<void>.delayed(const Duration(milliseconds: 200));
            evidence['logs'] = logs();
            expect(logs().any((r) => r['stage'] == terminal), true);
            if (mode == 'healthy') {
              expect(
                logs().any((r) => r['stage'] == 'health_acknowledged'),
                true,
              );
              expect(sha256Hex(await old.readAsBytes()), newHash);
              expect(File('${install.path}/new-marker.txt').existsSync(), true);
            } else {
              expect(
                logs().any((r) => r['stage'] == 'rollback_completed'),
                true,
              );
              expect(sha256Hex(await old.readAsBytes()), oldHash);
              expect(
                File('${install.path}/new-marker.txt').existsSync(),
                false,
              );
            }
          }
          expect(downloads, 1);
          evidence['status'] = 'PASS';
        } catch (e) {
          evidence['status'] = 'FAIL';
          evidence['failure'] = e.toString();
          rethrow;
        } finally {
          parent.kill();
          await server.close(force: true);
          final ids = install
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.pid'))
              .map((f) => int.tryParse(f.readAsStringSync()))
              .whereType<int>()
              .toSet();
          for (final id in ids) {
            final literal = old.path.replaceAll("'", "''");
            await Process.run('powershell.exe', [
              '-NoProfile',
              '-NonInteractive',
              '-WindowStyle',
              'Hidden',
              '-Command',
              "\$auditProcess=Get-Process -Id $id -ErrorAction SilentlyContinue; if(\$auditProcess -and \$auditProcess.Path -eq '$literal'){Stop-Process -Id $id -Force}",
            ]);
          }
          evidence['downloads'] = downloads;
          evidence['finishedAt'] = DateTime.now().toIso8601String();
          File(
            '${base.path}/$mode.json',
          ).writeAsStringSync(jsonEncode(evidence), flush: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: Platform.environment['UPDATER_AUDIT_OUTPUT'] == null
          ? 'Explicit isolated updater audit only'
          : false,
    );
  }
}
