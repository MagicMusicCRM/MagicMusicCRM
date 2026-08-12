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
}
