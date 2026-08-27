import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/architecture/dart_architecture_guard.dart';

const _directory = 'lib/features/crm/presentation/client_card';
const _purchaseModelPath = 'lib/core/models/subscription_purchase.dart';
const _serviceBarrelPath = 'lib/core/services/magic_crm_service.dart';
const _shellFilename = 'subscription_issue_sheet.dart';
const _controllerFilename = 'subscription_issue_controller.dart';
const _callbackNames = {'onPreview', '_onPreview', 'onSubmit', '_onSubmit'};
const _callbackTypes = {'SubscriptionIssuePreview', 'SubscriptionIssueSubmit'};
const _budget = DartArchitectureBudget(
  ownerNlocLimit: 500,
  shellFileName: _shellFilename,
  shellNlocLimit: 220,
  shellImportLimit: 12,
  executableCcnLimit: 10,
  executableNlocLimit: 130,
  typeNlocLimit: 420,
  typeMemberLimit: 50,
  typeCallableLimit: 40,
  namedTypeNlocLimits: {'_SubscriptionIssueFormState': 160},
);

void main() {
  test('purchase contracts stay independent from the CRM service barrel', () {
    final violations = <String>[];
    final issueModels = File(
      '$_directory/subscription_issue_models.dart',
    ).readAsStringSync();
    final purchaseModel = File(_purchaseModelPath);
    final serviceBarrel = File(_serviceBarrelPath).readAsStringSync();

    if (issueModels.contains('/services/magic_crm_service.dart')) {
      violations.add('subscription issue models import the CRM service barrel');
    }
    if (!purchaseModel.existsSync()) {
      violations.add('standalone subscription purchase model is missing');
    } else {
      final source = purchaseModel.readAsStringSync();
      if (RegExp(r"(?:package:flutter|/api/|/services/)").hasMatch(source)) {
        violations.add('subscription purchase model imports infrastructure');
      }
      if (RegExp(r'^\s*part(?:\s+of)?\s', multiLine: true).hasMatch(source)) {
        violations.add('subscription purchase model is coupled as a part file');
      }
    }
    if (!serviceBarrel.contains(
      "export 'package:magic_music_crm/core/models/subscription_purchase.dart';",
    )) {
      violations.add('CRM service barrel no longer exports purchase contracts');
    }

    expect(violations, isEmpty);
  });

  test('all discovered subscription issue owners pass the AST guard', () {
    final sources = discoverDartSources(
      directoryPath: _directory,
      filePrefix: 'subscription_issue_',
    );
    final inspections = inspectDartSources(sources);

    expect(sources, isNotEmpty);
    expect(sources, contains(_shellFilename));
    expect(_architectureViolations(inspections), isEmpty);

    final shell = inspections.singleWhere(
      (inspection) => inspection.fileName == _shellFilename,
    );
    final forbiddenExecutables =
        <String>{
          ...shell.executables.map((executable) => executable.name),
          ...shell.invocationNames,
        }.intersection(const {
          '_parseMoneyMinor',
          '_parsePercentBasisPoints',
          '_installments',
          '_buildPurchase',
        });
    expect(forbiddenExecutables, isEmpty);
    expect(
      shell.executables.any((executable) => executable.switchCount > 0),
      isFalse,
      reason: 'pricing switches belong outside the lifecycle shell',
    );

    final controller = inspections.singleWhere(
      (inspection) => inspection.fileName == _controllerFilename,
    );
    expect(
      controller.invokedCallableAliases(
        names: _callbackNames,
        typeNames: _callbackTypes,
      ),
      containsAll(const {'_onPreview', '_onSubmit'}),
    );
  });

  test('AST effects ignore lexical decoys and follow whitespace aliases', () {
    final violations = _architectureViolations([
      inspectDartSource('subscription_issue_future.dart', r'''
void leak(SubscriptionIssuePreview onPreview, dynamic input) {
  // onSubmit(input) is not executable code.
  const example = 'onPreview(input)';
  final previewAlias = onPreview;
  previewAlias
      (input);
}
class HiddenSubmit {
  HiddenSubmit(this.onSubmit);
  final SubscriptionIssueSubmit onSubmit;
  void leak(dynamic input) => this.onSubmit (input);
}
'''),
    ]);

    expect(
      violations,
      contains(
        'subscription_issue_future.dart: preview/submit effect previewAlias outside controller',
      ),
    );
    expect(
      violations,
      contains(
        'subscription_issue_future.dart: preview/submit effect onSubmit outside controller',
      ),
    );
  });

  test('dynamic discovery audits new subscription issue owners', () {
    final directory = Directory.systemTemp.createTempSync(
      'subscription-issue-architecture-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    File(
      '${directory.path}${Platform.pathSeparator}subscription_issue_future.dart',
    ).writeAsStringSync('''
void leak(SubscriptionIssueSubmit onSubmit, dynamic input) {
  final alias = onSubmit;
  alias(input);
}
''');
    File(
      '${directory.path}${Platform.pathSeparator}subscription_other.dart',
    ).writeAsStringSync('void unrelated() {}');

    final sources = discoverDartSources(
      directoryPath: directory.path,
      filePrefix: 'subscription_issue_',
    );
    expect(sources.keys, ['subscription_issue_future.dart']);
    expect(
      _architectureViolations(inspectDartSources(sources)),
      contains(contains('preview/submit effect alias outside controller')),
    );
  });

  test('CCN and type proxies reject future brain and god owners', () {
    final methods = List.generate(41, (index) => 'void m$index() {}').join();
    final inspections = [
      inspectDartSource('subscription_issue_tangled.dart', '''
int tangled(List<int> values, int x) {
  if (x > 0) x++;
  for (final value in values) { x += value; }
  while (x < 3) { x++; }
  do { x--; } while (x > 20);
  try { x++; } catch (_) { x--; }
  final choice = x > 0 ? 1 : 0;
  final boolean = x > 0 && x < 10 || x == 20;
  final collection = <int>[if (x > 0) choice, for (final v in values) v];
  return switch (x) { 1 => collection.length, _ => boolean ? 1 : 0 };
}
'''),
      inspectDartSource(
        'subscription_issue_brain.dart',
        'class FutureOwner {$methods}',
      ),
    ];
    final violations = _architectureViolations(inspections);

    expect(violations, contains(contains('CCN ')));
    expect(violations, contains(contains('callables 41 exceeds 40')));
  });
}

List<String> _architectureViolations(
  Iterable<DartSourceInspection> inspections,
) {
  final inspected = inspections.toList();
  final violations = auditDartArchitecture(inspected, _budget);
  for (final inspection in inspected) {
    if (inspection.fileName == _controllerFilename) continue;
    final effects = inspection.invokedCallableAliases(
      names: _callbackNames,
      typeNames: _callbackTypes,
    );
    for (final effect in effects) {
      violations.add(
        '${inspection.fileName}: preview/submit effect $effect outside controller',
      );
    }
  }
  return violations.toSet().toList()..sort();
}
