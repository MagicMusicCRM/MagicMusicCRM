import 'dart:io';

import '../../tool/src/naming_policy.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects generation and mechanical part names in production', () {
    final violations = findNamingViolations(
      paths: const [
        'lib/features/tasks/v9/tasks_panel.dart',
        'lib/features/tasks/tasks_view_a.dart',
        'lib/features/tasks/new_tasks.dart',
      ],
      exceptions: const [],
    );

    expect(
      violations.map((item) => item.rule),
      containsAll(<String>{
        'production-generation-name',
        'mechanical-part-suffix',
        'temporary-name',
      }),
    );
  });

  test('accepts a documented migration exception', () {
    const exception = NamingPolicyException(
      target: 'server/src/migration/commerce/v7/',
      category: 'migration',
      reason: 'Calls versioned PostgreSQL reconciliation functions.',
      owner: 'platform',
      removeWhen: 'V7 commerce migration is formally retired.',
    );

    expect(
      findNamingViolations(
        paths: const ['server/src/migration/commerce/v7/reconcile.ts'],
        exceptions: const [exception],
      ),
      isEmpty,
    );
  });

  test('migration directory exceptions cover only generation path debt', () {
    const exception = NamingPolicyException(
      target: 'server/src/migration/commerce/v7/',
      category: 'migration',
      reason: 'Calls versioned PostgreSQL reconciliation functions.',
      owner: 'platform',
      removeWhen: 'V7 commerce migration is formally retired.',
    );

    expect(
      findNamingViolations(
        paths: const ['server/src/migration/commerce/v7/old_reconcile.ts'],
        exceptions: const [exception],
      ).map((item) => item.rule),
      ['temporary-name'],
    );
  });

  test('rejects generation symbols and historical test buckets', () {
    expect(
      findSymbolViolations(
        sources: const {'lib/login.dart': 'class _V7Field {}'},
        exceptions: const [],
      ).single.rule,
      'production-generation-symbol',
    );
    expect(
      findNamingViolations(
        paths: const ['test/features/v9/example_test.dart'],
        exceptions: const [],
      ).single.rule,
      'test-generation-bucket',
    );
  });

  test('ignores generation-like contract strings and comments', () {
    final violations = findSymbolViolations(
      sources: const {
        'lib/contracts.dart': '''
          // V7NavShell remains in historical release notes.
          const path = '/analytics/v4/report';
          const namespace = 'mmcrm.v3';
        ''',
      },
      exceptions: const [],
    );

    expect(violations, isEmpty);
  });

  test('allows only an exact documented symbol exception', () {
    const exception = NamingPolicyException(
      target: 'lib/auth.dart::_V7Field',
      category: 'cleanup-debt',
      reason: 'Shared control extraction is pending.',
      owner: 'flutter',
      removeWhen: 'Foundation milestone auth-control extraction is complete.',
    );

    expect(
      findSymbolViolations(
        sources: const {'lib/auth.dart': 'class _V7Field {}'},
        exceptions: const [exception],
      ),
      isEmpty,
    );
    expect(
      findSymbolViolations(
        sources: const {'lib/auth.dart': 'class _V7PrimaryButton {}'},
        exceptions: const [exception],
      ).single.rule,
      'production-generation-symbol',
    );
  });

  test('rejects incomplete and unmatched exception entries', () {
    const incomplete = NamingPolicyException(
      target: 'lib/auth.dart::_V7Field',
      category: '',
      reason: '',
      owner: '',
      removeWhen: '',
    );
    const unmatched = NamingPolicyException(
      target: 'lib/auth.dart::_V7PrimaryButton',
      category: 'cleanup-debt',
      reason: 'The control is pending extraction.',
      owner: 'flutter',
      removeWhen: 'Foundation milestone extracts shared auth controls.',
    );

    final violations = findExceptionValidationViolations(
      exceptions: const [incomplete, unmatched],
      trackedPaths: const ['lib/auth.dart'],
      sources: const {'lib/auth.dart': 'class _V7Field {}'},
    );

    expect(
      violations.map((item) => item.rule),
      containsAll(<String>{
        'empty-category',
        'empty-reason',
        'empty-owner',
        'empty-remove_when',
        'unused-naming-exception',
      }),
    );
  });

  test('rejects an empty exception target without covering findings', () {
    const exception = NamingPolicyException(
      target: '',
      category: 'cleanup-debt',
      reason: 'This entry is intentionally invalid.',
      owner: 'flutter',
      removeWhen: 'It must never be accepted.',
    );

    final validation = findExceptionValidationViolations(
      exceptions: const [exception],
      trackedPaths: const ['lib/auth.dart'],
      sources: const {'lib/auth.dart': 'class _V7Field {}'},
    );

    expect(validation.map((item) => item.rule), contains('empty-target'));
    expect(
      findNamingViolations(
        paths: const ['lib/features/tasks/v9/tasks_panel.dart'],
        exceptions: const [exception],
      ),
      isNotEmpty,
    );
    expect(
      findSymbolViolations(
        sources: const {'lib/auth.dart': 'class _V7Field {}'},
        exceptions: const [exception],
      ),
      isNotEmpty,
    );
  });

  test('rejects broad Flutter prefixes without covering paths or symbols', () {
    for (final target in <String>['l', 'lib/']) {
      final exception = NamingPolicyException(
        target: target,
        category: 'cleanup-debt',
        reason: 'This entry is intentionally invalid.',
        owner: 'flutter',
        removeWhen: 'It must never be accepted.',
      );

      expect(
        findExceptionValidationViolations(
          exceptions: [exception],
          trackedPaths: const ['lib/auth.dart'],
          sources: const {'lib/auth.dart': 'class _V7Field {}'},
        ).map((item) => item.rule),
        contains('invalid-target'),
      );
      expect(
        findNamingViolations(
          paths: const ['lib/features/tasks/v9/tasks_panel.dart'],
          exceptions: [exception],
        ),
        isNotEmpty,
      );
      expect(
        findSymbolViolations(
          sources: const {'lib/auth.dart': 'class _V7Field {}'},
          exceptions: [exception],
        ),
        isNotEmpty,
      );
    }
  });

  test('rejects the test root without covering historical test buckets', () {
    final exception = NamingPolicyException(
      target: 'test/',
      category: 'historical-test-bucket',
      reason: 'This entry is intentionally invalid.',
      owner: 'flutter',
      removeWhen: 'It must never be accepted.',
    );

    expect(
      findExceptionValidationViolations(
        exceptions: [exception],
        trackedPaths: const ['test/features/v9/example_test.dart'],
        sources: const {},
      ).map((item) => item.rule),
      contains('invalid-target'),
    );
    expect(
      findNamingViolations(
        paths: const ['test/features/v9/example_test.dart'],
        exceptions: [exception],
      ),
      isNotEmpty,
    );
  });

  test('historical test directories cover only test generation buckets', () {
    const exception = NamingPolicyException(
      target: 'test/features/v9/',
      category: 'historical-test-bucket',
      reason: 'Preserves the historical generation test bucket.',
      owner: 'flutter',
      removeWhen: 'The historical test bucket is retired.',
    );
    const finding = 'test/features/v9/example_test.dart';

    expect(
      isExceptionCovered(finding, 'test-generation-bucket', const [exception]),
      isTrue,
    );
    expect(
      isExceptionCovered(finding, 'production-generation-name', const [
        exception,
      ]),
      isFalse,
    );
  });

  test('guards the live S8 historical test item', () {
    expect(
      findNamingViolations(
        paths: const ['test/features/s8_desktop_ux_states_test.dart'],
        exceptions: const [],
      ).single.rule,
      'test-generation-bucket',
    );
  });

  test('rejects lower-case generation symbols with exact exceptions only', () {
    const exactException = NamingPolicyException(
      target: 'lib/auth.dart::_v7PhoneDecoration',
      category: 'cleanup-debt',
      reason: 'The exact control extraction is pending.',
      owner: 'flutter',
      removeWhen: 'Shared auth controls replace this exact symbol.',
    );
    const sources = {
      'lib/auth.dart': '''
        class _v7PhoneDecoration {}
        class _v9Field {}
        class someV7Widget {}
      ''',
    };

    expect(
      findSymbolViolations(
        sources: sources,
        exceptions: const [],
      ).map((item) => item.path),
      containsAll(<String>{
        'lib/auth.dart::_v7PhoneDecoration',
        'lib/auth.dart::_v9Field',
        'lib/auth.dart::someV7Widget',
      }),
    );
    expect(
      findSymbolViolations(
        sources: sources,
        exceptions: const [exactException],
      ).map((item) => item.path),
      containsAll(<String>{
        'lib/auth.dart::_v9Field',
        'lib/auth.dart::someV7Widget',
      }),
    );
  });

  test('does not let a file contract exception cover an unrelated symbol', () {
    const exception = NamingPolicyException(
      target: 'lib/contracts.dart',
      category: 'api-contract',
      reason: 'The file documents a live V4 API contract.',
      owner: 'platform',
      removeWhen: 'The V4 API contract is retired.',
    );

    expect(
      findSymbolViolations(
        sources: const {'lib/contracts.dart': 'class _V99Unrelated {}'},
        exceptions: const [exception],
      ),
      isNotEmpty,
    );
  });

  test('rejects generic cleanup directories without covering debt', () {
    const exception = NamingPolicyException(
      target: 'lib/features/manager/',
      category: 'cleanup-debt',
      reason: 'This directory is intentionally too broad.',
      owner: 'flutter',
      removeWhen: 'It must never be accepted.',
    );

    expect(
      findExceptionValidationViolations(
        exceptions: const [exception],
        trackedPaths: const ['lib/features/manager/reporting_v4_panel.dart'],
        sources: const {},
      ).map((item) => item.rule),
      contains('invalid-target'),
    );
    expect(
      findNamingViolations(
        paths: const ['lib/features/manager/reporting_v4_panel.dart'],
        exceptions: const [exception],
      ),
      isNotEmpty,
    );
  });

  test('rejects stale cleanup file exceptions', () {
    const exception = NamingPolicyException(
      target: 'lib/contracts.dart',
      category: 'cleanup-debt',
      reason: 'This file has no remaining cleanup debt.',
      owner: 'flutter',
      removeWhen: 'It must never be accepted.',
    );

    expect(
      findExceptionValidationViolations(
        exceptions: const [exception],
        trackedPaths: const ['lib/contracts.dart'],
        sources: const {
          'lib/contracts.dart': 'const route = \'/analytics/v4\';',
        },
      ).map((item) => item.rule),
      contains('stale-cleanup-exception'),
    );
  });

  test('production code does not import a wide UI barrel', () {
    const historicalBarrelImport =
        'core/widgets/'
        'v7/'
        'v7.dart';
    final offenders = trackedDartSources().where((path) {
      final file = File(path);
      if (!file.existsSync()) return false;
      final source = file.readAsStringSync();
      return source.contains(historicalBarrelImport);
    }).toList();

    expect(offenders, isEmpty);
  });
}
