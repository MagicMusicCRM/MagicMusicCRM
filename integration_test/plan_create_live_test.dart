import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_section.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/preferred_schedule_editor.dart';
import 'live_audit_harness.dart';

void main(){
 IntegrationTestWidgetsFlutterBinding.ensureInitialized();setUpAll(()=>initializeDateFormatting('ru'));
 testWidgets('director real multi-row schedule creation', (tester)async{
  final h=LiveAuditHarness(tester,'director','plan-create');await h.initialize(size:const Size(1600,1500));
  final crm=h.scope.read(magicCrmServiceProvider),student=h.fixture['studentId'] as String;const title='AUDIT-MULTI-ROW-PLAN';
  Finder key(String k)=>find.byKey(ValueKey(k));
  Future<void> click(String k)=>h.tap(key(k));
  Future<List<SchedulePlan>> plans()=>crm.listSchedulePlans(studentId:student,includeArchived:true);
  Future<SchedulePlan> current()async{final p=(await plans()).singleWhere((p)=>p.title==title);h.facts.add({'step':h.currentStep,'planId':p.id,'rows':p.currentRows.map((r)=>{'id':r.id,'weekday':r.weekday,'beginTime':r.beginTime,'teacherId':r.teacherId,'roomId':r.roomId}).toList()});return p;}
  Future<void> open()async{await tester.pumpWidget(const SizedBox.shrink());await tester.pump();await h.mount(Scaffold(body:SingleChildScrollView(child:RecurringSchedulePlanSection(studentId:student,subjectName:'Student1 HTTP test',fallbackLessons:const[],branches:await crm.listBranches(limit:100),defaultBranchId:h.fixture['branchId'],subscriptions:await crm.listSubscriptions(studentId:student),canWrite:true,onChanged:(){}))));await h.quiet();}
  Future<void> fill(String k,String value)async{await h.tap(key(k));await tester.enterText(key(k),value);await h.quiet();}
  Future<void> weekdays(Set<int> wanted)async{for(var day=1;day<=7;day++){final f=key('preferred-schedule-weekday-$day');if(tester.widget<FilterChip>(f).selected!=wanted.contains(day))await h.tap(f);}}
  Future<void> select(String k,String label)async{await click(k);await h.tap(find.text(label).last);await h.quiet();}
  Future<void> date(String k,DateTime d)async{await click(k);final dialog=find.byType(DatePickerDialog);final loc=MaterialLocalizations.of(tester.element(dialog));await h.tap(find.byTooltip(loc.inputDateModeButtonLabel));final input=find.descendant(of:dialog,matching:find.byType(TextFormField));await h.tap(input);await tester.enterText(input,loc.formatCompactDate(d));await h.tap(find.text(loc.okButtonLabel));await h.quiet();expect(dialog,findsNothing);}
  await h.check('OPEN','Открыть добавление постоянного расписания',()async{await open();await click('schedule-plan-add');await h.quiet();expect(find.byType(PreferredScheduleEditor),findsOneWidget);});
  if(find.byType(PreferredScheduleEditor).evaluate().isEmpty){await h.finish();return;}
  await h.check('CANCEL','Отмена пустой формы не создаёт план',()async{await h.tap(find.widgetWithText(OutlinedButton,'Отмена'));await h.quiet();expect((await plans()).where((p)=>p.title==title),isEmpty);});
  await h.check('VALIDATION','Создание без педагога и аудитории показывает ошибку',()async{await click('schedule-plan-add');await h.quiet();await click('preferred-schedule-save');expect(key('preferred-schedule-error'),findsOneWidget);expect((await plans()).where((p)=>p.title==title),isEmpty);});
  await h.check('DRAFT','Выбрать два дня, два занятия подряд и конечный период',()async{
   await fill('schedule-plan-title',title);await weekdays({1,3});await select('preferred-schedule-teacher','Teacher1 HTTP test');await select('preferred-schedule-room','Room 1');
   await select('preferred-schedule-lessons-per-day','2');await click('schedule-plan-open-ended');await date('preferred-schedule-start',DateTime(2027,1,4));await date('preferred-schedule-end',DateTime(2027,1,17));
   await click('preferred-schedule-save');await h.quiet();expect(key('schedule-plan-row-group-0'),findsOneWidget);expect((await plans()).where((p)=>p.title==title),isEmpty);
  });
  await h.check('ADD-ROW','Добавить пятницу с другим педагогом и аудиторией',()async{
   await click('schedule-plan-add-row-group');await h.quiet();await weekdays({5});await select('preferred-schedule-lessons-per-day','1');await select('preferred-schedule-teacher','Teacher0 HTTP test');await select('preferred-schedule-room','Room 0');await click('preferred-schedule-save');await h.quiet();expect(key('schedule-plan-row-group-1'),findsOneWidget);
  });
  await h.check('DUPLICATE','Повтор одинаковой строки отклоняется без создания плана',()async{
   await click('schedule-plan-add-row-group');await h.quiet();await click('preferred-schedule-save');await h.quiet();expect(key('schedule-plan-row-group-2'),findsOneWidget);await click('schedule-plan-preview-and-create');await h.quiet();expect(find.text('Проверьте введённые данные.'),findsOneWidget);expect((await plans()).where((p)=>p.title==title),isEmpty);
  },expectedHttpErrors:const[(method:'POST',path:'/api/crm/schedule-plans/constraints/preview',status:422,maxCount:1)]);
  await h.check('CONFLICT','Пересечение разных строк показывает конфликт до создания',()async{
   await click('schedule-plan-edit-row-group-2');await h.quiet();await click('preferred-schedule-time');final dialog=find.byType(TimePickerDialog),local=MaterialLocalizations.of(tester.element(find.byType(TimePickerDialog)));await h.tap(find.byTooltip(local.inputTimeModeButtonLabel));final fields=find.descendant(of:dialog,matching:find.byType(TextField));await h.tap(fields.at(0));await tester.enterText(fields.at(0),'15');await h.tap(fields.at(1));await tester.enterText(fields.at(1),'30');await h.tap(find.descendant(of:dialog,matching:find.text(local.okButtonLabel)));await click('preferred-schedule-save');await h.quiet();await click('schedule-plan-preview-and-create');await h.quiet();expect(key('schedule-plan-constraint-errors'),findsOneWidget);expect((await plans()).where((p)=>p.title==title),isEmpty);
  });
  await h.check('REMOVE-DRAFT-ROW','Удалить конфликтующую строку из черновика',()async{await click('schedule-plan-delete-row-group-2');expect(key('schedule-plan-row-group-2'),findsNothing);expect(key('schedule-plan-row-group-1'),findsOneWidget);});
  await h.check('CREATE','Проверить и сохранить несколько дней одной командой',()async{await click('schedule-plan-preview-and-create');await h.quiet();final p=await current();expect(p.currentRows,hasLength(5));expect(p.currentRows.map((r)=>r.weekday).toSet(),{1,3,5});expect(p.currentRows.map((r)=>r.teacherId).toSet(),(h.fixture['teachers'] as List).toSet());});
  await h.check('REOPEN','Повторно открыть пять строк и обе страницы',()async{
   await open();await h.tap(find.text(title).first);await h.quiet();final p=await current();final seen=<String>{};void collect(){for(final row in p.currentRows){if(key('schedule-plan-row-edit-${row.id}').evaluate().isNotEmpty)seen.add(row.id);}}
   collect();expect(seen,hasLength(3));await h.tap(find.byTooltip('Следующие записи').first);await h.quiet();collect();expect(seen,p.currentRows.map((r)=>r.id).toSet());await h.tap(find.byTooltip('Предыдущие записи').first);await h.quiet();expect(find.text('1–3 из 5'),findsOneWidget);h.facts.add({'step':h.currentStep,'visibleRowIds':seen.toList()});
  });
  await h.check('COLLAPSE-REOPEN','Свернуть и повторно раскрыть расписание после смены страницы',()async{await h.tap(find.text(title).first);await h.quiet();expect(find.byTooltip('Изменить строку с выбранной даты'),findsNothing);await h.tap(find.text(title).first);await h.quiet();expect(find.byTooltip('Изменить строку с выбранной даты'),findsNWidgets(3));});
  await h.finish();
 });
}
