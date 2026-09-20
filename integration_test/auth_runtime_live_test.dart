import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';
import 'package:magic_music_crm/core/router/app_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/login_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/legal_consent_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/widgets/auth_form_controls.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';
import 'evidence_screenshot.dart';
import 'live_audit_harness.dart';

class AuditLegalLauncher extends UrlLauncherPlatform{
 @override get linkDelegate=>throw UnimplementedError('Link widget is outside this launchUrl audit');
 final urls=<String>[];bool succeed=true;
 @override Future<bool> launchUrl(String url,LaunchOptions options)async{urls.add(url);return succeed;}
 @override Future<bool> canLaunch(String url)async=>true;
}
void main(){
 IntegrationTestWidgetsFlutterBinding.ensureInitialized();setUpAll(()=>initializeDateFormatting('ru'));
 const roles=['admin','manager','director','teacher','client'];
 for(final role in roles.where((r)=>Platform.environment['AUTH_AUDIT_ROLE']==null||r==Platform.environment['AUTH_AUDIT_ROLE'])){testWidgets('$role actual access retry documents logout account switch',(tester)async{
  final h=LiveAuditHarness(tester,role,'auth-runtime');await h.initialize(size:const Size(1440,1600));
  final accounts=(h.fixture['accounts'] as List).cast<Map<String,dynamic>>(),nextRole=roles[(roles.indexOf(role)+1)%roles.length];
  final nextAccount=accounts.singleWhere((a)=>a['role']==nextRole);
  final second=MagicApiClient(baseUrl:h.fixture['baseUrl'],tokenStore:MemoryMagicTokenStore());addTearDown(()=>second.rawDio.close(force:true));
  final login=await second.post<Map<String,dynamic>>('/auth/login',authenticated:false,data:{'email':nextAccount['email'],'password':h.fixture['password']});await second.saveTokens(MagicApiTokens.fromJson(Map<String,dynamic>.from(login['session'] as Map)));
  for(final api in [h.api,second]){
   await api.patch<Map<String,dynamic>>('/profile/me',data:{'firstName':'AUDIT-AUTH','lastName':api==h.api?role:nextRole,'phone':'+79992220${accounts.indexOf(accounts.singleWhere((a)=>a['role']==(api==h.api?role:nextRole)))+100}'});
   final docs=await api.get<List<dynamic>>('/legal/documents/current');await api.post<Map<String,dynamic>>('/legal/consents/current',data:{'documentIds':docs.map((d)=>(d as Map)['id']).toList()});
  }
  final documents=await h.api.get<List<dynamic>>('/legal/documents/current');
  final launcher=AuditLegalLauncher(),previousLauncher=UrlLauncherPlatform.instance;UrlLauncherPlatform.instance=launcher;addTearDown(()=>UrlLauncherPlatform.instance=previousLauncher);
  bool gateFault=true;
  h.api.rawDio.interceptors.add(InterceptorsWrapper(onRequest:(o,handler){if(gateFault&&o.uri.path.endsWith('/legal/gate')){h.trace(o,503,error:'injectedGateFailure');handler.reject(DioException(requestOptions:o,type:DioExceptionType.badResponse,response:Response(requestOptions:o,statusCode:503,data:{'message':'AUDIT injected temporary gate failure'})));}else{handler.next(o);}}));
  GoRouter router()=>h.scope.read(routerProvider);final routers=<GoRouter>{};addTearDown((){for(final r in routers){r.dispose();}});
  String routeFor(String r)=>r=='director'||r=='manager'?'/manager':'/$r';
  await h.check('GATE-ERROR','Ошибка проверки доступа показывает повтор, сохраняя авторизацию',()async{
   await tester.pumpWidget(UncontrolledProviderScope(container:h.scope,child:RepaintBoundary(key:evidenceRootKey,child:Consumer(builder:(context,ref,child){final r=ref.watch(routerProvider);routers.add(r);return MaterialApp.router(theme:AppTheme.production,routerConfig:r,locale:const Locale('ru'),supportedLocales:const[Locale('ru'),Locale('en')],localizationsDelegates:const[GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate]);}))));
   await h.waitFor(()=>find.text('Повторить').evaluate().isNotEmpty,'Gate retry visible');expect(await h.api.readTokens(),isNotNull);
  },expectedHttpErrors:const[(method:'GET',path:'/api/legal/gate',status:503,maxCount:4)]);
  await h.check('GATE-RETRY','Повторить реальную проверку и открыть рабочее пространство роли',()async{gateFault=false;await h.tap(find.text('Повторить'));await h.waitFor(()=>router().routeInformationProvider.value.uri.path==routeFor(role),'Role after retry');await h.quiet();expect(find.byType(LoginScreen),findsNothing);});
  await h.check('LEGAL-OPEN','Профиль → Юридические документы показывает актуальные документы API',()async{
   router().push('/profile');await h.quiet();expect(find.byType(ProfileScreen),findsOneWidget);await h.tap(find.text('Юридические документы'));await h.quiet();expect(find.byType(LegalConsentScreen),findsOneWidget);expect(find.byTooltip('Открыть документ'),findsNWidgets(documents.length));
  });
  await h.check('LEGAL-LINKS','Каждая кнопка передаёт URL документа системному обработчику',()async{
   for(var i=0;i<documents.length;i++){await h.tap(find.byTooltip('Открыть документ').at(i));await h.quiet();}const expected=['https://magicmusiccrm-legal.vercel.app/privacy/','https://magicmusiccrm-legal.vercel.app/terms/','https://magicmusiccrm-legal.vercel.app/account-deletion/'];expect(launcher.urls,expected);h.facts.add({'step':h.currentStep,'urls':launcher.urls.toList(),'boundary':'OS browser dispatch captured; document hosting not exercised'});
  });
  await h.check('LEGAL-OPEN-ERROR','Отказ системного открытия показывает ошибку',()async{launcher.succeed=false;await h.tap(find.byTooltip('Открыть документ').first);await h.quiet();expect(find.text('Не удалось открыть документ'),findsOneWidget);launcher.succeed=true;});
  await h.check('LEGAL-BACK','Возврат из документов не разлогинивает пользователя',()async{await h.tap(find.text('Назад ко входу'));await h.waitFor(()=>router().routeInformationProvider.value.uri.path==routeFor(role),'Existing signed-in workspace');expect(await h.api.readTokens(),isNotNull);});
  await h.check('LOGOUT','Кнопка Выйти очищает токены и открывает форму входа',()async{
   await h.quiet();await h.tap(find.byIcon(Icons.menu_rounded).first);await h.tap(find.text('Выйти'));await h.waitFor(()=>find.byType(LoginScreen).evaluate().isNotEmpty,'Actual logout');expect(await h.api.readTokens(),isNull);expect(router().routeInformationProvider.value.uri.path,'/login');h.facts.add({'step':h.currentStep,'signedOut':true});
  },expectedHttpErrors:const[(method:'GET',path:'/api/legal/gate',status:401,maxCount:1),(method:'GET',path:'/api/access/me',status:401,maxCount:3)]);
  await h.check('SWITCH-ACCOUNT','Войти другим аккаунтом: новая роль и профиль без данных прежнего',()async{
   for(final entry in {'Телефон или почта':nextAccount['email'] as String,'Пароль':h.fixture['password'] as String}.entries){final input=find.descendant(of:find.byWidgetPredicate((w)=>w is AuthField&&w.label==entry.key),matching:find.byType(TextFormField));await h.tap(input);await tester.enterText(input,entry.value);await tester.pump();}
   await h.tap(find.text('Войти'));await h.waitFor(()=>router().routeInformationProvider.value.uri.path==routeFor(nextRole),'Different account workspace');await h.quiet();final p=await h.api.get<Map<String,dynamic>>('/profile/me');expect(p['role'],nextRole);expect(p['email'],nextAccount['email']);h.facts.add({'step':h.currentStep,'role':p['role'],'profileId':p['id'],'userId':p['userId']});
  });await h.finish();
 },timeout:const Timeout(Duration(minutes:5)));}
}
