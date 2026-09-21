import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';

class _PersonnelApi extends MagicApiClient {
  _PersonnelApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final requests = <String>[];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    requests.add(path);
    if (path == '/crm/staff/staff-a') {
      return <String, dynamic>{
            'id': 'staff-a',
            'role': 'manager',
            'position': 'Управляющий',
            'status': 'working',
            'customData': <String, dynamic>{},
            'profileId': 'profile-a',
            'profileUserId': 'user-a',
            'appRole': 'manager',
            'isAppAccount': true,
            'lifecycleState': 'active',
            'version': 1,
            'firstName': 'Анна',
            'lastName': 'Петрова',
            'phone': '+79990000000',
            'branches': <Map<String, dynamic>>[],
            'createdAt': '2026-09-20T00:00:00.000Z',
          }
          as T;
    }
    if (path == '/crm/teachers/teacher-a') {
      return <String, dynamic>{
            'id': 'teacher-a',
            'name': 'Мария Соколова',
            'phone': '+79991112233',
            'email': 'teacher@example.test',
            'app_role': 'teacher',
            'is_app_account': true,
            'lifecycle_state': 'active',
            'version': 1,
            'students_count': 18,
            'lessons_count': 42,
            'rating': 4.9,
            'branches': <Map<String, dynamic>>[
              {'id': 'branch-a', 'name': 'Центр'},
            ],
            'created_at': '2026-09-20T00:00:00.000Z',
          }
          as T;
    }
    return <String, dynamic>{'items': <dynamic>[]} as T;
  }
}

void main() {
  testWidgets('personnel link opens the existing staff card', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PersonnelApi();
    const snapshot = CapabilitySnapshot(
      accountId: 'account-a',
      role: 'manager',
      accessVersion: 1,
      capabilities: {
        'crm.client.read.basic',
        'schedule.lesson.read.assigned',
        'config.crm.read',
      },
      scopes: {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PersonnelWorkspace(
              snapshot: snapshot,
              initialLink: EntityLink.typed(
                entityType: EntityLinkType.user,
                entityId: 'staff-a',
                variant: 'staff',
                presentation: const EntityPresentationReference(
                  primary: 'Анна Петрова',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.requests, contains('/crm/staff/staff-a'));
    expect(find.text('Карточка сотрудника'), findsOneWidget);
    expect(find.text('Анна'), findsWidgets);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('personnel-detail-pane')), findsOneWidget);
    expect(find.byKey(const Key('staff-detail-embedded')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('personnel teacher link opens the full embedded teacher card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _PersonnelApi();
    const snapshot = CapabilitySnapshot(
      accountId: 'account-a',
      role: 'manager',
      accessVersion: 1,
      capabilities: {
        'crm.client.read.basic',
        'schedule.lesson.read.assigned',
        'config.crm.read',
      },
      scopes: {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PersonnelWorkspace(
              snapshot: snapshot,
              initialLink: EntityLink.typed(
                entityType: EntityLinkType.teacher,
                entityId: 'teacher-a',
                variant: 'personnel_teacher',
                presentation: const EntityPresentationReference(
                  primary: 'Мария Соколова',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.requests, contains('/crm/teachers/teacher-a'));
    expect(find.text('Карточка преподавателя'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('personnel-detail-pane')), findsOneWidget);
    expect(find.byKey(const Key('teacher-detail-embedded')), findsOneWidget);
    expect(find.text('Основные данные и доступ'), findsOneWidget);
    expect(find.text('Работа, филиалы и оплата'), findsOneWidget);
    expect(find.byKey(const Key('teacher-open-schedule')), findsOneWidget);
    expect(find.byKey(const Key('teacher-open-availability')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
