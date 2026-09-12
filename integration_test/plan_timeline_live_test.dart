import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_section.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/recurring_schedule_plan_view.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'live_audit_harness.dart';
void main(){IntegrationTestWidgetsFlutterBinding.ensureInitialized();setUpAll(()=>initializeDateFormatting('ru'));
 testWidgets('director plan and lesson timeline pagination',(tester)async{
  final h=LiveAuditHarness(tester,'director','plan-timeline');await h.initialize(size:const Size(1600,1400));final crm=h.scope.read(magicCrmServiceProvider),student=h.fixture['studentId'] as String;
  Finder key(String k)=>find.byKey(ValueKey(k));
  Future<void> open()async{await tester.pumpWidget(const SizedBox.shrink());await tester.pump();await h.mount(Scaffold(body:SingleChildScrollView(child:RecurringSchedulePlanSection(studentId:student,subjectName:'AUDIT-TIMELINE',fallbackLessons:const[],branches:await crm.listBranches(limit:100),defaultBranchId:h.fixture['branchId'],subscriptions:await crm.listSubscriptions(studentId:student),canWrite:true,onChanged:(){}))));await h.quiet();}
  StudentLessonTimelineView timeline()=>tester.widget<StudentLessonTimelineView>(find.byType(StudentLessonTimelineView));
  Set<String> visibleIds()=>timeline().page.items.map((i)=>i.id).toSet();
  final initial=<String>{},all=<String>{};
  await h.check('OPEN','Четыре расписания и первая страница ленты',()async{await open();expect(find.text('1–3 из 4'),findsOneWidget);expect(timeline().page.items,isNotEmpty);initial.addAll(visibleIds());all.addAll(initial);expect(initial.length,30);});
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
  await h.check('REOPEN','Повторно открыть раздел с теми же занятиями',()async{await open();expect(visibleIds(),initial);});await h.finish();
 });
}
