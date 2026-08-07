import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';

typedef IdempotentCardCall = ({
  String path,
  Map<String, dynamic> data,
  MagicMutationIdentity identity,
});
typedef CardPostCall = ({String path, Map<String, dynamic> data});
typedef CardGetCall = ({String path, Map<String, dynamic> query});

/// Фейк на шве API-клиента (НЕ `implements MagicCrmService` — его методы живут
/// на extension'ах и резолвятся статически, так что такой фейк не был бы
/// вызван вовсе). Отдаёт минимальные ответы всем эндпоинтам карточки и
/// перехватывает PATCH-тела сохранения.
class FakeCardApiClient extends MagicApiClient {
  FakeCardApiClient({
    this.role = 'admin',
    this.lead,
    this.student,
    this.leadTasks = const [],
    this.sharedTasks = const [],
    this.sharedTaskHistory = const [],
    this.subscriptionPackages = const [],
    this.studentSubscriptions = const [],
    this.studentAccounts = const [],
    this.studentMovements = const [],
    this.studentTechnicalHistory = const [],
    this.studentLessons = const [],
    this.customFields = const [],
    this.sources = const [],
    this.branches = const [],
    this.teachers = const [],
    this.rooms = const [],
    this.scheduleSeries = const [],
    this.schedulePlans = const [],
    this.schedulePlanTrays = const {},
    this.scheduleMatrix = const [],
    this.replacementPreview,
    this.replacementResult,
    this.replacementFailures = 0,
    this.cancellationPreview,
    this.cancellationResult,
    this.cancellationFailures = 0,
    this.paymentReversalPreview,
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final String role;

  /// Сырой (camelCase, как с сервера) лид для GET /crm/leads/:id/card.
  final Map<String, dynamic>? lead;

  /// Сырой ученик для GET /crm/students/:id/card.
  final Map<String, dynamic>? student;

  /// Сырые задачи лид-карточки (camelCase, как toTaskDto).
  final List<Map<String, dynamic>> leadTasks;
  final List<Map<String, dynamic>> sharedTasks;
  final List<Map<String, dynamic>> sharedTaskHistory;

  final List<Map<String, dynamic>> subscriptionPackages;
  final List<Map<String, dynamic>> studentSubscriptions;
  final List<Map<String, dynamic>> studentAccounts;
  final List<Map<String, dynamic>> studentMovements;
  final List<Map<String, dynamic>> studentTechnicalHistory;
  final List<Map<String, dynamic>> studentLessons;
  final List<Map<String, dynamic>> customFields;
  final List<Map<String, dynamic>> sources;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> rooms;
  final List<Map<String, dynamic>> scheduleSeries;
  final List<Map<String, dynamic>> schedulePlans;
  final Map<String, Map<String, dynamic>> schedulePlanTrays;
  final List<Map<String, dynamic>> scheduleMatrix;
  final Map<String, dynamic>? replacementPreview;
  final Map<String, dynamic>? replacementResult;
  int replacementFailures;
  final Map<String, dynamic>? cancellationPreview;
  final Map<String, dynamic>? cancellationResult;
  int cancellationFailures;
  final Map<String, dynamic>? paymentReversalPreview;

  Map<String, dynamic>? updateLeadBody;
  Map<String, dynamic>? updateStudentBody;
  final List<String> requests = [];
  final List<String> getRequests = [];
  final List<CardGetCall> getCalls = [];
  final List<CardPostCall> postRequests = [];
  final List<IdempotentCardCall> idempotentRequests = [];
  int studentCardLoadCount = 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    getRequests.add(path);
    getCalls.add((path: path, query: {...?queryParameters}));
    if (path == '/legal/gate') {
      return <String, dynamic>{
            'role': role,
            'profileComplete': true,
            'legalAccepted': true,
            'deletionPending': false,
          }
          as T;
    }
    if (path == '/settings/crm-custom-fields') {
      return <String, dynamic>{'fields': customFields} as T;
    }
    if (path == '/crm/client-config/sources') {
      return <String, dynamic>{'items': sources} as T;
    }
    if (path == '/crm/branches') {
      return <String, dynamic>{'items': branches} as T;
    }
    if (path == '/crm/teachers') {
      return <String, dynamic>{'items': teachers} as T;
    }
    if (path == '/crm/rooms') {
      return <String, dynamic>{'items': rooms} as T;
    }
    if (path == '/crm/schedule-series') {
      return <String, dynamic>{'items': scheduleSeries} as T;
    }
    if (path == '/crm/schedule-plans') {
      return <String, dynamic>{'items': schedulePlans} as T;
    }
    final trayMatch = RegExp(
      r'^/crm/schedule-plans/([^/]+)/tray$',
    ).firstMatch(path);
    if (trayMatch != null) {
      final planId = trayMatch.group(1)!;
      return Map<String, dynamic>.from(
            schedulePlanTrays[planId] ??
                {
                  'planId': planId,
                  'items': <dynamic>[],
                  'hasPrevious': false,
                  'hasNext': false,
                  'previousCursor': null,
                  'nextCursor': null,
                },
          )
          as T;
    }
    if (path == '/crm/clients/search') {
      final query = queryParameters?['q']?.toString().toLowerCase() ?? '';
      final refs = <String, Map<String, dynamic>>{};
      for (final item in scheduleMatrix) {
        final studentId = item['studentId']?.toString();
        final studentName = item['studentName']?.toString() ?? '';
        if (studentId != null && studentName.toLowerCase().contains(query)) {
          refs['student:$studentId'] = {
            'ref': {'type': 'student', 'id': studentId},
            'label': studentName,
          };
        }
        final leadId = item['leadId']?.toString();
        final leadName = item['leadName']?.toString() ?? '';
        if (leadId != null && leadName.toLowerCase().contains(query)) {
          refs['lead:$leadId'] = {
            'ref': {'type': 'lead', 'id': leadId},
            'label': leadName,
          };
        }
      }
      return <String, dynamic>{'items': refs.values.toList()} as T;
    }
    if (path == '/crm/schedule/matrix') {
      final studentId = queryParameters?['studentId']?.toString();
      final leadId = queryParameters?['leadId']?.toString();
      final teacherId = queryParameters?['teacherId']?.toString();
      final roomId = queryParameters?['roomId']?.toString();
      final items = scheduleMatrix
          .where((item) {
            if (studentId != null) {
              return item['studentId']?.toString() == studentId;
            }
            if (leadId != null) {
              return item['leadId']?.toString() == leadId;
            }
            if (teacherId != null) {
              return item['teacherId']?.toString() == teacherId;
            }
            if (roomId != null) {
              return item['roomId']?.toString() == roomId;
            }
            return true;
          })
          .toList(growable: false);
      return <String, dynamic>{
            'items': items,
            'groups': <dynamic>[],
            'conflicts': <dynamic>[],
          }
          as T;
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
    if (path == '/crm/shared-tasks') {
      final entityType = queryParameters?['linkedEntityType']?.toString();
      final entityId = queryParameters?['linkedEntityId']?.toString();
      final items = sharedTasks
          .where((task) {
            final link = task['linkedEntity'];
            if (link is! Map) return entityType == null && entityId == null;
            return (entityType == null ||
                    link['type']?.toString() == entityType) &&
                (entityId == null || link['id']?.toString() == entityId);
          })
          .toList(growable: false);
      return <String, dynamic>{
            'items': items,
            'counters': {'open': items.length, 'overdue': 0},
          }
          as T;
    }
    if (path.startsWith('/crm/shared-tasks/') && path.endsWith('/history')) {
      return <String, dynamic>{'items': sharedTaskHistory} as T;
    }
    if (path == '/crm/client-pipelines') {
      return <String, dynamic>{
            'clientType': queryParameters?['clientType'],
            'branchId': queryParameters?['branchId'],
            'source': 'school',
            'schoolVersion': 1,
            'branchVersion': 0,
            'stages': [
              {
                'key': 'active',
                'label': 'Занимается',
                'style': 'green',
                'active': true,
                'allowedTransitions': const <String>[],
              },
            ],
            'remediationStatuses': const <Map<String, dynamic>>[],
          }
          as T;
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
      studentCardLoadCount++;
      return <String, dynamic>{
            'student': student,
            'groups': <dynamic>[],
            'lessons': studentLessons,
            'payments': <dynamic>[],
            'tasks': <dynamic>[],
            'comments': <dynamic>[],
            'expectedPayments': <dynamic>[],
            'balance': null,
            'subscriptions': studentSubscriptions,
            'links': <dynamic>[],
            'timeline': <dynamic>[],
          }
          as T;
    }
    if (student != null && path == '/crm/students/${student!['id']}/commerce') {
      final subscriptions = studentSubscriptions
          .map(_commerceSubscription)
          .toList(growable: false);
      num sumUnits(String key) => subscriptions.fold<num>(
        0,
        (sum, item) =>
            sum + num.parse((item['units'] as Map<String, dynamic>)[key]),
      );
      final expiries = subscriptions
          .map((item) => item['expiresAt'])
          .whereType<String>()
          .toList(growable: false);
      return <String, dynamic>{
            'projection': switch (role) {
              'manager' => 'manager_scoped',
              'director' => 'director_scoped',
              'system_admin' => 'system_admin_emergency',
              _ => 'admin_scoped',
            },
            'student': {
              'studentId': student!['id'],
              'accounts': studentAccounts
                  .map(
                    (item) => {
                      ...item,
                      'adjustmentsMinor': item['adjustmentsMinor'] ?? '0',
                    },
                  )
                  .toList(growable: false),
              'subscriptions': subscriptions,
              'movements': studentMovements,
              'technicalHistory': studentTechnicalHistory,
              'lessonBalance': {
                'activeSubscriptionCount': subscriptions
                    .where((item) => item['status'] == 'active')
                    .length,
                'total': sumUnits('total').toString(),
                'used': sumUnits('used').toString(),
                'reserved': sumUnits('reserved').toString(),
                'paid': sumUnits('paid').toString(),
                'available': sumUnits('available').toString(),
                'debts': studentAccounts
                    .where(
                      (item) =>
                          BigInt.parse(item['debtMinor']?.toString() ?? '0') >
                          BigInt.zero,
                    )
                    .map(
                      (item) => {
                        'currencyCode': item['currencyCode'],
                        'amountMinor': item['debtMinor'],
                      },
                    )
                    .toList(growable: false),
                'nextPaymentAt': null,
                'expiresAt': expiries.isEmpty ? null : expiries.first,
              },
            },
          }
          as T;
    }
    // Остальные списки/справочники карточки: пустой обобщённый ответ.
    return <String, dynamic>{'items': <dynamic>[]} as T;
  }

  Map<String, dynamic> _commerceSubscription(Map<String, dynamic> item) {
    final packagePrice = item['packagePrice'];
    final priceMinor = packagePrice is num
        ? (packagePrice * 100).round().toString()
        : '0';
    final total = item['lessonsTotal'] as num? ?? 0;
    final used = item['lessonsUsed'] as num? ?? 0;
    final reserved = item['lessonsReserved'] as num? ?? 0;
    final paid = item['lessonsPaid'] as num? ?? total;
    return {
      'id': item['id'],
      'status': item['status'] ?? 'active',
      'startsAt': item['startsAt'] ?? '2026-01-01T00:00:00.000Z',
      'expiresAt': item['expiresAt'],
      'units': {
        'total': total.toString(),
        'used': used.toString(),
        'reserved': reserved.toString(),
        'paid': paid.toString(),
        'available': (paid - used - reserved).clamp(0, paid).toString(),
        'remaining': (total - used).toString(),
      },
      'financial': {
        'actualPaidMinor': item['paidMinor']?.toString() ?? priceMinor,
        'obligationMinor': priceMinor,
        'debtMinor': item['debtMinor']?.toString() ?? '0',
        'overpaymentMinor': '0',
        'nextPaymentAt': null,
      },
      'terms': {
        'displayName': item['packageName'] ?? 'Абонемент',
        'validityDays': null,
        'basePriceMinor': priceMinor,
        'finalPriceMinor': priceMinor,
        'currencyCode': 'RUB',
        'discount': {'type': 'none'},
      },
      'installments': <dynamic>[],
    };
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
    if (RegExp(r'^/crm/schedule-plans/[^/]+$').hasMatch(path)) {
      return <String, dynamic>{'version': 2} as T;
    }
    return <String, dynamic>{} as T;
  }

  @override
  Future<T> patchIdempotent<T>(
    String path, {
    required MagicMutationIdentity identity,
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final body = Map<String, dynamic>.from(data as Map);
    idempotentRequests.add((path: path, data: body, identity: identity));
    requests.add('PATCH $path');
    return <String, dynamic>{'version': 2} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    requests.add('POST $path');
    postRequests.add((
      path: path,
      data: data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
    ));
    if (replacementPreview != null && path.endsWith('/replace/preview')) {
      return Map<String, dynamic>.from(replacementPreview!) as T;
    }
    if (cancellationPreview != null && path.endsWith('/cancel/preview')) {
      return Map<String, dynamic>.from(cancellationPreview!) as T;
    }
    if (paymentReversalPreview != null && path.endsWith('/reversal/preview')) {
      return Map<String, dynamic>.from(paymentReversalPreview!) as T;
    }
    if (path.endsWith('/end/preview')) {
      return <String, dynamic>{
            'previewToken': 'schedule-plan-preview-token',
            'previewExpiresAt': '2026-08-07T12:00:00.000Z',
            'impact': {
              'futureUnsettledLessons': 2,
              'activeReservations': 2,
              'reservedUnits': '2.00',
              'preservedTerminalLessons': 3,
            },
          }
          as T;
    }
    if (path == '/crm/schedule-plans') {
      return <String, dynamic>{'id': 'created-plan', 'version': 1} as T;
    }
    if (lead != null &&
        path == '/crm/leads/${lead!['id']}/subscriptions/issue') {
      return <String, dynamic>{
            'student': {'id': 'student-from-${lead!['id']}'},
          }
          as T;
    }
    return <String, dynamic>{} as T;
  }

  @override
  Future<T> postIdempotent<T>(
    String path, {
    required MagicMutationIdentity identity,
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final body = Map<String, dynamic>.from(data as Map);
    idempotentRequests.add((path: path, data: body, identity: identity));
    requests.add('POST $path');
    if (path.endsWith('/replace')) {
      if (replacementFailures > 0) {
        replacementFailures--;
        throw const MagicApiException(
          message: 'Соединение прервано после отправки.',
        );
      }
      return Map<String, dynamic>.from(
            replacementResult ?? const <String, dynamic>{},
          )
          as T;
    }
    if (path.endsWith('/cancel')) {
      if (cancellationFailures > 0) {
        cancellationFailures--;
        throw const MagicApiException(
          message: 'Соединение прервано после отправки.',
        );
      }
      return Map<String, dynamic>.from(
            cancellationResult ?? const <String, dynamic>{},
          )
          as T;
    }
    if (path.endsWith('/end')) {
      return <String, dynamic>{'status': 'ended', 'version': 2} as T;
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
