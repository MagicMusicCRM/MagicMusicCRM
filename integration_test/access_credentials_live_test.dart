import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/security/access_management.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_dialog.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/user_roles_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/access_editor_sheet.dart';
import 'live_audit_harness.dart';

void main(){
 IntegrationTestWidgetsFlutterBinding.ensureInitialized();setUpAll(()=>initializeDateFormatting('ru'));
 for(final role in ['director','manager']){
 testWidgets('$role actual credential and account controls',(tester)async{
  final h=LiveAuditHarness(tester,role,'access-credentials');await h.initialize(size:const Size(1500,1600));
  final crm=h.scope.read(magicCrmServiceProvider),profiles=h.scope.read(magicProfileAdminServiceProvider);
  final ids=Map<String,dynamic>.from(h.fixture['credentialTargets'] as Map);
  Future<void> mount(Widget w)async{await tester.pumpWidget(const SizedBox.shrink());await tester.pump();await h.mount(Scaffold(body:w));await h.quiet();}
  Future<Map<String,dynamic>> current(String type)async=>type=='staff'?(await crm.listStaff(q:'AUDIT-ACCESS')).singleWhere((r)=>r['id']==ids[type]):await crm.getTeacher(ids[type]);
  Future<void> open(String type)async{
   final row=await current(type);
   await mount(Builder(builder:(context)=>TextButton(onPressed:()=>type=='staff'?StaffDetailDialog.show(context,row,currentRole:role):TeacherDetailDialog.show(context,row),child:const Text('Открыть карточку'))));
   await h.tap(find.text('Открыть карточку'));await h.quiet();
  }
  Finder field(String label)=>find.byWidgetPredicate((w)=>w is TextField&&w.decoration?.labelText==label);
  Future<void> fill(String label,String value)async{await h.tap(field(label));await tester.enterText(field(label),value);await tester.pump();}
  Future<Map<String,dynamic>> credentials(String type)=>type=='staff'?crm.getStaffAccess(ids[type]):crm.getTeacherAccess(ids[type]);
  for(final type in ['staff','teacher']){
   final email='audit-access-$type@example.test',password=h.fixture['password'] as String;
   await h.check('$type-OPEN','Карточка и доступ к реквизитам: $type',()async{await open(type);expect(find.text(role=='director'?'Создать доступ':'Данные для входа'),role=='director'?findsOneWidget:findsNothing);if(role=='manager')expect(find.text('Создать доступ'),findsNothing);});
   if(role!='director')continue;
   await h.check('$type-CANCEL','Отмена создания доступа сохраняет отсутствие учётной записи',()async{await h.tap(find.text('Создать доступ'));await h.quiet();await h.tap(find.widgetWithText(TextButton,'Отмена').last);await h.quiet();expect((await current(type))['is_app_account'],false);});
   await h.check('$type-VALIDATION','Пустой email и несовпадающие пароли не отправляют сохранение',()async{
    await h.tap(find.text('Создать доступ'));await h.quiet();await fill('Почта для входа *','');final start=h.requests.length;
    await h.tap(find.widgetWithText(FilledButton,'Создать доступ').last);await h.quiet();expect(find.text('Укажите почту для входа'),findsOneWidget);
    await fill('Почта для входа *',email);await fill('Пароль *',password);await fill('Повторите новый пароль','mismatch');await h.tap(find.widgetWithText(FilledButton,'Создать доступ').last);await h.quiet();expect(find.text('Пароли не совпадают'),findsOneWidget);expect(h.requests.skip(start).where((r)=>r['method']=='POST'),isEmpty);
   });
   await h.check('$type-CREATE','Создать доступ и прочитать сохранённые реквизиты через отдельный GET',()async{
    await fill('Почта для входа *',email);await fill('Пароль *',password);await fill('Повторите новый пароль',password);await h.tap(find.widgetWithText(FilledButton,'Создать доступ').last);await h.quiet();
    expect(find.text('Данные для входа'),findsOneWidget);final r=await credentials(type);expect(r['email'],email);expect(r['password'],password);expect((await current(type))['is_app_account'],true);h.facts.add({'step':h.currentStep,'id':ids[type],'credentialsMatch':true});
   });
   await h.check('$type-REOPEN','Повторно открыть доступ: пароль скрыт и раскрывается кнопкой',()async{
    await open(type);await h.tap(find.text('Данные для входа'));await h.quiet();expect(tester.widget<TextField>(field('Актуальный пароль')).obscureText,true);expect(tester.widget<TextField>(field('Актуальный пароль')).controller!.text,password);
    final button=find.descendant(of:field('Актуальный пароль'),matching:find.byTooltip('Показать пароль'));await h.tap(button);expect(tester.widget<TextField>(field('Актуальный пароль')).obscureText,false);await h.tap(find.descendant(of:field('Актуальный пароль'),matching:find.byTooltip('Скрыть пароль')));
   });
   await h.check('$type-NOOP','Сохранение без изменений оставляет диалог и не отправляет команду',()async{
    final start=h.requests.length;await h.tap(find.widgetWithText(FilledButton,'Сохранить').last);await h.quiet();expect(find.text('Измените почту или укажите новый пароль'),findsOneWidget);expect(h.requests.skip(start).where((r)=>r['method']=='POST'),isEmpty);
   });
   await h.check('$type-CHANGE','Изменить почту и пароль, закрыть и прочитать новое состояние',()async{
    await fill('Почта для входа *','updated-$email');await fill('Новый пароль',password+'2');await fill('Повторите новый пароль',password+'2');await h.tap(find.widgetWithText(FilledButton,'Сохранить').last);await h.quiet();await open(type);await h.tap(find.text('Данные для входа'));await h.quiet();
    expect(tester.widget<TextField>(field('Почта для входа *')).controller!.text,'updated-$email');expect(tester.widget<TextField>(field('Актуальный пароль')).controller!.text,password+'2');final r=await credentials(type);expect(r['email'],'updated-$email');expect(r['password'],password+'2');await h.tap(find.widgetWithText(TextButton,'Отмена').last);
   });
  }
  if(role=='director'){
   Future<void> directory()async=>mount(const UserRolesWidget(currentRole:'director'));
   final search=find.byWidgetPredicate((w)=>w is TextField&&w.decoration?.hintText=='Поиск по имени, почте, телефону...');
   Future<void> query(String text)async{FocusManager.instance.primaryFocus?.unfocus();await tester.pump();await h.tap(search);await tester.enterText(search,text);await h.quiet();}
   await h.check('SEARCH','Поиск аккаунта по имени, email и телефону через реальный список',()async{
    await directory();for(final q in ['AUDIT-AUTO','audit-autolink@example.test','79991234567']){await query(q);expect(find.text('HTTP test AUDIT-AUTO'),findsOneWidget);}await query('AUDIT-NO-ACCOUNT');expect(find.text('HTTP test AUDIT-AUTO'),findsNothing);await query('AUDIT-AUTO');
   });
   await h.check('AUTO-PREVIEW','Открыть кандидата автосвязи и отменить без изменения',()async{
    await h.tap(find.byTooltip('Связать по телефону'));await h.quiet();expect(find.text('Student1 HTTP test'),findsNothing);expect(find.text('HTTP test Student1'),findsOneWidget);await h.tap(find.widgetWithText(TextButton,'Закрыть').last);expect(await profiles.getProfileLinks(ids['autoProfile']),isEmpty);
   });
   await h.check('AUTO-LINK','Автосвязь с единственным учеником сохраняется после переоткрытия',()async{
    await h.tap(find.byTooltip('Связать по телефону'));await h.quiet();await h.tap(find.text('Автосвязь'));await h.quiet();final links=await profiles.getProfileLinks(ids['autoProfile']);expect(links.map((r)=>r['entity_id']),contains(h.fixture['studentId']));await directory();await query('AUDIT-AUTO');expect(find.text('1 учен.'),findsOneWidget);h.facts.add({'step':h.currentStep,'links':links});
   });
   final access=h.scope.read(accessManagementServiceProvider),target=ids['grantUser'] as String;
   String? cap;
   await h.check('GRANT','Выдать отсутствующее по роли персональное разрешение',()async{
    final original=await access.getUserAccess(target);cap=original.capabilities.firstWhere((c)=>!c.effectiveAllowed&&c.canAllow).key;
    await mount(AccessEditorSheet(actorRole:role,userId:target,userLabel:'AUDIT-GRANT',embedded:true));await h.tap(find.byKey(ValueKey('access-capability-$cap')));await h.quiet();final item=(await access.getUserAccess(target)).capabilities.singleWhere((c)=>c.key==cap);expect(item.effectiveAllowed,true);expect(item.overrideEffect,'allow');h.facts.add({'step':h.currentStep,'capability':cap,'allowed':true});
   });
   await h.check('GRANT-REOPEN','Персональное предоставление сохраняется после повторного открытия',()async{
    expect(cap,isNotNull);await mount(AccessEditorSheet(actorRole:role,userId:target,userLabel:'AUDIT-GRANT',embedded:true));expect(tester.widget<SwitchListTile>(find.byKey(ValueKey('access-capability-$cap'))).value,true);
   });
  }
  await h.finish();
 });}
}
