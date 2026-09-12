import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['client', 'teacher', 'admin', 'manager', 'director']) {
    testWidgets(
      '$role reporting and real CSV XLSX downloads',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'report-exports');
        await h.initialize(size: const Size(1500, 1300));
        final access = await h.scope.read(capabilitySnapshotProvider.future);
        final now = DateTime.now(), files = <Map<String, dynamic>>[];
        final filter = DashboardFilter(
          from: DateTime(now.year, 1, 1),
          to: DateTime(now.year, 12, 31),
          branchId: h.fixture['branchId'] as String,
        );
        final source = h.scope.read(reportingDataSourceProvider);
        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            ProviderScope(
              overrides: [
                reportFileOpenerProvider.overrideWithValue((bytes, name) async {
                  expect(name.contains(RegExp(r'[/\\]')), false);
                  final format = name.split('.').last;
                  validateReportExportBytes(bytes, format);
                  final path =
                      '${Platform.environment['EVIDENCE_SCREENSHOT_DIR']}/$role-${files.length}-$name';
                  await File(path).writeAsBytes(bytes, flush: true);
                  files.add({
                    'name': name,
                    'path': path,
                    'size': bytes.length,
                    'format': format,
                    if (format == 'csv') 'text': utf8.decode(bytes),
                  });
                  h.facts.add({'step': h.currentStep, 'file': files.last});
                  return ReportFileOpenResult(path: path, opened: false);
                }),
              ],
              child: Scaffold(
                body: ReportingPanel(
                  role: role,
                  filter: filter,
                  accessSnapshot: access,
                ),
              ),
            ),
          );
          await h.quiet();
        }

        if (!['manager', 'director'].contains(role)) {
          await h.check(
            'FORBIDDEN',
            'Недоступный отчёт не запускает аналитические запросы',
            () async {
              final start = h.requests.length;
              await open();
              expect(
                find.byKey(const ValueKey('reporting-forbidden')),
                findsOneWidget,
              );
              expect(
                h.requests
                    .skip(start)
                    .where(
                      (r) => (r['path'] as String).contains('/analytics/'),
                    ),
                isEmpty,
              );
            },
          );
          await h.finish();
          return;
        }
        await h.check(
          'OPEN',
          'Открыть настоящую сводку клиентов, занятий и задач',
          () async {
            await open();
            expect(
              find.byKey(const ValueKey('reporting-content')),
              findsOneWidget,
            );
            if (role == 'manager') {
              expect(find.text('Финансы XLSX'), findsNothing);
            }
          },
        );
        await h.check(
          'READBACK',
          'Проверить реальные данные API по тем же датам и филиалу',
          () async {
            final status = await source.loadClientStatus(filter),
                lessons = await source.loadLessonSuccess(filter);
            h.facts.add({
              'step': h.currentStep,
              'filter': filter.apiFilter,
              'status': status,
              'lessons': lessons,
            });
            expect(status, isNotEmpty);
            expect(lessons, isNotEmpty);
          },
        );
        Future<void> export(String label, String format) async {
          final count = files.length;
          await h.tap(find.widgetWithText(OutlinedButton, label));
          await h.waitFor(
            () => files.length > count,
            'Real export bytes received and written',
          );
          await h.quiet();
          expect(files.last['format'], format);
          expect(files.last['size'], greaterThan(0));
          expect(
            find.byKey(const ValueKey('report-export-error')),
            findsNothing,
          );
        }

        await h.check(
          'CSV',
          'Кнопка CSV скачивает и сохраняет настоящий UTF-8 BOM файл',
          () async {
            await export('CSV', 'csv');
            expect(
              (files.last['text'] as String).split('\n').length,
              greaterThan(1),
            );
          },
        );
        await h.check(
          'XLSX',
          'Кнопка XLSX скачивает структурно корректный OOXML архив',
          () async {
            await export('XLSX', 'xlsx');
          },
        );
        if (role == 'director') {
          await h.check(
            'FINANCE-XLSX',
            'Директор сохраняет отдельный финансовый XLSX',
            () async {
              await export('Финансы XLSX', 'xlsx');
              h.facts.add({
                'step': h.currentStep,
                'finance': await source.loadSchoolFinance(filter),
              });
            },
          );
        }
        await h.check(
          'REOPEN',
          'Повторное открытие восстанавливает отчёт без ошибки экспорта',
          () async {
            await open();
            expect(
              find.byKey(const ValueKey('reporting-content')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('report-export-error')),
              findsNothing,
            );
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );
  }
}
