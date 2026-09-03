import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_editor/lesson_client_funding_fields.dart';

const _student = LessonDecisionParticipant(id: 'student-a', name: 'Анна');
const _payer = LessonDecisionParticipant(id: 'payer-b', name: 'Пётр');
const _subscription = LessonDecisionSubscription(
  id: 'sub-a',
  label: 'Абонемент Анны',
);

Map<String, dynamic> _decision() => {
  'clientId': 'student-a',
  'payerStudentId': 'student-a',
  'chargeType': 'subscription',
  'subscriptionId': 'sub-a',
  'basePriceMinor': '125050',
  'discount': {'type': 'none'},
  'surcharge': {'type': 'none'},
  'settlementTypeKey': 'paid',
};

Widget _host({
  List<Map<String, dynamic>>? decisions,
  List<LessonDecisionParticipant> participants = const [_student],
  bool enabled = true,
  bool allowsNoFunding = false,
  Map<String, List<LessonDecisionSubscription>> subscriptionsByPayer = const {
    'student-a': [_subscription],
  },
  Future<List<LessonDecisionSubscription>> Function(String)? loadSubscriptions,
  required ValueChanged<List<Map<String, dynamic>>> onChanged,
  GlobalKey<FormState>? formKey,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: Form(
        key: formKey,
        child: LessonClientFundingFields(
          participants: participants,
          decisions: decisions ?? [_decision()],
          enabled: enabled,
          allowsNoFunding: allowsNoFunding,
          knownPayers: const [_payer],
          subscriptionsByPayer: subscriptionsByPayer,
          searchPayers: (_) async => [_payer],
          loadSubscriptions: loadSubscriptions ?? (_) async => [],
          onChanged: onChanged,
        ),
      ),
    ),
  ),
);

Finder _field(String name) =>
    find.byKey(ValueKey('lesson-client-$name-student-a'));

void _select(WidgetTester tester, String field, String value) {
  tester.widget<DropdownButtonFormField<String>>(_field(field)).onChanged!(
    value,
  );
}

