import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
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
    List<Map<String, dynamic>> studentSubscriptions = const [],
    this.studentAccounts = const [],
    this.studentMovements = const [],
    this.studentTechnicalHistory = const [],
    this.studentIndicators = const {},
    this.homeworks = const [],
    this.internalNote,
    this.operationalHistory = const [],
    this.studentTimeline = const [],
    Map<String, dynamic>? family,
    List<Map<String, dynamic>> linkedUsers = const [],
    List<Map<String, dynamic>> clientUserCandidates = const [],
    this.studentLessons = const [],
    this.customFields = const [],
    this.sources = const [],
    this.disciplines = const [],
    this.branches = const [],
    this.teachers = const [],
    this.rooms = const [],
    this.clientPipelineStages = const [
      {
        'key': 'active',
        'label': 'Занимается',
        'style': 'green',
        'active': true,
        'allowedTransitions': <String>[],
      },
    ],
    List<Map<String, dynamic>> scheduleSeries = const [],
    List<Map<String, dynamic>> schedulePlans = const [],
    this.schedulePlanTrays = const {},
    this.mutateSchedulePlanOnCreate = false,
    this.mutateSchedulePlanOnEnd = false,
    List<Map<String, dynamic>> schedulePlanConstraintPreviews = const [],
    this.scheduleMatrix = const [],
    this.replacementPreview,
    this.replacementResult,
    this.replacementFailures = 0,
    this.cancellationPreview,
    this.cancellationResult,
    this.cancellationFailures = 0,
    this.paymentReversalPreview,
    this.paymentCorrectionPreview,
    this.adjustmentReversalPreview,
    this.currentProfile = const {
      'id': 'current-user',
      'email': 'admin@example.test',
      'role': 'admin',
      'firstName': 'Анна',
      'lastName': 'Администратор',
    },
    this.failCurrentProfile = false,
    this.currentProfileGate,
  }) : studentSubscriptions = [
         for (final subscription in studentSubscriptions)
           Map<String, dynamic>.from(subscription),
       ],
       family = family == null ? null : Map<String, dynamic>.from(family),
       linkedUsers = [
         for (final item in linkedUsers) Map<String, dynamic>.from(item),
       ],
       clientUserCandidates = [
         for (final item in clientUserCandidates)
           Map<String, dynamic>.from(item),
       ],
       scheduleSeries = [
         for (final series in scheduleSeries) Map<String, dynamic>.from(series),
       ],
       schedulePlans = [
         for (final plan in schedulePlans) Map<String, dynamic>.from(plan),
       ],
       schedulePlanConstraintPreviews = [
         for (final preview in schedulePlanConstraintPreviews)
           Map<String, dynamic>.from(preview),
       ],
       super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final String role;

  /// Сырой (camelCase, как с сервера) лид для GET /crm/leads/:id/card.
  final Map<String, dynamic>? lead;

  /// Сырой ученик для GET /crm/students/:id/card.
  final Map<String, dynamic>? student;

  /// Сырые задачи лид-карточки (camelCase, как с сервера).
  final List<Map<String, dynamic>> leadTasks;
  final List<Map<String, dynamic>> sharedTasks;
  final List<Map<String, dynamic>> sharedTaskHistory;

  final List<Map<String, dynamic>> subscriptionPackages;
  final List<Map<String, dynamic>> studentSubscriptions;
  final List<Map<String, dynamic>> studentAccounts;
  final List<Map<String, dynamic>> studentMovements;
  final List<Map<String, dynamic>> studentTechnicalHistory;
  final Map<String, dynamic> studentIndicators;
  final List<Map<String, dynamic>> homeworks;
  Map<String, dynamic>? internalNote;
  final List<Map<String, dynamic>> operationalHistory;
  final List<Map<String, dynamic>> studentTimeline;
  Map<String, dynamic>? family;
  final List<Map<String, dynamic>> linkedUsers;
  final List<Map<String, dynamic>> clientUserCandidates;
  final List<Map<String, dynamic>> studentLessons;
  final List<Map<String, dynamic>> customFields;
  final List<Map<String, dynamic>> sources;
  final List<Map<String, dynamic>> disciplines;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> rooms;
  final List<Map<String, dynamic>> clientPipelineStages;
  final List<Map<String, dynamic>> scheduleSeries;
  final List<Map<String, dynamic>> schedulePlans;
  final Map<String, Map<String, dynamic>> schedulePlanTrays;
  final bool mutateSchedulePlanOnCreate;
  final bool mutateSchedulePlanOnEnd;
  final List<Map<String, dynamic>> schedulePlanConstraintPreviews;
  final List<Map<String, dynamic>> scheduleMatrix;
  final Map<String, dynamic>? replacementPreview;
  final Map<String, dynamic>? replacementResult;
  int replacementFailures;
  final Map<String, dynamic>? cancellationPreview;
  final Map<String, dynamic>? cancellationResult;
  int cancellationFailures;
  final Map<String, dynamic>? paymentReversalPreview;
  final Map<String, dynamic>? paymentCorrectionPreview;
  final Map<String, dynamic>? adjustmentReversalPreview;
  final Map<String, dynamic> currentProfile;
  final bool failCurrentProfile;
  final Future<Map<String, dynamic>>? currentProfileGate;

  Map<String, dynamic>? updateLeadBody;
  final List<Map<String, dynamic>> updateLeadBodies = [];
  Map<String, dynamic>? updateStudentBody;
  final List<Map<String, dynamic>> updateStudentBodies = [];
  Completer<void>? leadPatchGate;
  Completer<void>? studentPatchGate;
  Completer<void>? nextStudentCardGate;
  int studentPatchFailures = 0;
  int studentPatchConflicts = 0;
  int leadPatchConflicts = 0;
  int internalNotePutConflicts = 0;
  Map<String, dynamic>? updateInternalNoteBody;
  final List<Map<String, dynamic>> updateInternalNoteBodies = [];
  final List<String> requests = [];
  final List<String> getRequests = [];
  final List<CardGetCall> getCalls = [];
  final List<CardPostCall> postRequests = [];
  final List<CardPostCall> patchRequests = [];
  final List<IdempotentCardCall> idempotentRequests = [];
  final Map<String, String> _schedulePlanCreateIds = {};
  int studentCardLoadCount = 0;
  int leadBoardLoadCount = 0;
  final List<String> leadBoardQueries = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    getRequests.add(path);
    getCalls.add((path: path, query: {...?queryParameters}));
    if (path == '/profile/me') {
      if (failCurrentProfile) {
        throw const MagicApiException(message: 'Профиль недоступен.');
      }
      if (currentProfileGate != null) return await currentProfileGate! as T;
      return currentProfile as T;
    }
    if (path == '/legal/gate') {
      return <String, dynamic>{
            'role': role,
            'profileComplete': true,
            'legalAccepted': true,
            'deletionPending': false,
          }
          as T;
    }
    if (path == '/crm/client-config/fields') {
      final entityType = queryParameters?['entityType']?.toString();
      final items = <Map<String, dynamic>>[];
      for (var index = 0; index < customFields.length; index++) {
        final field = customFields[index];
        final rawEntity =
            field['entityType']?.toString() ?? field['entity']?.toString();
        final canonicalEntity = const {'lead', 'leads'}.contains(rawEntity)
            ? 'lead'
            : 'student';
        if (canonicalEntity != entityType) continue;
        items.add({
          'id':
              field['id'] ??
              '30000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
          'entityType': canonicalEntity,
          'key': field['key'],
          'label': field['label'],
          'valueType': field['valueType'] ?? field['type'] ?? 'text',
          'required': field['required'] == true,
          'isSystem': field['isSystem'] == true,
          'options': field['options'] ?? const [],
          'width': field['width'] ?? 'full',
          'placements': field['placements'] ?? const ['edit', 'card'],
        });
      }
      return <String, dynamic>{'items': items} as T;
    }
    if (path == '/crm/client-config/sources') {
      return <String, dynamic>{'items': sources} as T;
    }
    if (path == '/crm/disciplines') {
      return <String, dynamic>{'items': disciplines} as T;
    }
    if (path == '/crm/branches') {
      return <String, dynamic>{'items': branches} as T;
    }
    if (path == '/crm/leads/board') {
      leadBoardLoadCount++;
      leadBoardQueries.add(queryParameters?['q']?.toString() ?? '');
      return <String, dynamic>{'columns': <dynamic>[], 'totalCount': 0} as T;
    }
    if (path == '/crm/teachers') {
      return <String, dynamic>{'items': teachers} as T;
    }
    if (path == '/crm/rooms') {
      return <String, dynamic>{'items': rooms} as T;
    }
    if (path == '/crm/configuration/lesson-decisions') {
      return <String, dynamic>{
            'settlementTypes': const [
              {
                'stableKey': 'free_lesson',
                'label': 'Бесплатное занятие',
                'colorToken': 'warning',
                'hourShareBasisPoints': 0,
                'allowedContexts': ['cancel', 'reschedule', 'settle'],
                'active': true,
                'order': 0,
              },
            ],
            'teacherCompensationRules': const [
              {
                'stableKey': 'none',
                'label': 'Не оплачивать',
                'mode': 'none',
                'value': '0',
                'active': true,
                'order': 0,
              },
            ],
          }
          as T;
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
            <String, dynamic>{
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
    if (path == '/crm/homeworks') {
      return <String, dynamic>{'items': homeworks} as T;
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
            'stages': clientPipelineStages,
            'remediationStatuses': const <Map<String, dynamic>>[],
          }
          as T;
    }
    if (RegExp(
      r'^/crm/clients/(lead|student)/[^/]+/internal-note$',
    ).hasMatch(path)) {
      return Map<String, dynamic>.from(
            internalNote ?? const {'body': '', 'version': 0},
          )
          as T;
    }
    if (RegExp(
      r'^/crm/clients/(lead|student)/[^/]+/operational-history$',
    ).hasMatch(path)) {
      final requestedLimit = int.tryParse(
        queryParameters?['limit']?.toString() ?? '',
      );
      final limit = requestedLimit == null || requestedLimit < 1
          ? 10
          : requestedLimit;
      final cursor = queryParameters?['cursor']?.toString();
      final cursorIndex = cursor == null
          ? -1
          : operationalHistory.indexWhere(
              (item) => item['id']?.toString() == cursor,
            );
      final start = cursorIndex < 0 ? 0 : cursorIndex + 1;
      final end = (start + limit).clamp(0, operationalHistory.length);
      final items = operationalHistory.sublist(start, end);
      return <String, dynamic>{
            'items': items,
            'nextCursor': end < operationalHistory.length && items.isNotEmpty
                ? items.last['id']
                : null,
          }
          as T;
    }
    if (RegExp(
      r'^/crm/families/by-entity/(lead|student)/[^/]+$',
    ).hasMatch(path)) {
      return Map<String, dynamic>.from(
            family ?? const {'family': null, 'members': <dynamic>[]},
          )
          as T;
    }
    if (RegExp(
      r'^/crm/clients/(lead|student)/[^/]+/linked-users$',
    ).hasMatch(path)) {
      return <String, dynamic>{'items': linkedUsers} as T;
    }
    if (RegExp(
      r'^/crm/clients/(lead|student)/[^/]+/user-candidates$',
    ).hasMatch(path)) {
      return <String, dynamic>{'items': clientUserCandidates} as T;
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
            'customFieldValues': <String, dynamic>{},
          }
          as T;
    }
    if (student != null && path == '/crm/students/${student!['id']}/card') {
      studentCardLoadCount++;
      final gate = nextStudentCardGate;
      nextStudentCardGate = null;
      if (gate != null) await gate.future;
      return <String, dynamic>{
            'student': student,
            'groups': <dynamic>[],
            'lessons': studentLessons,
            'payments': <dynamic>[],
            'tasks': <dynamic>[],
            'comments': <dynamic>[],
            'indicators': studentIndicators,
            'expectedPayments': <dynamic>[],
            'balance': null,
            'subscriptions': studentSubscriptions,
            'links': <dynamic>[],
            'timeline': studentTimeline,
            'customFieldValues': <String, dynamic>{},
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
  Future<T> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    requests.add('PUT $path');
    final body = Map<String, dynamic>.from(data as Map);
    updateInternalNoteBody = body;
    updateInternalNoteBodies.add(body);
    if (internalNotePutConflicts > 0) {
      internalNotePutConflicts--;
      throw const MagicApiException(
        statusCode: 409,
        message: 'Заметку уже изменили.',
      );
    }
    internalNote = {
      'id': internalNote?['id'] ?? 'note-1',
      'body': body['body'],
      'version': (body['expectedVersion'] as int) + 1,
      'updatedBy': '55555555-5555-4555-8555-555555555555',
      'updatedByName': 'Мария Управляющая',
      'updatedAt': '2026-08-07T12:00:00.000Z',
    };
    return Map<String, dynamic>.from(internalNote!) as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    patchRequests.add((
      path: path,
      data: data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
    ));
    if (lead != null && path == '/crm/leads/${lead!['id']}') {
      requests.add('PATCH $path');
      final body = Map<String, dynamic>.from(data as Map);
      updateLeadBody = body;
      updateLeadBodies.add(body);
      final gate = leadPatchGate;
      if (gate != null) await gate.future;
      if (leadPatchConflicts > 0) {
        leadPatchConflicts--;
        throw const MagicApiException(
          statusCode: 409,
          message: 'Карточку уже изменили.',
          details: {'code': 'CLIENT_VERSION_CONFLICT', 'entityType': 'lead'},
        );
      }
      return <String, dynamic>{
            'id': lead!['id'],
            'version': (body['expectedVersion'] as int? ?? 0) + 1,
          }
          as T;
    }
    if (student != null && path == '/crm/students/${student!['id']}') {
      final body = Map<String, dynamic>.from(data as Map);
      updateStudentBody = body;
      updateStudentBodies.add(body);
      final gate = studentPatchGate;
      if (gate != null) await gate.future;
      if (studentPatchFailures > 0) {
        studentPatchFailures--;
        throw const MagicApiException(message: 'Тестовая ошибка сохранения.');
      }
      if (studentPatchConflicts > 0) {
        studentPatchConflicts--;
        throw const MagicApiException(
          statusCode: 409,
          message: 'Карточку уже изменили.',
          details: {'code': 'CLIENT_VERSION_CONFLICT', 'entityType': 'student'},
        );
      }
      return <String, dynamic>{
            'id': student!['id'],
            'version': (body['expectedVersion'] as int? ?? 0) + 1,
          }
          as T;
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
    if (adjustmentReversalPreview != null &&
        path.contains('/adjustments/') &&
        path.endsWith('/reversal/preview')) {
      return Map<String, dynamic>.from(adjustmentReversalPreview!) as T;
    }
    if (paymentReversalPreview != null && path.endsWith('/reversal/preview')) {
      return Map<String, dynamic>.from(paymentReversalPreview!) as T;
    }
    if (paymentCorrectionPreview != null &&
        path.endsWith('/correction/preview')) {
      return Map<String, dynamic>.from(paymentCorrectionPreview!) as T;
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
    if (path == '/crm/schedule-plans/constraints/preview' ||
        RegExp(
          r'^/crm/schedule-plans/[^/]+/constraints/preview$',
        ).hasMatch(path)) {
      if (schedulePlanConstraintPreviews.isNotEmpty) {
        return schedulePlanConstraintPreviews.removeAt(0) as T;
      }
      final rows = data is Map ? data['rows'] as List? ?? const [] : const [];
      return <String, dynamic>{
            'valid': true,
            'rows': [
              for (var index = 0; index < rows.length; index++)
                {
                  'index': index,
                  'valid': true,
                  'occurrencesChecked': 1,
                  'failures': <dynamic>[],
                },
            ],
          }
          as T;
    }
    if (path == '/crm/schedule-plans') {
      return <String, dynamic>{'id': 'created-plan', 'version': 1} as T;
    }
    if (lead != null &&
        path == '/crm/leads/${lead!['id']}/subscriptions/purchase/preview') {
      final body = Map<String, dynamic>.from(data as Map);
      final paidNowMinor = body['paymentAmountMinor']?.toString() ?? '0';
      return <String, dynamic>{
            'recipientStudentId': lead!['id'],
            'payerStudentId': body['payerStudentId'] ?? lead!['id'],
            'fundingMode': body['fundingMode'] ?? 'personal_account',
            'currencyCode': 'RUB',
            'finalPriceMinor': paidNowMinor,
            'payerBalanceMinor': '0',
            'paidNowMinor': paidNowMinor,
            'balanceAfterMinor': (-BigInt.parse(paidNowMinor)).toString(),
            'canCommit': true,
            'shortageMinor': paidNowMinor,
            'debtMinor': paidNowMinor,
            'overpaymentMinor': '0',
            'previewToken': 'lead-purchase-preview-token',
          }
          as T;
    }
    if (RegExp(r'^/crm/families/[^/]+/primary-payer/[^/]+$').hasMatch(path)) {
      final memberId = path.split('/').last;
      final familyRecord = family?['family'];
      if (familyRecord is Map<String, dynamic>) {
        familyRecord['primaryPayerMemberId'] = memberId;
      }
      return <String, dynamic>{'success': true} as T;
    }
    if (RegExp(
      r'^/crm/clients/(lead|student)/[^/]+/link-user$',
    ).hasMatch(path)) {
      final userId = (data as Map?)?['userId']?.toString();
      final candidate = clientUserCandidates
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (item) => item?['userId']?.toString() == userId,
            orElse: () => null,
          );
      if (candidate != null &&
          !linkedUsers.any((item) => item['userId']?.toString() == userId)) {
        linkedUsers.add({...candidate, 'linkSource': 'manual_phone'});
      }
      return <String, dynamic>{'items': linkedUsers} as T;
    }
    if (RegExp(r'^/crm/students/[^/]+/invite$').hasMatch(path)) {
      return <String, dynamic>{
            'studentId': student?['id'],
            'email': student?['email'] ?? 'student@example.com',
            'status': 'queued',
          }
          as T;
    }
    if (path == '/crm/comments') {
      final body = Map<String, dynamic>.from(data as Map);
      return <String, dynamic>{
            'id': 'comment-created',
            'entityType': body['entityType'],
            'entityId': body['entityId'],
            'authorId': 'manager-1',
            'authorName': 'Мария Управляющая',
            'body': body['body'],
            'kind': body['kind'],
            'progress': body['progress'] ?? false,
            'createdAt': '2026-08-30T12:00:00.000Z',
            'version': 1,
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
    if (lead != null &&
        path == '/crm/leads/${lead!['id']}/subscriptions/purchase') {
      return <String, dynamic>{
            'converted': true,
            'student': {'id': 'student-from-${lead!['id']}'},
          }
          as T;
    }
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
      final result = Map<String, dynamic>.from(
        cancellationResult ?? const <String, dynamic>{},
      );
      final cancellation = result['cancellation'];
      final match = RegExp(
        r'^/crm/students/[^/]+/subscriptions/([^/]+)/cancel$',
      ).firstMatch(path);
      if (cancellation is Map && match != null) {
        final issuedSubscriptionId = match.group(1);
        for (final subscription in studentSubscriptions) {
          if (subscription['id']?.toString() != issuedSubscriptionId) continue;
          subscription
            ..['status'] = cancellation['status']
            ..['version'] = cancellation['version'];
        }
      }
      return result as T;
    }
    if (path.endsWith('/end')) {
      if (mutateSchedulePlanOnEnd) {
        final match = RegExp(
          r'^/crm/schedule-plans/([^/]+)/end$',
        ).firstMatch(path);
        final planId = match?.group(1);
        for (final plan in schedulePlans) {
          if (plan['id']?.toString() != planId) continue;
          plan
            ..['status'] = 'ended'
            ..['version'] = (body['expectedVersion'] as num).toInt() + 1
            ..['activeUntil'] = body['lastDate']
            ..['endedAt'] = '2026-08-12T12:00:00.000Z'
            ..['endedBy'] = '55555555-5555-4555-8555-555555555555'
            ..['endedByName'] = 'Мария Управляющая'
            ..['endReason'] = body['reasonText']
            ..['rows'] = [
              for (final rawRow in plan['rows'] as List? ?? const [])
                if (rawRow is Map)
                  {
                    ...Map<String, dynamic>.from(rawRow),
                    'validUntil': body['lastDate'],
                    'active':
                        (rawRow['validFrom']?.toString() ?? '').compareTo(
                          body['lastDate'].toString(),
                        ) <=
                        0,
                  },
            ];
        }
      }
      return <String, dynamic>{'status': 'ended', 'version': 2} as T;
    }
    if (path == '/crm/schedule-plans') {
      final planId = _schedulePlanCreateIds.putIfAbsent(
        identity.idempotencyKey,
        () => 'created-plan-${_schedulePlanCreateIds.length + 1}',
      );
      if (mutateSchedulePlanOnCreate &&
          !schedulePlans.any((plan) => plan['id']?.toString() == planId)) {
        Map<String, dynamic>? byId(
          List<Map<String, dynamic>> rows,
          Object? id,
        ) {
          for (final row in rows) {
            if (row['id']?.toString() == id?.toString()) return row;
          }
          return null;
        }

        final rawRows = body['rows'] as List? ?? const [];
        schedulePlans.add({
          'id': planId,
          'kind': body['kind'],
          'title': body['title'],
          'studentId': body['studentId'],
          'groupId': body['groupId'],
          'subscriptionId': body['subscriptionId'],
          'activeFrom': body['activeFrom'],
          'activeUntil': body['activeUntil'],
          'status': 'active',
          'version': 1,
          'participants': body['participants'] ?? const [],
          'rows': [
            for (var index = 0; index < rawRows.length; index++)
              if (rawRows[index] is Map)
                () {
                  final row = Map<String, dynamic>.from(rawRows[index] as Map);
                  final teacher = byId(teachers, row['teacherId']);
                  final room = byId(rooms, row['roomId']);
                  final branch = byId(branches, row['branchId']);
                  final teacherName =
                      [teacher?['firstName'], teacher?['lastName']]
                          .where(
                            (part) => part != null && '$part'.trim().isNotEmpty,
                          )
                          .join(' ');
                  return {
                    ...row,
                    'id': 'created-series-${index + 1}',
                    'teacherName': teacherName,
                    'roomName': room?['name'],
                    'branchName': branch?['name'],
                    'validFrom': body['activeFrom'],
                    'validUntil': body['activeUntil'],
                    'active': true,
                  };
                }(),
          ],
        });
      }
      return <String, dynamic>{'id': planId, 'version': 1} as T;
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
  bool routed = false,
  String initialSection = 'overview',
  ContextViewState? initialViewState,
  ProviderContainer? container,
  ValueChanged<bool?>? onClosed,
}) async {
  final app = MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              showDialog<bool>(
                context: context,
                builder: (_) {
                  final card = ClientCard(
                    lead: seed,
                    entityType: entityType,
                    allStatuses: statuses,
                    routed: routed,
                    initialSection: initialSection,
                    initialViewState: initialViewState,
                  );
                  return routed ? Material(child: card) : card;
                },
              ).then((result) => onClosed?.call(result));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('evidence-screenshot-root'),
      child: container == null
          ? ProviderScope(
              overrides: [
                magicApiClientProvider.overrideWithValue(api),
                crmRealtimeProvider.overrideWith(
                  (ref) => const Stream<CrmChangedEvent>.empty(),
                ),
              ],
              child: app,
            )
          : UncontrolledProviderScope(container: container, child: app),
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
