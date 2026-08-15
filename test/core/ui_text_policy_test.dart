import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('known technical and English UI phrases do not return', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    const forbidden = <String>[
      'Schedule Analyzer:',
      'Расчётный snapshot',
      'Единый dashboard',
      'Email для входа',
      'Новый email',
      'CRM роль',
      'Конфигурация CRM',
      'Сервер не вернул id файла',
      'расчета backend',
      'Запись A',
      'Запись B',
      'Контакты из HolliHop',
      'Статус в HolliHop',
      'Код причины латиницей',
      "hintText: 'access.review'",
      'Пакет роли · версия',
    ];

    for (final phrase in forbidden) {
      expect(sources, isNot(contains(phrase)), reason: 'Найдено: $phrase');
    }
  });

  test('caught technical errors are not rendered directly', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    final forbidden = <RegExp>[
      RegExp(r'message:\s*(?:snapshot\.)?error\.toString\(\)'),
      RegExp(r'detail:\s*[a-zA-Z]+\.message\b'),
      RegExp(r'_showError\([a-zA-Z]+\.message\)'),
      RegExp(r'_errorMessage\s*=\s*error\.toString\(\)'),
      RegExp(r'''Text\([^\n]*\$_?error\b'''),
    ];

    for (final pattern in forbidden) {
      expect(sources, isNot(matches(pattern)), reason: 'Найдено: $pattern');
    }
  });
}
