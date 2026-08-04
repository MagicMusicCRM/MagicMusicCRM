import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
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
          sharedScope: const WorkspaceSharedScope(
            session: Object(),
            cache: Object(),
            realtime: Object(),
          ),
        );
        addTearDown(controller.dispose);
        EntityLink? opened;
        EntityOpenTarget? target;
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
                      showNewTabAction: testCase.desktop,
                      timeRange: '14:00 – 15:00',
                      currentStatus: 'scheduled',
                      conflicts: const [],
                      lessonId: 'lesson-1',
                      onEdit: () {},
                      onDelete: () async {},
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

        final linkedText = find.text('Ученик: Анна Смирнова');
        expect(linkedText, findsOneWidget);
        final semantics = tester.getSemantics(linkedText);
        expect(semantics.flagsCollection.isLink, isTrue);
        expect(semantics.flagsCollection.isButton, isTrue);
        expect(find.text('Связанная запись недоступна'), findsOneWidget);
        expect(find.text('Без аудитории'), findsOneWidget);
        expect(
          find.byTooltip('Открыть в новой вкладке'),
          testCase.desktop ? findsOneWidget : findsNothing,
        );

        await tester.tap(linkedText);
        await tester.pumpAndSettle();
        expect(opened?.entityId, 'student-1');
        expect(target, EntityOpenTarget.current);
      },
    );
  }
}
