import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/room_lifecycle_dialog.dart';

class RoomLifecycleTestApi extends MagicApiClient {
  RoomLifecycleTestApi({required this.blockers})
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final List<Map<String, dynamic>> blockers;
  Map<String, dynamic>? archiveBody;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/rooms/room-a/history') {
      return <String, dynamic>{'items': const <Map<String, dynamic>>[]} as T;
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/rooms/room-a/archive-preview') {
      return <String, dynamic>{
            'room': {
              'id': 'room-a',
              'name': 'Класс 1',
              'lifecycleState': 'active',
              'version': 1,
            },
            'canArchive': blockers.isEmpty,
            'canRestore': false,
            'blockers': blockers,
            'impact': const {
              'preservedHistory': {
                'lessons': 8,
                'completedLessons': 6,
                'endedSeries': 2,
                'endedPlans': 1,
              },
            },
          }
          as T;
    }
    if (path == '/crm/rooms/room-a/archive') {
      archiveBody = Map<String, dynamic>.from(data! as Map);
      return <String, dynamic>{
            'room': {
              'id': 'room-a',
              'lifecycleState': 'archived',
              'version': 2,
            },
          }
          as T;
    }
    throw StateError('Unexpected POST $path');
  }
}

Future<void> pumpRoomLifecycleDialog(
  WidgetTester tester,
  RoomLifecycleTestApi api,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [magicApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const RoomLifecycleDialog(
                    room: {
                      'id': 'room-a',
                      'name': 'Класс 1',
                      'lifecycle_state': 'active',
                      'version': 1,
                    },
                  ),
                ),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('room archive is disabled while a scheduling blocker remains', (
    tester,
  ) async {
    final api = RoomLifecycleTestApi(
      blockers: const [
        {
          'code': 'FUTURE_LESSONS',
          'label': 'Будущие занятия',
          'count': 2,
          'remediation': 'Перенесите или отмените будущие занятия.',
        },
      ],
    );
    await pumpRoomLifecycleDialog(tester, api);

    expect(find.text('Сначала устраните блокеры'), findsOneWidget);
    expect(find.text('Будущие занятия: 2'), findsOneWidget);
    final commit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'В архив'),
    );
    expect(commit.onPressed, isNull);
  });

  testWidgets('safe room archive sends explicit version and reason', (
    tester,
  ) async {
    final api = RoomLifecycleTestApi(blockers: const []);
    await pumpRoomLifecycleDialog(tester, api);

    expect(
      find.text('Активных связей нет. Аудиторию можно архивировать.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина архивации *'),
      'Ремонт класса',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'В архив'));
    await tester.pumpAndSettle();

    expect(api.archiveBody, {
      'expectedVersion': 1,
      'confirm': true,
      'reasonText': 'Ремонт класса',
      'effectiveDate': isA<String>(),
    });
    expect(find.byType(RoomLifecycleDialog), findsNothing);
  });
}
