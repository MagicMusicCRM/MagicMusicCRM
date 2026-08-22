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
}
