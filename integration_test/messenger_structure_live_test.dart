import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/widgets/telegram/create_group_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/channel_editor_dialog.dart';
import 'package:magic_music_crm/core/widgets/telegram/send_file_dialog.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'homework_files_live_test.dart' show AuditFilePicker;
import 'live_audit_harness.dart';

void main() {
 IntegrationTestWidgetsFlutterBinding.ensureInitialized();
 setUpAll(()=>initializeDateFormatting('ru'));
 for(final role in ['admin','manager','director']) {
  testWidgets('$role actual messenger groups channels files', (tester) async {
   final h=LiveAuditHarness(tester,role,'messenger-structure');
   await h.initialize(size:const Size(1600,1400));
   final service=h.scope.read(magicMessengerServiceProvider);
   final groupName='AUDIT-UI-GROUP-$role', channelName='AUDIT-UI-CHANNEL-$role';
   String? group, channel;
   Finder key(String value)=>find.byKey(ValueKey(value));
   Finder hint(String value)=>find.byWidgetPredicate((w)=>w is TextField&&w.decoration?.hintText==value);
   Future<void> fill(Finder field,String value)async{
    FocusManager.instance.primaryFocus?.unfocus();await tester.pump();await h.tap(field);await tester.enterText(field,value);await h.quiet();
   }
   Future<void> open()async{await tester.pumpWidget(const SizedBox.shrink());await tester.pump();await h.mount(const StaffWorkspaceScreen());await h.quiet();}
   Future<void> createMenu(String text)async{await h.tap(find.byTooltip('Создать чат или канал'));await h.tap(find.text(text));await h.quiet();}
   Future<void> info(String name)async{await h.tap(find.text(name).last);await h.quiet();expect(find.byType(ChatInfoDialog),findsOneWidget);}
   Future<void> closeInfo()async{await h.tap(find.descendant(of:find.byType(ChatInfoDialog),matching:find.byTooltip('Закрыть')));await h.quiet();}
   Future<List<Map<String,dynamic>>> members()async{final rows=await service.listChatMembers(group!);h.facts.add({'step':h.currentStep,'members':rows});return rows;}
   Future<void> addStudent1()async{
    await h.tap(find.descendant(of:find.byType(ChatInfoDialog),matching:find.text('Добавить')));
    await h.quiet();await h.tap(find.text('Student1 HTTP test'));await h.tap(find.text('Добавить (1)'));await h.quiet();
   }
   Future<void> removeStudent1()async{
    final row=find.ancestor(of:find.text('Student1 HTTP test'),matching:find.byType(Row)).first;
    await h.tap(find.descendant(of:row,matching:find.byTooltip('Удалить из группы')));await h.quiet();
   }
   await h.check('OPEN','Открыть рабочее пространство и меню создания чата',()async{await open();expect(find.byTooltip('Создать чат или канал'),findsOneWidget);});
   await h.check('GROUP-CANCEL','Отменить создание группы без записи',()async{
    await createMenu('Новая группа');expect(find.byType(CreateGroupChatDialog),findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Создать (0)')).onPressed,isNull);
    await fill(hint('Название группы'),groupName);await h.tap(find.text('Отмена'));
    expect((await service.listChats()).where((x)=>x['title']==groupName),isEmpty);
   });
   await h.check('GROUP-CREATE','Сохранить группу с выбранным участником и прочитать её через API',()async{
    await createMenu('Новая группа');await fill(hint('Название группы'),groupName);
    await fill(hint('Поиск пользователей...'),'Student0');await h.tap(find.text('Student0 HTTP test'));
    await h.tap(find.text('Создать (1)'));await h.quiet();
    final row=(await service.listChats()).singleWhere((x)=>x['title']==groupName);group=row['id'];
    expect((await members()).length,2);expect(find.text(groupName),findsWidgets);
   });
   if(group!=null){
    await h.check('GROUP-REOPEN','Повторное открытие группы сохраняет участников',()async{await open();await h.tap(find.text(groupName).first);await info(groupName);expect(find.text('Student0 HTTP test'),findsWidgets);});
    await h.check('MEMBER-ADD','Добавить второго ученика через сведения о группе',()async{await addStudent1();expect((await members()).length,3);});
    await h.check('MEMBER-REMOVE-CANCEL','Отменить удаление участника',()async{await removeStudent1();await h.tap(find.text('Отмена'));expect((await members()).length,3);});
    await h.check('MEMBER-REMOVE','Удалить участника с подтверждением',()async{await removeStudent1();await h.tap(find.text('Удалить'));await h.quiet();expect((await members()).length,2);});
    await h.check('MEMBER-READD','Вернуть участника и перечитать состав',()async{await addStudent1();expect((await members()).length,3);await closeInfo();});
    final file=File('${Platform.environment['EVIDENCE_SCREENSHOT_DIR']}/audit-messenger-$role.txt');
    file.writeAsBytesSync(utf8.encode('AUDIT messenger $role\nРитм и ноты\n'));
    final original=FilePicker.platform,picker=AuditFilePicker(file.path);FilePicker.platform=picker;addTearDown(()=>FilePicker.platform=original);
    Future<void> attach()async{await h.tap(find.byTooltip('Прикрепить файл'));await h.tap(find.text('Файл'));await h.quiet();}
    await h.check('FILE-CHOOSER-CANCEL','Отмена системного выбора не создаёт сообщение',()async{picker.cancel=true;await attach();expect(await service.listMessages(group!),isEmpty);picker.cancel=false;});
    await h.check('FILE-DIALOG-CANCEL','Отменить отправку выбранного файла',()async{await attach();expect(find.byType(SendFileDialog),findsOneWidget);await h.tap(find.descendant(of:find.byType(SendFileDialog),matching:find.byTooltip('Закрыть')));expect(await service.listMessages(group!),isEmpty);});
    await h.check('FILE-SEND','Отправить файл с подписью и сохранить attachment',()async{
     await attach();await fill(hint('Добавить подпись...'),'AUDIT-FILE-CAPTION-$role');await h.tap(find.text('ОТПРАВИТЬ'));await h.quiet();
     final messages=await service.listMessages(group!);h.facts.add({'step':h.currentStep,'messages':messages});
     final row=messages.singleWhere((x)=>x['content']=='AUDIT-FILE-CAPTION-$role');expect(row['attachment_file_id'],isNotNull);
    });
    await h.check('FILE-REOPEN','Вложение остаётся в переписке после открытия заново',()async{await open();await h.tap(find.text(groupName).first);await h.quiet();expect(find.text('AUDIT-FILE-CAPTION-$role'),findsWidgets);expect(find.text(file.uri.pathSegments.last),findsWidgets);});
    await h.check('GROUP-LEAVE-CANCEL','Отменить выход из группы',()async{await info(groupName);await h.tap(find.text('Выйти'));await h.tap(find.text('Отмена'));expect((await members()).length,3);});
    await h.check('GROUP-LEAVE','Выйти из группы и сохранить историю',()async{await h.tap(find.text('Выйти'));await h.tap(find.widgetWithText(TextButton,'Выйти'));await h.quiet();expect((await service.listChats()).where((x)=>x['id']==group),isEmpty);});
   }
   await open();
   await h.check('CHANNEL-CANCEL','Отмена создания канала не создаёт запись',()async{await createMenu('Новый канал');await fill(key('channel-title'),channelName);await h.tap(find.text('Отмена'));expect((await service.listChannels()).where((x)=>x['title']==channelName),isEmpty);});
   await h.check('CHANNEL-CREATE','Сохранить канал с описанием и правами по ролям',()async{
    await createMenu('Новый канал');await fill(key('channel-title'),channelName);await fill(key('channel-description'),'AUDIT description');
    await h.tap(key('channel-access-role:client'));await h.tap(find.text('Чтение').last);
    await h.tap(key('channel-access-role:teacher'));await h.tap(find.text('Чтение и публикация').last);
    await h.tap(key('save-channel'));await h.quiet();
    channel=(await service.listChannels()).singleWhere((x)=>x['title']==channelName)['id'];
    final rows=await service.listChannelPermissions(channel!);h.facts.add({'step':h.currentStep,'permissions':rows});
    expect(rows.singleWhere((x)=>x['role']=='client')['can_write'],false);expect(rows.singleWhere((x)=>x['role']=='teacher')['can_write'],true);
   });
   if(channel!=null){
    await h.check('CHANNEL-EDIT','Изменить название и очистить описание через сведения канала',()async{
     await open();await h.tap(find.text(channelName).first);await info(channelName);
     await h.tap(find.descendant(of:find.byType(ChatInfoDialog),matching:find.text(channelName)).first);await h.quiet();expect(find.byType(ChannelEditorDialog),findsOneWidget);
     await fill(key('channel-title'),'$channelName edited');await fill(key('channel-description'),'');await h.tap(key('save-channel'));await h.quiet();
     final row=(await service.listChannels()).singleWhere((x)=>x['id']==channel);expect(row['title'],'$channelName edited');expect(row['description']??'','');
     await closeInfo();
    });
    await h.check('CHANNEL-REOPEN','Название и права канала сохраняются при повторном открытии',()async{await open();expect(find.text('$channelName edited'),findsWidgets);final rows=await service.listChannelPermissions(channel!);expect(rows.singleWhere((x)=>x['role']=='teacher')['can_write'],true);});
    await h.check('CHANNEL-POST','Опубликовать запись через редактор сообщения',()async{await h.tap(find.text('$channelName edited').first);await h.quiet();await fill(hint('Сообщение...'),'AUDIT-POST-$role');await h.tap(find.byTooltip('Отправить'));await h.quiet();expect((await service.listChannelPosts(channel!)).singleWhere((x)=>x['content']=='AUDIT-POST-$role')['id'],isNotNull);});
   }
   h.facts.add({'groupId':group,'channelId':channel});await h.finish();
  });
 }
}
