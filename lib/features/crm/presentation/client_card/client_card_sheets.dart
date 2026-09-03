import 'package:magic_music_crm/core/widgets/magic_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/utils/money_format.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/homework_attachment_widgets.dart';
import 'package:magic_music_crm/core/widgets/magic_toast.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';

import 'client_card_ui.dart';

/// Self-contained modal sheet builders peeled off `_ClientCardState`. Each one
/// owns its own form controllers and returns the collected values as a record
/// (or `null` on cancel); the card keeps the thin wrapper that talks to the CRM
/// service and mutates card state. Presentation only — no card state reached.

/// «Продать абонемент» sheet. [packages] must be non-empty (the caller guards).
/// Returns the selected package map, or `null` if dismissed.
Future<Map<String, dynamic>?> showIssueSubscriptionSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> packages,
  String title = 'Продать абонемент',
  String subtitle = 'Выберите пакет занятий',
}) {
  return showMagicSheet<Map<String, dynamic>>(
    context,
    title: title,
    subtitle: subtitle,
    icon: Icons.card_membership_rounded,
    builder: (sheetContext) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final pkg in packages) ...[
            SubscriptionPackageTile(
              key: Key('issue-subscription-package-${pkg['id']}'),
              package: pkg,
              onTap: () => Navigator.pop(sheetContext, pkg),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ],
      );
    },
  );
}

/// Selectable subscription-package row inside the «Продать абонемент» sheet
/// (ported from student_detail_screen).
class SubscriptionPackageTile extends StatelessWidget {
  final Map<String, dynamic> package;
  final VoidCallback onTap;
  const SubscriptionPackageTile({
    super.key,
    required this.package,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = package['name']?.toString() ?? 'Абонемент';
    final lessons =
        package['unitCount'] ??
        package['lessons_total'] ??
        package['lessonsTotal'];
    final minor = BigInt.tryParse(
      (package['basePriceMinor'] ?? package['base_price_minor'])?.toString() ??
          '',
    );
    final currency =
        (package['currencyCode'] ?? package['currency_code'])?.toString() ??
        'RUB';
    final price = minor == null
        ? package['price'] == null
              ? null
              : formatPaymentMajor(package['price'], currencyCode: currency)
        : formatPaymentMinor(minor, currencyCode: currency);
    final validity = package['validity_days'] ?? package['validityDays'];
    final meta = [
      if (lessons != null) '$lessons ч.',
      ?price,
      if (validity != null) '$validity дн.',
    ].join(' · ');

    return Material(
      color: AppColor.input,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: AppColor.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColor.goldSoft,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: AppColor.goldLine),
                ),
                child: const Icon(
                  Icons.card_membership_rounded,
                  size: 18,
                  color: AppColor.gold,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColor.text,
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          meta,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColor.text2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColor.text2),
            ],
          ),
        ),
      ),
    );
  }
}

// Booking dialogs intentionally do not live in a client card. Card/kanban
// actions navigate to the Schedule tab; Schedule alone owns CreateLessonDialog
// and its branch/room/teacher conflict validation.

/// Collected values from [showAddTaskSheet].
typedef TaskInput = ({String title, DateTime? due, String? assignedTo});