void main() {
  testWidgets(
    'a lead uses an explicitly selected student payer and cannot select subscription funding',
    (tester) async {
      const lead = LessonDecisionParticipant(
        id: 'lead-a',
        name: 'Анна',
        isStudent: false,
      );
      final emitted = <List<Map<String, dynamic>>>[];
      var loads = 0;
      await tester.pumpWidget(
        _host(
          participants: [lead],
          decisions: [],
          subscriptionsByPayer: const {},
          loadSubscriptions: (_) async {
            loads++;
            return [];
          },
          onChanged: emitted.add,
        ),
      );
      await tester.pumpAndSettle();

      final source = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const ValueKey('lesson-client-charge-type-lead-a')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(source.items!.map((item) => item.value), ['personal_account']);
      final payer = tester.widget<SearchablePickerField>(
        find.byKey(const ValueKey('lesson-client-payer-lead-a')),
      );
      expect(payer.selectedId, isNull);
      expect(payer.items.map((item) => item.id), ['payer-b']);
      expect(payer.errorText, 'Выберите ученика-плательщика');
      payer.onSelected((await payer.onSearch!('Пётр')).single);
      await tester.pumpAndSettle();

      expect(emitted.single.single['payerStudentId'], 'payer-b');
      expect(emitted.single.single['clientId'], 'lead-a');
      expect(emitted.single.single['chargeType'], 'personal_account');
      expect(loads, 0);
    },
  );

  testWidgets('a free lead has no default student payer or subscription load', (
    tester,
  ) async {
    final emitted = <List<Map<String, dynamic>>>[];
    var loads = 0;
    await tester.pumpWidget(
      _host(
        participants: const [
          LessonDecisionParticipant(
            id: 'lead-a',
            name: 'Анна',
            isStudent: false,
          ),
        ],
        decisions: [],
        allowsNoFunding: true,
        subscriptionsByPayer: const {},
        loadSubscriptions: (_) async {
          loads++;
          return [];
        },
        onChanged: emitted.add,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .state<FormFieldState<String>>(
            find.byKey(const ValueKey('lesson-client-charge-type-lead-a')),
          )
          .value,
      'none',
    );
    final payer = tester.widget<SearchablePickerField>(
      find.byKey(const ValueKey('lesson-client-payer-lead-a')),
    );
    expect(payer.selectedId, isNull);
    expect(payer.enabled, isFalse);
    expect(loads, 0);
    expect(emitted, isEmpty);
  });

  testWidgets(
    'a missing decision defaults to the participant and first subscription without forcing a price',
    (tester) async {
      final emitted = <List<Map<String, dynamic>>>[];
      await tester.pumpWidget(_host(decisions: [], onChanged: emitted.add));
      await tester.pumpAndSettle();

      expect(emitted.single.single, {
        'clientId': 'student-a',
        'payerStudentId': 'student-a',
        'chargeType': 'subscription',
        'subscriptionId': 'sub-a',
        'discount': {'type': 'none'},
        'surcharge': {'type': 'none'},
      });
    },
  );

  testWidgets(
    'an external authoritative decision refreshes visible values without an edit',
    (tester) async {
      final emitted = <List<Map<String, dynamic>>>[];
      await tester.pumpWidget(_host(onChanged: emitted.add));
      await tester.pumpAndSettle();
      final updated = {
        ..._decision(),
        'chargeType': 'personal_account',
        'basePriceMinor': '200000',
        'discount': {
          'type': 'fixed',
          'fixedMinor': '2000',
          'reason': 'Уточнение',
        },
      }..remove('subscriptionId');

      await tester.pumpWidget(
        _host(decisions: [updated], onChanged: emitted.add),
      );
      await tester.pumpAndSettle();

      expect(
        tester.state<FormFieldState<String>>(_field('charge-type')).value,
        'personal_account',
      );
      expect(
        tester.state<FormFieldState<String>>(_field('discount-type')).value,
        'fixed',
      );
      expect(
        tester.widget<TextFormField>(_field('price')).controller!.text,
        '2000',
      );
      expect(
        tester.widget<TextFormField>(_field('discount-value')).controller!.text,
        '20',
      );
      expect(emitted, isEmpty);
    },
  );

  testWidgets(
    'existing payment values display in rubles without emitting changes',
    (tester) async {
      final emitted = <List<Map<String, dynamic>>>[];
      await tester.pumpWidget(
        _host(
          decisions: [
            {..._decision(), 'chargeType': 'personal_account'}
              ..remove('subscriptionId'),
          ],
          onChanged: emitted.add,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<SearchablePickerField>(_field('payer')).selectedLabel,
        'Анна',
      );
      expect(
        tester.widget<TextFormField>(_field('price')).controller!.text,
        '1250,50',
      );
      expect(_field('subscription'), findsNothing);
      expect(emitted, isEmpty);
    },
  );

  testWidgets(
    'personal account removes subscription and preserves unrelated decisions',
    (tester) async {
      final other = {'clientId': 'student-z', 'custom': 'untouched'};
      final emitted = <List<Map<String, dynamic>>>[];
      await tester.pumpWidget(
        _host(decisions: [_decision(), other], onChanged: emitted.add),
      );
      await tester.pumpAndSettle();

      _select(tester, 'charge-type', 'personal_account');
      await tester.pumpAndSettle();

      expect(emitted.single.first['payerStudentId'], 'student-a');
      expect(emitted.single.first['chargeType'], 'personal_account');
      expect(emitted.single.first.containsKey('subscriptionId'), isFalse);
      expect(emitted.single.first['settlementTypeKey'], 'paid');
      expect(emitted.single.last, other);
      _select(tester, 'charge-type', 'personal_account');
      expect(emitted, hasLength(1));
    },
  );

  testWidgets(
    'late own subscription cannot replace the newly chosen payer subscription',
    (tester) async {
      final own = Completer<List<LessonDecisionSubscription>>();
      final other = Completer<List<LessonDecisionSubscription>>();
      final emitted = <List<Map<String, dynamic>>>[];
      final decision = _decision()..remove('subscriptionId');
      await tester.pumpWidget(
        _host(
          decisions: [decision],
          subscriptionsByPayer: const {},
          loadSubscriptions: (id) =>
              id == 'student-a' ? own.future : other.future,
          onChanged: emitted.add,
        ),
      );
      await tester.pump();

      final payerField = tester.widget<SearchablePickerField>(_field('payer'));
      final results = await payerField.onSearch!('Пётр');
      payerField.onSelected(results.single);
      await tester.pump();
      other.complete(const [
        LessonDecisionSubscription(id: 'sub-b', label: 'Абонемент Петра'),
      ]);
      await tester.pumpAndSettle();
      own.complete([_subscription]);
      await tester.pumpAndSettle();

      expect(emitted.last.first['payerStudentId'], 'payer-b');
      expect(emitted.last.first['subscriptionId'], 'sub-b');
      expect(
        tester.widget<SearchablePickerField>(_field('subscription')).selectedId,
        'sub-b',
      );
      expect(
        tester.widget<SearchablePickerField>(_field('payer')).selectedLabel,
        'Пётр',
      );
      expect(
        emitted.where((rows) => rows.first['subscriptionId'] == 'sub-a'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'price and manual adjustments emit canonical minor units with reasons',
    (tester) async {
      final emitted = <List<Map<String, dynamic>>>[];
      await tester.pumpWidget(_host(onChanged: emitted.add));
      await tester.pumpAndSettle();
      _select(tester, 'charge-type', 'personal_account');
      await tester.pumpAndSettle();

      await tester.enterText(_field('price'), '1500,25');
      _select(tester, 'discount-type', 'percent');
      await tester.pump();
      await tester.enterText(_field('discount-value'), '12,5');
      await tester.enterText(_field('discount-reason'), 'По договорённости');
      _select(tester, 'surcharge-type', 'fixed');
      await tester.pump();
      await tester.enterText(_field('surcharge-value'), '100,50');
      await tester.enterText(
        _field('surcharge-reason'),
        'Дополнительное время',
      );

      final result = emitted.last.first;
      expect(result['basePriceMinor'], '150025');
      expect(result['discount'], {
        'type': 'percent',
        'percentBasisPoints': 1250,
        'reason': 'По договорённости',
      });
      expect(result['surcharge'], {
        'type': 'fixed',
        'amountMinor': '10050',
        'reason': 'Дополнительное время',
      });
      expect(result['settlementTypeKey'], 'paid');
    },
  );

  testWidgets(
    'invalid discount and missing reason remain visible and block form validation',
    (tester) async {
      final key = GlobalKey<FormState>();
      final emitted = <List<Map<String, dynamic>>>[];
      await tester.pumpWidget(_host(formKey: key, onChanged: emitted.add));
      await tester.pumpAndSettle();
      _select(tester, 'charge-type', 'personal_account');
      await tester.pumpAndSettle();
      _select(tester, 'discount-type', 'percent');
      await tester.pump();
      await tester.enterText(_field('discount-value'), '101');

      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Скидка должна быть от 0 до 100%'), findsOneWidget);
      expect(find.text('Укажите причину скидки'), findsOneWidget);
      expect(
        (emitted.last.first['discount'] as Map)['percentBasisPoints'],
        10100,
      );
    },
  );

  testWidgets(
    'manual pricing is visible and sent only for personal account while switching preserves its draft',
    (tester) async {
      final emitted = <List<Map<String, dynamic>>>[];
      await tester.pumpWidget(
        _host(allowsNoFunding: true, onChanged: emitted.add),
      );
      await tester.pumpAndSettle();

      const pricingFields = [
        'price',
        'discount-type',
        'discount-value',
        'discount-reason',
        'surcharge-type',
        'surcharge-value',
        'surcharge-reason',
      ];
      for (final field in pricingFields) {
        expect(_field(field), findsNothing, reason: 'subscription: $field');
      }
      _select(tester, 'charge-type', 'personal_account');
      await tester.pumpAndSettle();
      await tester.enterText(_field('price'), '1500,25');
      _select(tester, 'discount-type', 'percent');
      await tester.pump();
      await tester.enterText(_field('discount-value'), '12,5');
      await tester.enterText(_field('discount-reason'), 'По договорённости');
      _select(tester, 'surcharge-type', 'fixed');
      await tester.pump();
      await tester.enterText(_field('surcharge-value'), '100,50');
      await tester.enterText(
        _field('surcharge-reason'),
        'Дополнительное время',
      );
      final personalPayload = lessonClientDecisionsPayload(emitted.last);

      for (final source in ['subscription', 'none']) {
        _select(tester, 'charge-type', source);
        await tester.pumpAndSettle();
        for (final field in pricingFields) {
          expect(_field(field), findsNothing, reason: '$source: $field');
        }
        final payload = lessonClientDecisionsPayload(emitted.last).single;
        expect(payload['chargeType'], source);
        for (final field in ['basePriceMinor', 'discount', 'surcharge']) {
          expect(payload, isNot(contains(field)), reason: '$source: $field');
        }
      }

      _select(tester, 'charge-type', 'personal_account');
      await tester.pumpAndSettle();
      for (final entry in {
        'price': '1500,25',
        'discount-value': '12,5',
        'discount-reason': 'По договорённости',
        'surcharge-value': '100,50',
        'surcharge-reason': 'Дополнительное время',
      }.entries) {
        expect(
          tester.widget<TextFormField>(_field(entry.key)).controller!.text,
          entry.value,
        );
      }
      expect(lessonClientDecisionsPayload(emitted.last), personalPayload);
    },
  );

  testWidgets('disabled controls do not load or modify funding', (
    tester,
  ) async {
    var loads = 0;
    final emitted = <List<Map<String, dynamic>>>[];
    await tester.pumpWidget(
      _host(
        enabled: false,
        subscriptionsByPayer: const {},
        loadSubscriptions: (_) async {
          loads++;
          return [];
        },
        onChanged: emitted.add,
      ),
    );
    await tester.pumpAndSettle();

    expect(loads, 0);
    expect(
      tester.widget<SearchablePickerField>(_field('payer')).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(_field('charge-type'))
          .onChanged,
      isNull,
    );
    expect(_field('price'), findsNothing);
    await tester.pumpWidget(
      _host(
        decisions: [
          {..._decision(), 'chargeType': 'personal_account'}
            ..remove('subscriptionId'),
        ],
        enabled: false,
        onChanged: emitted.add,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(_field('price')).enabled, isFalse);
    expect(emitted, isEmpty);
  });
}
