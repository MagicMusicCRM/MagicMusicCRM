import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/services/alert_policy.dart';
import 'package:magic_music_crm/core/services/section_unseen_service.dart';

void main() {
  group('sectionKeyForTab', () {
    test('вкладки со счётчиком разложены по ключам сервера', () {
      expect(sectionKeyForTab(CrmSection.clients), SectionKeys.clients);
      expect(sectionKeyForTab(CrmSection.tasks), SectionKeys.tasks);
      expect(sectionKeyForTab(CrmSection.schedule), SectionKeys.schedule);
      expect(sectionKeyForTab(CrmSection.finance), SectionKeys.finance);
    });

    /// ⚠️ У «Чата» счётчика ЗДЕСЬ нет намеренно: его непрочитанные считаются
    /// точно, по факту прочтения каждого сообщения (мессенджер), а не по «когда
    /// я в последний раз заглядывал». Подменить их приблизительным — ухудшить
    /// работающее.
    test('у Чата своего счётчика тут нет — у него точный', () {
      expect(sectionKeyForTab(CrmSection.chat), isNull);
    });

    /// «Обзор», «Пользователи» и «Отчёты» — витрины над теми же данными.
    /// Счётчик на них дублировал бы соседние вкладки.
    test('витрины без своих объектов счётчика не получают', () {
      expect(sectionKeyForTab(CrmSection.overview), isNull);
      expect(sectionKeyForTab(CrmSection.users), isNull);
      expect(sectionKeyForTab(CrmSection.reports), isNull);
    });

    test('неизвестная вкладка — не падаем', () {
      expect(sectionKeyForTab(99), isNull);
    });
  });

  /// Ключи фронта обязаны совпадать с SECTION_KEYS сервера
  /// (server/src/crm/section-views.service.ts). Разъедутся — вкладка попросит
  /// счёт по разделу, которого сервер не знает, и бейдж молча замрёт.
  group('ключи разделов совпадают с серверными', () {
    test('набор ровно тот же', () {
      final frontKeys = {
        SectionKeys.clients,
        SectionKeys.tasks,
        SectionKeys.schedule,
        SectionKeys.finance,
      };
      // Список продублирован намеренно: тест обязан упасть, если поменяли
      // только одну сторону.
      expect(frontKeys, {'clients', 'tasks', 'schedule', 'finance'});
    });
  });
}
