import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'card_fake_api.dart';

class _UnifiedClientFieldApi extends FakeCardApiClient {
  _UnifiedClientFieldApi({
    Map<String, dynamic> customData = const <String, dynamic>{},
  }) : super(
         lead: {
           'id': 'lead-1',
           'firstName': 'Иван',
           'lastName': 'Петров',
           'phone': '+79990000000',
           'customData': customData,
         },
       );

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) {
    if (path == '/crm/client-config/fields') {
      // Current backend contract: one canonical field with visibility flags,
      // projected by the entityType query but without legacy entityType in the
      // response row.
      return Future<T>.value(
        <String, dynamic>{
              'items': const [
                {
                  'id': '30000000-0000-4000-8000-000000000001',
                  'key': 'contactPersonRelation',
                  'label': 'Кем приходится',
                  'valueType': 'select',
                  'required': false,
                  'options': ['Мама', 'Папа'],
                  'visibility': {'lead': true, 'student': true},
                  'visibleOnLead': true,
                  'visibleOnStudent': true,
                  'placements': ['edit', 'card'],
                },
              ],
            }
            as T,
      );
    }
    return super.get<T>(
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }
}

Future<void> _openContacts(
  WidgetTester tester,
  _UnifiedClientFieldApi api,
) async {
  await pumpClientCard(tester, api: api, seed: const {'id': 'lead-1'});
  await tester.ensureVisible(find.text('Контакты').first);
  await tester.tap(find.text('Контакты').first);
  await tester.pumpAndSettle();
}

Future<void> _expectConfiguredRelationOptions(WidgetTester tester) async {
  final dropdown = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(DropdownButtonFormField<String>),
  );
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  expect(find.text('Мама'), findsWidgets);
  expect(find.text('Папа'), findsWidgets);
}

void main() {
  testWidgets(
    'shows configured relation options when adding a contact person',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.reset);

      await _openContacts(tester, _UnifiedClientFieldApi());
      await tester.ensureVisible(find.text('Добавить контактное лицо'));
      await tester.tap(find.text('Добавить контактное лицо'));
      await tester.pumpAndSettle();

      await _expectConfiguredRelationOptions(tester);
    },
  );

  testWidgets(
    'shows configured relation options when editing a contact person',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.reset);

      await _openContacts(
        tester,
        _UnifiedClientFieldApi(
          customData: const {
            'contactPersons': [
              {'name': 'Илья', 'relation': 'Мама'},
            ],
          },
        ),
      );

      final contactTile = find.ancestor(
        of: find.text('Илья'),
        matching: find.byType(ListTile),
      );
      await tester.ensureVisible(contactTile);
      await tester.tap(
        find.descendant(of: contactTile, matching: find.byTooltip('Изменить')),
      );
      await tester.pumpAndSettle();

      await _expectConfiguredRelationOptions(tester);
    },
  );
}
