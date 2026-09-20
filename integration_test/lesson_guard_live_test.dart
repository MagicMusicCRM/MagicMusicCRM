import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'live_audit_harness.dart';
void main(){IntegrationTestWidgetsFlutterBinding.ensureInitialized();setUpAll(()=>initializeDateFormatting('ru'));
 testWidgets('director dirty and saving lesson close guards',(tester)async{
  final h=LiveAuditHarness(tester,'director','lesson-guard');await h.initialize(size:const Size(1500,1400));final crm=h.scope.read(magicCrmServiceProvider),id=h.fixture['lessonId'] as String;
  Future<Map<String,dynamic>> read()async=>(await crm.listLessons(lessonId:id,limit:1)).single;
  final before=await read();
  Finder editor()=>find.byType(CreateLessonDialog);
  Finder note()=>find.byKey(const Key('lesson-notes-input'));
  Future<void> open()async{await tester.pumpWidget(const SizedBox.shrink());await tester.pump();final row=await read();await h.mount(Scaffold(body:Builder(builder:(context)=>FilledButton(onPressed:()=>CreateLessonDialog.show(context,lesson:row),child:const Text('Открыть занятие')))));await h.tap(find.text('Открыть занятие'));await h.quiet();expect(editor(),findsOneWidget);}
  Future<void> fill(String value)async{await h.tap(note());await tester.enterText(note(),value);await tester.pump();}
  Future<void> cancel()=>h.tap(find.descendant(of:editor(),matching:find.widgetWithText(TextButton,'Отмена')));
  String value()=>tester.widget<EditableText>(find.descendant(of:note(),matching:find.byType(EditableText))).controller.text;
  await h.check('OPEN','Открыть актуальное занятие и его заметку',()async{await open();expect(value(),before['notes']??'');});
  await h.check('STAY','Отменить закрытие несохранённой заметки и сохранить черновик',()async{await fill('AUDIT-LESSON-DRAFT');await cancel();await h.quiet();expect(find.text('Отменить изменения?'),findsOneWidget);await h.tap(find.widgetWithText(TextButton,'Остаться'));await h.quiet();expect(editor(),findsOneWidget);expect(value(),'AUDIT-LESSON-DRAFT');expect((await read())['notes'],before['notes']);});
  await h.check('DISCARD','Подтвердить отказ от черновика без изменения занятия',()async{await cancel();await h.quiet();await h.tap(find.widgetWithText(FilledButton,'Отменить изменения'));await h.quiet();expect(editor(),findsNothing);expect((await read())['notes'],before['notes']);});
  final hold=Completer<void>();bool entered=false,holdSave=false;
  h.api.rawDio.interceptors.add(InterceptorsWrapper(onRequest:(o,handler)async{if(holdSave&&o.method=='PATCH'&&o.uri.path=='/api/crm/lessons/$id'){entered=true;await hold.future;}handler.next(o);}));
  await h.check('BUSY','Во время незавершённого сохранения форма не закрывается',()async{await open();await fill('AUDIT-LESSON-BUSY');holdSave=true;var remained=false;try{await h.tap(find.descendant(of:editor(),matching:find.widgetWithText(FilledButton,'Рассчитать')));await h.waitFor(()=>entered,'Actual note mutation entered transport');await cancel();await tester.pump(const Duration(milliseconds:400));remained=editor().evaluate().isNotEmpty;h.facts.add({'step':h.currentStep,'remainedOpen':remained,'requestHeld':entered});}finally{holdSave=false;if(!hold.isCompleted)hold.complete();}await h.quiet();expect(remained,true,reason:'Busy form must keep the in-flight command visible');});
  await h.check('SAVED','Единственное сохранение заметки меняет только версию и текст',()async{final after=await read();expect(after['notes'],'AUDIT-LESSON-BUSY');expect(int.parse(after['version'].toString()),int.parse(before['version'].toString())+1);expect(after['status'],before['status']);h.facts.add({'step':h.currentStep,'before':before,'after':after});});
  await h.check('REOPEN','Сохранённая заметка читается при повторном открытии',()async{await open();expect(value(),'AUDIT-LESSON-BUSY');});await h.finish();
 },timeout:const Timeout(Duration(minutes:4)));
}
