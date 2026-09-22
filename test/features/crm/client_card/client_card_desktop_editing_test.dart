import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';

import 'card_fake_api.dart';

const desktopStudent = <String, dynamic>{
  'id': 'student-1',
  'version': 2,
  'firstName': 'Анна',
  'lastName': 'Соколова',
  'phone': '+79990000000',
  'email': 'anna@example.test',
  'status': 'active',
  'branchId': 'branch-1',
  'branchName': 'Сокол',
};
const desktopManager = CapabilitySnapshot(
  accountId: 'manager-1',
  role: 'manager',
  accessVersion: 1,
  capabilities: {
    'crm.client.read.basic',
    'crm.client.write',
    'commerce.client_finance.read',
    'commerce.client_finance.write',
    'schedule.lesson.read.assigned',
    'schedule.lesson.write',
    'workflow.task.read',
    'workflow.task.write',
  },
  scopes: {},
);

class DesktopGroupApi extends FakeCardApiClient {
  DesktopGroupApi() : super(role: 'manager', student: desktopStudent);
  bool joined = false;
  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/groups') {
      getRequests.add(path);
      getCalls.add((path: path, query: queryParameters ?? {}));
      return {
            'items': [
              {'id': 'group-1', 'name': 'Вокальная группа'},
            ],
          }
          as T;
    }
    final result = await super.get<T>(
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
    if (joined && path == '/crm/students/student-1/card' && result is Map) {
      result['groups'] = [
        {'id': 'group-1', 'name': 'Вокальная группа'},
      ];
    }
    return result;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/groups/group-1/students') joined = true;
    return super.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final entity in ['student', 'lead']) {
    testWidgets(
      '$entity desktop edits contacts, header name and note without section navigation',
      (tester) async {
        tester.view.physicalSize = const Size(1366, 768);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final record = {...desktopStudent, 'id': '$entity-1'};
        final api = FakeCardApiClient(
          role: 'manager',
          student: entity == 'student' ? record : null,
          lead: entity == 'lead' ? record : null,
          internalNote: const {'body': 'Первое занятие', 'version': 3},
        );
        await pumpClientCard(
          tester,
          api: api,
          seed: record,
          entityType: entity,
          routed: true,
          capabilitySnapshot: desktopManager,
        );
        expect(
          find.byKey(const Key('client-desktop-section-jumps')),
          findsNothing,
        );
        final sidebar = find.byKey(const Key('client-desktop-contact-sidebar'));
        expect(
          find.descendant(of: sidebar, matching: find.byType(RuPhoneField)),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('client-internal-note-input')).hitTestable(),
          findsOneWidget,
        );
        for (final key in [
          'profile',
          'lessons',
          'subscriptions',
          'progress',
          'history_tasks',
        ]) {
          expect(
            find.byKey(Key('client-desktop-section-$key')),
            findsOneWidget,
          );
        }
        final phone = find.descendant(
          of: find.byType(RuPhoneField).first,
          matching: find.byType(TextField),
        );
        await tester.enterText(phone, '79991234567');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Электронная почта'),
          'new@example.test',
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        final contactPatch = entity == 'student'
            ? api.updateStudentBody
            : api.updateLeadBody;
        expect(contactPatch?['phone'], '+79991234567');
        expect(contactPatch?['email'], 'new@example.test');
        expect(contactPatch?['expectedVersion'], 2);

        await tester.tap(find.byKey(const Key('client-edit-name')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('client-name-first')),
          'Мария',
        );
        await tester.enterText(
          find.byKey(const Key('client-name-last')),
          'Иванова',
        );
        await tester.tap(find.byKey(const Key('client-name-apply')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        final namePatch = entity == 'student'
            ? api.updateStudentBody
            : api.updateLeadBody;
        expect(namePatch?['firstName'], 'Мария');
        expect(namePatch?['lastName'], 'Иванова');
        expect(find.text('Мария Иванова'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('client-internal-note-input')),
          'Позвонить до занятия',
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(api.updateInternalNoteBody, {
          'body': 'Позвонить до занятия',
          'expectedVersion': 3,
        });
        FocusManager.instance.primaryFocus?.unfocus();
        final heading = find.byKey(
          const Key('client-section-heading-history_tasks'),
        );
        await tester.ensureVisible(heading);
        await tester.pumpAndSettle();
        expect(heading.hitTestable(), findsOneWidget);
        // The contact editor stays available while the central page is scrolled.
        expect(
          find.widgetWithText(TextFormField, 'Электронная почта').hitTestable(),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const Key('client-internal-note-input')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.byKey(const Key('client-internal-note-input')),
              )
              .controller!
              .text,
          'Позвонить до занятия',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('header name cancel and blank name do not write', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(student: desktopStudent);
    await pumpClientCard(
      tester,
      api: api,
      seed: desktopStudent,
      entityType: 'student',
      routed: true,
      capabilitySnapshot: desktopManager,
    );
    await tester.tap(find.byKey(const Key('client-edit-name')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('client-name-first')), '');
    await tester.tap(find.byKey(const Key('client-name-apply')));
    await tester.pumpAndSettle();
    expect(find.text('Введите имя'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(api.updateStudentBodies, isEmpty);
  });

  testWidgets(
    'read-only desktop does not offer writes or query forbidden sections',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = FakeCardApiClient(role: 'teacher', student: desktopStudent);
      await pumpClientCard(
        tester,
        api: api,
        seed: desktopStudent,
        entityType: 'student',
        routed: true,
        capabilitySnapshot: const CapabilitySnapshot(
          accountId: 'teacher-1',
          role: 'teacher',
          accessVersion: 1,
          capabilities: {'crm.client.read.basic'},
          scopes: {},
        ),
      );
      for (final key in [
        'client-edit-name',
        'client-add-to-group',
        'client-book-trial',
        'client-sell-subscription',
        'client-internal-note-input',
      ]) {
        expect(find.byKey(Key(key)), findsNothing);
      }
      expect(
        tester.widget<RuPhoneField>(find.byType(RuPhoneField)).enabled,
        isFalse,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Электронная почта'),
            )
            .enabled,
        isNot(false),
      );
      final email = find.descendant(
        of: find.widgetWithText(TextFormField, 'Электронная почта'),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(email).readOnly, isTrue);
      for (final picker in tester.widgetList<SearchablePickerField>(
        find.byType(SearchablePickerField),
      )) {
        expect(picker.enabled, isFalse);
      }
      expect(api.getRequests, isNot(contains('/crm/schedule-plans')));
      expect(api.getRequests, isNot(contains('/crm/groups')));
      expect(api.updateStudentBodies, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sidebar group action saves membership and refreshes the same client',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = DesktopGroupApi();
      await pumpClientCard(
        tester,
        api: api,
        seed: desktopStudent,
        entityType: 'student',
        routed: true,
        capabilitySnapshot: desktopManager,
      );
      await tester.tap(find.byKey(const Key('client-add-to-group')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Название группы…'),
        'Вокал',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Вокальная группа'));
      await tester.pumpAndSettle();
      expect(
        api.postRequests.any(
          (call) =>
              call.path == '/crm/groups/group-1/students' &&
              call.data['studentId'] == 'student-1',
        ),
        isTrue,
      );
      expect(find.text('Вокальная группа'), findsOneWidget);
      expect(api.studentCardLoadCount, 2);
      expect(
        api.getCalls.where((call) => call.path == '/crm/groups').first.query,
        {'limit': 100, 'branchId': 'branch-1'},
      );
      expect(
        api.getCalls.where((call) => call.path == '/crm/groups').last.query,
        {'limit': 100, 'branchId': 'branch-1', 'q': 'Вокал'},
      );
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sidebar trial action prefills current student', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(student: desktopStudent);
    await pumpClientCard(
      tester,
      api: api,
      seed: desktopStudent,
      entityType: 'student',
      routed: true,
      capabilitySnapshot: desktopManager,
    );
    await tester.tap(find.byKey(const Key('client-book-trial')));
    await tester.pumpAndSettle();
    final editor = tester.widget<CreateLessonDialog>(
      find.byType(CreateLessonDialog),
    );
    expect(editor.clientId, 'student-1');
    expect(editor.clientType, 'student');
    expect(editor.initialIsTrial, isTrue);
    expect(editor.initialBranchId, 'branch-1');
    expect(tester.takeException(), isNull);
  });
}
