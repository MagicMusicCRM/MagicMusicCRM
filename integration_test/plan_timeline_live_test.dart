import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_section.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_view.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'live_audit_harness.dart';
void main(){IntegrationTestWidgetsFlutterBinding.ensureInitialized();setUpAll(()=>initializeDateFormatting('ru'));
 final restart = Platform.environment['ST04_TIMELINE_RESTART'] == '1';
 testWidgets('director plan and lesson timeline pagination',(tester)async{
  final h=LiveAuditHarness(tester,'director','plan-timeline');await h.initialize(size:const Size(1600,1400));final crm=h.scope.read(magicCrmServiceProvider),student=h.fixture['studentId'] as String;
  Finder key(String k)=>find.byKey(ValueKey(k));
  Future<void> open()async{await tester.pumpWidget(const SizedBox.shrink());await tester.pump();await h.mount(Scaffold(body:SingleChildScrollView(child:RecurringSchedulePlanSection(studentId:student,subjectName:'AUDIT-TIMELINE',fallbackLessons:const[],branches:await crm.listBranches(limit:100),defaultBranchId:h.fixture['branchId'],subscriptions:await crm.listSubscriptions(studentId:student),canWrite:true,onChanged:(){}))));await h.quiet();}
  StudentLessonTimelineView timeline()=>tester.widget<StudentLessonTimelineView>(find.byType(StudentLessonTimelineView));
  Set<String> visibleIds()=>timeline().page.items.map((i)=>i.id).toSet();
  final initial=<String>{},all=<String>{};
  await h.check('OPEN','Четыре расписания и первая страница ленты',()async{final watch=Stopwatch()..start();await open();watch.stop();expect(find.text('1–3 из 4'),findsOneWidget);expect(timeline().page.items,isNotEmpty);initial.addAll(visibleIds());all.addAll(initial);expect(initial.length,30);h.facts.add({'step':h.currentStep,'loadElapsedMs':watch.elapsedMilliseconds});});
  await h.check('PLAN-PAGE','Следующая страница расписаний и возврат',()async{
   final pager=key('individual-schedule-plans');await h.tap(find.descendant(of:pager,matching:find.byTooltip('Следующие записи')));await h.quiet();expect(find.text('4–4 из 4'),findsOneWidget);await h.tap(find.descendant(of:pager,matching:find.byWidgetPredicate((w)=>w is Text&&(w.data??'').startsWith('AUDIT-TIMELINE-'))));await h.quiet();expect(find.byTooltip('Изменить строку с выбранной даты'),findsOneWidget);await h.tap(find.descendant(of:pager,matching:find.byTooltip('Предыдущие записи')));await h.quiet();expect(find.text('1–3 из 4'),findsOneWidget);
  });
  await h.check('TIMELINE-NEXT','Все следующие страницы ленты без потерь и повторов',()async{
   var rounds=0;while(timeline().page.hasNext){expect(rounds++,lessThan(12));final before=visibleIds();await h.tap(key('student-lesson-timeline-next'));await h.quiet();final after=visibleIds();if(after.difference(before).isNotEmpty){expect(all.intersection(after),isEmpty);all.addAll(after);}}
   expect(all,(h.fixture['lessonIds'] as List).cast<String>().toSet());h.facts.add({'step':h.currentStep,'allLessonIds':all.toList(),'pageCount':rounds});
  });
  await h.check('TIMELINE-PREVIOUS','Вернуться к первой странице занятий',()async{
   var rounds=0;while(!visibleIds().containsAll(initial)){expect(rounds++,lessThan(15));await h.tap(key('student-lesson-timeline-previous'));await h.quiet();}expect(visibleIds(),initial);
  });
  await h.check('OPEN-LESSON','Дата в ленте открывает настоящий редактор нужного занятия',()async{
   final item=timeline().page.items.first;await h.tap(key('student-timeline-${item.id}'));await h.quiet();expect(find.byType(CreateLessonDialog),findsOneWidget);expect(h.requests.any((r)=>r['step']==h.currentStep&&r['path']=='/api/crm/lessons'&&r['status']==200),true);h.facts.add({'step':h.currentStep,'lessonId':item.id});
  });
  await h.check('CLOSE-LESSON','Закрыть просмотр занятия и сохранить исходную ленту',()async{
   await h.tap(find.descendant(of:find.byType(CreateLessonDialog),matching:find.widgetWithText(TextButton,'Отмена')));await h.quiet();expect(find.byType(CreateLessonDialog),findsNothing);expect(visibleIds(),initial);
  });
   await h.check('REOPEN','Повторно открыть раздел с теми же занятиями',()async{await open();expect(visibleIds(),initial);});
   final source = timeline().page.items.firstWhere((item) => item.scheduledAt.toLocal().day <= 24);
   var currentId = source.id;
   final chain = <String>[currentId];
   Future<void> move(DateTime date, int hour) async {
     await h.tap(key('student-timeline-$currentId'));
     await h.quiet();
     await h.tap(key('lesson-date-field'));
     await h.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('${date.day}')).last);
     await h.tap(find.text('OK').last);
     await h.tap(key('lesson-time-field'));
     final timeDialog = find.byType(TimePickerDialog);
     final local = MaterialLocalizations.of(tester.element(timeDialog));
     await h.tap(find.byTooltip(local.inputTimeModeButtonLabel));
     final fields = find.descendant(of: timeDialog, matching: find.byType(TextField));
     await tester.enterText(fields.at(0), '$hour');
     await tester.enterText(fields.at(1), '0');
     await h.tap(find.descendant(of: timeDialog, matching: find.text(local.okButtonLabel)));
     await h.tap(key('lesson-edit-reason'));
     await tester.enterText(key('lesson-edit-reason'), 'Проверка актуальной ленты');
     await h.tap(find.widgetWithText(FilledButton, 'Рассчитать'));
     await h.quiet();
     expect(key('lesson-decision-preview'), findsOneWidget);
     await h.tap(find.widgetWithText(FilledButton, 'Подтвердить изменения'));
     await h.quiet();
     await h.waitFor(() => timeline().page.items.any((item) => item.reschedule.predecessorId == currentId), 'Current successor loaded');
     expect(visibleIds(), isNot(contains(currentId)));
     currentId = timeline().page.items.singleWhere((item) => item.reschedule.predecessorId == currentId).id;
     chain.add(currentId);
   }
   await h.check('TWO-MOVES','Два переноса через UI оставляют один текущий урок',()async{
     final date = source.scheduledAt.toLocal();
     await move(DateTime(date.year, date.month, date.day + 1), 11);
     await move(DateTime(date.year, date.month, date.day + 2), 12);
     expect(visibleIds().intersection(chain.toSet()), {currentId});
     h.facts.add({'step':h.currentStep,'chain':chain});
   });
   await h.check('CANCEL-CURRENT','Отмена из календаря убирает урок, сохраняя цепочку',()async{
     final current = timeline().page.items.singleWhere((item) => item.id == currentId);
     await tester.pumpWidget(const SizedBox.shrink());await tester.pump();
     await h.mount(Scaffold(body: ScheduleWidget(initialBranchId: h.fixture['branchId'], initialViewState: ContextViewState(date: current.scheduledAt.toLocal(), filters: {'view':'day','branchId':h.fixture['branchId']}))));
     await h.quiet();
     await h.tap(key('schedule-lesson-$currentId').first);
     await h.tap(find.text('Отменить занятие'));
     await h.quiet();
     await h.tap(key('lesson-decision-reason'));
     await tester.enterText(key('lesson-decision-reason'), 'Проверка отмены актуального урока');
     await h.tap(key('lesson-decision-submit'));
     await h.quiet();
     expect(key('lesson-decision-preview'), findsOneWidget);
     await h.tap(key('lesson-decision-submit'));
     await h.quiet();
     final reloadWatch = Stopwatch()..start();
     await open();
     reloadWatch.stop();
     final seen = <String>{...visibleIds()};
     var rounds = 0;
     while (timeline().page.hasNext) {
       expect(rounds++, lessThan(12));
       await h.tap(key('student-lesson-timeline-next'));
       await h.quiet();
       seen.addAll(visibleIds());
     }
     expect(seen.intersection(chain.toSet()), isEmpty);
     expect(seen.length, (h.fixture['lessonIds'] as List).length - 1);
     h.facts.add({'step':h.currentStep,'chain':chain,'visibleCount':seen.length,'loadElapsedMs':reloadWatch.elapsedMilliseconds});
   });
   await h.finish();
 }, skip: restart);
 testWidgets('client sees only current lessons after process restart',(tester)async{
  final h=LiveAuditHarness(tester,'client','plan-timeline-restart');
  await h.initialize(size:const Size(1600,1400));
  final student=h.fixture['studentId'] as String;
  final chain=(h.fixture['chain'] as List).cast<String>().toSet();
  await h.check('RESTART-CLIENT','Новый процесс клиента читает текущую ленту без истории переносов',()async{
   await h.mount(Scaffold(body:SingleChildScrollView(child:RecurringSchedulePlanSection(
    studentId:student,subjectName:'AUDIT-TIMELINE',fallbackLessons:const[],
    branches:const[],defaultBranchId:h.fixture['branchId'],subscriptions:const[],
    canWrite:false,onChanged:(){}))));
   await h.waitFor(() {final found=find.byType(StudentLessonTimelineView);return found.evaluate().isNotEmpty&&tester.widget<StudentLessonTimelineView>(found).page.items.isNotEmpty;},'Client timeline loaded');
   expect(find.byKey(const ValueKey('schedule-plan-add')),findsNothing);
   expect(find.byTooltip('Изменить строку с выбранной даты'),findsNothing);
   final seen=<String>{};var rounds=0;
   StudentLessonTimelineView view()=>tester.widget<StudentLessonTimelineView>(find.byType(StudentLessonTimelineView));
   while(true){seen.addAll(view().page.items.map((item)=>item.id));if(!view().page.hasNext)break;
    expect(rounds++,lessThan(12));await h.tap(find.byKey(const ValueKey('student-lesson-timeline-next')));await h.quiet();}
   expect(seen.length,(h.fixture['lessonIds'] as List).length-1);
   expect(seen.intersection(chain),isEmpty);
   h.facts.add({'step':h.currentStep,'visibleCount':seen.length,'pageCount':rounds});
  });
  await h.finish();
 },skip:!restart,timeout:const Timeout(Duration(minutes:4)));
}
