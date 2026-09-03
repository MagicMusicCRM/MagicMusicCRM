import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_details_sheet.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/subscription_issue_sheet.dart';

import '../../support/modal_layout_evidence.dart';

void main() {
  for (final (size, scale) in [
    (const Size(1280, 900), 1.0),
    (const Size(320, 800), 1.3),
    (const Size(430, 932), 1.5),
  ]) {
    testWidgets('action windows layout ${size.width} text $scale', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(loadModalFonts);
      const student = 'Александра Константинова';
      await tester.pumpWidget(
        RepaintBoundary(
          key: evidenceRootKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('ru')],
            locale: const Locale('ru'),
            theme: AppTheme.production.copyWith(
              platform: size.width >= 840
                  ? TargetPlatform.windows
                  : TargetPlatform.android,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () => showLessonDetailsSheet(
                        context,
                        teacherName: 'Константин Александрович',
                        studentName: student,
                        roomName: 'Большой зал музыкальной школы',
                        timeRange: '15:00–16:00',
                        currentStatus: 'settlement_pending',
                        conflicts: const [],
                        lessonId: 'lesson-a',
                        settlementIssue:
                            'Проверьте списание и оплату преподавателю.',
                        onEdit: () {},
                        onCancel: () async {},
                      ),
                      child: const Text('Занятие'),
                    ),
                    TextButton(
                      onPressed: () => showSubscriptionIssueFormSheet(
                        context,
                        package: const {
                          'id': 'package-a',
                          'name': 'Индивидуальные занятия вокалом',
                          'basePriceMinor': '800000',
                          'currencyCode': 'RUB',
                        },
                        recipientStudentId: 'student-a',
                        recipientLabel: student,
                        searchPayers: (_) async => [],
                        onPreview: (_) async => throw StateError(
                          'No financial command in a layout test',
                        ),
                        onSubmit: (_) async => throw StateError(
                          'No financial command in a layout test',
                        ),
                      ),
                      child: const Text('Абонемент'),
                    ),
                    TextButton(
                      onPressed: () => SearchableSelect.show(
                        context: context,
                        title: 'Выберите клиента',
                        hintText: 'Поиск по ФИО',
                        items: [
                          SearchableSelectItem(id: 'student-a', label: student),
                        ],
                        onSelected: (_) {},
                      ),
                      child: const Text('Клиент'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      for (final (label, name) in [
        ('Занятие', 'details'),
        ('Абонемент', 'subscription'),
        ('Клиент', 'selection'),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        if (size.width < 840) {
          await tester.tap(find.byTooltip('Развернуть'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        final frame = tester.getRect(
          find.byKey(const ValueKey('magic-sheet-frame')),
        );
        expect(frame.width, closeTo(size.width >= 840 ? 728 : size.width, 1));
        if (name == 'subscription' && size.width < 840) {
          expect(
            tester.getRect(find.text('Условия абонемента')).width,
            greaterThan(size.width - 55),
          );
        }
        await captureModalLayout(tester, '$name-${size.width.toInt()}');
        if (name == 'details') {
          final reason = tester.getRect(
            find.text('Проверьте списание и оплату преподавателю.'),
          );
          expect(
            reason.width,
            greaterThan(size.width >= 840 ? 300 : size.width - 100),
          );
          await tester.ensureVisible(find.text('Изменить занятие'));
          await tester.pumpAndSettle();
          expect(find.text('Изменить занятие').hitTestable(), findsOneWidget);
        }
        if (name == 'subscription' && size.width < 840) {
          final date = find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText == 'Дата оплаты',
          );
          await tester.ensureVisible(date);
          await tester.pumpAndSettle();
          expect(tester.getSize(date).width, greaterThan(size.width - 100));
          await captureModalLayout(
            tester,
            'subscription-payment-${size.width.toInt()}',
          );
        }
        await tester.tap(find.byTooltip('Закрыть'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
