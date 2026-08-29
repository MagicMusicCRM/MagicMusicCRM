import 'package:archive/archive.dart';
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

  Map<String, dynamic>? bulkRateBody;
  int bulkRateCalls = 0;
  Map<String, dynamic>? exportQuery;
  final List<({List<int> bytes, String filename})> openedReports = [];

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
            'version': 3,
            'hoursTotal': 12,
            'completedLessons': 12,
            'payableLessons': 11,
            'noAccrualLessons': 1,
            'accruedTotal': 10800,
            'currentRate': 900,
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
    if (path == '/crm/client-config/fields') return {'items': []} as T;
    return {'items': <dynamic>[]} as T;
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

  @override
  Future<List<int>> downloadBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/crm/reports/teacher-stats/export') {
      exportQuery = Map<String, dynamic>.from(queryParameters ?? const {});
      return _minimalXlsxBytes();
    }
    throw UnsupportedError('Unexpected binary download: $path');
  }
}

List<int> _minimalXlsxBytes() {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        '[Content_Types].xml',
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            '</Types>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        '_rels/.rels',
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
            '</Relationships>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'xl/workbook.xml',
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
            '</workbook>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'xl/_rels/workbook.xml.rels',
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
            '</Relationships>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'xl/worksheets/sheet1.xml',
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<sheetData/>'
            '</worksheet>',
      ),
    );
  return ZipEncoder().encode(archive);
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

  testWidgets('teacher detail omits debt, payout, and rate history controls', (
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

    expect(find.textContaining('Задолженность'), findsNothing);
    expect(find.textContaining('выплачено'), findsNothing);
    expect(find.textContaining('Оплатить всю задолженность'), findsNothing);
    expect(find.textContaining('История выплат'), findsNothing);
    expect(find.textContaining('История ставок'), findsNothing);
    await captureEvidence(tester, 'teacher-payroll-accrual-only');
    debugPrint('V7_TEACHER_PAYROLL_ACCRUAL_ONLY_DEVICE_PASS');
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
    expect(exported.filename, endsWith('.xlsx'));
    expect(
      () => validateReportExportBytes(exported.bytes, 'xlsx'),
      returnsNormally,
    );
    expect(api.exportQuery, containsPair('from', isNotEmpty));
    expect(api.exportQuery, containsPair('to', isNotEmpty));
    expect(find.text('Файл открыт: ${exported.filename}'), findsOneWidget);

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
