// Existing plugin interfaces are used only as audit hardware adapters.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/widgets/voice_recorder_widget.dart';
import 'package:magic_music_crm/core/widgets/voice_player_widget.dart';
import 'package:magic_music_crm/core/widgets/telegram/message_bubble.dart';
import 'package:magic_music_crm/features/client/presentation/screens/client_dashboard_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'live_audit_harness.dart';
import 'attachment_runtime_live_test.dart' show AuditDownloadDirectory;

class SyntheticRecorder extends RecordPlatform {
  SyntheticRecorder(this.bytes);
  Uint8List bytes;
  bool permitted = true;
  final paths = <String, String>{};
  String? lastPath;
  @override
  Future<void> create(String id) async {}
  @override
  Stream<RecordState> onStateChanged(String id) => const Stream.empty();
  @override
  Future<bool> hasPermission(String id, {bool request = true}) async =>
      permitted;
  @override
  Future<void> start(
    String id,
    RecordConfig config, {
    required String path,
  }) async {
    expectSync(config.encoder, AudioEncoder.aacLc);
    paths[id] = path;
    lastPath = path;
    await File(path).writeAsBytes(bytes);
  }

  @override
  Future<String?> stop(String id) async => paths[id];
  @override
  Future<void> dispose(String id) async {
    paths.remove(id);
  }

