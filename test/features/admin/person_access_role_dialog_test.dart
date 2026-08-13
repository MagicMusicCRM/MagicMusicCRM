import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/security/access_management.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/person_access_role_dialog.dart';

class _AccessSource implements AccessManagementDataSource {
  String? assignedRole;
  int? expectedVersion;
  bool? resetConfirmed;
  bool? emergencySurface;
  String? reasonCode;

  @override
  Future<ManagedUserAccess> getUserAccess(String userId) async {
    return ManagedUserAccess(
      userId: userId,
      role: 'admin',
      accessVersion: 7,
      packageVersion: 3,
      capabilities: const [],
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
    assignedRole = role;
    this.expectedVersion = expectedVersion;
    resetConfirmed = resetOverridesConfirmed;
    this.emergencySurface = emergencySurface;
    this.reasonCode = reasonCode;
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
  }) => throw UnimplementedError();
}

void main() {
  test('role options stay below the actor and match the card type', () {
    expect(personAccessRoleOptions(actorRole: 'director', teacher: false), [
      'admin',
      'manager',
    ]);
    expect(personAccessRoleOptions(actorRole: 'director', teacher: true), [
      'teacher',
      'admin',
      'manager',
    ]);
    expect(personAccessRoleOptions(actorRole: 'system_admin', teacher: false), [
      'admin',
      'manager',
      'director',
    ]);
  });

  testWidgets('card role editor uses the canonical versioned access command', (
    tester,
  ) async {
    final source = _AccessSource();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PersonAccessRoleDialog(
              actorRole: 'director',
              userId: 'user-a',
              personLabel: 'Ольга Смирнова',
              teacher: false,
              dataSource: source,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('person-access-role-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Управляющий').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('person-access-reset-confirmation')));
    await tester.tap(find.byKey(const Key('person-access-role-save')));
    await tester.pumpAndSettle();

    expect(source.assignedRole, 'manager');
    expect(source.expectedVersion, 7);
    expect(source.resetConfirmed, isTrue);
    expect(source.emergencySurface, isFalse);
    expect(source.reasonCode, 'crm.person_card.role_change');
  });
}
