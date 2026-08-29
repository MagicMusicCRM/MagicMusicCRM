import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/providers/schedule_navigation_provider.dart';

import 'card_fake_api.dart';

Finder _clientNameField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextFormField &&
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('Имя-'),
);

/// Бар ученика хранит только контекстные действия и на 360dp переносится
/// Wrap'ом без переполнения. Общего меню «Действия» больше нет.
void main() {
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets('студенческий бар действий не переполняется на 360x690', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = FakeCardApiClient(
      student: {
        'id': 'stu-1',
        'firstName': 'Анна',
        'lastName': 'Смирнова',
        'status': 'Занимается',
        'customData': <String, dynamic>{},
      },
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'stu-1', 'custom_data': {}},
      entityType: 'student',
      statuses: const [],
    );

    expect(find.text('Действия'), findsNothing);
    expect(find.text('Открыть в расписании'), findsOneWidget);
    expect(find.text('Закрыть'), findsOneWidget);
    expect(find.text('Отмена'), findsNothing);
    expect(find.text('Сохранить'), findsNothing);
    expect(find.text('Сохранено'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('изменение ученика сохраняется автоматически после паузы', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = FakeCardApiClient(
      student: {
        'id': 'stu-1',
        'version': 1,
        'firstName': 'Анна',
        'lastName': 'Смирнова',
        'status': 'Занимается',
        'customData': <String, dynamic>{},
      },
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'stu-1', 'custom_data': {}},
      entityType: 'student',
      statuses: const [],
    );

    final name = _clientNameField();
    await tester.enterText(name, 'Мария');
    await tester.pump(const Duration(milliseconds: 799));
    expect(api.updateStudentBody, isNull);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(api.updateStudentBody, isNotNull);
    expect(api.updateStudentBody!['firstName'], 'Мария');
    expect(find.text('Сохранено'), findsWidgets);
  });

  testWidgets(
    'автосохранение не запускает параллельные PATCH и не теряет ввод',
    (tester) async {
      final api = FakeCardApiClient(
        student: {
          'id': 'stu-1',
          'version': 1,
          'firstName': 'Анна',
          'lastName': 'Смирнова',
          'status': 'Занимается',
          'customData': <String, dynamic>{},
        },
      );
      await pumpClientCard(
        tester,
        api: api,
        seed: {'id': 'stu-1', 'custom_data': {}},
        entityType: 'student',
        statuses: const [],
      );
      final name = _clientNameField();
      api.studentPatchGate = Completer<void>();

      await tester.enterText(name, 'Мария');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      expect(api.updateStudentBodies, hasLength(1));

      await tester.enterText(name, 'Мария Иванова');
      await tester.pump(const Duration(milliseconds: 800));
      expect(api.updateStudentBodies, hasLength(1));

      api.studentPatchGate!.complete();
      await tester.pumpAndSettle();

      expect(api.updateStudentBodies, hasLength(2));
      expect(api.updateStudentBodies.last['firstName'], 'Мария Иванова');
    },
  );

  testWidgets('ошибка автосохранения оставляет явный повтор', (tester) async {
    final api = FakeCardApiClient(
      student: {
        'id': 'stu-1',
        'version': 1,
        'firstName': 'Анна',
        'lastName': 'Смирнова',
        'status': 'Занимается',
        'customData': <String, dynamic>{},
      },
    )..studentPatchFailures = 1;
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'stu-1', 'custom_data': {}},
      entityType: 'student',
      statuses: const [],
    );
    final name = _clientNameField();
    await tester.enterText(name, 'Мария');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.text('Повторить'), findsWidgets);
    await tester.tap(find.text('Повторить').last);
    await tester.pumpAndSettle();

    expect(api.updateStudentBodies, hasLength(2));
    expect(api.updateStudentBody!['firstName'], 'Мария');
    expect(find.text('Сохранено'), findsWidgets);
  });

  testWidgets('закрытие карточки сначала сохраняет свежий ввод', (
    tester,
  ) async {
    bool? closeResult;
    final api = FakeCardApiClient(
      student: {
        'id': 'stu-1',
        'version': 1,
        'firstName': 'Анна',
        'lastName': 'Смирнова',
        'status': 'Занимается',
        'customData': <String, dynamic>{},
      },
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'stu-1', 'custom_data': {}},
      entityType: 'student',
      statuses: const [],
      onClosed: (result) => closeResult = result,
    );

    await tester.enterText(_clientNameField(), 'Мария');
    await tester.tap(find.text('Закрыть').last);
    await tester.pumpAndSettle();

    expect(find.text('Несохранённые изменения'), findsNothing);
    expect(api.updateStudentBody?['firstName'], 'Мария');
    expect(closeResult, isTrue);
  });

  testWidgets(
    'Lead card opens client month in its default branch before trial creation',
    (tester) async {
      final api = FakeCardApiClient(
        lead: {
          'id': 'lead-1',
          'firstName': 'Анна',
          'lastName': 'Смирнова',
          'phone': '+79990000000',
          'branchId': 'branch-default',
          'customData': <String, dynamic>{},
        },
      );
      await pumpClientCard(
        tester,
        api: api,
        seed: {'id': 'lead-1', 'name': 'Анна', 'custom_data': {}},
        statuses: const [],
      );

      final action = find.text('Открыть в расписании');
      final container = ProviderScope.containerOf(tester.element(action));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();

      final focus = container.read(scheduleNavigationProvider);
      expect(focus, isNotNull);
      expect(focus!.openMonth, isTrue);
      expect(focus.clientType, 'lead');
      expect(focus.clientId, 'lead-1');
      expect(focus.clientName, 'Анна Смирнова');
      expect(focus.branchId, 'branch-default');
      expect(focus.leadId, isNull);
    },
  );

  testWidgets('лид конвертируется только кнопкой выдачи абонемента', (
    tester,
  ) async {
    final api = FakeCardApiClient(
      lead: {
        'id': 'lead-1',
        'firstName': 'Анна',
        'lastName': 'Смирнова',
        'phone': '+79990000000',
        'statusId': null,
        'customData': <String, dynamic>{},
      },
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: {'id': 'lead-1', 'name': 'Анна', 'custom_data': {}},
      statuses: const [],
    );

    final subscriptions = find.text('Абонементы');
    await tester.ensureVisible(subscriptions);
    await tester.tap(subscriptions);
    await tester.pumpAndSettle();
    expect(find.text('Продать абонемент'), findsOneWidget);
    expect(find.text('Выдать абонемент'), findsNothing);
    expect(find.text('Создать ученика'), findsNothing);
  });

  testWidgets(
    'pending lead edits are saved before preview and idempotent purchase',
    (tester) async {
      const statusId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
      final api = FakeCardApiClient(
        lead: {
          'id': 'lead-1',
          'version': 1,
          'firstName': 'Анна',
          'lastName': 'Смирнова',
          'phone': '+79990000000',
          'statusId': null,
          'customData': <String, dynamic>{},
        },
        internalNote: const {
          'id': 'note-1',
          'body': 'Старый контекст',
          'version': 2,
          'updatedByName': 'Администратор',
          'updatedAt': '2026-08-07T10:00:00.000Z',
        },
        subscriptionPackages: const [
          {
            'id': 'package-1',
            'name': 'Демо — Фортепиано, 8 часов',
            'lessonsTotal': 8,
            'price': 24000,
          },
        ],
      );
      await pumpClientCard(
        tester,
        api: api,
        seed: {'id': 'lead-1', 'name': 'Анна', 'custom_data': {}},
        statuses: const <StatusRecord>[(statusId, 'В работе', Colors.blue)],
      );

      final status = find.byType(DropdownButtonFormField<String>).first;
      await tester.ensureVisible(status);
      await tester.tap(status);
      await tester.pumpAndSettle();
      await tester.tap(find.text('В работе').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('client-internal-note-input')),
        'Контекст перед продажей',
      );

      final subscriptions = find.text('Абонементы');
      await tester.ensureVisible(subscriptions);
      await tester.tap(subscriptions);
      await tester.pumpAndSettle();
      final issue = find.text('Продать абонемент');
      await tester.ensureVisible(issue);
      await tester.tap(issue);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('subscription-accepted-by')),
            )
            .initialValue,
        'Анна Администратор',
      );
      final packageSelector = find.byKey(
        const Key('subscription-package-selector'),
      );
      await tester.ensureVisible(packageSelector);
      final packagePicker = tester.widget<SearchablePickerField>(
        packageSelector,
      );
      packagePicker.onSelected(packagePicker.items.single);
      await tester.pumpAndSettle();

      final submit = find.byKey(const Key('subscription-issue-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(api.updateLeadBody?['statusId'], statusId);
      expect(api.updateInternalNoteBody, {
        'body': 'Контекст перед продажей',
        'expectedVersion': 2,
      });
      expect(api.requests, [
        'PUT /crm/clients/lead/lead-1/internal-note',
        'PATCH /crm/leads/lead-1',
        'POST /crm/leads/lead-1/subscriptions/purchase/preview',
      ]);
      expect(api.idempotentRequests, isEmpty);

      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(api.requests, [
        'PUT /crm/clients/lead/lead-1/internal-note',
        'PATCH /crm/leads/lead-1',
        'POST /crm/leads/lead-1/subscriptions/purchase/preview',
        'POST /crm/leads/lead-1/subscriptions/purchase',
      ]);
      expect(api.idempotentRequests, hasLength(1));
      expect(
        api.idempotentRequests.single.path,
        '/crm/leads/lead-1/subscriptions/purchase',
      );
      expect(api.idempotentRequests.single.data, containsPair('confirm', true));
      expect(
        api.idempotentRequests.single.data,
        containsPair('previewToken', 'lead-purchase-preview-token'),
      );
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('subscription actor falls back to email or failure label', (
    tester,
  ) async {
    Future<void> openSale(FakeCardApiClient api) async {
      await pumpClientCard(
        tester,
        api: api,
        seed: {'id': 'lead-1', 'name': 'Анна', 'custom_data': {}},
        statuses: const [],
      );
      final subscriptions = find.text('Абонементы');
      await tester.ensureVisible(subscriptions);
      await tester.tap(subscriptions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продать абонемент'));
      await tester.pumpAndSettle();
    }

    FakeCardApiClient api({
      required Map<String, dynamic> profile,
      bool fail = false,
    }) => FakeCardApiClient(
      lead: const {
        'id': 'lead-1',
        'firstName': 'Анна',
        'lastName': 'Смирнова',
        'customData': <String, dynamic>{},
      },
      subscriptionPackages: const [
        {'id': 'package-1', 'name': 'Демо', 'lessonsTotal': 8, 'price': 24000},
      ],
      currentProfile: profile,
      failCurrentProfile: fail,
    );

    await openSale(
      api(
        profile: const {
          'id': 'current-user',
          'email': 'fallback@example.test',
          'role': 'admin',
          'firstName': 'Анна',
        },
      ),
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('subscription-accepted-by')),
          )
          .initialValue,
      'fallback@example.test',
    );
    await tester.pumpWidget(const SizedBox.shrink());

    await openSale(api(profile: const {}, fail: true));
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('subscription-accepted-by')),
          )
          .initialValue,
      'Текущий пользователь',
    );
  });

  testWidgets(
    'disposing a card during delayed actor lookup opens no sale sheet',
    (tester) async {
      final profileGate = Completer<Map<String, dynamic>>();
      final api = FakeCardApiClient(
        lead: const {
          'id': 'lead-1',
          'firstName': 'Анна',
          'lastName': 'Смирнова',
          'customData': <String, dynamic>{},
        },
        subscriptionPackages: const [
          {
            'id': 'package-1',
            'name': 'Демо',
            'lessonsTotal': 8,
            'price': 24000,
          },
        ],
        currentProfileGate: profileGate.future,
      );
      await pumpClientCard(
        tester,
        api: api,
        seed: {'id': 'lead-1', 'name': 'Анна', 'custom_data': {}},
        statuses: const [],
      );

      final subscriptions = find.text('Абонементы');
      await tester.ensureVisible(subscriptions);
      await tester.tap(subscriptions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продать абонемент'));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      profileGate.complete(const {
        'id': 'current-user',
        'email': 'admin@example.test',
        'role': 'admin',
        'firstName': 'Анна',
        'lastName': 'Администратор',
      });
      await tester.pump();

      expect(find.byKey(const Key('subscription-accepted-by')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
