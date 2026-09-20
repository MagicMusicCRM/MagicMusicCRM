import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/router/app_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/login_screen.dart';
import 'package:magic_music_crm/features/auth/presentation/widgets/auth_form_controls.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'evidence_screenshot.dart';
import 'live_audit_harness.dart';

void main(){IntegrationTestWidgetsFlutterBinding.ensureInitialized();setUpAll(()=>initializeDateFormatting('ru'));
 for(final role in ['admin','manager','director']){testWidgets('$role entity URI across login',(tester)async{
  final h=LiveAuditHarness(tester,role,'deep-link');await h.initialize(size:const Size(1500,1300));
  final account=(h.fixture['accounts'] as List).cast<Map<String,dynamic>>().singleWhere((a)=>a['role']==role),student=h.fixture['students'][0] as String;
  await h.api.patch<Map<String,dynamic>>('/profile/me',data:{'firstName':'AUDIT-DEEPLINK','lastName':role,'phone':'+79994445566'});
  final docs=await h.api.get<List<dynamic>>('/legal/documents/current');await h.api.post<Map<String,dynamic>>('/legal/consents/current',data:{'documentIds':docs.map((d)=>(d as Map)['id']).toList()});
  await h.scope.read(magicAuthServiceProvider).signOut();
  GoRouter router()=>h.scope.read(routerProvider);final routers=<GoRouter>{};addTearDown((){for(final r in routers){r.dispose();}});
  await h.check('SIGNED-OUT','Открыть приложение без сессии и получить форму входа',()async{
   await tester.pumpWidget(UncontrolledProviderScope(container:h.scope,child:RepaintBoundary(key:evidenceRootKey,child:Consumer(builder:(context,ref,child){final r=ref.watch(routerProvider);routers.add(r);return MaterialApp.router(theme:AppTheme.production,routerConfig:r,locale:const Locale('ru'),supportedLocales:const[Locale('ru'),Locale('en')],localizationsDelegates:const[GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate]);}))));await h.quiet();expect(find.byType(LoginScreen),findsOneWidget);
  });
  await h.check('URI-LOGIN','Ссылка ученика без сессии открывает вход и не выдаёт данные',()async{final start=h.requests.length;router().go('/students/$student?section=overview');await h.quiet();expect(find.byType(LoginScreen),findsOneWidget);expect(h.requests.skip(start).any((r)=>r['path'].toString().contains(student)),false);});
  await h.check('LOGIN','Войти настоящими реквизитами после перехода по ссылке',()async{
   for(final item in {'Телефон или почта':account['email'] as String,'Пароль':h.fixture['password'] as String}.entries){final f=find.descendant(of:find.byWidgetPredicate((w)=>w is AuthField&&w.label==item.key),matching:find.byType(TextFormField));await h.tap(f);await tester.enterText(f,item.value);await tester.pump();}await h.tap(find.text('Войти'));await h.waitFor(()=>find.byType(LoginScreen).evaluate().isEmpty,'Signed in after URI');await h.quiet();expect(await h.api.readTokens(),isNotNull);
  });
  await h.check('RESUME-ENTITY','После входа автоматически открыть ученика из исходной ссылки',()async{h.facts.add({'step':h.currentStep,'uri':router().routeInformationProvider.value.uri.toString(),'expectedStudent':student});expect(find.byType(ClientCard),findsOneWidget);expect(router().routeInformationProvider.value.uri.queryParameters['entityId'],student);});
  await h.check('SIGNED-IN-URI','Та же ссылка в активной сессии открывает нужную карточку',()async{router().go('/students/$student?section=overview');await h.quiet();expect(find.byType(ClientCard),findsOneWidget);expect(router().routeInformationProvider.value.uri.queryParameters['entityId'],student);h.facts.add({'step':h.currentStep,'uri':router().routeInformationProvider.value.uri.toString(),'studentId':student});});
  await h.finish();
 },timeout:const Timeout(Duration(minutes:4)));}
}
