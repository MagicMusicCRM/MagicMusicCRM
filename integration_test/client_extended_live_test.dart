import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_create_dialogs.dart';
import 'live_audit_harness.dart';

void main(){IntegrationTestWidgetsFlutterBinding.ensureInitialized();setUpAll(()=>initializeDateFormatting('ru'));
 for(final role in ['admin','manager','director'])testWidgets('$role extended create and card fields',(tester)async{
  final h=LiveAuditHarness(tester,role,'client-extended');await h.initialize(size:const Size(1600,1800));
  final crm=h.scope.read(magicCrmServiceProvider),access=await h.scope.read(capabilitySnapshotProvider.future);
  Finder key(String k)=>find.byKey(ValueKey(k));
  Future<void> fill(Finder f,String text)async{FocusManager.instance.primaryFocus?.unfocus();await tester.pump();await h.tap(f);await tester.enterText(f,text);await tester.pump();}
  Future<void> select(Finder f,String label)async{await h.tap(f);await h.tap(find.text(label));await h.quiet();}
  Finder picker(String label)=>find.byWidgetPredicate((w)=>w is SearchablePickerField&&w.label==label);
  Future<void> settle()async{await tester.pump(const Duration(seconds:2));await h.quiet();await h.waitFor(()=>find.byWidgetPredicate((w)=>w is Semantics&&w.properties.label=='Изменения сохранены').evaluate().isNotEmpty,'Card autosave settled');}
  for(final entity in ['lead','student']){
   Map<String,dynamic>? created;String? id;
   Future<Map<String,dynamic>> read()async{final card=entity=='student'?await crm.getStudentCard(id!):await crm.getLeadCard(id!);return {...Map<String,dynamic>.from(card[entity] as Map),'custom_field_values':card['custom_field_values']};}
   Future<void> openCard()async{await tester.pumpWidget(const SizedBox.shrink());await tester.pump();await h.mount(Scaffold(body:ClientCard(lead:await read(),entityType:entity,routed:true,initialSection:'overview',capabilitySnapshot:access)));await h.quiet();}
   Map<String,dynamic> custom(Map<String,dynamic> row)=>{...Map<String,dynamic>.from(row['custom_data'] as Map? ??{}),...Map<String,dynamic>.from(row['custom_field_values'] as Map? ??{})};
   await h.check('$entity-CREATE-DRAFT','Новая карточка: заполнить текст, дату, список и флажок',()async{
    await tester.pumpWidget(const SizedBox.shrink());await tester.pump();await h.mount(Scaffold(body:Builder(builder:(context)=>TextButton(onPressed:()async{created=await showDialog<Map<String,dynamic>>(context:context,builder:(_)=>entity=='lead'?const LeadCreateDialog():StudentCreateDialog(initialBranchId:h.fixture['branchId']));},child:const Text('Новый клиент')))));
    await h.tap(find.text('Новый клиент'));await h.quiet();await fill(key('$entity-first-name'),'AUDIT-EXTENDED');await fill(key('$entity-last-name'),'$role-$entity');
    final phone=find.descendant(of:key('$entity-phone'),matching:find.byType(TextField));await fill(phone,'9991234567');
    await select(key('$entity-branch'),'HTTP test');
    final source=tester.widget<SearchablePickerField>(key('$entity-source'));await select(key('$entity-source'),source.items.first.label);
    await fill(key('custom-field-learningGoal'),'AUDIT-CREATE-GOAL');await fill(key('custom-field-birthday'),'2000-02-29');await select(key('custom-field-level'),'Средний');
    if(entity=='student'){await h.tap(key('custom-field-noEmail'));}
   });
   await h.check('$entity-CREATE-SAVE','Сохранить дополнительные поля и независимо прочитать карточку',()async{
    await h.tap(key('$entity-submit'));await h.quiet();expect(created,isNotNull);id=created!['id'];final row=await read(),data=custom(row);expect(data['learningGoal'],'AUDIT-CREATE-GOAL');expect(data['birthday'],'2000-02-29');expect(data['level'],'Средний');if(entity=='student'){expect(data['noEmail'],true);}h.facts.add({'step':h.currentStep,'id':id,'entity':entity,'row':row});
   });
   if(id==null){continue;}
   await h.check('$entity-BRANCH','Сменить основной филиал и проверить после повторного открытия',()async{await openCard();await select(picker('Основной филиал'),'AUDIT-SECOND-BRANCH');await settle();expect((await read())['branch_id'],h.fixture['secondBranchId']);await openCard();expect(tester.widget<SearchablePickerField>(picker('Основной филиал')).selectedId,h.fixture['secondBranchId']);});
   await h.check('$entity-BRANCH-RETURN','Вернуть исходный филиал',()async{await select(picker('Основной филиал'),'HTTP test');await settle();expect((await read())['branch_id'],h.fixture['branchId']);});
   await h.check('$entity-SOURCE','Сменить рекламный источник и прочитать сохранённый ID',()async{
    final field=picker('Рекламный источник *'),w=tester.widget<SearchablePickerField>(field),option=w.items.firstWhere((i)=>i.id!=w.selectedId);await select(field,option.label);await settle();final row=await read();expect(row['source_id'],option.id);await openCard();expect(tester.widget<SearchablePickerField>(picker('Рекламный источник *')).selectedId,option.id);h.facts.add({'step':h.currentStep,'id':id,'row':row});
   });
   await h.check('$entity-DISCIPLINE','Выбрать два направления и сохранить после переоткрытия',()async{
    final chips=find.byType(FilterChip);final candidates=tester.widgetList<FilterChip>(chips).where((w)=>w.label is Text).map((w)=>(w.label as Text).data).whereType<String>().where((s)=>['Вокал','Гитара','Фортепиано','Барабаны'].contains(s)).toList();expect(candidates.length,greaterThanOrEqualTo(2));
    for(final label in candidates.take(2)){final f=find.widgetWithText(FilterChip,label);if(!tester.widget<FilterChip>(f).selected)await h.tap(f);}await settle();await openCard();for(final label in candidates.take(2)){expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip,label)).selected,true);}h.facts.add({'step':h.currentStep,'id':id,'row':await read()});
   });
   await h.check('$entity-DOB','Изменить дату рождения через настоящий ввод даты и сохранить',()async{
    final layout=key('custom-field-layout-birthday');if(layout.evaluate().isEmpty){await h.tap(find.text('Дополнительные поля').first);await h.quiet();}
    final dateField=find.descendant(of:layout,matching:find.byType(InkWell)).first;await h.tap(dateField);final dialog=find.byType(DatePickerDialog),loc=MaterialLocalizations.of(tester.element(find.byType(DatePickerDialog)));final input=find.descendant(of:dialog,matching:find.byType(TextFormField));await fill(input,loc.formatCompactDate(DateTime(1996,2,29)));await h.tap(find.descendant(of:dialog,matching:find.text(loc.okButtonLabel)));await settle();expect(custom(await read())['birthday'],'1996-02-29');await openCard();if(key('custom-field-layout-birthday').evaluate().isEmpty){await h.tap(find.text('Дополнительные поля').first);await h.quiet();}expect(find.text('29.02.1996'),findsOneWidget);h.facts.add({'step':h.currentStep,'id':id,'row':await read()});
   });
  }await h.finish();
 });
}
