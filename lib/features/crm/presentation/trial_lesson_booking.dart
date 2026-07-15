import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import 'client_card/client_card_sheets.dart';

/// Caller-provided feedback sink. The two booking surfaces present differently —
/// the client card uses `MagicToast`, the lead kanban card uses
/// `ScaffoldMessenger` — so each owns its presentation while the flow is shared.
typedef TrialFeedback =
    void Function(String message, {String? detail, bool ok});

/// Shared «Пробное занятие» booking used by the client card
/// ([_scheduleTrialFromCard]) and the lead kanban card ([_LeadCard._scheduleTrial]).
///
/// Loads teacher/room options, shows the shared [showScheduleTrialDialog], and
/// on confirm creates the trial lesson for [leadId]. Feedback and refresh are
/// delegated to the caller ([feedback] / [onBooked]) since the surfaces differ;
/// the load → guard → dialog → `createLesson(isTrial: true)` orchestration —
/// previously copy-pasted in both — lives here once.
Future<void> bookTrialLesson(
  BuildContext context,
  WidgetRef ref, {
  required String leadId,
  required String leadName,
  required TrialFeedback feedback,
  required Future<void> Function() onBooked,
}) async {
  final crm = ref.read(magicCrmServiceProvider);

  List<Map<String, dynamic>> teachers;
  List<Map<String, dynamic>> rooms;
  try {
    final results = await Future.wait([
      crm.listTeachers(limit: 100),
      crm.listRooms(limit: 100),
    ]);
    teachers = List<Map<String, dynamic>>.from(results[0]);
    rooms = List<Map<String, dynamic>>.from(results[1]);
  } catch (e) {
    if (context.mounted) {
      feedback('Не удалось загрузить данные', detail: '$e', ok: false);
    }
    return;
  }
  if (!context.mounted) return;
  if (teachers.isEmpty) {
    feedback('Нет доступных преподавателей', ok: false);
    return;
  }

  final slot = await showScheduleTrialDialog(
    context,
    teachers: teachers,
    rooms: rooms,
  );
  if (slot == null) return;

  try {
    await crm.createLesson(
      leadId: leadId,
      teacherId: slot.teacherId,
      roomId: slot.roomId,
      scheduledAt: slot.scheduledAt.toIso8601String(),
      isTrial: true,
      status: 'scheduled',
      notes: 'Пробное занятие по лиду: $leadName',
    );
    await onBooked();
    if (context.mounted) feedback('Пробное занятие назначено', ok: true);
  } catch (e) {
    if (context.mounted) feedback('Ошибка назначения', detail: '$e', ok: false);
  }
}