/// «Новая задача» sheet. [staff] populates the optional «Исполнитель» dropdown
/// (blank/failed load simply hides it). Returns the form values (title may be
/// blank — the caller validates and toasts), or `null` if dismissed.
Future<TaskInput?> showAddTaskSheet(
  BuildContext context, {
  required bool isStudent,
  required List<Map<String, dynamic>> staff,
}) async {
  final cs = Theme.of(context).colorScheme;
  final titleCtrl = TextEditingController();
  DateTime? due;
  String? assignedTo;

  final confirmed = await showMagicSheet<bool>(
    context,
    title: 'Новая задача',
    subtitle: isStudent
        ? 'Поставьте задачу по этому ученику'
        : 'Поставьте задачу по этому лиду',
    icon: Icons.task_alt_rounded,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final dueLabel = due == null
              ? 'Без срока'
              : DateFormat('dd.MM.yyyy HH:mm', 'ru').format(due!);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: clientCardInputDecoration(
                  cs,
                  label: 'Название',
                  hint: 'Например: Перезвонить клиенту',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'Срок',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: () async {
                  final picked = await showMagicDatePicker(
                    context: context,
                    initialDate: due ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked == null || !context.mounted) return;
                  // Time as well as date: the deadline drives the -1h/-10m and
                  // overdue reminders, and a midnight due date fires them in
                  // the middle of the night.
                  final time = await showMagicTimePicker(
                    context: context,
                    initialTime: due == null
                        ? const TimeOfDay(hour: 12, minute: 0)
                        : TimeOfDay.fromDateTime(due!),
                  );
                  final fallback = due == null
                      ? const TimeOfDay(hour: 12, minute: 0)
                      : TimeOfDay.fromDateTime(due!);
                  final at = time ?? fallback;
                  setSheetState(
                    () => due = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                      at.hour,
                      at.minute,
                    ),
                  );
                },
                child: InputDecorator(
                  decoration: clientCardInputDecoration(cs, isDense: true),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(dueLabel),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (due != null)
                            InkWell(
                              onTap: () => setSheetState(() => due = null),
                              child: Icon(
                                Icons.clear_rounded,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                            color: AppColor.gold,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (staff.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                SearchablePickerField(
                  label: 'Исполнитель',
                  placeholder: 'Не назначен',
                  selectedId: assignedTo,
                  items: [
                    for (final s in staff)
                      if (s['profile_user_id'] != null)
                        SearchableSelectItem(
                          id: s['profile_user_id'].toString(),
                          label:
                              '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'
                                  .trim(),
                        ),
                  ],
                  onSelected: (item) =>
                      setSheetState(() => assignedTo = item?.id),
                ),
              ],
            ],
          );
        },
      );
    },
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        style: FilledButton.styleFrom(
          backgroundColor: AppColor.gold,
          foregroundColor: AppColor.onGold,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        child: const Text('Создать'),
      ),
    ],
  );

  final title = titleCtrl.text.trim();
  titleCtrl.dispose();
  if (confirmed != true) return null;
  return (title: title, due: due, assignedTo: assignedTo);
}

/// Collected values from [showAssignHomeworkSheet].
typedef HomeworkInput = ({
  String title,
  String? description,
  DateTime? dueAt,
  String? lessonId,
  HomeworkPickedFile? attachment,
});

