import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/security/capability_shell.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/crm_nav_rbac.dart';

const _adminSnapshot = CapabilitySnapshot(
  accountId: '11111111-1111-4111-8111-111111111111',
  role: 'manager',
  accessVersion: 1,
  capabilities: {
    'crm.client.read.basic',
    'crm.client.write',
    'schedule.lesson.read.assigned',
    'schedule.lesson.write',
    'workflow.task.read',
    'workflow.task.write',
  },
  scopes: {'client': 'branch', 'schedule': 'branch'},
);

const _revokedSnapshot = CapabilitySnapshot(
  accountId: '11111111-1111-4111-8111-111111111111',
  role: 'manager',
  accessVersion: 2,
  capabilities: {'crm.client.read.basic'},
  scopes: {'client': 'branch', 'schedule': 'branch'},
);

class _LiveSnapshotNotifier extends Notifier<CapabilitySnapshot> {
  @override
  CapabilitySnapshot build() => _adminSnapshot;

  void replace(CapabilitySnapshot value) => state = value;
}

final _liveSnapshotProvider =
    NotifierProvider<_LiveSnapshotNotifier, CapabilitySnapshot>(
      _LiveSnapshotNotifier.new,
    );

void main() {
  test('snapshot parser is account/accessVersion keyed and fail-closed', () {
    final snapshot = CapabilitySnapshot.fromJson(const {
      'accountId': 'account-1',
      'role': 'director',
      'accessVersion': 7,
      'capabilities': ['workflow.task.read'],
      'scopes': {'client': 'allBranches'},
    });

    expect(snapshot.cacheKey, 'account-1:7');
    expect(snapshot.allows('workflow.task.read'), isTrue);
    expect(snapshot.allows('commerce.school_finance.read'), isFalse);
  });

  test('navigation follows capabilities rather than the role label', () {
    expect(crmVisibleTabsForCapabilities(_adminSnapshot, isDesktop: true), [
      0,
      6,
      2,
      3,
    ]);

    final directorCapabilities = CapabilitySnapshot(
      accountId: _adminSnapshot.accountId,
      role: 'admin',
      accessVersion: 3,
      capabilities: const {
        'crm.client.read.basic',
        'schedule.lesson.read.assigned',
        'workflow.task.read',
        'report.status.read',
        'system.settings.manage',
        'commerce.school_finance.read',
      },
      scopes: const {'client': 'allBranches', 'schedule': 'allBranches'},
    );
    expect(
      crmVisibleTabsForCapabilities(directorCapabilities, isDesktop: true),
      [0, 1, 2, 3, 4, 5, 6, 7],
    );
  });

  testWidgets('new accessVersion recreates shell and removes sensitive UI', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        capabilitySnapshotProvider.overrideWith(
          (ref) async => ref.watch(_liveSnapshotProvider),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: CapabilityShellGate(
            builder: (_, snapshot) => Scaffold(
              body: Column(
                children: [
                  Text('version:${snapshot.accessVersion}'),
                  if (snapshot.allows('workflow.task.write'))
                    const Text('Чувствительное действие'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('version:1'), findsOneWidget);
    expect(find.text('Чувствительное действие'), findsOneWidget);

    container.read(_liveSnapshotProvider.notifier).replace(_revokedSnapshot);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('version:2'), findsOneWidget);
    expect(find.text('Чувствительное действие'), findsNothing);
  });
}
