import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/manage_entities_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/branch_form_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/reference_catalog_lifecycle_dialog.dart';

import 'live_audit_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Director manages a branch discipline binding',
    (tester) async {
      final h = LiveAuditHarness(tester, 'director', 'branch-discipline');
      await h.initialize(size: const Size(1440, 1400));
      final crm = h.scope.read(magicCrmServiceProvider);
      final branchId = h.fixture['branchId'] as String;
      final disciplineId = h.fixture['disciplineId'] as String;
      const name = 'BRANCH-DISCIPLINE-AUDIT';
      String? linkId;
      var restored = false;
      Future<List<Map<String, dynamic>>> links() =>
          crm.listBranchDisciplines(branchId, includeArchived: true);
      Future<Map<String, dynamic>> link() async {
        final value = (await links()).singleWhere((r) => r['id'] == linkId);
        h.facts.add({'step': h.currentStep, 'link': value});
        return value;
      }

      Future<void> openBranch() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await h.mount(
          SystemSettingsRouteScreen(
            key: UniqueKey(),
            initialArea: 'organization',
          ),
        );
        await h.waitFor(
          () => find.text('HTTP test').evaluate().isNotEmpty,
          'Branch list loaded',
        );
        await h.tap(find.text('HTTP test'));
        await h.waitFor(
          () => find.byType(BranchFormDialog).evaluate().isNotEmpty,
          'Actual branch editor opened',
        );
        await h.quiet();
      }

      Future<void> reason(String value) async {
        final field = find.byKey(const ValueKey('reference-reason-field'));
        await h.tap(field);
        await tester.enterText(field, value);
        await tester.pump();
      }

      Future<void> lifecycle(bool archived) async {
        await h.tap(
          find.byTooltip(
            archived ? 'Восстановить привязку' : 'Проверить связи и отвязать',
          ),
        );
        await h.waitFor(
          () => find
              .byKey(const ValueKey('reference-reason-field'))
              .evaluate()
              .isNotEmpty,
          'Binding lifecycle preview loaded',
        );
        await h.quiet();
      }

      await h.check(
        'OPEN',
        'Настройки → филиал → дисциплины филиала',
        () async {
          await openBranch();
          expect(find.text('Дисциплины филиала'), findsOneWidget);
        },
      );
      await h.check(
        'PICKER-CANCEL',
        'Закрытие выбора дисциплины не создаёт привязку',
        () async {
          await h.tap(find.widgetWithText(FilledButton, 'Добавить'));
          expect(find.byType(SimpleDialog), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await h.quiet();
          expect(find.byType(SimpleDialog), findsNothing);
          expect(
            (await links()).any((r) => r['discipline_id'] == disciplineId),
            isFalse,
          );
        },
      );
      await h.check(
        'ASSIGN',
        'Выбрать дисциплину и сохранить активную связь',
        () async {
          await h.tap(find.widgetWithText(FilledButton, 'Добавить'));
          await h.tap(find.widgetWithText(SimpleDialogOption, name));
          await h.quiet();
          final value = (await links()).singleWhere(
            (r) => r['discipline_id'] == disciplineId,
          );
          linkId = value['id'] as String;
          expect(value['lifecycle_state'], 'active');
          expect(find.text(name), findsOneWidget);
          await link();
        },
      );
      if (linkId == null) {
        h.blocked('LIFECYCLE', 'Привязка дисциплины', 'No binding created');
        await h.finish();
        return;
      }
      await h.check(
        'REOPEN',
        'Привязка сохраняется после закрытия и открытия формы филиала',
        () async {
          await openBranch();
          expect(find.text(name), findsOneWidget);
          expect((await link())['lifecycle_state'], 'active');
        },
      );
      await h.check(
        'UNASSIGN-CANCEL',
        'Закрытие preview отвязки сохраняет связь',
        () async {
          await lifecycle(false);
          await reason('BRANCH-NO-COMMIT');
          await h.tap(find.widgetWithText(TextButton, 'Закрыть'));
          expect((await link())['lifecycle_state'], 'active');
        },
      );
      await h.check(
        'UNASSIGN',
        'Отвязать дисциплину с причиной, сохранив историю',
        () async {
          await lifecycle(false);
          await reason('BRANCH-UNASSIGN');
          await h.tap(find.byKey(const ValueKey('reference-lifecycle-button')));
          await h.quiet();
          expect(find.byType(ReferenceCatalogLifecycleDialog), findsNothing);
          expect((await link())['lifecycle_state'], 'archived');
          expect(find.text('$name (в архиве)'), findsOneWidget);
          expect(
            (await crm.listDisciplines()).any((r) => r['id'] == disciplineId),
            isTrue,
          );
        },
      );
      await h.check(
        'RESTORE',
        'Восстановить привязку при активных родительских записях',
        () async {
          await lifecycle(true);
          await reason('BRANCH-RESTORE');
          await h.tap(find.byKey(const ValueKey('reference-lifecycle-button')));
          await h.quiet();
          final value = await link();
          restored = value['lifecycle_state'] == 'active';
          expect(restored, isTrue);
          expect(find.text(name), findsOneWidget);
        },
      );
      await h.check(
        'HISTORY',
        'История содержит отвязку и соответствует реально выполненным командам',
        () async {
          final history = await crm.listReferenceCatalogHistory(
            entityType: 'branch_discipline',
            id: linkId!,
          );
          h.facts.add({'step': h.currentStep, 'history': history});
          expect(history.any((r) => r['operation'] == 'unassign'), isTrue);
          expect(history.any((r) => r['operation'] == 'restore'), restored);
        },
      );
      if (!restored) {
        h.blocked(
          'RESTORED-STATE',
          'Повторное открытие восстановленной связи',
          'Restore command failed; binding remains archived',
        );
      }
      await h.finish();
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
