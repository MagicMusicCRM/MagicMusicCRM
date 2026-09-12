import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/access_management.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/access_invalidation_provider.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/features/crm/presentation/staff_workspace_screen.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'live_audit_harness.dart';

void main(){IntegrationTestWidgetsFlutterBinding.ensureInitialized();setUpAll(()=>initializeDateFormatting('ru'));
 for(final role in ['admin','manager'].where((r)=>Platform.environment['ACCESS_AUDIT_ROLE']==null||r==Platform.environment['ACCESS_AUDIT_ROLE'])){testWidgets('$role open card live access revocation',(tester)async{
  final h=LiveAuditHarness(tester,role,'access-runtime');await h.initialize(size:const Size(1500,1200));
  final director=(h.fixture['accounts'] as List).cast<Map<String,dynamic>>().singleWhere((a)=>a['role']=='director');
  final api=MagicApiClient(baseUrl:h.fixture['baseUrl'],tokenStore:MemoryMagicTokenStore());addTearDown(()=>api.rawDio.close(force:true));
  final login=await api.post<Map<String,dynamic>>('/auth/login',authenticated:false,data:{'email':director['email'],'password':h.fixture['password']});await api.saveTokens(MagicApiTokens.fromJson(Map<String,dynamic>.from(login['session'] as Map)));
  final service=MagicAccessManagementService(api),before=await h.scope.read(capabilitySnapshotProvider.future),student=h.fixture['students'][0] as String;
  final row=await h.api.get<Map<String,dynamic>>('/crm/students/$student');
  final conn=await h.scope.read(magicRealtimeServiceProvider).connect();addTearDown(conn.dispose);bool connected=false;conn.onConnect(()=>connected=true);conn.connect();
  Finder name()=>find.widgetWithText(TextFormField,'Имя').first;
  await h.check('OPEN','Открыть карточку с правом редактирования и реальным WebSocket',()async{
   await h.mount(Consumer(builder:(context,ref,child){ref.watch(accessInvalidationProvider);return StaffWorkspaceScreen(initialLink:EntityLink.typed(entityType:EntityLinkType.client,entityId:student,variant:'student'));}));await h.quiet();await h.waitFor(()=>connected,'Authenticated WebSocket connected');expect(find.byType(ClientCard),findsOneWidget);expect(tester.widget<TextFormField>(name()).enabled,isNot(false));expect(before.allows('crm.client.write'),true);
  });
  await h.check('REVOKE-EVENT','Директор отзывает право; открытая сессия сама получает новую версию доступа',()async{
   final access=await service.getUserAccess(before.accountId);await service.setOverride(userId:before.accountId,capabilityKey:'crm.client.write',effect:'deny',expectedVersion:access.accessVersion,emergencySurface:false,reasonCode:'audit.live_revoke',identity:MagicMutationIdentity.create('audit.live_revoke'));
   await h.waitFor(()=>h.scope.read(capabilitySnapshotProvider).asData?.value.accessVersion!=null&&h.scope.read(capabilitySnapshotProvider).asData!.value.accessVersion>before.accessVersion,'Automatic access invalidation');await h.quiet();final current=h.scope.read(capabilitySnapshotProvider).asData!.value;expect(current.allows('crm.client.write'),false);expect(h.scope.read(accessInvalidationProvider).asData,isNotNull);h.facts.add({'step':h.currentStep,'accountId':before.accountId,'beforeVersion':before.accessVersion,'afterVersion':current.accessVersion,'allowed':current.allows('crm.client.write')});
  });
  await h.check('CONTROLS','Отозванное право отключает изменение полей уже открытой карточки',()async{
   final edit=find.descendant(of:name(),matching:find.byType(EditableText));final w=tester.widget<EditableText>(edit);h.facts.add({'step':h.currentStep,'readOnly':w.readOnly,'formEnabled':tester.widget<TextFormField>(name()).enabled});expect(w.readOnly||tester.widget<TextFormField>(name()).enabled==false,true);
  });
  await h.check('SERVER-GUARD','Сервер отклоняет изменение после отзыва и сохраняет прежнее имя',()async{
   Object? error;try{await h.api.patch<Map<String,dynamic>>('/crm/students/$student',data:{'firstName':'AUDIT-DENIED-CHANGE','expectedVersion':row['version']});}catch(e){error=e;}expect(error,isNotNull);final after=await h.api.get<Map<String,dynamic>>('/crm/students/$student');expect(after['first_name']??after['firstName'],row['first_name']??row['firstName']);h.facts.add({'step':h.currentStep,'studentId':student,'unchanged':true});
  },expectedHttpErrors:[(method:'PATCH',path:'/api/crm/students/$student',status:403,maxCount:1)]);
  await h.finish();
 },timeout:const Timeout(Duration(minutes:4)));}
}
