import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/branch_form_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_room_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/room_lifecycle_dialog.dart';

class _RoomManagementApi extends MagicApiClient {
  _RoomManagementApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final rooms = <Map<String, dynamic>>[];
  final archiveBodies = <String, Map<String, dynamic>>{};
  int _sequence = 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/rooms') {
      final includeArchived = queryParameters?['includeArchived'] == true;
      return <String, dynamic>{
            'items': rooms
                .where(
                  (room) =>
                      includeArchived || room['lifecycleState'] == 'active',
                )
                .map(Map<String, dynamic>.from)
                .toList(),
          }
          as T;
    }
    if (path == '/crm/branches/branch-a/disciplines' ||
        path == '/crm/disciplines') {
      return <String, dynamic>{'items': <Map<String, dynamic>>[]} as T;
    }
    final historyMatch = RegExp(
      r'^/crm/rooms/([^/]+)/history$',
    ).firstMatch(path);
    if (historyMatch != null) {
      return <String, dynamic>{'items': <Map<String, dynamic>>[]} as T;
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
    if (path == '/crm/rooms') {
      final body = Map<String, dynamic>.from(data! as Map);
      final room = <String, dynamic>{
        'id': 'room-${++_sequence}',
        'branchId': body['branchId'],
        'branchName': 'Сокол',
        'name': body['name'],
        'capacity': body['capacity'],
        'lifecycleState': 'active',
        'version': 1,
      };
      rooms.add(room);
      return Map<String, dynamic>.from(room) as T;
    }
    final previewMatch = RegExp(
      r'^/crm/rooms/([^/]+)/archive-preview$',
    ).firstMatch(path);
    if (previewMatch != null) {
      final room = _room(previewMatch.group(1)!);
      final occupied = room['name'] == 'Ансамблевая';
      return <String, dynamic>{
            'room': Map<String, dynamic>.from(room),
            'canArchive': !occupied,
            'canRestore': false,
            'blockers': occupied
                ? <Map<String, dynamic>>[
                    {
                      'code': 'FUTURE_LESSONS',
                      'label': 'Будущие занятия',
                      'count': 2,
                      'remediation': 'Перенесите или отмените будущие занятия.',
                    },
                  ]
                : <Map<String, dynamic>>[],
            'impact': const {
              'preservedHistory': {
                'lessons': 5,
                'completedLessons': 5,
                'endedSeries': 1,
                'endedPlans': 1,
              },
            },
          }
          as T;
    }
    final archiveMatch = RegExp(
      r'^/crm/rooms/([^/]+)/archive$',
    ).firstMatch(path);
    if (archiveMatch != null) {
      final id = archiveMatch.group(1)!;
      final body = Map<String, dynamic>.from(data! as Map);
      archiveBodies[id] = body;
      final room = _room(id);
      room['lifecycleState'] = 'archived';
      room['version'] = 2;
      room['archiveReason'] = body['reasonText'];
      return <String, dynamic>{'room': Map<String, dynamic>.from(room)} as T;
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final match = RegExp(r'^/crm/rooms/([^/]+)$').firstMatch(path);
    if (match == null) throw StateError('Unexpected PATCH $path');
    final room = _room(match.group(1)!);
    final body = Map<String, dynamic>.from(data! as Map);
    room.addAll(body);
    return Map<String, dynamic>.from(room) as T;
  }

  Map<String, dynamic> _room(String id) =>
      rooms.singleWhere((room) => room['id'] == id);
}

Finder _roomTile(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(ListTile));

Finder _roomAction(String name, String tooltip) =>
    find.descendant(of: _roomTile(name), matching: find.byTooltip(tooltip));

Future<void> _createRoom(
  WidgetTester tester, {
  required String name,
  required int capacity,
}) async {
  final roomHeader = find
      .ancestor(of: find.text('Аудитории филиала'), matching: find.byType(Row))
      .first;
  await tester.tap(
    find.descendant(
      of: roomHeader,
      matching: find.widgetWithText(FilledButton, 'Добавить'),
    ),
  );
  await tester.pumpAndSettle();
  final dialog = find.byType(CreateRoomDialog);
  await tester.enterText(
    find.descendant(
      of: dialog,
      matching: find.widgetWithText(TextFormField, 'Название *'),
    ),
    name,
  );
  await tester.enterText(
    find.descendant(
      of: dialog,
      matching: find.widgetWithText(TextFormField, 'Вместимость, человек'),
    ),
    '$capacity',
  );
  await tester.tap(
    find.descendant(
      of: dialog,
      matching: find.widgetWithText(FilledButton, 'Сохранить'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Director creates three rooms, edits one, protects occupied and archives free',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _RoomManagementApi();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [magicApiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: Scaffold(
              body: BranchFormDialog(
                branch: {
                  'id': 'branch-a',
                  'name': 'Сокол',
                  'address': 'Оборонная 30',
                  'utc_offset_minutes': 180,
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _createRoom(tester, name: 'Индивидуальная', capacity: 1);
      await _createRoom(tester, name: 'Парная', capacity: 2);
      await _createRoom(tester, name: 'Ансамблевая', capacity: 8);
      expect(api.rooms.map((room) => room['capacity']), [1, 2, 8]);
      expect(find.text('Индивидуальная'), findsOneWidget);
      expect(find.text('Парная'), findsOneWidget);
      expect(find.text('Ансамблевая'), findsOneWidget);

      await tester.tap(_roomAction('Парная', 'Редактировать'));
      await tester.pumpAndSettle();
      final editDialog = find.byType(CreateRoomDialog);
      final nameField = find.descendant(
        of: editDialog,
        matching: find.widgetWithText(TextFormField, 'Название *'),
      );
      final capacityField = find.descendant(
        of: editDialog,
        matching: find.widgetWithText(TextFormField, 'Вместимость, человек'),
      );
      await tester.enterText(nameField, 'Парная обновлённая');
      await tester.enterText(capacityField, '3');
      await tester.tap(
        find.descendant(
          of: editDialog,
          matching: find.widgetWithText(FilledButton, 'Сохранить'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Парная обновлённая'), findsOneWidget);
      expect(find.text('Вместимость: 3'), findsOneWidget);

      await tester.tap(
        _roomAction('Ансамблевая', 'Проверить связи и архивировать'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Будущие занятия: 2'), findsOneWidget);
      expect(find.text('История останется без изменений'), findsOneWidget);
      final occupiedCommit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'В архив'),
      );
      expect(occupiedCommit.onPressed, isNull);
      await tester.tap(
        find.descendant(
          of: find.byType(RoomLifecycleDialog),
          matching: find.widgetWithText(TextButton, 'Отмена'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        _roomAction('Индивидуальная', 'Проверить связи и архивировать'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Активных связей нет. Аудиторию можно архивировать.'),
        findsOneWidget,
      );
      expect(find.text('Все занятия: 5'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Причина архивации *'),
        'Освобождение помещения',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'В архив'));
      await tester.pumpAndSettle();

      expect(find.text('Индивидуальная'), findsNothing);
      expect(api.archiveBodies['room-1'], {
        'expectedVersion': 1,
        'confirm': true,
        'reasonText': 'Освобождение помещения',
        'effectiveDate': isA<String>(),
      });
      expect(api.archiveBodies.containsKey('room-3'), isFalse);
    },
  );
}
