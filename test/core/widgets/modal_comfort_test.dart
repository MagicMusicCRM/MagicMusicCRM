import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_details_sheet.dart';

import '../../support/modal_layout_evidence.dart';

void main() {
  setUpAll(loadModalFonts);
  for (final scenario in [
    (const Size(1280, 800), 1.0, TargetPlatform.windows),
    (const Size(960, 640), 1.5, TargetPlatform.windows),
    (const Size(390, 844), 1.0, TargetPlatform.android),
  ]) {
    testWidgets('lesson details remain readable at $scenario', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.$1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepaintBoundary(
          key: evidenceRootKey,
          child: MaterialApp(
            theme: AppTheme.production.copyWith(platform: scenario.$3),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scenario.$2)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showLessonDetailsSheet(
                    context,
                    teacherName: 'Ирина Смирнова',
                    studentName: 'Анна Иванова',
                    roomName: 'Класс 1',
                    timeRange: '15:00 — 16:00',
                    currentStatus: 'scheduled',
                    lessonId: 'lesson-fixture',
                    conflicts: const [],
                    onEdit: () {},
                    onMove: () {},
                    onCancel: () async {},
                  ),
                  child: const Text('Открыть'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      expect(find.text('Занятие: '), findsNothing);
      expect(find.text('Ученик: '), findsOneWidget);
      for (final text in [
        'Изменить занятие',
        'Перенести',
        'Отменить занятие',
      ]) {
        final button = find.ancestor(
          of: find.text(text),
          matching: find.byWidgetPredicate(
            (widget) => widget is ButtonStyleButton,
          ),
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        expect(
          tester.getRect(button).bottom,
          lessThanOrEqualTo(scenario.$1.height),
        );
      }
      expect(find.byTooltip('Закрыть').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (scenario.$2 == 1 && scenario.$3 == TargetPlatform.windows) {
        await tester.ensureVisible(find.text('Ученик: '));
        await tester.pumpAndSettle();
        await captureModalLayout(tester, 'lesson-details-comfort');
      }
    });
  }
}