  @override
  Future<Amplitude> getAmplitude(String id) async =>
      Amplitude(current: -160, max: -160);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['client', 'teacher', 'admin', 'manager', 'director']) {
    testWidgets(
      '$role actual voice controls storage playback and failed upload',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'voice-runtime');
        await h.initialize(size: const Size(1550, 1350));
        final chat = h.fixture['chatId'] as String,
            service = h.scope.read(magicMessengerServiceProvider),
            original = RecordPlatform.instance,
            recorder = SyntheticRecorder(
              File(h.fixture['audioPath']).readAsBytesSync(),
            );
        RecordPlatform.instance = recorder;
        final originalPaths = PathProviderPlatform.instance,
            dir = Directory(
              '${Platform.environment['EVIDENCE_SCREENSHOT_DIR']}/voice-temp-$role',
            )..createSync();
        PathProviderPlatform.instance = AuditDownloadDirectory(dir.path);
        addTearDown(() {
          RecordPlatform.instance = original;
          PathProviderPlatform.instance = originalPaths;
        });
        String? messageId;
        Finder record() => find.byType(VoiceRecorderWidget);
        Finder player() => find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is MessageBubble && w.message['id'] == messageId,
          ),
          matching: find.byType(VoicePlayerWidget),
        );
        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            role == 'client'
                ? const ClientDashboardScreen()
                : const StaffWorkspaceScreen(),
          );
          await h.quiet();
          await h.tap(find.text('AUDIT-VOICE-CHAT').first);
          await h.quiet();
        }

        Future<void> begin() async {
          await h.tap(find.byTooltip('Голосовое сообщение'));
          await h.quiet();
        }

        await h.check(
          'PERMISSION',
          'Отказ микрофона возвращает ввод без загрузки файла',
          () async {
            await open();
            recorder.permitted = false;
            final n = h.requests.length;
            await begin();
            expect(record(), findsNothing);
            expect(find.byTooltip('Голосовое сообщение'), findsOneWidget);
            expect(
              h.requests
                  .skip(n)
                  .where(
                    (r) => r['method'] == 'POST' && r['path'] == '/api/files',
                  ),
              isEmpty,
            );
            recorder.permitted = true;
          },
        );
        await h.check(
          'CANCEL',
          'Начать и отменить запись: временный файл удаляется, сообщение не создаётся',
          () async {
            final before = (await service.listMessages(chat)).length;
            await begin();
            expect(record(), findsOneWidget);
            expect(File(recorder.lastPath!).existsSync(), true);
            await h.tap(
              find.descendant(
                of: record(),
                matching: find.byTooltip('Отменить'),
              ),
            );
            await h.quiet();
            expect(record(), findsNothing);
            expect(File(recorder.lastPath!).existsSync(), false);
            expect((await service.listMessages(chat)).length, before);
          },
        );
        await h.check(
          'SEND',
          'Остановить запись и отправить реальные AAC-байты через HTTP',
          () async {
            final before = (await service.listMessages(
              chat,
            )).map((m) => m['id']).toSet();
            await begin();
            await tester.pump(const Duration(seconds: 2));
            await h.tap(find.byTooltip('Остановить и отправить запись'));
            await h.quiet();
            expect(record(), findsNothing);
            final row = (await service.listMessages(
              chat,
            )).singleWhere((m) => !before.contains(m['id']));
            messageId = row['id'];
            expect(row['message_type'], 'voice');
            expect(row['attachment_file_id'], isNotEmpty);
            expect(player(), findsOneWidget);
            expect(File(recorder.lastPath!).existsSync(), false);
            h.facts.add({'step': h.currentStep, 'message': row});
          },
        );
        await h.check(
          'REOPEN',
          'Голосовое сообщение и длительность сохраняются при повторном открытии',
          () async {
            await open();
            expect(player(), findsOneWidget);
            expect(
              tester.widget<VoicePlayerWidget>(player()).durationMs,
              greaterThan(0),
            );
          },
        );
        await h.check(
          'PLAY-PAUSE',
          'Настоящий проигрыватель загружает приватный файл, время движется, пауза работает',
          () async {
            await tester.tap(
              find.descendant(
                of: player(),
                matching: find.byIcon(Icons.play_arrow_rounded),
              ),
            );
            await tester.pump();
            await h.waitFor(
              () => find
                  .descendant(
                    of: player(),
                    matching: find.byIcon(Icons.pause_rounded),
                  )
                  .evaluate()
                  .isNotEmpty,
              'Native audio playback started',
            );
            await h.waitFor(
              () => tester
                  .widgetList<Text>(
                    find.descendant(of: player(), matching: find.byType(Text)),
                  )
                  .any(
                    (w) =>
                        w.data != null &&
                        w.data!.startsWith('00:') &&
                        (int.tryParse(w.data!.substring(3)) ?? 0) > 0,
                  ),
              'Playback position advances',
            );
            h.facts.add({
              'step': h.currentStep,
              'positionTexts': tester
                  .widgetList<Text>(
                    find.descendant(of: player(), matching: find.byType(Text)),
                  )
                  .map((w) => w.data)
                  .toList(),
            });
            await h.tap(
              find.descendant(
                of: player(),
                matching: find.byIcon(Icons.pause_rounded),
              ),
            );
            await h.quiet();
            expect(
              find.descendant(
                of: player(),
                matching: find.byIcon(Icons.play_arrow_rounded),
              ),
              findsOneWidget,
            );
            expect(
              h.requests.any(
                (r) =>
                    r['path'].toString().endsWith('/download-token') &&
                    r['status'] == 201,
              ),
              true,
            );
          },
        );
        await h.check(
          'REPLAY',
          'Возобновить воспроизведение с движением времени и снова поставить на паузу',
          () async {
            await tester.tap(
              find.descendant(
                of: player(),
                matching: find.byIcon(Icons.play_arrow_rounded),
              ),
            );
            await tester.pump();
            await h.waitFor(
              () => find
                  .descendant(
                    of: player(),
                    matching: find.byIcon(Icons.pause_rounded),
                  )
                  .evaluate()
                  .isNotEmpty,
              'Playback resumed',
            );
            await h.waitFor(
              () => tester
                  .widgetList<Text>(
                    find.descendant(of: player(), matching: find.byType(Text)),
                  )
                  .any(
                    (w) =>
                        w.data != null &&
                        w.data!.startsWith('00:') &&
                        (int.tryParse(w.data!.substring(3)) ?? 0) > 0,
                  ),
              'Resumed playback position advances',
            );
            await h.tap(
              find.descendant(
                of: player(),
                matching: find.byIcon(Icons.pause_rounded),
              ),
            );
            await h.quiet();
          },
        );
        if (role == 'director') {
          await h.check(
            'SHORT-SEND',
            'Запись короче секунды отправляется с корректной положительной длительностью',
            () async {
              recorder.bytes = File(
                h.fixture['shortAudioPath'],
              ).readAsBytesSync();
              final before = (await service.listMessages(
                chat,
              )).map((m) => m['id']).toSet();
              await tester.tap(find.byTooltip('Голосовое сообщение'));
              await tester.pump();
              await h.waitFor(
                () =>
                    find
                        .byTooltip('Остановить и отправить запись')
                        .evaluate()
                        .isNotEmpty &&
                    tester
                        .widgetList<IconButton>(find.byType(IconButton))
                        .any(
                          (w) =>
                              w.tooltip == 'Остановить и отправить запись' &&
                              w.onPressed != null,
                        ),
                'Recorder started',
              );
              expect(
                find.descendant(of: record(), matching: find.text('00:00')),
                findsOneWidget,
              );
              await tester.tap(find.byTooltip('Остановить и отправить запись'));
              await h.quiet();
              final added = (await service.listMessages(
                chat,
              )).where((m) => !before.contains(m['id'])).toList();
              h.facts.add({
                'step': h.currentStep,
                'newMessages': added,
                'recorderVisible': record().evaluate().isNotEmpty,
              });
              recorder.bytes = File(h.fixture['audioPath']).readAsBytesSync();
              expect(added, hasLength(1));
              expect(added.single['voice_duration_ms'], greaterThan(0));
            },
            expectedHttpErrors: [
              (
                method: 'POST',
                path: '/api/messenger/chats/$chat/messages',
                status: 400,
                maxCount: 1,
              ),
            ],
          );
        }
        await h.check(
          'FAILED-SEND',
          'Ошибка загрузки сохраняет доступную пользователю запись для повторной отправки',
          () async {
            await begin();
            final before = (await service.listMessages(chat)).length;
            bool rejected = false;
            final gate = InterceptorsWrapper(
              onRequest: (o, next) {
                if (!rejected &&
                    o.method == 'POST' &&
                    o.uri.path == '/api/files') {
                  rejected = true;
                  h.trace(o, 503, error: 'badResponse');
                  next.reject(
                    DioException(
                      requestOptions: o,
                      type: DioExceptionType.badResponse,
                      response: Response(
                        requestOptions: o,
                        statusCode: 503,
                        data: {'message': 'AUDIT synthetic upload failure'},
                      ),
                    ),
                  );
                } else {
                  next.next(o);
                }
              },
            );
            h.api.rawDio.interceptors.add(gate);
            await h.tap(find.byTooltip('Остановить и отправить запись'));
            await h.quiet();
            h.api.rawDio.interceptors.remove(gate);
            expect(rejected, true);
            expect((await service.listMessages(chat)).length, before);
            h.facts.add({
              'step': h.currentStep,
              'tempExists': File(recorder.lastPath!).existsSync(),
              'recorderVisible': record().evaluate().isNotEmpty,
            });
            expect(
              record(),
              findsOneWidget,
              reason: 'Failed upload must keep a recoverable voice draft',
            );
          },
          expectedHttpErrors: [
            (method: 'POST', path: '/api/files', status: 503, maxCount: 1),
          ],
        );
        if (role == 'client') {
          await h.check(
            'NATIVE-FILE-PROBE',
            'Диагностика: тот же AAC воспроизводится нативным проигрывателем из локального файла',
            () async {
              final probe = AudioPlayer();
              try {
                final duration = await probe.setFilePath(
                  h.fixture['audioPath'],
                );
                unawaited(probe.play());
                await h.waitFor(
                  () => probe.position.inMilliseconds >= 500,
                  'Local AAC playback position advances',
                );
                await probe.pause();
                h.facts.add({
                  'step': h.currentStep,
                  'durationMs': probe.duration?.inMilliseconds,
                  'loadReturnDurationMs': duration?.inMilliseconds,
                  'positionMs': probe.position.inMilliseconds,
                  'playing': probe.playing,
                  'processingState': probe.processingState.name,
                });
                expect(
                  probe.duration?.inMilliseconds,
                  greaterThanOrEqualTo(9900),
                );
              } finally {
                await probe.dispose();
              }
            },
          );
        }
        // This wave intentionally records expected product failures; preserve
        // per-step evidence without making Flutter treat the audit as aborted.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        h.save();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
