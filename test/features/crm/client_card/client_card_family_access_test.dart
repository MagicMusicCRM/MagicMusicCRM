import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';

import 'card_fake_api.dart';

void main() {
  testWidgets(
    'family contacts expose entity navigation, payer, app link and invite',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.reset);

      final api = FakeCardApiClient(
        role: 'manager',
        student: const {
          'id': 'student-1',
          'firstName': 'Анна',
          'lastName': 'Соколова',
          'email': 'anna@example.com',
          'status': 'active',
        },
        family: {
          'family': {
            'id': 'family-1',
            'name': 'Соколовы',
            'branchId': 'branch-1',
            'primaryPayerMemberId': null,
          },
          'members': [
            {
              'id': 'member-1',
              'entityType': 'student',
              'entityId': 'student-2',
              'role': 'payer',
              'isPrimaryContact': true,
              'name': 'Пётр Соколов',
            },
          ],
        },
        linkedUsers: const [
          {
            'userId': 'user-own',
            'name': 'Анна Соколова',
            'phone': '+79990000001',
            'linkSource': 'self',
          },
        ],
        clientUserCandidates: const [
          {
            'userId': 'user-parent',
            'name': 'Пётр Соколов',
            'phone': '+79990000001',
            'email': 'parent@example.com',
          },
        ],
      );

      await pumpClientCard(
        tester,
        api: api,
        seed: const {'id': 'student-1'},
        entityType: 'student',
        routed: true,
      );

      await tester.ensureVisible(find.byKey(const Key('client-app-access')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(EntityLinkText),
          matching: find.text('Пётр Соколов'),
        ),
        findsOneWidget,
      );
      expect(find.text('Личный аккаунт ученика'), findsOneWidget);
      expect(find.text('parent@example.com'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('family-primary-payer-member-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('family-primary-payer-member-1')));
      await tester.pumpAndSettle();
      expect(
        api.postRequests.any(
          (request) =>
              request.path == '/crm/families/family-1/primary-payer/member-1',
        ),
        isTrue,
      );

      await tester.ensureVisible(
        find.byKey(const Key('client-link-user-user-parent')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('client-link-user-user-parent')));
      await tester.pumpAndSettle();
      expect(
        api.postRequests.any(
          (request) =>
              request.path == '/crm/clients/student/student-1/link-user' &&
              request.data['userId'] == 'user-parent',
        ),
        isTrue,
      );

      await tester.ensureVisible(find.byKey(const Key('client-send-invite')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('client-send-invite')));
      await tester.pumpAndSettle();
      expect(
        api.postRequests.any(
          (request) => request.path == '/crm/students/student-1/invite',
        ),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invite flushes a valid email edit before posting', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final patchGate = Completer<void>();
    final api = FakeCardApiClient(
      role: 'manager',
      student: _studentWithEmail('old@example.com'),
    )..studentPatchGate = patchGate;
    await pumpClientCard(
      tester,
      api: api,
      seed: const {'id': 'student-1'},
      entityType: 'student',
      routed: true,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Электронная почта'),
      'new@example.com',
    );
    await tester.ensureVisible(find.byKey(const Key('client-send-invite')));
    await tester.tap(find.byKey(const Key('client-send-invite')));
    await tester.pump();

    expect(api.updateStudentBody, containsPair('email', 'new@example.com'));
    expect(_invitePosts(api), isEmpty);

    patchGate.complete();
    await tester.pumpAndSettle();
    expect(_invitePosts(api), hasLength(1));
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('invite rejects an invalid email draft without posting', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(
      role: 'manager',
      student: _studentWithEmail('old@example.com'),
    );
    await pumpClientCard(
      tester,
      api: api,
      seed: const {'id': 'student-1'},
      entityType: 'student',
      routed: true,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Электронная почта'),
      'broken@',
    );
    await tester.ensureVisible(find.byKey(const Key('client-send-invite')));
    await tester.tap(find.byKey(const Key('client-send-invite')));
    await tester.pumpAndSettle();

    expect(api.updateStudentBodies, isEmpty);
    expect(_invitePosts(api), isEmpty);
    expect(find.textContaining('корректный адрес'), findsWidgets);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('invite is not posted when the email save fails', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final api = FakeCardApiClient(
      role: 'manager',
      student: _studentWithEmail('old@example.com'),
    )..studentPatchFailures = 1;
    await pumpClientCard(
      tester,
      api: api,
      seed: const {'id': 'student-1'},
      entityType: 'student',
      routed: true,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Электронная почта'),
      'new@example.com',
    );
    await tester.ensureVisible(find.byKey(const Key('client-send-invite')));
    await tester.tap(find.byKey(const Key('client-send-invite')));
    await tester.pumpAndSettle();

    expect(api.updateStudentBodies, hasLength(1));
    expect(_invitePosts(api), isEmpty);
    expect(find.textContaining('Сначала сохраните'), findsWidgets);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('cleared email is persisted and invite is not posted', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    final patchGate = Completer<void>();
    final api = FakeCardApiClient(
      role: 'manager',
      student: _studentWithEmail('old@example.com'),
    )..studentPatchGate = patchGate;
    await pumpClientCard(
      tester,
      api: api,
      seed: const {'id': 'student-1'},
      entityType: 'student',
      routed: true,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Электронная почта'),
      '',
    );
    await tester.ensureVisible(find.byKey(const Key('client-send-invite')));
    await tester.tap(find.byKey(const Key('client-send-invite')));
    await tester.pump();

    expect(api.updateStudentBody, containsPair('clearEmail', true));
    expect(_invitePosts(api), isEmpty);
    expect(find.textContaining('Укажите электронную почту'), findsNothing);

    patchGate.complete();
    await tester.pumpAndSettle();
    expect(_invitePosts(api), isEmpty);
    expect(find.textContaining('Укажите электронную почту'), findsWidgets);
    await tester.pump(const Duration(seconds: 4));
  });
}

Map<String, dynamic> _studentWithEmail(String email) => <String, dynamic>{
  'id': 'student-1',
  'version': 2,
  'firstName': 'Анна',
  'lastName': 'Соколова',
  'email': email,
  'status': 'active',
  'customData': <String, dynamic>{},
};

Iterable<CardPostCall> _invitePosts(FakeCardApiClient api) => api.postRequests
    .where((request) => request.path == '/crm/students/student-1/invite');
