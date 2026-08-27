import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_model.dart';

class _StaffApi extends MagicApiClient {
  _StaffApi({
    this.branchFailures = 0,
    this.branchResponse,
    this.patchResponse,
    this.provisionResponse,
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  int branchFailures;
  final Completer<List<Map<String, dynamic>>>? branchResponse;
  final Completer<Map<String, dynamic>>? patchResponse;
  final Completer<Map<String, dynamic>>? provisionResponse;
  final List<Map<String, dynamic>> branches = const [
    {'id': 'branch-a', 'name': 'Сокол'},
  ];
  final patches = <String, Map<String, dynamic>>{};
  final posts = <String, Map<String, dynamic>>{};
  int branchReads = 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/branches') {
      branchReads++;
      if (branchFailures > 0) {
        branchFailures--;
        throw StateError('network unavailable');
      }
      if (branchResponse != null) {
        return <String, dynamic>{'items': await branchResponse!.future} as T;
      }
      return <String, dynamic>{'items': branches} as T;
    }
    if (path.endsWith('/access')) {
      return <String, dynamic>{
            'email': 'managed@example.test',
            'password': 'managed-password',
          }
          as T;
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final body = Map<String, dynamic>.from(data! as Map);
    patches[path] = body;
    if (patchResponse != null) return await patchResponse!.future as T;
    return <String, dynamic>{'id': path.split('/').last, ...body} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final body = Map<String, dynamic>.from(data! as Map);
    posts[path] = body;
    if (provisionResponse != null) {
      return await provisionResponse!.future as T;
    }
    return <String, dynamic>{
          'id': path.split('/')[3],
          'isAppAccount': true,
          'appRole': 'admin',
          ...body,
        }
        as T;
  }
}

Map<String, dynamic> _staff({
  List<Map<String, dynamic>> branches = const [
    {'id': 'branch-a', 'name': 'Сокол'},
  ],
  String lifecycleState = 'active',
  bool isAppAccount = false,
}) {
  return <String, dynamic>{
    'id': 'staff-a',
    'first_name': 'Ольга',
    'last_name': 'Смирнова',
    'phone': '+79990000000',
    'email': 'olga@example.test',
    'position': 'Администратор',
    'role': 'admin',
    'status': 'working',
    'branches': branches,
    'lifecycle_state': lifecycleState,
    'is_app_account': isAppAccount,
  };
}

StaffDetailController _controller(_StaffApi api, Map<String, dynamic> staff) {
  return StaffDetailController(crm: MagicCrmService(api), staff: staff);
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required _StaffApi api,
  required String currentRole,
  required Map<String, dynamic> staff,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        magicCrmServiceProvider.overrideWithValue(MagicCrmService(api)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: StaffDetailDialog(staff: staff, currentRole: currentRole),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('StaffDetailDraft', () {
    test('uses legacy profile fallback and canonical phone for linking', () {
      final draft = StaffDetailDraft.fromStaff({
        'id': 'legacy-staff',
        'profiles': {
          'first_name': 'Легаси',
          'last_name': 'Профиль',
          'phone': '+79991112233',
        },
        'email': 'legacy@example.test',
        'custom_data': {'birthday': '1990-06-01'},
      });

      expect(draft.firstName, 'Легаси');
      expect(draft.lastName, 'Профиль');
      expect(draft.canonicalPhone, '+79991112233');
      expect(draft.linkSearchValue(), '+79991112233');

      draft.birthday = '1991-07-02';
      expect(draft.customDataPatch(), {'birthday': '1991-07-02'});
    });

    test('suppresses migration and local invalid emails from linking', () {
      for (final email in const [
        'hollihop-staff-1@migration.invalid',
        'staff@local.magicmusiccrm.invalid',
      ]) {
        final draft = StaffDetailDraft.fromStaff({'email': email});

        expect(draft.linkSearchValue(), isNull, reason: email);
      }
    });

    test('does not clear or resend an unchanged birthday', () {
      final draft = StaffDetailDraft.fromStaff({
        'custom_data': {'birthday': '1990-06-01'},
      });

      expect(draft.customDataPatch(), isEmpty);
      draft.birthday = '';
      expect(draft.customDataPatch(), isEmpty);
    });
  });

  group('StaffDetailController', () {
    test('exposes exact branch load failure and supports retry', () async {
      final api = _StaffApi(branchFailures: 1);
      final controller = _controller(api, _staff());

      await controller.loadBranches();

      expect(controller.loadingBranches, isFalse);
      expect(controller.branchesError, 'Не удалось загрузить филиалы.');
      expect(controller.branches, isEmpty);

      await controller.loadBranches();

      expect(api.branchReads, 2);
      expect(controller.branchesError, isNull);
      expect(controller.branches.single['name'], 'Сокол');
    });

    for (final fails in const [false, true]) {
      test(
        'ignores a late branch ${fails ? 'error' : 'result'} after disposal',
        () async {
          final response = Completer<List<Map<String, dynamic>>>();
          final controller = _controller(
            _StaffApi(branchResponse: response),
            _staff(),
          );

          final loading = controller.loadBranches();
          final originalStaff = Map<String, dynamic>.from(controller.staff);
          final originalEmail = controller.draft.email;
          controller.dispose();
          if (fails) {
            response.completeError(StateError('late branch failure'));
          } else {
            response.complete(const [
              {'id': 'branch-late', 'name': 'Поздний филиал'},
            ]);
          }

          await expectLater(loading, completes);
          expect(controller.branches, isEmpty);
          expect(controller.loadingBranches, isTrue);
          expect(controller.branchesError, isNull);
          expect(controller.staff, originalStaff);
          expect(controller.draft.email, originalEmail);
          expect(controller.saving, isFalse);
        },
      );
    }

    for (final fails in const [false, true]) {
      test(
        'ignores a late provision ${fails ? 'error' : 'result'} after disposal',
        () async {
          final response = Completer<Map<String, dynamic>>();
          final controller = _controller(
            _StaffApi(provisionResponse: response),
            _staff(),
          );
          final originalStaff = Map<String, dynamic>.from(controller.staff);
          final originalEmail = controller.draft.email;

          final provision = controller.provisionAccess(
            email: 'late@example.test',
            password: 'late-password',
          );
          controller.dispose();
          if (fails) {
            response.completeError(StateError('late provision failure'));
            await expectLater(provision, throwsStateError);
          } else {
            response.complete({
              ...originalStaff,
              'email': 'late@example.test',
              'is_app_account': true,
            });
            await expectLater(provision, completes);
          }

          expect(controller.branches, isEmpty);
          expect(controller.loadingBranches, isTrue);
          expect(controller.branchesError, isNull);
          expect(controller.staff, originalStaff);
          expect(controller.draft.email, originalEmail);
          expect(controller.saving, isFalse);
        },
      );
    }

    for (final fails in const [false, true]) {
      test(
        'keeps save state unchanged after a late ${fails ? 'error' : 'result'} and disposal',
        () async {
          final response = Completer<Map<String, dynamic>>();
          final controller = _controller(
            _StaffApi(patchResponse: response),
            _staff(),
          );
          final originalStaff = Map<String, dynamic>.from(controller.staff);
          final originalEmail = controller.draft.email;

          final save = controller.save();
          expect(controller.saving, isTrue);
          controller.dispose();
          if (fails) {
            response.completeError(StateError('late save failure'));
            await expectLater(save, throwsStateError);
          } else {
            response.complete(originalStaff);
            await expectLater(save, completes);
          }

          expect(controller.branches, isEmpty);
          expect(controller.loadingBranches, isTrue);
          expect(controller.branchesError, isNull);
          expect(controller.staff, originalStaff);
          expect(controller.draft.email, originalEmail);
          expect(controller.saving, isTrue);
        },
      );
    }

    test('saves the exact profile payload without access keys', () async {
      final api = _StaffApi();
      final controller = _controller(api, _staff());
      controller.draft
        ..firstName = '  Ольга  '
        ..lastName = '  Смирнова  '
        ..canonicalPhone = '+79995554433'
        ..email = 'forbidden@example.test'
        ..position = '  Старший администратор  '
        ..role = 'director'
        ..status = 'working'
        ..birthday = '1990-06-01';

      await controller.save();

      expect(api.patches['/crm/staff/staff-a'], {
        'firstName': 'Ольга',
        'lastName': 'Смирнова',
        'phone': '+79995554433',
        'position': 'Старший администратор',
        'status': 'working',
        'branchIds': ['branch-a'],
        'customDataPatch': {'birthday': '1990-06-01'},
      });
      expect(
        api.patches['/crm/staff/staff-a']!.keys,
        isNot(containsAll(const ['email', 'password', 'role'])),
      );
    });

    test('rejects an empty branch selection without a mutation', () async {
      final api = _StaffApi();
      final controller = _controller(api, _staff(branches: const []));

      await expectLater(
        controller.save(),
        throwsA(
          isA<StaffDetailValidationException>().having(
            (error) => error.message,
            'message',
            'Выберите хотя бы один филиал.',
          ),
        ),
      );
      expect(api.patches, isEmpty);
    });

    test(
      'requires first name, last name, and status before mutation',
      () async {
        for (final missingField in const ['firstName', 'lastName', 'status']) {
          final api = _StaffApi();
          final controller = _controller(api, _staff());
          switch (missingField) {
            case 'firstName':
              controller.draft.firstName = ' ';
            case 'lastName':
              controller.draft.lastName = ' ';
            case 'status':
              controller.draft.status = ' ';
          }

          await expectLater(
            controller.save(),
            throwsA(
              isA<StaffDetailValidationException>().having(
                (error) => error.message,
                'message',
                'Обязательное поле',
              ),
            ),
            reason: missingField,
          );
          expect(api.patches, isEmpty, reason: missingField);
        }
      },
    );

    test(
      'reads and provisions access through the existing service paths',
      () async {
        final api = _StaffApi();
        final controller = _controller(api, _staff());

        expect(await controller.loadCredentials(), {
          'email': 'managed@example.test',
          'password': 'managed-password',
        });
        await controller.provisionAccess(
          email: 'new@example.test',
          password: 'new-password',
        );

        expect(api.posts['/crm/staff/staff-a/access'], {
          'email': 'new@example.test',
          'password': 'new-password',
        });
      },
    );
  });

  group('StaffDetailDialog actions', () {
    for (final role in const ['manager', 'director']) {
      testWidgets('$role sees only authorized access actions', (tester) async {
        await _pumpDialog(
          tester,
          api: _StaffApi(),
          currentRole: role,
          staff: _staff(),
        );

        expect(
          find.text('Создать доступ'),
          role == 'director' ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Отключить сотрудника'),
          role == 'director' ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets('archived staff disables access and save but keeps restore', (
      tester,
    ) async {
      await _pumpDialog(
        tester,
        api: _StaffApi(),
        currentRole: 'director',
        staff: _staff(lifecycleState: 'archived'),
      );

      final access = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Создать доступ'),
      );
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Сохранить'),
      );
      final restore = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Восстановить сотрудника'),
      );

      expect(access.onPressed, isNull);
      expect(save.onPressed, isNull);
      expect(restore.onPressed, isNotNull);
    });

    testWidgets(
      'empty branch selection shows the exact snackbar and does not mutate',
      (tester) async {
        final api = _StaffApi();
        await _pumpDialog(
          tester,
          api: api,
          currentRole: 'director',
          staff: _staff(branches: const []),
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
        await tester.pump();

        expect(find.text('Выберите хотя бы один филиал.'), findsOneWidget);
        expect(api.patches, isEmpty);
      },
    );
  });
}
