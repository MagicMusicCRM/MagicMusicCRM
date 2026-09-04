import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/schedule_plan_row_removal_flow.dart';

void main() {
  testWidgets('previews signed impact before committing a row removal', (
    tester,
  ) async {
    final api = _RowRemovalApi();
    bool? result;

    await _pumpLauncher(
      tester,
      width: 1440,
      platform: TargetPlatform.windows,
      onPressed: (context) async {
        result = await SchedulePlanRowRemovalFlow(
          service: MagicCrmService(api),
          onInvalidated: () async {},
        ).remove(context, plan: _plan, row: _row);
      },
    );

    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('magic-sheet-desktop')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('schedule-plan-row-removal-reason')),
      'Смена преподавателя',
    );
    await tester.tap(find.byKey(const Key('schedule-plan-row-removal-submit')));
    await tester.pumpAndSettle();

    expect(api.previewData, {
      'expectedVersion': 4,
      'reasonText': 'Смена преподавателя',
    });
    expect(find.text('С 10.09.2026'), findsOneWidget);
    expect(find.text('Будет отменено будущих занятий: 3'), findsOneWidget);
    expect(find.text('Освободится активных резервов: 3'), findsOneWidget);
    expect(find.text('Завершённых занятий сохранится: 2'), findsOneWidget);
    expect(find.text('Изменённых занятий сохранится: 1'), findsOneWidget);
    expect(find.text('История проведённых занятий сохранится'), findsOneWidget);

    final confirm = find.byKey(const Key('schedule-plan-row-removal-confirm'));
    await tester.tap(confirm);
    await tester.pump();
    await tester.tap(find.byKey(const Key('schedule-plan-row-removal-submit')));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(result, isTrue);
    expect(api.commitData, {
      'expectedVersion': 4,
      'effectiveFrom': '2026-09-10',
      'reasonText': 'Смена преподавателя',
      'previewToken': 'signed-row-preview',
      'confirm': true,
    });
    expect(api.identity?.idempotencyKey, isNotEmpty);
  });

  testWidgets('uses the draggable sheet with close control on a phone', (
    tester,
  ) async {
    await _pumpLauncher(
      tester,
      width: 390,
      platform: TargetPlatform.android,
      onPressed: (context) => SchedulePlanRowRemovalFlow(
        service: MagicCrmService(_RowRemovalApi()),
        onInvalidated: () async {},
      ).remove(context, plan: _plan, row: _row),
    );

    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('magic-sheet-mobile')), findsOneWidget);
    expect(find.byKey(const ValueKey('magic-sheet-handle')), findsOneWidget);
    expect(find.byKey(const ValueKey('magic-modal-close')), findsOneWidget);
  });

  test('maps row-removal conflicts to exact Russian messages', () {
    expect(
      schedulePlanRowRemovalMessage('SCHEDULE_PLAN_VERSION_STALE'),
      'Расписание уже изменилось. Я обновил данные — проверьте строку ещё раз.',
    );
    expect(
      schedulePlanRowRemovalMessage('SCHEDULE_PLAN_ROW_PREVIEW_INVALID'),
      'Состав занятий изменился. Повторите предварительную проверку.',
    );
    expect(
      schedulePlanRowRemovalMessage('SCHEDULE_PLAN_ROW_HAS_NO_FUTURE_BOUNDARY'),
      'Укажите дату, с которой строка перестаёт действовать.',
    );
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  required double width,
  required TargetPlatform platform,
  required Future<void> Function(BuildContext context) onPressed,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onPressed(context),
            child: const Text('Удалить'),
          ),
        ),
      ),
    ),
  );
}

final _plan = SchedulePlan.fromMap(const {
  'id': 'plan-a',
  'title': 'Вокал',
  'kind': 'individual',
  'studentId': 'student-1',
  'activeFrom': '2026-09-01',
  'status': 'active',
  'version': 4,
  'rows': [],
  'participants': [],
});

final _row = SchedulePlanRow.fromMap(const {
  'id': 'series-a',
  'teacherId': 'teacher-1',
  'teacherName': 'Мария Иванова',
  'roomId': 'room-1',
  'roomName': 'Класс 1',
  'branchId': 'branch-1',
  'branchName': 'Сокол',
  'weekday': 4,
  'beginTime': '16:00',
  'durationMinutes': 60,
  'validFrom': '2026-09-10',
  'validUntil': null,
  'active': true,
});

class _RowRemovalApi extends MagicApiClient {
  _RowRemovalApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  Map<String, dynamic>? previewData;
  Map<String, dynamic>? commitData;
  MagicMutationIdentity? identity;

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    previewData = Map<String, dynamic>.from(data! as Map);
    return <String, dynamic>{
          'plan': {'id': 'plan-a', 'title': 'Вокал', 'version': 4},
          'row': {
            'id': 'series-a',
            'validFrom': '2026-09-10',
            'validUntil': null,
          },
          'effectiveFrom': '2026-09-10',
          'impact': {
            'futureUnfinishedLessons': 3,
            'terminalLessonsPreserved': 2,
            'changedLessonsPreserved': 1,
            'activeReservationsToRelease': 3,
            'endsPlan': false,
          },
          'canConfirm': true,
          'confirmRequired': true,
          'previewToken': 'signed-row-preview',
          'previewExpiresAt': '2026-09-04T12:15:00.000Z',
        }
        as T;
  }

  @override
  Future<T> postIdempotent<T>(
    String path, {
    required MagicMutationIdentity identity,
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    this.identity = identity;
    commitData = Map<String, dynamic>.from(data! as Map);
    return <String, dynamic>{
          'id': 'plan-a',
          'seriesId': 'series-a',
          'status': 'active',
          'version': 5,
          'endsPlan': false,
          'cancelledLessons': 3,
          'releasedReservations': 3,
          'preservedTerminalLessons': 2,
          'preservedChangedLessons': 1,
          'replayed': false,
        }
        as T;
  }
}
