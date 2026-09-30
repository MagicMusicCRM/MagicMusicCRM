// lib/core/services/section_unseen_service.dart
//
// Счётчики непросмотренного на вкладках CRM.
//
// ✔ Требование заказчика 17.07: «в зависимости от изменений в определённых
// папках или окнах должны приходить свои уведомления с счётчиком непрочитанных
// или непросмотренных изменений».
// ✔ Решение заказчика: считает и хранит СЕРВЕР — счётчик переживает перезапуск
// и одинаков на телефоне и на компьютере.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/magic_api_providers.dart';
import 'alert_policy.dart';

/// Ключи разделов. Обязаны совпадать с `SECTION_KEYS` на сервере
/// (server/src/crm/section-views.service.ts) — иначе вкладка попросит счёт по
/// разделу, которого сервер не знает, и бейдж молча замрёт.
class SectionKeys {
  static const clients = 'clients';
  static const tasks = 'tasks';
  static const schedule = 'schedule';
  static const finance = 'finance';
}

/// Ключ раздела для вкладки CRM. `null` — у вкладки счётчика нет.
///
/// «Чата» здесь нет намеренно: его непрочитанные считаются точно, по факту
/// прочтения каждого сообщения, и живут своей дорогой (`_unreadCounts` в
/// мессенджере). «Обзор», «Пользователи» и «Отчёты» — витрины над теми же
/// данными: счётчик на них дублировал бы соседние вкладки.
String? sectionKeyForTab(int tab) {
  switch (tab) {
    case CrmSection.clients:
      return SectionKeys.clients;
    case CrmSection.tasks:
      return SectionKeys.tasks;
    case CrmSection.schedule:
      return SectionKeys.schedule;
    case CrmSection.finance:
      return SectionKeys.finance;
    default:
      return null;
  }
}

class SectionUnseenService {
  final Ref _ref;
  SectionUnseenService(this._ref);

  Future<Map<String, int>> unseen() async {
    final api = _ref.read(magicApiClientProvider);
    final response = await api.get<Map<String, dynamic>>(
      '/crm/sections/unseen',
    );
    return response.map(
      (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
    );
  }

  Future<void> markSeen(String section) async {
    final api = _ref.read(magicApiClientProvider);
    await api.post<Map<String, dynamic>>(
      '/crm/sections/seen',
      data: {'section': section},
    );
  }
}

final sectionUnseenServiceProvider = Provider<SectionUnseenService>(
  SectionUnseenService.new,
);

/// Shared clock for the task day and navigation counters.
final crmDayClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Счётчики непросмотренного: {раздел → сколько}.
///
/// Обновляется сам, когда realtime приносит событие: подписка на
/// `crmRealtimeProvider` живёт в оболочке (messenger_screen), она же и
/// инвалидирует этот провайдер. Тянуть событие сюда нельзя — провайдер
/// используется и там, где realtime не поднят (тесты, клиентский портал).
final sectionUnseenProvider = FutureProvider<Map<String, int>>((ref) async {
  final now = ref
      .watch(crmDayClockProvider)()
      .toUtc()
      .add(const Duration(hours: 3));
  final nextDay = DateTime.utc(now.year, now.month, now.day + 1);
  final rollover = Timer(
    nextDay.difference(now) + const Duration(milliseconds: 1),
    ref.invalidateSelf,
  );
  ref.onDispose(rollover.cancel);
  return ref.read(sectionUnseenServiceProvider).unseen();
});
