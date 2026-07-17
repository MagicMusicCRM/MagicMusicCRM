// lib/core/services/alert_policy.dart
//
// Где сейчас пользователь и надо ли звучать.
//
// ✔ Требование заказчика 17.07: «чтобы звуковое уведомление не работало, если
// пользователь находится в окне или виджете или чате/диалоге — тоже чтобы не
// спамить». ✔ Решение заказчика: молчать про то, НА ЧТО СМОТРИШЬ.
//
// Смысл: звук — это «посмотри туда, тебя там ждут». Если человек уже там,
// звук ничего не сообщает, только раздражает. Новый лид, когда ты на доске
// лидов, появится на глазах сам; сообщение в открытом чате ты и так читаешь.
//
// Правило чистое и без Flutter — поэтому проверяется тестами без звука, экрана
// и таймеров.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ворота «не чаще раза в N секунд».
///
/// ✔ Требование заказчика 17.07: «интервал между звуковыми уведомлениями внутри
/// приложения — 5 секунд между каждым возможным, чтобы не спамить звуком».
///
/// Отдельно от проигрывателя, и не для красоты: `AlertSoundService.play()`
/// трогает just_audio, а он в юнит-тесте виснет — платформы нет. Правило,
/// спрятанное внутри звука, проверялось бы только ушами.
///
/// Общее на ВСЕ источники сразу: звук у приложения один, и человеку всё равно,
/// десять лидов подряд прилетело или лид, задача и сообщение вперемешку — он
/// слышит трель.
class AlertThrottle {
  static const defaultInterval = Duration(seconds: 5);

  final Duration interval;

  /// Часы — параметром: иначе «прошло ли 5 секунд» нельзя проверить, не
  /// проспав их в тесте.
  final DateTime Function() _now;

  DateTime? _lastAt;

  AlertThrottle({this.interval = defaultInterval, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// Сколько осталось до следующего разрешённого раза.
  Duration get cooldownLeft {
    final last = _lastAt;
    if (last == null) return Duration.zero;
    final passed = _now().difference(last);
    return passed >= interval ? Duration.zero : interval - passed;
  }

  /// `true` — можно, и время засчитано. `false` — рано.
  ///
  /// Метка ставится ЗДЕСЬ, а не после проигрывания: два события в одном кадре
  /// иначе оба прошли бы проверку и сыграли дуплетом — ровно тот спам, от
  /// которого ворота и стоят.
  bool tryAcquire() {
    if (cooldownLeft > Duration.zero) return false;
    _lastAt = _now();
    return true;
  }
}

/// Разделы CRM — те же индексы вкладок, что в `crm_nav_rbac.dart`.
///
/// ⚠️ Числа обязаны совпадать с тамошней раскладкой: 0 Чат · 1 Обзор ·
/// 2 Расписание · 3 Клиенты · 4 Пользователи · 5 Финансы · 6 Задачи ·
/// 7 Отчёты. Разъедутся — звук замолчит не про то.
class CrmSection {
  static const chat = 0;
  static const overview = 1;
  static const schedule = 2;
  static const clients = 3;
  static const users = 4;
  static const finance = 5;
  static const tasks = 6;
  static const reports = 7;
}

/// Что пользователь видит прямо сейчас.
class ActiveView {
  /// Индекс открытой вкладки CRM. `null` — приложение не на экране CRM.
  final int? crmTab;

  /// Id открытого чата. Заполнен только когда чат реально открыт (а не когда
  /// просто выбрана вкладка «Чат» со списком).
  final String? chatId;

  const ActiveView({this.crmTab, this.chatId});

  ActiveView copyWith({int? crmTab, String? chatId, bool clearChat = false}) =>
      ActiveView(
        crmTab: crmTab ?? this.crmTab,
        chatId: clearChat ? null : (chatId ?? this.chatId),
      );

  @override
  bool operator ==(Object other) =>
      other is ActiveView && other.crmTab == crmTab && other.chatId == chatId;

  @override
  int get hashCode => Object.hash(crmTab, chatId);
}

class ActiveViewNotifier extends Notifier<ActiveView> {
  @override
  ActiveView build() => const ActiveView();

  /// Одним вызовом, а не двумя сеттерами: вкладка и чат меняются вместе (ушёл
  /// с «Чата» — чат закрылся), и два подряд присвоения дали бы промежуточное
  /// состояние «другая вкладка, но чат ещё открыт», по которому кто-нибудь
  /// успел бы решить, что звучать не надо.
  ///
  /// Молча выходит, если ничего не изменилось: иначе каждый кадр build()
  /// перерисовывал бы подписчиков.
  void set({int? crmTab, String? chatId}) {
    final next = ActiveView(crmTab: crmTab, chatId: chatId);
    if (state == next) return;
    state = next;
  }
}

/// Где пользователь сейчас. Обновляется оболочкой приложения.
final activeViewProvider =
    NotifierProvider<ActiveViewNotifier, ActiveView>(ActiveViewNotifier.new);

/// Раздел, к которому относится событие realtime/push.
///
/// `null` — событие ни к какому разделу не привязано (звучим: молчать про то,
/// чего не понимаем, значит терять уведомления).
int? sectionForEntity(String? entity) {
  switch (entity) {
    case 'lead':
    case 'student':
    case 'comment':
      return CrmSection.clients;
    case 'task':
      return CrmSection.tasks;
    case 'lesson':
    case 'group':
      return CrmSection.schedule;
    case 'payment':
    case 'expense':
    case 'subscription':
      return CrmSection.finance;
    case 'chat_work':
      return CrmSection.chat;
    default:
      return null;
  }
}

/// Звучать ли по событию раздела [section] (и, для чата, конкретного [chatId]).
///
/// Правило одно: **молчим только про то, на что человек смотрит прямо сейчас.**
///
/// Чат разбирается точнее остальных: вкладка «Чат» — это список диалогов, и
/// сообщение из ДРУГОГО чата там вполне стоит озвучить. Молчим, только если
/// открыт именно тот чат, куда пришло сообщение.
bool shouldSoundFor({
  required ActiveView view,
  required int? section,
  String? chatId,
}) {
  // Событие не привязано к разделу — озвучиваем: пропустить настоящее
  // уведомление хуже, чем лишний раз звякнуть.
  if (section == null) return true;
  if (view.crmTab != section) return true;

  if (section == CrmSection.chat) {
    // Открыт ровно этот чат — человек его читает.
    if (chatId != null && view.chatId == chatId) return false;
    // Открыт другой чат либо просто список — сообщение стоит услышать.
    return true;
  }

  // Раздел открыт — изменение появится у человека на глазах.
  return false;
}
