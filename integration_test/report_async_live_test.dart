import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_drilldown_view.dart';
import 'live_audit_harness.dart';
void main(){IntegrationTestWidgetsFlutterBinding.ensureInitialized();setUpAll(()=>initializeDateFormatting('ru'));
 for(final role in ['manager','director']){testWidgets('$role large asynchronous export and report entity links',(tester)async{
  final h=LiveAuditHarness(tester,role,'report-async');await h.initialize(size:const Size(1650,1600));final files=<Map<String,dynamic>>[],jobs=<Map<String,dynamic>>[],queries=<Map<String,dynamic>>[];
  h.api.rawDio.interceptors.add(InterceptorsWrapper(onRequest:(o,handler){queries.add({'method':o.method,'path':o.uri.path,'query':Map<String,dynamic>.from(o.queryParameters)});handler.next(o);},onResponse:(r,handler){if(r.requestOptions.uri.path.endsWith('/analytics/v4/exports')){final data=r.data is List<int>?jsonDecode(utf8.decode(r.data as List<int>)):r.data;if(data is Map&&data['mode']=='async'){expect(r.statusCode,201);jobs.add(Map<String,dynamic>.from(data));}}handler.next(r);}));
  Finder key(String k)=>find.byKey(ValueKey(k));
  await h.check('OPEN','Открыть аналитику с более чем 10 000 реальных клиентов',()async{await h.mount(ProviderScope(overrides:[reportFileOpenerProvider.overrideWithValue((bytes,name)async{validateReportExportBytes(bytes,name.split('.').last);final p='${Platform.environment['EVIDENCE_SCREENSHOT_DIR']}/$role-${files.length}-$name';await File(p).writeAsBytes(bytes,flush:true);files.add({'path':p,'name':name,'size':bytes.length,'format':name.split('.').last});if(name.endsWith('.csv')){final text=utf8.decode(bytes);expect(text.contains('AUDIT-LARGE-00001'),true);expect(text.contains('AUDIT-LARGE-10001'),true);}return ReportFileOpenResult(path:p,opened:false);})],child:StaffWorkspaceScreen(initialLink:EntityLink.typed(entityType:EntityLinkType.report,entityId:'__section__',optionalFocus:EntityLinkFocus(focus:'section',filter:{'from':'2026-01-01','to':'2026-12-31','branchId':h.fixture['branchId']})))));await h.quiet();expect(key('reporting-content'),findsOneWidget);expect(find.textContaining('10001'),findsWidgets);});
  for(final format in ['CSV','XLSX']){await h.check('EXPORT-$format','Кнопка $format создаёт async job, получает готовность и скачивает файл',()async{final before=files.length,jobsBefore=jobs.length;await h.tap(find.widgetWithText(OutlinedButton,format));final deadline=DateTime.now().add(const Duration(seconds:70));while(files.length==before&&DateTime.now().isBefore(deadline)){await tester.pump(const Duration(milliseconds:200));}expect(files.length,before+1);expect(jobs.length,jobsBefore+1);expect(jobs.last['rowCount'],greaterThan(10000));final job=jobs.last['jobId'];expect(queries.where((q)=>q['method']=='GET'&&q['path'].toString().contains(job)),isNotEmpty);expect(key('report-export-error'),findsNothing);h.facts.add({'step':h.currentStep,'job':jobs.last,'file':files.last});});}
  await h.check('DRILLDOWN','Открыть реальный список активных учеников',()async{await h.tap(find.text('active').first);await h.quiet();expect(key('reporting-drilldown'),findsOneWidget);final view=tester.widget<ReportingDrilldownView>(find.byType(ReportingDrilldownView));expect((view.data!['items'] as List),isNotEmpty);h.facts.add({'step':h.currentStep,'data':view.data});});
  String? target;
  await h.check('ENTITY-LINK','Строка отчёта открывает карточку того самого ученика',()async{final view=tester.widget<ReportingDrilldownView>(find.byType(ReportingDrilldownView)),item=(view.data!['items'] as List).first as Map;target=(item['entityLink'] as Map)['entityId'];await h.tap(find.descendant(of:key('reporting-drilldown'),matching:find.byType(ListTile)).first);await h.quiet();expect(find.byType(ClientCard),findsOneWidget);expect(tester.widget<ClientCard>(find.byType(ClientCard)).lead['id'],target);expect(h.requests.any((r)=>r['path']=='/api/crm/students/$target/card'&&r['status']==200),true);});
  await h.check('RETURN','Вернуться в исходную аналитику с открытым списком и теми же фильтрами',()async{await h.tap(find.widgetWithText(TextButton,'Аналитика').first);await h.quiet();expect(key('reporting-drilldown'),findsOneWidget);await h.tap(find.text('К отчёту'));await h.quiet();expect(key('reporting-content'),findsOneWidget);});h.facts.add({'files':files,'jobs':jobs,'queries':queries});await h.finish();
 },timeout:const Timeout(Duration(minutes:6)));}
}
