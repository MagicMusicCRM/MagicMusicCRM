import 'package:flutter_test/flutter_test.dart';

import '../support/architecture/icon_tooltip_guard.dart';

void main() {
  test('a later tooltip cannot label an earlier button', () {
    const source = '''
Widget controls() => Column(children: [
  IconButton(icon: Icon(Icons.add), onPressed: save),
  IconButton.filled(tooltip: 'Сохранить', icon: Icon(Icons.save), onPressed: save),
]);
''';
    expect(findMissingIconTooltips(source), ['input.dart:2']);
  });

  test('nested tooltip, comment and string do not replace an own argument', () {
    for (final child in [
      "Tooltip(message: 'tooltip: подпись', child: Icon(Icons.add))",
      "Icon(Icons.add) /* tooltip: 'подпись' */",
      "Text(\"tooltip: 'подпись'\")",
    ]) {
      expect(
        findMissingIconTooltips(
          'Widget button() => IconButton(icon: $child, onPressed: save);',
        ),
        hasLength(1),
      );
    }
  });

  for (final constructor in [
    'IconButton',
    'IconButton.filled',
    'IconButton.filledTonal',
    'IconButton.outlined',
    'FloatingActionButton',
    'FloatingActionButton.small',
    'FloatingActionButton.large',
    'material.IconButton',
    'material.IconButton.filled',
  ]) {
    test('$constructor checks its own tooltip', () {
      expect(
        findMissingIconTooltips(
          'Widget button() => $constructor(onPressed: save);',
        ),
        hasLength(1),
      );
      expect(
        findMissingIconTooltips(
          "Widget button() => $constructor(tooltip: 'Создать', onPressed: save);",
        ),
        isEmpty,
      );
    });
  }

  test('const and new constructor calls have the same requirement', () {
    expect(
      findMissingIconTooltips(
        'Widget button() => const IconButton(icon: Icon(Icons.add), onPressed: null);',
      ),
      hasLength(1),
    );
    expect(
      findMissingIconTooltips(
        'Widget button() => new FloatingActionButton.large(onPressed: save);',
      ),
      hasLength(1),
    );
    expect(
      findMissingIconTooltips(
        'Widget button() => const material.IconButton.filled(onPressed: null);',
      ),
      hasLength(1),
    );
  });

  test('static style factories are not button constructors', () {
    expect(
      findMissingIconTooltips(
        'final style = IconButton.styleFrom(iconSize: 20);',
      ),
      isEmpty,
    );
    expect(
      findMissingIconTooltips(
        "Widget button() => IconButton(tooltip: 'Создать', style: IconButton.styleFrom(iconSize: 20));",
      ),
      isEmpty,
    );
  });

  test('null and empty literal tooltips are rejected', () {
    for (final tooltip in ['null', "''", "'   '"]) {
      expect(
        findMissingIconTooltips(
          'Widget button() => IconButton(tooltip: $tooltip, onPressed: save);',
        ),
        hasLength(1),
      );
    }
  });

  test(
    'labeled extended FABs and source-like comments are not icon-only calls',
    () {
      expect(
        findMissingIconTooltips(
          "Widget button() => FloatingActionButton.extended(label: Text('Создать'), onPressed: save);",
        ),
        isEmpty,
      );
      expect(
        findMissingIconTooltips(
          "// IconButton(onPressed: save)\nconst example = 'IconButton(onPressed: save)';",
        ),
        isEmpty,
      );
    },
  );

  test(
    'dynamic own tooltip is allowed; runtime semantics require widget tests',
    () {
      expect(
        findMissingIconTooltips(
          'Widget button(String label) => IconButton(tooltip: label, onPressed: save);',
        ),
        isEmpty,
      );
    },
  );

  test('invalid Dart fails the guard instead of silently omitting calls', () {
    expect(
      () => findMissingIconTooltips('Widget button() => IconButton('),
      throwsFormatException,
    );
  });
}
