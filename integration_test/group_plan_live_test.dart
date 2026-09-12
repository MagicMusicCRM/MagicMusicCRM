import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/group_detail_dialog.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/preferred_schedule_editor.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/group_schedule_participants_editor.dart';
import 'live_audit_harness.dart';

void main(){
 IntegrationTestWidgetsFlutterBinding.ensureInitialized();setUpAll(()=>initializeDateFormatting('ru'));
 testWidgets('director group plan creation and dated membership',(tester)async{
  final h=LiveAuditHarness(tester,'director','group-plan');await h.initialize(size:const Size(1600,1500));
  final crm=h.scope.read(magicCrmServiceProvider),group=h.fixture['groupId'] as String;
  final students=(h.fixture['students'] as List).cast<String>();const title='AUDIT-GROUP-PLAN';
  Finder key(String k)=>find.byKey(ValueKey(k));
  Future<void> click(String k)=>h.tap(key(k));
  Future<List<SchedulePlan>> plans()=>crm.listSchedulePlans(groupId:group,includeArchived:true);
  Future<SchedulePlan> current()async{final p=(await plans()).singleWhere((p)=>p.title==title);h.facts.add({'step':h.currentStep,'planId':p.id,'version':p.version,'participants':p.currentParticipants.map((v)=>{'studentId':v.studentId,'subscriptionId':v.subscriptionId}).toList()});return p;}
  Future<void> open()async{await tester.pumpWidget(const SizedBox.shrink());await tester.pump();final row=await crm.getGroup(group);await h.mount(Scaffold(body:Builder(builder:(context)=>FilledButton(onPressed:()=>GroupDetailDialog.show(context,row,canWrite:true),child:const Text('Открыть группу')))));await h.tap(find.text('Открыть группу'));await h.quiet();}
  Future<void> fill(String k,String value)async{await h.tap(key(k));await tester.enterText(key(k),value);await h.quiet();}
  Future<void> weekdays(Set<int> wanted)async{for(var day=1;day<=7;day++){final f=key('preferred-schedule-weekday-$day');if(tester.widget<FilterChip>(f).selected!=wanted.contains(day))await h.tap(f);}}
  Future<void> select(String k,String label)async{await click(k);await h.tap(find.text(label).last);await h.quiet();}
  Future<void> date(String k,DateTime d)async{await click(k);final dialog=find.byType(DatePickerDialog);final loc=MaterialLocalizations.of(tester.element(dialog));await h.tap(find.byTooltip(loc.inputDateModeButtonLabel));final input=find.descendant(of:dialog,matching:find.byType(TextFormField));await h.tap(input);await tester.enterText(input,loc.formatCompactDate(d));await h.tap(find.text(loc.okButtonLabel));await h.quiet();expect(dialog,findsNothing);}
  Future<void> member(String id)=>h.tap(find.descendant(of:key('group-plan-member-$id'),matching:find.byType(CheckboxListTile)));
  await h.check('OPEN','Открыть групповую карточку и участников нового расписания',()async{await open();await click('schedule-plan-add');await h.quiet();expect(find.byType(GroupScheduleParticipantsEditor),findsOneWidget);expect(find.byType(CheckboxListTile),findsNWidgets(2));});
  await h.check('EMPTY','Запретить сохранение без участников',()async{for(final id in students)await member(id);await click('group-plan-participants-submit');expect(key('group-plan-participants-error'),findsOneWidget);expect(await plans(),isEmpty);});
  await h.check('DRAFT','Выбрать двух участников с абонементами и заполнить план',()async{for(final id in students)await member(id);await click('group-plan-participants-submit');await h.quiet();expect(find.byType(PreferredScheduleEditor),findsOneWidget);await fill('schedule-plan-title',title);await weekdays({1});await select('preferred-schedule-teacher','Teacher1 HTTP test');await select('preferred-schedule-room','Room 1');await click('schedule-plan-open-ended');await date('preferred-schedule-start',DateTime(2027,1,4));await date('preferred-schedule-end',DateTime(2027,1,17));await click('preferred-schedule-save');await h.quiet();expect(key('schedule-plan-row-group-0'),findsOneWidget);});
  await h.check('CREATE','Создать групповые занятия с двумя учениками',()async{await click('schedule-plan-preview-and-create');await h.quiet();final p=await current();expect(p.isGroup,true);expect(p.currentParticipants.map((v)=>v.studentId).toSet(),students.toSet());expect(p.currentRows,hasLength(1));});
  await h.check('GROUP-TIMELINE','Созданные занятия видны в списке группы',()async{await open();expect(find.text('Занятий группы пока нет.'),findsNothing,reason:'The group just created a plan with scheduled lessons');});
  Future<void> editMembers()async{await open();final p=await current();if(key('schedule-plan-participants-${p.id}').evaluate().isEmpty){await h.tap(find.text(title).first);await h.quiet();}await click('schedule-plan-participants-${p.id}');await h.quiet();expect(find.byType(GroupScheduleParticipantsEditor),findsOneWidget);}
  await h.check('REMOVE','Убрать второго участника только с 11 января',()async{await editMembers();await date('group-plan-effective-from',DateTime(2027,1,11));await member(students[1]);await click('group-plan-participants-submit');await h.quiet();await click('schedule-plan-preview-and-create');await h.quiet();await current();});
  await h.check('REOPEN','Переоткрыть состав и вернуть второго участника',()async{await editMembers();final tile=tester.widget<CheckboxListTile>(find.descendant(of:key('group-plan-member-${students[1]}'),matching:find.byType(CheckboxListTile)));expect(tile.value,false);await date('group-plan-effective-from',DateTime(2027,1,11));await member(students[1]);await click('group-plan-participants-submit');await h.quiet();await click('schedule-plan-preview-and-create');await h.quiet();await current();});
  await h.check('RESTORED','После открытия состав содержит обоих учеников',()async{await editMembers();for(final id in students)expect(tester.widget<CheckboxListTile>(find.descendant(of:key('group-plan-member-$id'),matching:find.byType(CheckboxListTile))).value,true);});
  await h.finish();
 },timeout:const Timeout(Duration(minutes:6)));
}
