import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';

/// Фейк на шве API-клиента (НЕ `implements MagicCrmService` — его методы живут
/// на extension'ах и резолвятся статически, так что такой фейк не был бы
/// вызван вовсе). Отдаёт минимальные ответы всем эндпоинтам карточки и
/// перехватывает PATCH-тела сохранения.
class FakeCardApiClient extends MagicApiClient {
  FakeCardApiClient({
    this.lead,
    this.student,
    this.leadTasks = const [],
    this.subscriptionPackages = const [],
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  /// Сырой (camelCase, как с сервера) лид для GET /crm/leads/:id/card.
  final Map<String, dynamic>? lead;

  /// Сырой ученик для GET /crm/students/:id/card.
  final Map<String, dynamic>? student;

  /// Сырые задачи лид-карточки (camelCase, как toTaskDto).
  final List<Map<String, dynamic>> leadTasks;

  final List<Map<String, dynamic>> subscriptionPackages;

  Map<String, dynamic>? updateLeadBody;
  Map<String, dynamic>? updateStudentBody;
  final List<String> requests = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/legal/gate') {
      return <String, dynamic>{
            'role': 'admin',
            'profileComplete': true,
            'legalAccepted': true,
            'deletionPending': false,
          }
          as T;
    }
    if (path == '/settings/crm-custom-fields') {
      return <String, dynamic>{'fields': <dynamic>[]} as T;
    }
    if (path == '/admin/staff') {
      return <dynamic>[
            {
              'id': '55555555-5555-4555-8555-555555555555',
              'displayName': 'Мария Управляющая',
              'role': 'manager',
            },
          ]
          as T;
    }
    if (path == '/crm/subscription-packages') {
      return <String, dynamic>{'items': subscriptionPackages} as T;
    }
    if (lead != null && path == '/crm/leads/${lead!['id']}/card') {
      return <String, dynamic>{
            'lead': lead,
            'linkedStudents': <dynamic>[],
            'otherLeads': <dynamic>[],
            'comments': <dynamic>[],
            'tasks': leadTasks,
            'trials': <dynamic>[],
            'timeline': <dynamic>[],
          }
          as T;
    }
    if (student != null && path == '/crm/students/${student!['id']}/card') {
      return <String, dynamic>{
            'student': student,
            'groups': <dynamic>[],
            'lessons': <dynamic>[],
            'payments': <dynamic>[],
            'tasks': <dynamic>[],
            'comments': <dynamic>[],
            'expectedPayments': <dynamic>[],
            'balance': null,
            'subscriptions': <dynamic>[],
            'links': <dynamic>[],
            'timeline': <dynamic>[],
          }
          as T;
    }
    // Остальные списки/справочники карточки: пустой обобщённый ответ.
    return <String, dynamic>{'items': <dynamic>[]} as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (lead != null && path == '/crm/leads/${lead!['id']}') {
      requests.add('PATCH $path');
      updateLeadBody = Map<String, dynamic>.from(data as Map);
      return <String, dynamic>{'id': lead!['id']} as T;
    }
    if (student != null && path == '/crm/students/${student!['id']}') {
      updateStudentBody = Map<String, dynamic>.from(data as Map);
      return <String, dynamic>{'id': student!['id']} as T;
    }
    return <String, dynamic>{} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    requests.add('POST $path');
    if (lead != null &&
        path == '/crm/leads/${lead!['id']}/subscriptions/issue') {
      return <String, dynamic>{
            'student': {'id': 'student-from-${lead!['id']}'},
          }
          as T;
    }
    return <String, dynamic>{} as T;
  }
}

/// Поднимает карточку клиента как диалог поверх минимального приложения —
/// так `Navigator.pop` после сохранения закрывает именно карточку.
Future<void> pumpClientCard(
  WidgetTester tester, {
  required FakeCardApiClient api,
  required Map<String, dynamic> seed,
  String entityType = 'lead',
  List<StatusRecord>? statuses,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        magicApiClientProvider.overrideWithValue(api),
        crmRealtimeProvider.overrideWith(
          (ref) => const Stream<CrmChangedEvent>.empty(),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => ClientCard(
                    lead: seed,
                    entityType: entityType,
                    allStatuses: statuses,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Converted cards can keep harmless progress/animation frames scheduled
    // while both halves resolve. Drive a bounded amount of async UI time.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}
