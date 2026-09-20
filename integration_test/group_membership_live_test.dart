import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_group_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/group_detail_dialog.dart';
import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final role in ['director', 'manager']) {
    testWidgets(
      '$role creates a group and manages its membership',
      (tester) async {
        final h = LiveAuditHarness(tester, role, 'groups');
        await h.initialize(size: const Size(1440, 1500));
        final crm = h.scope.read(magicCrmServiceProvider);
        final groupName = 'GROUP-AUDIT-$role';
        final studentId = h.fixture['studentId'] as String;
        final teacherId = h.fixture['teacherId'] as String;
        final roomId = h.fixture['roomId'] as String;
        String? groupId;
        final create = find.byType(CreateGroupDialog),
            detail = find.byType(GroupDetailDialog);
        Finder field(String label) => find.descendant(
          of: create,
          matching: find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == label,
          ),
        );
        Future<void> fill(String label, String value) async {
          await h.tap(field(label));
          await tester.enterText(field(label), value);
          await tester.pump();
        }

        Future<void> catalog() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await h.mount(
            SystemSettingsRouteScreen(
              key: UniqueKey(),
              initialArea: 'schedule',
            ),
          );
          await h.quiet();
          await h.tap(find.text('Группы'));
          await h.quiet();
        }

        Future<void> newGroup() async {
          await catalog();
          await h.tap(find.text('Новая группа'));
          await h.quiet();
          expect(create, findsOneWidget);
        }

        Future<void> pick(String key, String id) async {
          final finder = find.byKey(ValueKey(key));
          final widget = tester.widget<SearchablePickerField>(finder);
          final label = widget.items.singleWhere((i) => i.id == id).label;
          await h.tap(finder);
          await h.tap(find.widgetWithText(MenuItemButton, label));
          await h.quiet();
        }

        Future<void> references() async {
          await h.tap(
            find.descendant(
              of: create,
              matching: find.byType(DropdownButtonFormField<String>),
            ),
          );
          await h.tap(find.text('HTTP test').last);
          await h.quiet();
          await pick('group-teacher-field', teacherId);
          await pick('group-room-field', roomId);
        }

        Future<void> button(String label) =>
            h.tap(find.descendant(of: create, matching: find.text(label)));
        Future<void> openGroup() async {
          await catalog();
          await h.tap(find.text(groupName));
          await h.quiet();
          expect(detail, findsOneWidget);
        }

        Future<List<Map<String, dynamic>>> members() async {
          final value = await crm.listGroupStudents(groupId!);
          h.facts.add({'step': h.currentStep, 'members': value});
          return value;
        }

        await h.check(
          'CREATE-CANCEL',
          'Отмена заполненного создания группы не оставляет запись',
          () async {
            await newGroup();
            await fill('Название группы *', 'GROUP-CANCELLED-$role');
            await references();
            await button('Отмена');
            expect(
              (await crm.listGroups()).any(
                (r) => r['name'] == 'GROUP-CANCELLED-$role',
              ),
              false,
            );
          },
        );
        await h.check(
          'VALIDATION',
          'Название, филиал и ссылки обязательны; отрицательная цена не отправляется',
          () async {
            await newGroup();
            await button('Создать группу');
            expect(find.text('Введите название группы'), findsOneWidget);
            expect(find.text('Выберите филиал'), findsOneWidget);
            await fill('Название группы *', groupName);
            await references();
            await fill('Цена за занятие', '-1');
            await button('Создать группу');
            expect(find.text('Введите корректную цену'), findsOneWidget);
            expect(
              h.requests.where(
                (r) =>
                    r['step'] == h.currentStep &&
                    r['method'] == 'POST' &&
                    r['path'] == '/api/crm/groups',
              ),
              isEmpty,
            );
            await button('Отмена');
          },
        );
        await h.check(
          'CREATE',
          'Создать группу с преподавателем, аудиторией и ценой с копейками',
          () async {
            await newGroup();
            await fill('Название группы *', groupName);
            await references();
            await fill('Цена за занятие', '1500,50');
            expect(
              find.byType(TeacherRateSelector),
              role == 'director' ? findsOneWidget : findsNothing,
            );
            await button('Создать группу');
            await h.quiet();
            expect(create, findsNothing);
            final group = (await crm.listGroups()).singleWhere(
              (r) => r['name'] == groupName,
            );
            groupId = group['id'] as String;
            h.facts.add({'step': h.currentStep, 'group': group});
            expect(group['teacher_id'], teacherId);
            expect(group['room_id'], roomId);
            expect(find.text(groupName), findsOneWidget);
          },
        );
        if (groupId == null) {
          h.blocked('DEPENDENTS', 'Состав группы', 'Group creation failed');
          await h.finish();
          return;
        }
        await h.check('SEARCH', 'Поиск группы и очистка фильтра', () async {
          final search = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Поиск группы',
          );
          await h.tap(search);
          await tester.enterText(search, 'не-существует');
          await tester.pump();
          expect(find.text('Ничего не найдено'), findsOneWidget);
          await tester.enterText(search, groupName.toLowerCase());
          await tester.pump();
          expect(find.text(groupName), findsOneWidget);
          await tester.enterText(search, '');
          await tester.pump();
        });
        await h.check(
          'OPEN',
          'Повторное открытие новой группы показывает пустой состав',
          () async {
            await openGroup();
            expect(await members(), isEmpty);
            expect(find.text('Добавить ученика'), findsOneWidget);
          },
        );
        await h.check(
          'MEMBER-ADD',
          'Добавить ученика через выбор и проверить сохранение',
          () async {
            final student = (await crm.listStudents()).singleWhere(
              (r) => r['id'] == studentId,
            );
            final name = '${student['first_name']} ${student['last_name']}'
                .trim();
            await h.tap(find.text('Добавить ученика'));
            await h.quiet();
            await h.tap(find.text(name));
            await h.quiet();
            expect((await members()).map((r) => r['id']).toList(), [studentId]);
          },
        );
        await h.check(
          'MEMBER-REOPEN',
          'Ученик сохраняется после закрытия и открытия группы',
          () async {
            await h.tap(
              find.descendant(of: detail, matching: find.text('Закрыть')),
            );
            await h.quiet();
            await openGroup();
            expect((await members()).map((r) => r['id']).toList(), [studentId]);
            expect(
              find.descendant(
                of: detail,
                matching: find.byIcon(Icons.remove_circle_outline),
              ),
              findsOneWidget,
            );
          },
        );
        await h.check(
          'MEMBER-REMOVE-CANCEL',
          'Отказ от удаления оставляет ученика в группе',
          () async {
            await h.tap(
              find.descendant(
                of: detail,
                matching: find.byIcon(Icons.remove_circle_outline),
              ),
            );
            final confirm = find.ancestor(
              of: find.text('Удалить из группы?'),
              matching: find.byType(AlertDialog),
            );
            await h.tap(
              find.descendant(of: confirm, matching: find.text('Отмена')),
            );
            expect(await members(), hasLength(1));
          },
        );
        await h.check(
          'MEMBER-REMOVE',
          'Удалить ученика из состава и повторно открыть группу',
          () async {
            await h.tap(
              find.descendant(
                of: detail,
                matching: find.byIcon(Icons.remove_circle_outline),
              ),
            );
            final confirm = find.ancestor(
              of: find.text('Удалить из группы?'),
              matching: find.byType(AlertDialog),
            );
            await h.tap(
              find.descendant(of: confirm, matching: find.text('Удалить')),
            );
            await h.quiet();
            expect(await members(), isEmpty);
            await openGroup();
            expect(
              find.descendant(
                of: detail,
                matching: find.byIcon(Icons.remove_circle_outline),
              ),
              findsNothing,
            );
          },
        );
        await h.finish();
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  }
}
