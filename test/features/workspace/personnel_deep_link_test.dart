import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';

import '../../support/modal_layout_evidence.dart';

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
            'firstName': 'Мария',
            'lastName': 'Соколова',
            'phone': '+79991112233',
            'email': 'teacher@example.test',
            'profileUserId': 'user-teacher-a',
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
    if (path == '/crm/teachers/teacher-a/lifecycle-history') {
      return <String, dynamic>{
            'items': [
              {
                'id': 'lifecycle-a',
                'operation': 'offboard',
                'reasonText': 'Завершение работы',
                'createdAt': '2026-09-22T10:00:00Z',
              },
            ],
            'activity': [
              {
                'id': 'audit-a',
                'action': 'crm.teacher_availability_replaced',
                'createdAt': '2026-09-23T10:00:00Z',
              },
            ],
          }
          as T;
    }
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': [
              {'id': 'branch-a', 'name': 'Центр'},
            ],
          }
          as T;
    }
    if (path == '/crm/teachers') {
      return <String, dynamic>{
            'items': [
              {
                'id': 'teacher-a',
                'firstName': 'Мария',
                'lastName': 'Соколова',
                'status': 'active',
              },
            ],
          }
          as T;
    }
    if (path == '/crm/schedule-reference') {
      return <String, dynamic>{
            'branch': {
              'version': 1,
              'timezone': 'Europe/Moscow',
              'weekly': <Map<String, dynamic>>[],
              'exceptions': <Map<String, dynamic>>[],
            },
            'teacher': {
              'version': 4,
              'assignments': [
                {'branchId': 'branch-a'},
              ],
              'availability': [
                {
                  'id': 'rule-a',
                  'kind': 'recurring',
                  'weekday': 1,
                  'localStart': '10:00',
                  'localEnd': '18:00',
                  'validFrom': '2026-09-01',
                  'timezone': 'Europe/Moscow',
                },
              ],
            },
          }
          as T;
    }
    return <String, dynamic>{'items': <dynamic>[]} as T;
  }
}

void main() {
  setUpAll(loadModalFonts);

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
        'config.crm.edit',
      },
      scopes: {},
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: ProviderScope(
          overrides: [
            magicApiClientProvider.overrideWithValue(api),
            capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
          ],
          child: MaterialApp(
            theme: AppTheme.production,
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
      ),
    );
    await tester.pumpAndSettle();
    await captureModalLayout(tester, 'windows-staff-card-overview');

    expect(api.requests, contains('/crm/staff/staff-a'));
    expect(find.textContaining('Карточка сотрудника ·'), findsOneWidget);
    expect(find.text('Анна'), findsWidgets);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('personnel-detail-pane')), findsOneWidget);
    expect(find.byKey(const Key('staff-detail-embedded')), findsOneWidget);
    expect(
      find.byKey(const Key('staff-detail-save')).hitTestable(),
      findsOneWidget,
    );
    for (final section in const [
      'profile',
      'employment',
      'access',
      'history',
    ]) {
      expect(find.byKey(Key('staff-card-$section')), findsOneWidget);
    }
    expect(
      find.byKey(const Key('staff-personnel-section-access')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(430, 932);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('staff-detail-embedded')), findsOneWidget);
    expect(
      find.byKey(const Key('staff-detail-save')).hitTestable(),
      findsOneWidget,
    );
    await captureModalLayout(tester, 'mobile-staff-card-overview');
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
      role: 'director',
      accessVersion: 1,
      capabilities: {
        'crm.client.read.basic',
        'schedule.lesson.read.assigned',
        'config.crm.read',
        'config.crm.edit',
        'commerce.teacher_payroll.write',
      },
      scopes: {},
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: evidenceRootKey,
        child: ProviderScope(
          overrides: [
            magicApiClientProvider.overrideWithValue(api),
            capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
          ],
          child: MaterialApp(
            theme: AppTheme.production,
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
      ),
    );
    await tester.pumpAndSettle();
    await captureModalLayout(tester, 'windows-teacher-card-overview');

    expect(api.requests, contains('/crm/teachers/teacher-a'));
    expect(find.textContaining('Карточка преподавателя ·'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('personnel-detail-pane')), findsOneWidget);
    expect(find.byKey(const Key('teacher-detail-embedded')), findsOneWidget);
    expect(
      find.byKey(const Key('teacher-detail-save')).hitTestable(),
      findsOneWidget,
    );
    for (final section in const [
      'profile',
      'schedule',
      'employment',
      'access',
      'history',
    ]) {
      expect(find.byKey(Key('teacher-card-$section')), findsOneWidget);
    }
    expect(
      find.byKey(const Key('teacher-personnel-section-access')),
      findsNothing,
    );
    expect(find.byKey(const Key('teacher-open-schedule')), findsOneWidget);
    expect(find.byKey(const Key('teacher-open-availability')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('teacher-card-schedule')));
    await tester.pumpAndSettle();
    await captureModalLayout(tester, 'windows-teacher-card-availability');
    expect(api.requests, contains('/crm/branches'));
    expect(api.requests, contains('/crm/teachers'));
    expect(api.requests, contains('/crm/schedule-reference'));
    expect(find.text('Доступность преподавателя'), findsOneWidget);
    expect(
      find.byKey(const Key('teacher-schedule-fixed-person')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('teacher-availability-add-1')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('teacher-availability-add-1')),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.text('Недоступность по датам'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('teacher-card-employment')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('teacher-rate-change-confirmation')),
      findsOneWidget,
    );
    await captureModalLayout(tester, 'windows-teacher-card-rate-guard');
    await tester.ensureVisible(find.byKey(const Key('teacher-card-access')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('teacher-personal-access')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('teacher-card-history')));
    await tester.pumpAndSettle();
    expect(api.requests, contains('/crm/teachers/teacher-a/lifecycle-history'));
    expect(find.text('График и занятые периоды изменены'), findsOneWidget);
    expect(find.text('Карточка архивирована'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(430, 932);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('teacher-card-profile')));
    await tester.pumpAndSettle();
    await captureModalLayout(tester, 'mobile-teacher-card-overview');
    expect(find.byKey(const Key('teacher-detail-embedded')), findsOneWidget);
    expect(
      find.byKey(const Key('teacher-detail-save')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('teacher card does not load restricted schedule references', (
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
      capabilities: {'crm.client.read.basic'},
      scopes: {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicApiClientProvider.overrideWithValue(api),
          capabilitySnapshotProvider.overrideWith((ref) async => snapshot),
        ],
        child: MaterialApp(
          theme: AppTheme.production,
          home: Scaffold(
            body: PersonnelWorkspace(
              snapshot: snapshot,
              initialLink: EntityLink.typed(
                entityType: EntityLinkType.teacher,
                entityId: 'teacher-a',
                variant: 'personnel_teacher',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('teacher-card-profile')), findsOneWidget);
    expect(find.byKey(const Key('teacher-card-schedule')), findsNothing);
    expect(api.requests, isNot(contains('/crm/schedule-reference')));
    expect(tester.takeException(), isNull);
  });
}
