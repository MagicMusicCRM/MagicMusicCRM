import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _directory =
    'lib/features/crm/presentation/client_card/subscription_issue_';

String _source(String suffix) =>
    File('$_directory$suffix.dart').readAsStringSync();

int _nloc(String source) => source.split('\n').where((line) {
  final trimmed = line.trim();
  return trimmed.isNotEmpty &&
      !trimmed.startsWith('//') &&
      !trimmed.startsWith('///');
}).length;

String _classBody(String source, String className) {
  final declaration = source.indexOf('class $className');
  expect(declaration, isNonNegative, reason: className);
  final openingBrace = source.indexOf('{', declaration);
  var depth = 0;
  for (var index = openingBrace; index < source.length; index++) {
    if (source[index] == '{') depth++;
    if (source[index] == '}') {
      depth--;
      if (depth == 0) return source.substring(openingBrace, index + 1);
    }
  }
  fail('Unclosed class $className');
}

void main() {
  test('subscription issue shell stays a bounded lifecycle adapter', () {
    final shell = _source('sheet');
    final imports = shell
        .split('\n')
        .where((line) => line.trimLeft().startsWith('import '))
        .length;
    final state = _classBody(shell, '_SubscriptionIssueFormState');

    expect(_nloc(shell), lessThanOrEqualTo(220));
    expect(imports, lessThanOrEqualTo(12));
    expect(_nloc(state), lessThanOrEqualTo(160));
    for (final forbidden in [
      '_parseMoneyMinor',
      '_parsePercentBasisPoints',
      '_installments',
      '_buildPurchase',
    ]) {
      expect(shell, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(shell, isNot(contains('switch (')));
  });

  test('every extracted subscription issue owner stays bounded', () {
    for (final suffix in [
      'models',
      'pricing',
      'controller',
      'form_view',
      'components',
    ]) {
      expect(_nloc(_source(suffix)), lessThanOrEqualTo(500), reason: suffix);
    }
  });

  test('preview and commit effects are orchestrated only by controller', () {
    final controller = _source('controller');
    final shell = _source('sheet');
    expect(controller, contains('await _onPreview(purchase)'));
    expect(controller, contains('await _onSubmit('));
    expect(shell, isNot(contains('await widget.onPreview')));
    expect(shell, isNot(contains('await widget.onSubmit')));
    for (final suffix in ['models', 'pricing', 'form_view', 'components']) {
      final source = _source(suffix);
      expect(source, isNot(contains('onPreview')), reason: suffix);
      expect(source, isNot(contains('onSubmit')), reason: suffix);
    }
  });
}
