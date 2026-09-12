import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';
import 'package:magic_music_crm/core/widgets/avatar_cropper_dialog.dart';
import 'live_audit_harness.dart';

class AvatarAuditPicker extends FilePicker {
  AvatarAuditPicker(this.path);
  final String path;
  bool cancel = false;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    if (cancel) return null;
    final f = File(path);
    return FilePickerResult([
      PlatformFile(
        name: 'audit-avatar.png',
        size: f.lengthSync(),
        bytes: f.readAsBytesSync(),
        path: path,
      ),
    ]);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final role
      in Platform.environment['AVATAR_AUDIT_ROLE'] != null
          ? [Platform.environment['AVATAR_AUDIT_ROLE']!]
          : ['admin', 'manager', 'director', 'teacher', 'client'])
    testWidgets('$role profile avatar lifecycle', (tester) async {
      final h = LiveAuditHarness(tester, role, 'profile-avatar');
      await h.initialize(size: const Size(1440, 1100));
      final original = FilePicker.platform,
          picker = AvatarAuditPicker(h.fixture['avatarPath'] as String);
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = original);
      Future<Map<String, dynamic>> read() async {
        final p = await h.api.get<Map<String, dynamic>>('/profile/me');
        h.facts.add({'step': h.currentStep, 'profile': p});
        return p;
      }

      Future<void> open() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(ProfileScreen(key: UniqueKey()));
        await h.waitFor(
          () => find.text('Сменить фото').evaluate().isNotEmpty,
          'Profile loaded',
        );
        await h.quiet();
      }

      Future<void> pick() async {
        await h.tap(find.text('Сменить фото'));
        await h.quiet();
      }

      Future<void> crop() async {
        await pick();
        expect(find.byType(AvatarCropperDialog), findsOneWidget);
        await h.tap(find.widgetWithText(ElevatedButton, 'Сохранить'));
        await h.waitFor(
          () => find.byType(AvatarCropperDialog).evaluate().isEmpty,
          'Crop finished',
        );
        await h.quiet();
      }

      String? first, current;
      Future<void> assertFile(String id) async {
        final t = await h.api.post<Map<String, dynamic>>(
          '/files/$id/download-token',
        );
        final bytes = await h.api.downloadBytes(
          '/files/download/${t['token']}',
        );
        expect(bytes.length, greaterThan(100));
        expect(bytes.take(2).toList(), [255, 216]);
        h.facts.add({
          'step': h.currentStep,
          'fileId': id,
          'downloadBytes': bytes.length,
          'jpeg': true,
        });
      }

      await h.check('OPEN', 'Открыть профиль без аватара', () async {
        await open();
        expect((await read())['avatarFileId'], isNull);
      });
      await h.check('PICK-CANCEL', 'Отмена выбора не меняет профиль', () async {
        picker.cancel = true;
        await pick();
        picker.cancel = false;
        expect(find.byType(AvatarCropperDialog), findsNothing);
        expect(find.byTooltip('Сохранить'), findsNothing);
        expect((await read())['avatarFileId'], isNull);
      });
      await h.check('CROP-CANCEL', 'Отмена обрезки не создаёт файл', () async {
        await pick();
        await h.tap(find.widgetWithText(TextButton, 'Отмена').last);
        expect(find.byTooltip('Сохранить'), findsNothing);
        expect((await read())['avatarFileId'], isNull);
      });
      await h.check('CROP', 'Обрезать фото в настоящем редакторе', () async {
        await crop();
        expect(find.byTooltip('Сохранить'), findsOneWidget);
        expect((await read())['avatarFileId'], isNull);
      });
      await h.check(
        'SAVE',
        'Сохранить JPEG в приватном хранилище и профиле',
        () async {
          await h.tap(find.byTooltip('Сохранить'));
          await h.quiet();
          first = (await read())['avatarFileId'] as String?;
          expect(first, isNotNull);
          current = first;
          await assertFile(first!);
        },
      );
      await h.check(
        'REOPEN',
        'После открытия профиль ссылается на сохранённый файл',
        () async {
          await open();
          expect((await read())['avatarFileId'], first);
          await assertFile(first!);
        },
      );
      await h.check(
        'REPLACE',
        'Заменить аватар с сохранением нового файла',
        () async {
          await crop();
          await h.tap(find.byTooltip('Сохранить'));
          await h.quiet();
          current = (await read())['avatarFileId'] as String?;
          expect(current, isNot(first));
          await assertFile(current!);
          h.facts.add({
            'step': h.currentStep,
            'oldId': first,
            'newId': current,
          });
        },
      );
      if (role == 'director') {
        bool reject = false;
        final interceptor = InterceptorsWrapper(
          onRequest: (o, handler) {
            if (reject &&
                o.method == 'PATCH' &&
                o.uri.path.endsWith('/profile/me')) {
              h.trace(o, 503, error: 'auditSyntheticUnavailable');
              handler.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: o,
                    statusCode: 503,
                    data: {'message': 'AUDIT synthetic unavailable'},
                  ),
                ),
              );
              return;
            }
            handler.next(o);
          },
        );
        h.api.rawDio.interceptors.add(interceptor);
        addTearDown(() => h.api.rawDio.interceptors.remove(interceptor));
        await h.check(
          'FAILED-SAVE-PRESERVES-OLD',
          'Отказ сохранения профиля должен сохранить прежний доступный аватар',
          () async {
            await crop();
            reject = true;
            await h.tap(find.byTooltip('Сохранить'));
            await h.quiet();
            reject = false;
            expect((await read())['avatarFileId'], current);
            bool readable = true;
            try {
              await assertFile(current!);
            } catch (_) {
              readable = false;
            }
            h.facts.add({
              'step': h.currentStep,
              'oldFileId': current,
              'oldFileReadable': readable,
            });
            expect(
              readable,
              isTrue,
              reason:
                  'Profile must not reference a deleted avatar after failed PATCH',
            );
          },
          expectedHttpErrors: const [
            (
              method: 'PATCH',
              path: '/api/profile/me',
              status: 503,
              maxCount: 3,
            ),
          ],
        );
      }
      await h.finish();
    }, timeout: const Timeout(Duration(minutes: 8)));
}
