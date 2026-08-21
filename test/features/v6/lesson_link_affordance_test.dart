import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_presentation_resolver.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_details_sheet.dart';

void main() {
  for (final testCase in const [
    (width: 412.0, desktop: false, platform: TargetPlatform.android),
    (width: 1200.0, desktop: true, platform: TargetPlatform.windows),
  ]) {
    testWidgets(
      '${testCase.platform.name} lesson refs expose honest link affordances',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(testCase.width, 900);
        addTearDown(tester.view.reset);
        final controller = WorkspaceController(
          accountId: 'account-1',
          initialLink: EntityLink.typed(
            entityType: EntityLinkType.report,
            entityId: '__section__',
          ),
          titleResolver: const EntityPresentationResolver().pageTitle,
          sharedScope: const WorkspaceSharedScope(
            session: Object(),
            cache: Object(),
            realtime: Object(),
          ),
        );
        addTearDown(controller.dispose);
        EntityLink? opened;
        EntityOpenTarget? target;
        var adjusted = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: testCase.platform),
            home: WorkspaceNavigationScope(
              controller: controller,
              isDesktop: testCase.desktop,
              child: Builder(
                builder: (context) => Scaffold(
                  body: FilledButton(
                    onPressed: () => showLessonDetailsSheet(
                      context,
                      teacherName: 'Мария Иванова',
                      studentName: 'Анна Смирнова',
                      roomName: 'Класс 1',
                      references: [
                        LessonEntityReference(
                          icon: Icons.person,
                          label: 'Ученик',
                          value: 'Анна Смирнова',
                          link: EntityLink.typed(
                            entityType: EntityLinkType.client,
                            entityId: 'student-1',
                            variant: 'student',
                          ),
                        ),
                        const LessonEntityReference(
                          icon: Icons.school,
                          label: 'Педагог',
                          value: 'Мария Иванова',
                          available: false,
                        ),
                        const LessonEntityReference(
                          icon: Icons.room,
                          label: 'Аудитория',
                          value: 'Без аудитории',
                        ),
                      ],
                      onOpenReference: (link, openTarget) {
                        opened = link;
                        target = openTarget;
                      },
                      timeRange: '14:00 – 15:00',
                      currentStatus: 'scheduled',
                      conflicts: const [],
                      lessonId: 'lesson-1',
                      settlementHistory: const [
                        {
                          'kind': 'plan',
                          'effective': false,
                          'decision': {
                            'settlementTypeKey': 'lesson',
                            'teacherCompensationRuleKey': 'standard',
                          },
                          'reason': 'Исходный расчёт',
                          'actorName': 'Анна Администратор',
                          'createdAt': '2026-08-07T07:00:00.000Z',
                        },
                        {
                          'kind': 'correction',
                          'effective': true,
                          'decision': {
                            'settlementTypeKey': 'free_lesson',
                            'teacherCompensationRuleKey': 'none',
                          },
                          'reason': 'Согласовано бесплатное занятие',
                          'actorName': 'Мария Управляющая',
                          'createdAt': '2026-08-07T08:00:00.000Z',
                        },
                      ],
                      adjustSettlementLabel: 'Изменить расчёт',
                      onAdjustSettlement: () async => adjusted = true,
                      onEdit: () {},
                      onCancel: () async {},
                    ),
                    child: const Text('Открыть занятие'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Открыть занятие'));
        await tester.pumpAndSettle();

        final linkedText = find.byKey(
          const ValueKey('lesson-reference-Ученик'),
        );
        expect(find.text('Анна Смирнова'), findsWidgets);
        expect(linkedText, findsOneWidget);
        final semantics = tester.getSemantics(linkedText);
        expect(semantics.flagsCollection.isLink, isTrue);
        expect(semantics.flagsCollection.isButton, isTrue);
        expect(find.text('Связанная запись недоступна'), findsOneWidget);
        expect(find.text('Без аудитории'), findsOneWidget);
        expect(find.byTooltip('Открыть в новой вкладке'), findsNothing);
        expect(
          find.byKey(const Key('lesson-adjust-settlement')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('lesson-settlement-history')));
        await tester.pumpAndSettle();
        expect(find.text('План расчёта · заменён'), findsOneWidget);
        expect(find.text('Корректировка · действующий'), findsOneWidget);
        expect(
          find.text('Причина: Согласовано бесплатное занятие'),
          findsOneWidget,
        );

        await tester.tap(linkedText);
        await tester.pumpAndSettle();
        expect(opened?.entityId, 'student-1');
        expect(target, EntityOpenTarget.current);

        await tester.tap(find.text('Открыть занятие'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('lesson-adjust-settlement')));
        await tester.pumpAndSettle();
        expect(adjusted, isTrue);
      },
    );
  }
}
