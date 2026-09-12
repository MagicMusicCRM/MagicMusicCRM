import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_details.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_view.dart';
import 'live_audit_harness.dart';

void main(){
 IntegrationTestWidgetsFlutterBinding.ensureInitialized();setUpAll(()=>initializeDateFormatting('ru'));
 for(final role in ['admin','manager','director']){testWidgets('$role tasks filters history entity navigation',(tester)async{
  final h=LiveAuditHarness(tester,role,'task-navigation');await h.initialize(size:const Size(1600,1300));
  final director=(h.fixture['accounts'] as List).cast<Map<String,dynamic>>().singleWhere((a)=>a['role']=='director');
  final api=MagicApiClient(baseUrl:h.fixture['baseUrl'],tokenStore:MemoryMagicTokenStore());addTearDown(()=>api.rawDio.close(force:true));
  final login=await api.post<Map<String,dynamic>>('/auth/login',authenticated:false,data:{'email':director['email'],'password':h.fixture['password']});await api.saveTokens(MagicApiTokens.fromJson(Map<String,dynamic>.from(login['session'] as Map)));
  final now=DateTime.now(),day=DateTime(now.year,now.month,now.day,12),student=h.fixture['students'][0];
  final title='AUDIT-TASK-NAV-$role';
  final task=await api.post<Map<String,dynamic>>('/crm/shared-tasks',data:{'title':title,'body':'Переход к ученику и история','allDay':true,'startAt':day.toUtc().toIso8601String(),'audiences':[{'type':'branch','targetId':h.fixture['branchId']}],'linkedEntity':{'type':'student','id':student}});
  final queries=<Map<String,dynamic>>[];
  h.api.rawDio.interceptors.add(InterceptorsWrapper(onRequest:(o,handler){if(o.method=='GET'&&o.uri.path.contains('/shared-tasks'))queries.add({'path':o.uri.path,...o.queryParameters});handler.next(o);}));
  Finder key(String k)=>find.byKey(Key(k));
  SharedTasksView view()=>tester.widget<SharedTasksView>(find.byType(SharedTasksView).first);
  await h.check('OPEN','Открыть задачи рабочего пространства и назначенную задачу',()async{await h.mount(StaffWorkspaceScreen(initialLink:EntityRouteRegistry.sectionRootLink('tasks')));await h.quiet();expect(find.text(title),findsOneWidget);});
  await h.check('SCOPE','Переключить Мой филиал, Вся школа и Все доступные',()async{for(final item in [('branch','Мой филиал'),('school','Вся школа'),('all','Все доступные')]){await h.tap(key('shared-task-scope-filter'));await h.tap(find.text(item.$2).last);await h.quiet();expect(view().state.query.scope,item.$1);expect(queries.any((q)=>q['scope']==item.$1),true);}expect(find.text(title),findsOneWidget);});
  await h.check('CALENDAR','Открыть календарь задач и перейти на следующий месяц и обратно',()async{await h.tap(key('shared-task-calendar-toggle'));await h.quiet();expect(key('shared-task-month-grid'),findsOneWidget);await h.tap(find.byTooltip('Следующий месяц'));await h.quiet();expect(view().state.query.calendarMonth,DateTime(now.year,now.month+1));await h.tap(find.byTooltip('Предыдущий месяц'));await h.quiet();expect(view().state.query.calendarMonth,DateTime(now.year,now.month));});
  await h.check('DAY','Открыть выбранный день из календаря и получить соответствующую задачу',()async{final date='${day.year}-${day.month.toString().padLeft(2,'0')}-${day.day.toString().padLeft(2,'0')}';await h.tap(key('shared-task-day-$date'));await h.quiet();expect(view().state.query.calendarMode,false);expect(view().state.query.day,DateTime(day.year,day.month,day.day));expect(find.text(title),findsOneWidget);h.facts.add({'step':h.currentStep,'queries':queries.toList()});});
  await h.check('HISTORY','Открыть детали и реальную историю создания задачи',()async{await h.tap(find.text(title));await h.quiet();expect(find.byType(SharedTaskDetails),findsOneWidget);expect(find.text('Задача создана'),findsOneWidget);expect(key('shared-task-linked-entity'),findsOneWidget);expect(h.requests.any((r)=>r['path'].toString().contains(task['id'])&&r['path'].toString().contains('history')&&r['status']==200),true);});
  await h.check('ENTITY','Нажать связанную запись и открыть карточку нужного ученика',()async{await h.tap(key('shared-task-linked-entity'));await h.quiet();expect(find.byType(ClientCard),findsOneWidget);expect(find.widgetWithText(TextFormField,'Имя'),findsWidgets);expect(h.requests.any((r)=>r['path']=='/api/crm/students/$student/card'&&r['status']==200),true);expect(find.byType(SharedTaskDetails),findsNothing,reason:'The source modal must release the opened destination');});
  await h.check('RETURN','Закрыть оставшееся окно и вернуться в исходную вкладку задач',()async{if(find.byType(SharedTaskDetails).evaluate().isNotEmpty){await h.tap(find.byTooltip('Закрыть').last);await h.quiet();}await h.tap(find.widgetWithText(TextButton,'Задачи'));await h.quiet();expect(find.byType(SharedTasksView),findsOneWidget);expect(find.text(title),findsOneWidget);});
  h.facts.add({'taskId':task['id'],'studentId':student});await h.finish();
 },timeout:const Timeout(Duration(minutes:5)));}
}
