import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/services/alert_policy.dart';

void main() {
  group('shouldSoundFor — молчим про то, на что смотришь', () {
    test('новый лид, а человек на «Клиентах» — тихо', () {
      expect(
        shouldSoundFor(
          view: const ActiveView(crmTab: CrmSection.clients),
          section: sectionForEntity('lead'),
        ),
        isFalse,
      );
    });

    test('новый лид, а человек в «Задачах» — звук', () {
      expect(
        shouldSoundFor(
          view: const ActiveView(crmTab: CrmSection.tasks),
          section: sectionForEntity('lead'),
        ),
        isTrue,
      );
    });

    test('новая задача, а человек в «Задачах» — тихо', () {
      expect(
        shouldSoundFor(
          view: const ActiveView(crmTab: CrmSection.tasks),
          section: sectionForEntity('task'),
        ),
        isFalse,
      );
    });

    /// Чат — единственный раздел, где мало знать вкладку: список диалогов и
    /// открытый диалог это разные вещи.
    test('сообщение в ОТКРЫТОМ чате — тихо', () {
      expect(
        shouldSoundFor(
          view: const ActiveView(crmTab: CrmSection.chat, chatId: 'chat-a'),
          section: CrmSection.chat,
          chatId: 'chat-a',
        ),
        isFalse,
      );
    });

    test('сообщение в ДРУГОМ чате — звук, хоть вкладка и та же', () {
      expect(
        shouldSoundFor(
          view: const ActiveView(crmTab: CrmSection.chat, chatId: 'chat-a'),
          section: CrmSection.chat,
          chatId: 'chat-b',
        ),
        isTrue,
      );
    });

    test('открыт список чатов, диалог не выбран — звук', () {
      expect(
        shouldSoundFor(
          view: const ActiveView(crmTab: CrmSection.chat),
          section: CrmSection.chat,
          chatId: 'chat-a',
        ),
        isTrue,
      );
    });

    /// ⚠️ Молчать про то, чего не понимаем, значит терять уведомления. Лучше
    /// лишний раз звякнуть.
    test('событие без раздела — звук', () {
      expect(
        shouldSoundFor(
          view: const ActiveView(crmTab: CrmSection.clients),
          section: sectionForEntity('какая-то-новая-сущность'),
        ),
        isTrue,
      );
    });

    test('приложение не на экране CRM — звук', () {
      expect(
        shouldSoundFor(view: const ActiveView(), section: CrmSection.clients),
        isTrue,
      );
    });
  });

  group('sectionForEntity', () {
    test('сущности разложены по разделам', () {
      expect(sectionForEntity('lead'), CrmSection.clients);
      expect(sectionForEntity('student'), CrmSection.clients);
      expect(sectionForEntity('comment'), CrmSection.clients);
      expect(sectionForEntity('task'), CrmSection.tasks);
      expect(sectionForEntity('lesson'), CrmSection.schedule);
      expect(sectionForEntity('group'), CrmSection.schedule);
      expect(sectionForEntity('payment'), CrmSection.finance);
      expect(sectionForEntity('expense'), CrmSection.finance);
      expect(sectionForEntity('subscription'), CrmSection.finance);
      expect(sectionForEntity('chat_work'), CrmSection.chat);
    });

    test('неизвестное и null — не раздел', () {
      expect(sectionForEntity('setting'), isNull);
      expect(sectionForEntity(null), isNull);
    });
  });

  group('AlertThrottle — 5 секунд между звуками', () {
    /// Часы подставные: иначе «прошло ли 5 секунд» пришлось бы проспать.
    late DateTime now;
    late AlertThrottle throttle;

    setUp(() {
      now = DateTime(2026, 7, 17, 12, 0, 0);
      throttle = AlertThrottle(now: () => now);
    });

    test('первый звук проходит', () {
      expect(throttle.tryAcquire(), isTrue);
    });

    test('второй сразу — проглатывается', () {
      throttle.tryAcquire();
      expect(throttle.tryAcquire(), isFalse);
    });

    test('через 4 секунды — ещё рано', () {
      throttle.tryAcquire();
      now = now.add(const Duration(seconds: 4));
      expect(throttle.tryAcquire(), isFalse);
      expect(throttle.cooldownLeft, const Duration(seconds: 1));
    });

    test('через 5 секунд — можно', () {
      throttle.tryAcquire();
      now = now.add(const Duration(seconds: 5));
      expect(throttle.tryAcquire(), isTrue);
    });

    /// ⚠️ Троттлинг общий на ВСЕ источники: у приложения один звук, и человеку
    /// всё равно, десять лидов подряд или лид с задачей вперемешку.
    test('десять событий подряд — один звук', () {
      var played = 0;
      for (var i = 0; i < 10; i++) {
        if (throttle.tryAcquire()) played++;
      }
      expect(played, 1);
    });

    test('счётчик ожидания честен до звука и после', () {
      expect(throttle.cooldownLeft, Duration.zero);
      throttle.tryAcquire();
      expect(throttle.cooldownLeft, AlertThrottle.defaultInterval);
      now = now.add(const Duration(seconds: 5));
      expect(throttle.cooldownLeft, Duration.zero);
    });
  });
}
