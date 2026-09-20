import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_view.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru'));
  for (final role in ['manager', 'director']) {
    testWidgets(
      '$role payroll report export rate correction',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'payroll');
        await h.initialize(size: const Size(1500, 1400));
        final crm = h.scope.read(magicCrmServiceProvider),
            branch = h.fixture['branchId'] as String;
        final now = DateTime.now(),
            range = DateTimeRange(
              start: DateTime(now.year, 1, 1),
              end: DateTime(now.year, 12, 31),
            );
        final files = <String>[];
        Future<void> open() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            ProviderScope(
              overrides: [
                reportFileOpenerProvider.overrideWithValue((bytes, name) async {
                  validateReportExportBytes(bytes, 'xlsx');
                  expect(name.contains(RegExp(r'[/\\]')), false);
                  final path =
                      '${Platform.environment['EVIDENCE_SCREENSHOT_DIR']}/$role-$name';
                  await File(path).writeAsBytes(bytes, flush: true);
                  files.add(path);
                  h.facts.add({
                    'step': h.currentStep,
                    'file': path,
                    'bytes': bytes.length,
                  });
                  return ReportFileOpenResult(path: path, opened: false);
                }),
              ],
              child: Scaffold(
                body: TeacherStatsWidget(filterRange: range, branchId: branch),
              ),
            ),
          );
          await h.quiet();
        }

        Future<Map<String, dynamic>> read() async {
          final r = await crm.getTeacherStatsReport(
            from: range.start.toUtc().toIso8601String(),
            to: range.end
                .add(const Duration(days: 1))
                .toUtc()
                .toIso8601String(),
            branchId: branch,
          );
          h.facts.add({'step': h.currentStep, 'report': r});
          return r;
        }

        await h.check(
          'OPEN',
          'Отчёт показывает реальные проведённые занятия и ненулевые начисления',
          () async {
            await open();
            final r = await read();
            expect((r['items'] as List).isNotEmpty, true);
            expect(
              num.parse(r['totals']['accruedTotal'].toString()),
              greaterThan(0),
            );
            expect(find.text('Не удалось загрузить отчёт'), findsNothing);
          },
        );
        await h.check(
          'EXPORT',
          'Экспорт сохраняет настоящий XLSX с начислениями',
          () async {
            await h.tap(find.text('Экспорт'));
            await h.quiet();
            expect(files, hasLength(1));
          },
        );
        if (role == 'manager') {
          await h.check(
            'RATE-FORBIDDEN',
            'Управляющий читает отчёт без кнопок массового изменения ставки',
            () async {
              expect(find.byType(Checkbox), findsNothing);
              expect(find.text('Проставить ставку'), findsNothing);
            },
          );
          await h.finish();
          return;
        }
        final selected = <String>[];
        Future<void> select() async {
          await h.tap(find.byType(Checkbox).first);
          final state = tester
              .widget<TeacherStatsView>(find.byType(TeacherStatsView))
              .controller
              .state;
          selected.clear();
          for (final ids in state.selectedUnits.values) {
            selected.addAll(ids);
          }
          expect(selected, isNotEmpty);
          await h.tap(find.text('Проставить ставку'));
          await h.quiet();
        }

        Future<void> fill() async {
          final field = find.descendant(
            of: find.byType(TeacherRateSelector),
            matching: find.byType(DropdownButtonFormField<String>),
          );
          await h.tap(field);
          await h.tap(find.text('750 ₽').last);
          final reason = find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.labelText == 'Причина изменения *',
          );
          await tester.enterText(reason, 'AUDIT-PAYROLL-RATE');
        }

        await h.check(
          'RATE-CANCEL',
          'Отмена массовой ставки не меняет отчёт',
          () async {
            final before = await read();
            await select();
            await fill();
            await h.tap(find.text('Отмена').last);
            final after = await read();
            expect(after['rateMutationVersion'], before['rateMutationVersion']);
          },
        );
        await h.check(
          'RATE',
          'Директор исправляет ставку выбранных занятий с причиной',
          () async {
            await h.tap(find.text('Проставить ставку'));
            await fill();
            await h.tap(find.text('Применить').last);
            await h.quiet();
            for (final id in selected) {
              final l = (await crm.listLessons(lessonId: id, limit: 1)).single;
              h.facts.add({'step': h.currentStep, 'lesson': l});
              expect(num.parse(l['teacher_rate'].toString()), 750);
            }
            await read();
          },
        );
        await h.check(
          'REOPEN',
          'Исправленные ставки и начисления сохраняются после открытия',
          () async {
            final before = await read();
            await open();
            final after = await read();
            expect(after['totals'], before['totals']);
            expect(after['rateMutationVersion'], before['rateMutationVersion']);
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  }
}
