import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';

/// Staff roles that should hear about new leads. Teachers are excluded on
/// purpose (the task is for admins/managers), clients never see CRM events.
const _leadNotificationRoles = {'admin', 'manager', 'director'};

/// KVA-240: app-level listener that turns realtime «lead created» events into
/// a desktop system notification (with the standard Windows toast sound).
///
/// Desktop-only on purpose: FCM does not work on Windows/Linux, while mobile
/// staff already receive the server push for the same event. Living at the
/// app level (not inside a screen) it fires from any section of the app.
final leadNotificationListenerProvider = Provider<void>((ref) {
  if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return;
  ref.listen(crmRealtimeProvider, (previous, next) {
    final event = next.value;
    if (event == null || event.entity != 'lead' || event.action != 'created') {
      return;
    }
    final role = ref.read(releaseGateStatusProvider).asData?.value.role;
    if (role == null || !_leadNotificationRoles.contains(role)) return;
    // The toast plays the system notification sound; a custom branded audio
    // asset can be added later without touching this listener.
    LocalNotification(
      title: 'Новая заявка',
      body: 'Поступил новый лид — откройте раздел «Лиды».',
    ).show();
  });
});

/// #11: pops «У вас новая задача» on the ASSIGNEE's desktop when a task is
/// created for them. Targeted via the event's affectedUserIds (mobile staff get
/// the server push for the same task). Desktop-only, same rationale as leads.
final taskNotificationListenerProvider = Provider<void>((ref) {
  if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return;
  ref.listen(crmRealtimeProvider, (previous, next) {
    final event = next.value;
    if (event == null || event.entity != 'task' || event.action != 'created') {
      return;
    }
    final userId = ref.read(currentUserIdProvider).asData?.value;
    if (userId == null || !event.affectedUserIds.contains(userId)) return;
    LocalNotification(
      title: 'У вас новая задача',
      body: 'Вам назначена задача — откройте раздел «Задачи».',
    ).show();
  });
});
