import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/features/auth/data/models/release_gate_models.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/leads_widget.dart';

class _LeadBoardApi extends MagicApiClient {
  _LeadBoardApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  static const statusA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  static const statusB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  final boardQueries = <Map<String, dynamic>>[];

  Map<String, dynamic> _lead(String id, String name, String? statusId) => {
    'id': id,
    'statusId': statusId,
    'statusName': statusId == null ? 'Без статуса' : 'Статус',
    'firstName': name,
    'lastName': null,
    'phone': null,
    'email': null,
    'source': null,
    'notes': null,
    'assignedTo': null,
    'customData': <String, dynamic>{},
    'createdAt': '2026-07-18T10:00:00.000Z',
    'updatedAt': '2026-07-18T10:00:00.000Z',
  };

  Map<String, dynamic> _column({
    required String id,
    required String label,
    required String? nextCursor,
    required List<Map<String, dynamic>> items,
  }) => {
    'id': id,
    'name': label,
    'color': '#8B5CF6',
    'sortOrder': id == statusA ? 1 : (id == statusB ? 2 : 9999),
    'createdAt': '2026-07-18T10:00:00.000Z',
    'totalCount': 2,
    'nextCursor': nextCursor,
    'items': items,
  };

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/leads/board') {
      final query = Map<String, dynamic>.from(queryParameters ?? const {});
      boardQueries.add(query);
      final cursor = query['cursor']?.toString();
      if (cursor == null) {
        return <String, dynamic>{
              'columns': [
                _column(
                  id: statusA,
                  label: 'A',
                  nextCursor: 'cursor-a',
                  items: [_lead('a-1', 'A one', statusA)],
                ),
                _column(
                  id: statusB,
                  label: 'B',
                  nextCursor: 'cursor-b',
                  items: [_lead('b-1', 'B one', statusB)],
                ),
                _column(
                  id: 'unassigned',
                  label: 'Без статуса',
                  nextCursor: 'cursor-u',
                  items: [_lead('u-1', 'U one', null)],
                ),
              ],
              'totalCount': 6,
              'nextCursor': null,
            }
            as T;
      }
      if (query['statusId'] == statusA) {
        return <String, dynamic>{
              'columns': [
                _column(
                  id: statusA,
                  label: 'A',
                  nextCursor: null,
                  // Repeated boundary proves the UI dedupes within A.
                  items: [
                    _lead('a-1', 'A one', statusA),
                    _lead('a-2', 'A two', statusA),
                  ],
                ),
              ],
              'totalCount': 2,
              'nextCursor': null,
            }
            as T;
      }
      if (query['statusId'] == statusB) {
        return <String, dynamic>{
              'columns': [
                _column(
                  id: statusB,
                  label: 'B',
                  nextCursor: null,
                  items: [_lead('b-2', 'B two', statusB)],
                ),
              ],
              'totalCount': 2,
              'nextCursor': null,
            }
            as T;
      }
      return <String, dynamic>{
            'columns': [
              _column(
                id: 'unassigned',
                label: 'Без статуса',
                nextCursor: null,
                items: [_lead('u-2', 'U two', null)],
              ),
            ],
            'totalCount': 2,
            'nextCursor': null,
          }
          as T;
    }

    return switch (path) {
          '/crm/lead-statuses' => <String, dynamic>{
            'items': [
              {'id': statusA, 'name': 'A', 'color': '#8B5CF6'},
              {'id': statusB, 'name': 'B', 'color': '#8B5CF6'},
            ],
          },
          _ => <String, dynamic>{'items': <dynamic>[]},
        }
        as T;
  }
}

void main() {
  testWidgets(
    'loads, dedupes and advances each lead-board column independently',
    (tester) async {
      await initializeDateFormatting('ru');
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _LeadBoardApi();
      final realtime = StreamController<CrmChangedEvent>.broadcast();
      addTearDown(realtime.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            magicApiClientProvider.overrideWithValue(api),
            crmRealtimeProvider.overrideWith((ref) => realtime.stream),
            releaseGateStatusProvider.overrideWith(
              (ref) async => const ReleaseGateStatus(
                role: 'manager',
                profileComplete: true,
                legalAccepted: true,
                deletionPending: false,
              ),
            ),
          ],
          child: const MaterialApp(home: LeadsWidget()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_more_rounded), findsNWidgets(3));
      await tester.tap(find.byIcon(Icons.expand_more_rounded).first);
      await tester.pumpAndSettle();
      expect(api.boardQueries[1]['statusId'], _LeadBoardApi.statusA);
      expect(api.boardQueries[1].containsKey('unassigned'), false);
      expect(find.text('A one'), findsOneWidget);
      expect(find.text('A two'), findsOneWidget);

      // A has no cursor now, so the first remaining button belongs to B.
      await tester.tap(find.byIcon(Icons.expand_more_rounded).first);
      await tester.pumpAndSettle();
      expect(api.boardQueries[2]['statusId'], _LeadBoardApi.statusB);
      expect(find.text('A two'), findsOneWidget);
      expect(find.text('B two'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.expand_more_rounded).first);
      await tester.pumpAndSettle();
      expect(api.boardQueries[3]['unassigned'], true);
      expect(api.boardQueries[3].containsKey('statusId'), false);
      expect(find.text('A two'), findsOneWidget);
      expect(find.text('B two'), findsOneWidget);
      expect(find.text('U two'), findsOneWidget);
    },
  );
}
