import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_filters_sheet.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_shared.dart';

void main() {
  setUpAll(() async {
    EditableText.debugDeterministicCursor = true;
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  tearDownAll(() => EditableText.debugDeterministicCursor = false);
  testWidgets(
    'financial dropdown keeps the anchor visible in the actual filters panel',
    (tester) async {
      tester.view.physicalSize = const Size(720, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('visual'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.production,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: ScheduleFiltersPanel(
                  initialBranchId: null,
                  initialMode: DayViewMode.byRoom,
                  branches: const [],
                  isDayView: true,
                  initialOnlyTrial: false,
                  initialOnlyConflicts: false,
                  initialTeacherId: null,
                  teacherOptions: const [],
                  loadFinancialCatalog: (_) async => {
                    'teacherCompensationRules': [
                      {
                        'stableKey': 'standard',
                        'label': 'Полная стандартная ставка',
                      },
                      {'stableKey': 'none', 'label': 'Не оплачивать'},
                    ],
                  },
                  onApply: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('financial-filter-Списание клиента')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('type-filter-trial_lesson')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('visual')),
        matchesGoldenFile('goldens/financial_dropdown.png'),
      );
    },
  );
}
