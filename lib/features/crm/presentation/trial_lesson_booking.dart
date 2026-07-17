import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';

/// Caller-provided feedback sink. The two booking surfaces present differently —
/// the client card uses `MagicToast`, the lead kanban card uses
/// `ScaffoldMessenger` — so each owns its presentation while the flow is shared.
typedef TrialFeedback =
    void Function(String message, {String? detail, bool ok});

/// «Пробное занятие» по лиду: используется карточкой клиента
/// ([_scheduleTrialFromCard]) и карточкой лида на канбане
/// ([_LeadCard._scheduleTrial]).
///
/// ✔ Решение владельца 17.07: «при назначении пробного это просто готовый
/// пресет под создание нового занятия, поэтому можно не дублировать
/// какой-то другой функционал, а переиспользовать создание нового занятия,
/// в котором обязательно есть выбор филиала и аудитории».
///
/// Отсюда всё, что здесь осталось, — открыть тот же диалог с пресетом.
/// Прежнее окно пробного (`showScheduleTrialDialog`) было отдельной формой на
/// четыре поля: без филиала, без длительности, без ставки, без проверки
/// конфликта аудитории. Аудитории в нём не фильтровались по филиалу ровно
/// потому, что филиала в нём и не было — фильтровать было не по чему.
///
/// Загрузку справочников, guard'ы и создание диалог делает сам.
Future<void> bookTrialLesson(
  BuildContext context,
  WidgetRef ref, {
  required String leadId,
  required String leadName,
  required TrialFeedback feedback,
  required Future<void> Function() onBooked,
}) async {
  final created = await CreateLessonDialog.showTrialPreset(
    context,
    leadId: leadId,
    leadName: leadName,
  );
  // Диалог сам показывает и успех, и ошибку сохранения — второй тост поверх
  // его снекбара был бы шумом. Колбэк остаётся: обновить карточку/канбан
  // может только вызывающий.
  if (created == true) await onBooked();
}
