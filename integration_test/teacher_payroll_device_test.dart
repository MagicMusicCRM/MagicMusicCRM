import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_dialog.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_widget.dart';

import 'evidence_screenshot.dart';

class _TeacherPayrollApi extends MagicApiClient {
  _TeacherPayrollApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  Map<String, dynamic>? payoutBody;
  Map<String, dynamic>? deletedRateBody;
  String? deletedRatePath;
  Map<String, dynamic>? bulkRateBody;
  int bulkRateCalls = 0;
  Map<String, dynamic>? exportQuery;
  final List<({List<int> bytes, String filename})> openedReports = [];
  bool paid = false;
  int payrollVersion = 3;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/access/me') {
      return {
            'accountId': 'director-a',
            'role': 'director',
            'accessVersion': 3,
            'capabilities': [
              'commerce.teacher_payroll.read',
              'commerce.teacher_payroll.write',
            ],
            'scopes': <String, String>{},
          }
          as T;
    }
    if (path == '/crm/teachers/teacher-a/payroll') {
      return {
            'teacherId': 'teacher-a',
            'version': payrollVersion,
            'hoursTotal': 12,
            'completedLessons': 12,
            'payableLessons': 11,
            'noAccrualLessons': 1,
            'accruedTotal': 10800,
            'bonusTotal': 500,
            'deductionTotal': 300,
            'paidTotal': paid ? 11000 : 5000,
            'debt': paid ? 0 : 6000,
            'currentRate': 900,
            'rateHistory': [
              {
                'id': 'rate-1',
                'rate': 750,
                'effectiveFrom': '2026-01-01',
                'createdAt': '2026-01-01T09:00:00Z',
                'authorName': 'Диана Директор',
              },
              {
                'id': 'rate-2',
                'rate': 900,
                'effectiveFrom': '2026-08-01',
                'createdAt': '2026-08-01T09:00:00Z',
                'authorName': 'Диана Директор',
              },
            ],
            'payouts': [
              if (paid)
                {
                  'id': 'payout-2',
                  'kind': 'payout',
                  'amount': 6000,
                  'comment': 'Оплата всей задолженности',
                  'paidAt': '2026-08-12T10:00:00Z',
                  'authorName': 'Диана Директор',
                },
              {
                'id': 'payout-1',
                'kind': 'payout',
                'amount': 5000,
                'comment': 'За июль',
                'paidAt': '2026-08-05T10:00:00Z',
                'authorName': 'Диана Директор',
              },
            ],
          }
          as T;
    }
    if (path == '/crm/reports/teacher-stats') {
      return {
            'from': '2026-08-01T00:00:00Z',
            'to': '2026-09-01T00:00:00Z',
            'items': [
              {
                'teacherId': 'teacher-a',
                'teacherName': 'Ирина Педагог',
                'currentRate': 900,
                'completedLessons': 2,
                'payableLessons': 2,
                'hoursTotal': 2,
                'accruedTotal': 1800,
                'bonusTotal': 0,
                'deductionTotal': 0,
                'paidTotal': 1000,
                'periodBalance': 800,
                'units': [
                  {
                    'unitType': 'individual_trial',
                    'groupId': null,
                    'unitName': 'Анна Смирнова',
                    'rate': 900,
                    'days': [
                      {'date': '2026-08-04', 'hours': 1},
                      {'date': '2026-08-11', 'hours': 1},
                    ],
                    'lessonIds': ['lesson-1', 'lesson-2'],
                    'editableLessonIds': <String>[],
                    'settledLessons': 2,
                    'compensationLocked': true,
                    'completedLessons': 2,
                    'payableLessons': 2,
                    'hoursTotal': 2,
                    'accruedTotal': 1800,
                  },
                ],
              },
            ],
            'totals': {
              'completedLessons': 2,
              'payableLessons': 2,
              'hoursTotal': 2,
              'accruedTotal': 1800,
              'bonusTotal': 0,
              'deductionTotal': 0,
              'paidTotal': 1000,
              'periodBalance': 800,
            },
          }
          as T;
    }
    if (path == '/crm/reports/teacher-stats/export') {
      exportQuery = Map<String, dynamic>.from(queryParameters ?? const {});
      return '\uFEFFПреподаватель;Учебная единица;Тип\r\n'
              'Ирина Педагог;Анна Смирнова;Индивидуальный пробный\r\n'
          as T;
    }
    if (path == '/crm/client-config/fields') return {'items': []} as T;
    return {'items': <dynamic>[]} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/teachers/teacher-a/payouts') {
      payoutBody = Map<String, dynamic>.from(data! as Map);
      paid = true;
      payrollVersion += 1;
      return {
            'id': 'payout-2',
            'teacherId': 'teacher-a',
            'kind': 'payout',
            'amount': 6000,
            'version': 4,
            'replayed': false,
          }
          as T;
    }
    return <String, dynamic>{} as T;
  }

  @override
  Future<T> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/teachers/teacher-a/rates/rate-2') {
      deletedRatePath = path;
      deletedRateBody = Map<String, dynamic>.from(data! as Map);
      payrollVersion += 1;
      return {
            'id': 'rate-2',
            'teacherId': 'teacher-a',
            'deleted': true,
            'version': 4,
            'replayed': false,
          }
          as T;
    }
    return <String, dynamic>{} as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/lessons/teacher-rate') {
      bulkRateCalls += 1;
      bulkRateBody = Map<String, dynamic>.from(data! as Map);
      return {'updated': 2, 'correctedSettled': 2} as T;
    }
    return <String, dynamic>{} as T;
  }
}

