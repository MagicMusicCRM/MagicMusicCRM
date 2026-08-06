import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/security/access_management.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/access_editor_sheet.dart';

class _FakeAccessSource implements AccessManagementDataSource {
  String role = 'client';
  int version = 1;
  int getCalls = 0;
  bool conflictNext = false;
  Map<String, Object?>? lastRoleCall;
  Map<String, Object?>? lastOverrideCall;

  @override
  Future<ManagedUserAccess> getUserAccess(String userId) async {
    getCalls++;
    return ManagedUserAccess(
      userId: userId,
      role: role,
      accessVersion: version,
      packageVersion: 4,
      capabilities: const [
        ManagedCapability(
          key: 'crm.client.read.basic',
          domain: 'crm',
          overrideMode: 'allow_deny',
          packageEffect: 'allow',
          overrideEffect: null,
          effectiveAllowed: true,
        ),
        ManagedCapability(
          key: 'schedule.attendance.write',
          domain: 'schedule',
          overrideMode: 'locked',
          packageEffect: 'deny',
          overrideEffect: null,
          effectiveAllowed: false,
        ),
      ],
    );
  }

  @override
  Future<void> assignRole({
    required String userId,
    required String role,
    required int expectedVersion,
    required bool resetOverridesConfirmed,
    required bool emergencySurface,
    required String reasonCode,
    required MagicMutationIdentity identity,
  }) async {
    lastRoleCall = {
      'userId': userId,
      'role': role,
      'expectedVersion': expectedVersion,
      'resetOverridesConfirmed': resetOverridesConfirmed,
      'emergencySurface': emergencySurface,
      'reasonCode': reasonCode,
      'idempotencyKey': identity.idempotencyKey,
    };
    if (conflictNext) {
      conflictNext = false;
      throw const MagicApiException(
        statusCode: 409,
        message: 'stale access version',
      );
    }
    this.role = role;
    version++;
  }

  @override
  Future<void> setOverride({
    required String userId,
    required String capabilityKey,
    required String effect,
    required int expectedVersion,
    required bool emergencySurface,
    required String reasonCode,
    required MagicMutationIdentity identity,
  }) async {
    lastOverrideCall = {
      'userId': userId,
      'capabilityKey': capabilityKey,
      'effect': effect,
      'expectedVersion': expectedVersion,
      'emergencySurface': emergencySurface,
      'reasonCode': reasonCode,
    };
    version++;
  }
}

Widget _host(String actorRole, _FakeAccessSource source) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(900, 900)),
      child: AccessEditorSheet(
        actorRole: actorRole,
        userId: '11111111-1111-4111-8111-111111111111',
        userLabel: 'Анна Петрова',
        dataSource: source,
      ),
    ),
  );
}

Future<void> _selectRole(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('access-role-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _confirmRoleChange(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('access-reason')),
    'access.review',
  );
  await tester.tap(find.byKey(const Key('access-reset-confirmation')));
  await tester.tap(find.byKey(const Key('access-save-role')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('access editor is a fullscreen route and system Back closes it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = _FakeAccessSource();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accessManagementServiceProvider.overrideWithValue(source)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => AccessEditorSheet.show(
                context,
                actorRole: 'director',
                userId: '11111111-1111-4111-8111-111111111111',
                userLabel: 'Анна Петрова',
              ),
              child: const Text('Открыть доступ'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть доступ'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('access-editor-surface'))).height,
      900,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Открыть доступ'), findsOneWidget);
  });

  testWidgets('Manager gets zero access controls', (tester) async {
    final source = _FakeAccessSource();
    await tester.pumpWidget(_host('manager', source));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('access-editor-forbidden')), findsOneWidget);
    expect(find.byKey(const Key('access-role-selector')), findsNothing);
    expect(find.byKey(const Key('access-save-role')), findsNothing);
    expect(source.getCalls, 0);
  });

  testWidgets(
    'Director sees lower roles, package/effective values and explicit reset',
    (tester) async {
      final source = _FakeAccessSource();
      await tester.pumpWidget(_host('director', source));
      await tester.pumpAndSettle();

      expect(find.text('Пакет роли · версия 4'), findsOneWidget);
      expect(find.textContaining('Пакет: включено'), findsOneWidget);
      expect(find.text('Администратор системы'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('access-reason')),
        'access.review',
      );
      await tester.tap(
        find.byKey(const Key('access-capability-crm.client.read.basic')),
      );
      await tester.pumpAndSettle();
      expect(source.lastOverrideCall, containsPair('effect', 'deny'));

      await _selectRole(tester, 'Управляющий');
      expect(
        find.byKey(const Key('access-role-reset-warning')),
        findsOneWidget,
      );
      await _confirmRoleChange(tester);

      expect(source.lastRoleCall, containsPair('role', 'manager'));
      expect(
        source.lastRoleCall,
        containsPair('resetOverridesConfirmed', true),
      );
      expect(source.lastRoleCall, containsPair('emergencySurface', false));
      expect(find.text('Изменения сохранены.'), findsOneWidget);
    },
  );

  testWidgets('system_admin emergency surface can assign every role', (
    tester,
  ) async {
    final source = _FakeAccessSource();
    await tester.pumpWidget(_host('system_admin', source));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('access-emergency-surface')), findsOneWidget);
    await _selectRole(tester, 'Администратор системы');
    await _confirmRoleChange(tester);

    expect(source.lastRoleCall, containsPair('role', 'system_admin'));
    expect(source.lastRoleCall, containsPair('emergencySurface', true));
  });

  testWidgets('409 refreshes server state without partial optimistic UI', (
    tester,
  ) async {
    final source = _FakeAccessSource()..conflictNext = true;
    await tester.pumpWidget(_host('director', source));
    await tester.pumpAndSettle();

    await _selectRole(tester, 'Управляющий');
    await _confirmRoleChange(tester);

    expect(source.role, 'client');
    expect(source.getCalls, 2);
    expect(
      find.text('Доступ уже изменён в другой сессии. Данные обновлены.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('access-role-selector')),
          )
          .initialValue,
      'client',
    );
  });
}
