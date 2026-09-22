import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/homework_attachment_service.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/widgets/file_attachment_widget.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/teacher_client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'homework_files_live_test.dart' show AuditFilePicker;
import 'live_audit_harness.dart';

class AuditDownloadDirectory extends PathProviderPlatform{
 AuditDownloadDirectory(this.directory);final String directory;
 @override Future<String?> getDownloadsPath()async=>directory;
 @override Future<String?> getTemporaryPath()async=>directory;
 @override Future<String?> getApplicationSupportPath()async=>directory;
}
void main(){IntegrationTestWidgetsFlutterBinding.ensureInitialized();setUpAll(()=>initializeDateFormatting('ru'));
 for(final role in ['admin','manager','director','teacher']){testWidgets('$role homework answers and real attachments',(tester)async{
  final h=LiveAuditHarness(tester,role,'attachment-runtime');await h.initialize(size:const Size(1550,1350));final crm=h.scope.read(magicCrmServiceProvider),access=await h.scope.read(capabilitySnapshotProvider.future),student=h.fixture['studentId'] as String,homework=h.fixture['homeworkId'] as String;
  const answerName='audit-homework-answer.txt';
  if(role=='admin'){
   final account=(h.fixture['accounts'] as List).cast<Map<String,dynamic>>().singleWhere((a)=>a['role']=='client');final api=MagicApiClient(baseUrl:h.fixture['baseUrl'],tokenStore:MemoryMagicTokenStore());addTearDown(()=>api.rawDio.close(force:true));final login=await api.post<Map<String,dynamic>>('/auth/login',authenticated:false,data:{'email':account['email'],'password':h.fixture['password']});await api.saveTokens(MagicApiTokens.fromJson(Map<String,dynamic>.from(login['session'] as Map)));
   final attachments=HomeworkAttachmentService(api);await attachments.uploadAndAttach(homeworkId:homework,bytes:Uint8List.fromList(utf8.encode('AUDIT homework answer\nРитм и ноты\n')),fileName:answerName,kind:'submission');await attachments.uploadAndAttach(homeworkId:homework,bytes:File(h.fixture['imagePath']).readAsBytesSync(),fileName:'audit-homework-answer.png',kind:'submission');await api.post<Map<String,dynamic>>('/crm/homeworks/$homework/submit',data:{});
  }
  Future<void> open()async{await tester.pumpWidget(const SizedBox.shrink());await tester.pump();await h.mount(Scaffold(body:role=='teacher'?TeacherClientCard(entityType:'student',entityId:student,routed:true):ClientCard(lead:{'id':student},entityType:'student',routed:true,initialSection:'progress',capabilitySnapshot:access)));await h.quiet();if(role=='teacher'){await h.tap(find.widgetWithText(ChoiceChip,'Домашние задания'));await h.quiet();}else{await h.tap(find.byKey(const Key('client-section-heading-progress')));await h.quiet();}}
  Finder file(String name)=>find.byWidgetPredicate((w)=>w is FileAttachmentWidget&&w.fileName==name);
  await h.check('OPEN','Открыть домашнее задание со сданным решением',()async{await open();expect(find.text('AUDIT-SUBMITTED-ANSWER'),findsOneWidget);});
  await h.check('ANSWER','Видеть вложения решения ученика',()async{final row=(await crm.listHomeworks(studentId:student)).singleWhere((r)=>r['id']==homework);expect(row['status'],'submitted');expect(row['attachments'],hasLength(2));h.facts.add({'step':h.currentStep,'homework':row});expect(file(answerName),findsOneWidget);expect(file('audit-homework-answer.png'),findsOneWidget);expect(find.text('Решение'),findsWidgets);});
  if(file('audit-homework-answer.png').evaluate().isNotEmpty){
   await h.check('PREVIEW','Открыть изображение решения и закрыть просмотр',()async{await h.tap(file('audit-homework-answer.png'));await h.quiet();expect(find.byType(InteractiveViewer),findsOneWidget);expect(find.byIcon(Icons.broken_image_rounded),findsNothing);await h.tap(find.byTooltip('Закрыть').last);await h.quiet();expect(find.byType(InteractiveViewer),findsNothing);});
   await h.check('REOPEN','Вложения решения сохраняются при повторном открытии',()async{await open();expect(file(answerName),findsOneWidget);expect(file('audit-homework-answer.png'),findsOneWidget);});
  }else{h.blocked('PREVIEW','Открыть изображение решения','Вложения не представлены в учебной карточке');h.blocked('REOPEN','Повторно открыть вложения','Вложения не представлены в учебной карточке');}
  if(role=='director'){
   final messenger=h.scope.read(magicMessengerServiceProvider),service=h.scope.read(chatAttachmentServiceProvider);final group=await messenger.createGroup(name:'AUDIT-ATTACHMENT-CHAT',memberUserIds:[h.fixture['memberUserId']]);final groupId=group['id'] as String;
   final bytes=Uint8List.fromList(utf8.encode('AUDIT attachment download\nНоты\n'));const name='audit-chat-download.txt';final fileId=await service.uploadFile(bytes:bytes,originalFileName:name,senderId:access.accountId,chatId:groupId);await messenger.sendMessage(groupId,content:'AUDIT-DOWNLOAD',attachmentFileId:fileId,messageType:'file');
   Future<void> chat()async{await tester.pumpWidget(const SizedBox.shrink());await tester.pump();await h.mount(const StaffWorkspaceScreen());await h.quiet();await h.tap(find.text('AUDIT-ATTACHMENT-CHAT').first);await h.quiet();}
   final dir=Directory('${Platform.environment['EVIDENCE_SCREENSHOT_DIR']}/attachment-downloads');dir.createSync(recursive:true);final previous=PathProviderPlatform.instance;PathProviderPlatform.instance=AuditDownloadDirectory(dir.path);addTearDown(()=>PathProviderPlatform.instance=previous);
   await h.check('DOWNLOAD','Нажать файл в чате и сверить сохранённые байты',()async{await chat();await h.tap(file(name));await h.waitFor(()=>File('${dir.path}/$name').existsSync(),'Download file created');await h.waitFor(()=>find.text('Файл сохранён: ${dir.path}${Platform.pathSeparator}$name').evaluate().isNotEmpty,'Actual download completed');expect(File('${dir.path}/$name').readAsBytesSync(),bytes);h.facts.add({'step':h.currentStep,'fileId':fileId,'byteCount':bytes.length,'bytesEqual':true,'path':'${dir.path}/$name'});});
   final original=FilePicker.platform;FilePicker.platform=AuditFilePicker(h.fixture['imagePath']);addTearDown(()=>FilePicker.platform=original);
   await h.check('PHOTO-SEND','Фото из галереи проходит реальную отправку и сохранение',()async{await h.tap(find.byTooltip('Прикрепить файл'));await h.tap(find.text('Фото из галереи'));await h.quiet();await h.tap(find.text('ОТПРАВИТЬ'));await h.quiet();final messages=await messenger.listMessages(groupId);expect(messages.where((m)=>m['attachment_file_id']!=null),hasLength(2));h.facts.add({'step':h.currentStep,'messages':messages});});
   await h.check('PHOTO-REOPEN','Переоткрыть чат и изображение в увеличенном виде',()async{await chat();await h.tap(file('icon.png'));await h.quiet();expect(find.byType(InteractiveViewer),findsOneWidget);expect(find.byIcon(Icons.broken_image_rounded),findsNothing);await h.tap(find.byTooltip('Закрыть').last);await h.quiet();});
  }
  await h.finish();
 },timeout:const Timeout(Duration(minutes:5)));}
}