Widget _host(_TeacherPayrollApi api, Widget child) => RepaintBoundary(
  key: evidenceRootKey,
  child: ProviderScope(
    overrides: [
      magicApiClientProvider.overrideWithValue(api),
      reportFileOpenerProvider.overrideWithValue((bytes, filename) async {
        api.openedReports.add((
          bytes: List<int>.from(bytes),
          filename: filename,
        ));
        return ReportFileOpenResult(path: 'C:/Reports/$filename', opened: true);
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: Center(child: child)),
    ),
  ),
);

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('director sees history and creates a versioned payout', (
    tester,
  ) async {
    _desktop(tester);
    final api = _TeacherPayrollApi();
    await tester.pumpWidget(
      _host(
        api,
        TeacherDetailDialog(
          teacher: const {
            'id': 'teacher-a',
            'first_name': 'Ирина',
            'last_name': 'Педагог',
            'status': 'active',
            'is_app_account': true,
            'app_role': 'teacher',
            'password_configured': true,
            'custom_data': <String, dynamic>{},
            'assigned_branches': <dynamic>[],
            'disciplines': <dynamic>[],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Задолженность: 6'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('teacher-rate-history')),
    );
    await tester.tap(find.textContaining('История ставок'));
    await tester.pumpAndSettle();
    expect(find.text('900 ₽/астр.ч.'), findsOneWidget);
    expect(find.textContaining('Диана Директор'), findsWidgets);
    final rateRow = find.ancestor(
      of: find.text('900 ₽/астр.ч.'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: rateRow,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Изменить'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина удаления *'),
      'Ошибочная дублирующая ставка',
    );
    await tester.tap(find.text('Удалить').last);
    await tester.pumpAndSettle();
    expect(api.deletedRatePath, '/crm/teachers/teacher-a/rates/rate-2');
    expect(api.deletedRateBody?['expectedVersion'], 3);
    expect(api.deletedRateBody?['reasonText'], 'Ошибочная дублирующая ставка');
    await captureEvidence(tester, 'teacher-payroll-history');

    await tester.ensureVisible(find.text('Оплатить всю задолженность'));
    await tester.tap(find.text('Оплатить всю задолженность'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выплатить'));
    await tester.pumpAndSettle();

    expect(api.payoutBody, isNotNull);
    expect(api.payoutBody!['expectedVersion'], 4);
    expect(api.payoutBody!['reasonText'], 'Оплата всей задолженности');
    expect(find.textContaining('Задолженность: 0'), findsOneWidget);
    debugPrint('V7_TEACHER_PAYROLL_DEVICE_PASS');
  });

  testWidgets('director can mass-correct settled teacher rates', (
    tester,
  ) async {
    _desktop(tester);
    final api = _TeacherPayrollApi();
    await tester.pumpWidget(_host(api, const TeacherStatsWidget()));
    await tester.pumpAndSettle();

    expect(find.text('Ирина Педагог'), findsOneWidget);
    expect(find.textContaining('Зафиксировано расчётов: 2'), findsOneWidget);
    expect(
      find.textContaining('директор может исправить массово'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    expect(find.byType(Checkbox), findsOneWidget);

    await tester.tap(find.text('Экспорт'));
    await tester.pumpAndSettle();
    expect(api.openedReports, hasLength(1));
    final exported = api.openedReports.single;
    expect(exported.filename, startsWith('teacher-stats-'));
    expect(exported.filename, endsWith('.csv'));
    expect(exported.bytes.take(3), [0xef, 0xbb, 0xbf]);
    expect(utf8.decode(exported.bytes), contains('Ирина Педагог'));
    expect(api.exportQuery, containsPair('from', isNotEmpty));
    expect(api.exportQuery, containsPair('to', isNotEmpty));
    expect(find.textContaining('Файл открыт:'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Проставить ставку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ставка педагога (по умолчанию)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('900 ₽').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Причина изменения *'),
      'Исправление ошибочной ставки админа',
    );
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();

    expect(api.bulkRateCalls, 1);
    expect(api.bulkRateBody?['lessonIds'], ['lesson-1', 'lesson-2']);
    expect(api.bulkRateBody?['teacherRate'], 900);
    expect(
      api.bulkRateBody?['reasonText'],
      'Исправление ошибочной ставки админа',
    );
    await captureEvidence(tester, 'teacher-statistics-integrity');
    debugPrint('V7_TEACHER_STATS_DEVICE_PASS');
  });
}
