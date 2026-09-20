import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Director offboards and restores staff with actual login access',
    (tester) async {
      final h = LiveAuditHarness(tester, 'director', 'teacher-offboard');
      await h.initialize(size: const Size(1440, 1500));
      final crm = h.scope.read(magicCrmServiceProvider),
          id = h.fixture['staffId'] as String;
      final detail = find.byType(TeacherDetailDialog);
      Finder modal() => find.byWidgetPredicate(
        (w) =>
            w is AlertDialog &&
            w.title is Text &&
            [
              'Отключить и архивировать',
              'Восстановить карточку',
            ].contains((w.title as Text).data),
      );
      Finder commit() =>
          find.descendant(of: modal(), matching: find.byType(FilledButton));
      Future<void> cancel() =>
          h.tap(find.descendant(of: modal(), matching: find.text('Отмена')));
      Future<void> reason(String value) async {
        final field = find.descendant(
          of: modal(),
          matching: find.byType(TextField),
        );
        await h.tap(field);
        await tester.enterText(field, value);
        await tester.pump();
      }

      Future<void> open({bool archived = false}) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(
          SystemSettingsRouteScreen(key: UniqueKey(), initialArea: 'users'),
        );
        await h.quiet();
        await h.tap(find.text('Преподаватели'));
        await h.quiet();
        await h.tap(find.text('OFFBOARD-TEACHER Проверка'));
        await h.quiet();
        expect(detail, findsOneWidget);
        await h.tap(
          find.text(
            archived ? 'Восстановить преподавателя' : 'Отключить преподавателя',
          ),
        );
        await h.quiet();
        expect(modal(), findsOneWidget);
      }

      Future<Map<String, dynamic>> preview() async {
        final result = await crm.previewPersonLifecycle(
          personType: 'teacher',
          personId: id,
        );
        h.facts.add({'step': h.currentStep, 'preview': result});
        return result;
      }

      Future<Map<String, dynamic>> login() => h.api.post<Map<String, dynamic>>(
        '/auth/login',
        authenticated: false,
        data: {
          'email': h.fixture['staffEmail'],
          'password': h.fixture['password'],
        },
      );
      await h.check('LOGIN-BEFORE', 'Сотрудник входит до отключения', () async {
        final result = await login();
        expect(result['session']['accessToken'], isNotEmpty);
      });
      await h.check(
        'PREVIEW-CANCEL',
        'Preview разрешает отключение свободного сотрудника; причина обязательна, отмена сохраняет доступ',
        () async {
          await open();
          expect((await preview())['canOffboard'], true);
          await h.tap(commit());
          expect(
            find.text('Укажите причину не короче 5 символов.'),
            findsOneWidget,
          );
          await reason('CANCEL-OFFBOARD');
          await cancel();
          expect((await preview())['person']['lifecycleState'], 'active');
        },
      );
      await h.check(
        'OFFBOARD',
        'Отключение архивирует карточку и закрывает доступ аккаунта',
        () async {
          await open();
          await reason('AUDIT-OFFBOARD');
          await h.tap(commit());
          await h.quiet();
          expect(modal(), findsNothing);
          final result = await preview();
          expect(result['person']['lifecycleState'], 'archived');
        },
      );
      await h.check(
        'LOGIN-DENIED',
        'После отключения прежние реквизиты не позволяют войти',
        () async {
          try {
            await login();
            fail('Offboarded account authenticated');
          } on MagicApiException catch (error) {
            expect(error.statusCode, 401);
          }
        },
        expectedHttpErrors: [
          (method: 'POST', path: '/api/auth/login', status: 401, maxCount: 1),
        ],
      );
      await h.check(
        'RESTORE-CANCEL',
        'Отмена восстановления сохраняет архив',
        () async {
          await open(archived: true);
          await reason('CANCEL-RESTORE');
          await cancel();
          expect((await preview())['person']['lifecycleState'], 'archived');
        },
      );
      await h.check(
        'RESTORE',
        'Восстановление возвращает активную карточку и назначение филиала',
        () async {
          await open(archived: true);
          await reason('AUDIT-RESTORE');
          await h.tap(commit());
          await h.quiet();
          expect(modal(), findsNothing);
          expect((await preview())['person']['lifecycleState'], 'active');
          final staff = (await crm.listTeachers(q: 'OFFBOARD-TEACHER')).single;
          expect(staff['assigned_branches'], isNotEmpty);
          expect(staff['is_app_account'], true);
        },
      );
      await h.check(
        'LOGIN-RESTORED',
        'Восстановленный сотрудник входит прежними реквизитами',
        () async {
          final result = await login();
          expect(result['session']['accessToken'], isNotEmpty);
        },
      );
      await h.check(
        'HISTORY',
        'API истории содержит отключение и восстановление с причинами',
        () async {
          final result = await h.api.get<Map<String, dynamic>>(
            '/crm/teachers/$id/lifecycle-history',
          );
          h.facts.add({'step': h.currentStep, 'history': result});
          expect((result['items'] as List).length, 2);
        },
      );
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
