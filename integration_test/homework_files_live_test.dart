import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/homework_widget.dart';
import 'live_audit_harness.dart';

// Only the operating system chooser is replaced. Disk bytes, upload, binding,
// status mutation and authenticated download use the real product services.
class AuditFilePicker extends FilePicker {
  AuditFilePicker(this.path);
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
    final file = File(path);
    return FilePickerResult([
      PlatformFile(
        name: file.uri.pathSegments.last,
        size: file.lengthSync(),
        path: path,
      ),
    ]);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  final role = Platform.environment['HOMEWORK_AUDIT_ROLE']!;
  testWidgets('$role real homework files', (tester) async {
    final h = LiveAuditHarness(tester, role, 'homework-files');
    await h.initialize(size: const Size(1440, 1200));
    final crm = h.scope.read(magicCrmServiceProvider);
    final student = h.fixture['studentId'] as String;
    final file = File(
      '${Platform.environment['EVIDENCE_SCREENSHOT_DIR']}/audit-$role.txt',
    );
    final bytes = utf8.encode('AUDIT HOMEWORK $role\nНоты и ритм\n');
    file.writeAsBytesSync(bytes);
    final original = FilePicker.platform, picker = AuditFilePicker(file.path);
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = original);
    final access = await h.scope.read(capabilitySnapshotProvider.future);
    final title = role == 'client' ? 'AUDIT-CLIENT-FILE' : 'AUDIT-ADMIN-FILE';
    Future<List<Map<String, dynamic>>> rows() =>
        crm.listHomeworks(studentId: student);
    Future<Map<String, dynamic>> current() async {
      final value = (await rows()).singleWhere((r) => r['title'] == title);
      h.facts.add({'step': h.currentStep, 'homework': value});
      return value;
    }

    Future<void> open() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await h.mount(
        Scaffold(
          body: role == 'client'
              ? HomeworkWidget(key: UniqueKey(), studentId: student)
              : ClientCard(
                  key: UniqueKey(),
                  lead: await crm.getStudent(student),
                  entityType: 'student',
                  routed: true,
                  initialSection: 'progress',
                  capabilitySnapshot: access,
                ),
        ),
      );
      await h.quiet();
    }

    Future<void> assign() => h.tap(find.byKey(const Key('assign-homework')));
    Finder titleField() => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Заголовок *',
    );
    if (role == 'admin') {
      await h.check(
        'OPEN',
        'Открыть выдачу домашнего задания из карточки',
        () async {
          await open();
          await assign();
          expect(titleField(), findsOneWidget);
        },
      );
      await h.check('REQUIRED', 'Пустой заголовок не создаёт ДЗ', () async {
        await h.tap(find.text('Создать').last);
        expect(find.text('Введите заголовок'), findsWidgets);
        expect((await rows()).where((r) => r['title'] == title), isEmpty);
      });
      await h.check(
        'PICK-CANCEL',
        'Отмена выбора файла не создаёт вложение',
        () async {
          picker.cancel = true;
          await h.tap(find.byKey(const Key('homework-pick-attachment')));
          expect(
            find.byKey(const Key('homework-selected-attachment')),
            findsNothing,
          );
          picker.cancel = false;
        },
      );
      await h.check(
        'PICK-REMOVE',
        'Выбор настоящего файла и удаление его из черновика',
        () async {
          await h.tap(find.byKey(const Key('homework-pick-attachment')));
          expect(find.text('audit-admin.txt'), findsOneWidget);
          await h.tap(find.byTooltip('Убрать файл'));
          expect(
            find.byKey(const Key('homework-selected-attachment')),
            findsNothing,
          );
        },
      );
      await h.check('CREATE', 'Сохранить ДЗ с файлом через форму', () async {
        await tester.enterText(titleField(), title);
        await tester.enterText(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.hintText == 'Подробности (необязательно)',
          ),
          'AUDIT-DESCRIPTION',
        );
        await h.tap(find.byKey(const Key('homework-pick-attachment')));
        await h.tap(find.text('Создать').last);
        await h.quiet();
        expect((await current())['attachments'], hasLength(1));
      });
    } else {
      await h.check(
        'OPEN',
        'Клиент видит назначенное домашнее задание',
        () async {
          await open();
          expect(find.text(title), findsOneWidget);
          expect((await current())['status'], 'assigned');
        },
      );
      await h.check(
        'SUBMIT-CANCEL',
        'Отмена выбора файла сохраняет assigned',
        () async {
          await h.tap(find.text('Сдать').last);
          picker.cancel = true;
          await h.tap(find.byKey(const Key('homework-submit-with-file')));
          await h.quiet();
          picker.cancel = false;
          expect((await current())['status'], 'assigned');
          expect((await current())['attachments'], isEmpty);
        },
      );
      await h.check(
        'SUBMIT-FILE',
        'Сдать решение с настоящим файлом',
        () async {
          await h.tap(find.text('Сдать').last);
          await h.tap(find.byKey(const Key('homework-submit-with-file')));
          await h.quiet();
          final row = await current();
          expect(row['status'], 'submitted');
          expect(row['attachments'], hasLength(1));
        },
      );
    }
    await h.check(
      'REOPEN',
      'Статус и вложение сохраняются при повторном открытии',
      () async {
        await open();
        final row = await current();
        expect(row['status'], role == 'client' ? 'submitted' : 'assigned');
        expect(row['attachments'], hasLength(1));
        expect(find.text('audit-$role.txt'), findsWidgets);
      },
    );
    await h.check(
      'DOWNLOAD',
      'Авторизованная загрузка возвращает исходные байты',
      () async {
        final row = await current();
        final attachment = (row['attachments'] as List).single as Map;
        final api = h.scope.read(magicApiClientProvider);
        final token = await api.post<Map<String, dynamic>>(
          '/files/${attachment['fileId']}/download-token',
        );
        final downloaded = await api.downloadBytes(
          '/files/download/${token['token']}',
        );
        expect(downloaded, bytes);
        h.facts.add({
          'step': h.currentStep,
          'fileId': attachment['fileId'],
          'byteCount': downloaded.length,
          'bytesEqual': true,
        });
      },
    );
    await h.finish();
  }, timeout: const Timeout(Duration(minutes: 8)));
}