/// «Задать ДЗ» sheet. [recentHomeworks] is a best-effort preview list shown
/// under the form. Returns the new homework's fields, or `null` if cancelled.
Future<HomeworkInput?> showAssignHomeworkSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> recentHomeworks,
  List<Map<String, dynamic>> lessons = const [],
  bool requireLesson = false,
  Future<HomeworkPickedFile?> Function(BuildContext context) pickAttachment =
      pickHomeworkAttachment,
}) async {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  DateTime? dueAt;
  String? lessonId = lessons.firstOrNull?['id']?.toString();
  HomeworkPickedFile? attachment;

  final created = await showMagicSheet<bool>(
    context,
    title: 'Задать ДЗ',
    subtitle: 'Новое домашнее задание',
    icon: Icons.assignment_rounded,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final dueLabel = dueAt == null
              ? 'Срок не задан'
              : DateFormat('d MMM yyyy, HH:mm', 'ru').format(dueAt!);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Заголовок *',
                  hintText: 'Что нужно выучить?',
                ),
              ),
              if (lessons.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  key: const ValueKey('homework-lesson'),
                  initialValue: lessonId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: requireLesson ? 'Занятие *' : 'Занятие',
                    helperText: 'Привязка определяет преподавателя и контекст',
                  ),
                  items: [
                    if (!requireLesson)
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Без привязки к занятию'),
                      ),
                    for (final lesson in lessons)
                      DropdownMenuItem<String>(
                        value: lesson['id']?.toString(),
                        child: Text(_homeworkLessonLabel(lesson)),
                      ),
                  ],
                  onChanged: (value) => setSheetState(() => lessonId = value),
                ),
              ],
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Описание',
                  hintText: 'Подробности (необязательно)',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: () async {
                  final now = DateTime.now();
                  final date = await showMagicDatePicker(
                    context: sheetContext,
                    initialDate: dueAt ?? now,
                    firstDate: now.subtract(const Duration(days: 1)),
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (date == null || !sheetContext.mounted) return;
                  final time = await showMagicTimePicker(
                    context: sheetContext,
                    initialTime: TimeOfDay.fromDateTime(dueAt ?? now),
                  );
                  setSheetState(() {
                    dueAt = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time?.hour ?? 0,
                      time?.minute ?? 0,
                    );
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.md,
                  ),
                  decoration: BoxDecoration(
                    color: AppColor.input,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: AppColor.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_rounded,
                        size: 18,
                        color: AppColor.gold,
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Text(
                          dueLabel,
                          style: TextStyle(
                            fontSize: 14,
                            color: dueAt == null
                                ? AppColor.text2
                                : AppColor.text,
                          ),
                        ),
                      ),
                      if (dueAt != null)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: AppColor.text2,
                          tooltip: 'Сбросить срок',
                          onPressed: () => setSheetState(() => dueAt = null),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              OutlinedButton.icon(
                key: const ValueKey('homework-pick-attachment'),
                onPressed: () async {
                  final picked = await pickAttachment(sheetContext);
                  if (picked != null && sheetContext.mounted) {
                    setSheetState(() => attachment = picked);
                  }
                },
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(
                  attachment == null ? 'Прикрепить файл' : 'Заменить файл',
                ),
              ),
              if (attachment case final file?) ...[
                const SizedBox(height: AppSpace.sm),
                Container(
                  key: const ValueKey('homework-selected-attachment'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColor.input,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: AppColor.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.insert_drive_file_outlined,
                        color: AppColor.gold,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Убрать файл',
                        onPressed: () => setSheetState(() => attachment = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              ],
              if (recentHomeworks.isNotEmpty) ...[
                const SizedBox(height: AppSpace.lg),
                const Divider(height: 1, color: AppColor.divider),
                const SizedBox(height: AppSpace.md),
                const Text(
                  'Последние ДЗ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColor.gold,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                for (final hw in recentHomeworks) HomeworkTile(homework: hw),
              ],
            ],
          );
        },
      );
    },
    actions: [
      clientCardGhostButton('Отмена', () => Navigator.pop(context, false)),
      clientCardGoldButton('Создать', () {
        if (titleCtrl.text.trim().isEmpty) {
          MagicToast.show(
            context,
            'Введите заголовок',
            type: MagicToastType.danger,
          );
          return;
        }
        if (requireLesson && (lessonId == null || lessonId!.isEmpty)) {
          MagicToast.show(
            context,
            'Выберите занятие',
            type: MagicToastType.danger,
          );
          return;
        }
        Navigator.pop(context, true);
      }),
    ],
  );

  final title = titleCtrl.text.trim();
  final description = descCtrl.text.trim();
  titleCtrl.dispose();
  descCtrl.dispose();
  if (created != true || title.isEmpty) return null;
  return (
    title: title,
    description: description.isEmpty ? null : description,
    dueAt: dueAt,
    lessonId: lessonId,
    attachment: attachment,
  );
}

String _homeworkLessonLabel(Map<String, dynamic> lesson) {
  final scheduled = DateTime.tryParse(
    (lesson['scheduled_at'] ?? lesson['scheduledAt'] ?? '').toString(),
  );
  final date = scheduled == null
      ? 'Дата не указана'
      : DateFormat('d MMM yyyy, HH:mm', 'ru').format(scheduled.toLocal());
  final teacher =
      (lesson['teacher_name'] ?? lesson['teacherName'])?.toString().trim() ??
      '';
  return teacher.isEmpty ? date : '$date · $teacher';
}

/// Compact read-only homework row for the «Последние ДЗ» section in the «Задать
/// ДЗ» sheet (ported from student_detail_screen).
class HomeworkTile extends StatelessWidget {
  final Map<String, dynamic> homework;
  const HomeworkTile({super.key, required this.homework});

  @override
  Widget build(BuildContext context) {
    final title = homework['title']?.toString() ?? 'Не указано';
    final status = homework['status']?.toString();
    final dueRaw = homework['due_at'] ?? homework['dueAt'];
    final due = DateTime.tryParse(dueRaw?.toString() ?? '');
    final subtitle = [
      if (status != null && status.isNotEmpty) _statusLabel(status),
      if (due != null) DateFormat('d MMM yyyy', 'ru').format(due.toLocal()),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.assignment_outlined,
              size: 16,
              color: AppColor.text2,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColor.text),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: AppColor.text2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'assigned':
        return 'Назначено';
      case 'submitted':
        return 'Сдано';
      case 'done':
      case 'completed':
        return 'Завершено';
      default:
        return status;
    }
  }
}
