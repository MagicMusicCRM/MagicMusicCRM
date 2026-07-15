import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

import 'client_card_ui.dart';

/// Self-contained modal sheet builders peeled off `_ClientCardState`. Each one
/// owns its own form controllers and returns the collected values as a record
/// (or `null` on cancel); the card keeps the thin wrapper that talks to the CRM
/// service and mutates card state. Presentation only — no card state reached.

/// Family roles offered when linking a record to a family.
const List<(String, String)> kFamilyRoleOptions = [
  ('parent', 'Родитель'),
  ('child', 'Ребёнок'),
  ('partner', 'Партнёр'),
  ('sibling', 'Брат/сестра'),
  ('guardian', 'Опекун'),
  ('payer', 'Плательщик'),
];

/// Collected values from [showAddFamilyMemberSheet].
typedef FamilyMemberInput = ({
  String role,
  String entityType,
  String entityId,
  bool isPrimaryContact,
});

/// «Добавить участника» sheet. Returns the form values (entityId may be blank —
/// the caller validates and toasts), or `null` if dismissed.
Future<FamilyMemberInput?> showAddFamilyMemberSheet(
  BuildContext context, {
  required bool isStudent,
  required String defaultEntityType,
  String? defaultEntityId,
}) async {
  final cs = Theme.of(context).colorScheme;
  var role = kFamilyRoleOptions.first.$1;
  var entityType = defaultEntityType;
  final entityIdCtrl = TextEditingController(text: defaultEntityId ?? '');
  var isPrimaryContact = false;

  final confirmed = await showMagicSheet<bool>(
    context,
    title: 'Добавить участника',
    subtitle: isStudent
        ? 'Свяжите запись с семьёй ученика'
        : 'Свяжите запись с семьёй лида',
    icon: Icons.person_add_alt_1_rounded,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Роль',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              DropdownButtonFormField<String>(
                initialValue: role,
                isExpanded: true,
                decoration: clientCardInputDecoration(cs, isDense: true),
                items: kFamilyRoleOptions
                    .map(
                      (option) => DropdownMenuItem(
                        value: option.$1,
                        child: Text(option.$2),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setSheetState(() => role = value);
                },
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'Тип записи',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              DropdownButtonFormField<String>(
                initialValue: entityType,
                isExpanded: true,
                decoration: clientCardInputDecoration(cs, isDense: true),
                items: const [
                  DropdownMenuItem(value: 'lead', child: Text('Лид')),
                  DropdownMenuItem(value: 'student', child: Text('Ученик')),
                  DropdownMenuItem(value: 'profile', child: Text('Профиль')),
                ],
                onChanged: (value) {
                  if (value != null) setSheetState(() => entityType = value);
                },
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: entityIdCtrl,
                decoration: clientCardInputDecoration(
                  cs,
                  label: 'ID записи',
                  hint: 'Идентификатор лида/ученика/профиля',
                  helperText: defaultEntityId == null
                      ? null
                      : (isStudent
                            ? 'По умолчанию — текущий ученик'
                            : 'По умолчанию — текущий лид'),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              CheckboxListTile(
                value: isPrimaryContact,
                activeColor: AppColor.gold,
                onChanged: (value) =>
                    setSheetState(() => isPrimaryContact = value ?? false),
                title: const Text('Основной контакт'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
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
        child: const Text('Добавить'),
      ),
    ],
  );

  final entityId = entityIdCtrl.text.trim();
  entityIdCtrl.dispose();
  if (confirmed != true) return null;
  return (
    role: role,
    entityType: entityType,
    entityId: entityId,
    isPrimaryContact: isPrimaryContact,
  );
}

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
              : DateFormat('dd.MM.yyyy', 'ru').format(due!);
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
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: due ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setSheetState(() => due = picked);
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
                DropdownButtonFormField<String?>(
                  initialValue: assignedTo,
                  isExpanded: true,
                  decoration: clientCardInputDecoration(
                    cs,
                    label: 'Исполнитель',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Не назначен'),
                    ),
                    for (final s in staff)
                      if (s['profile_user_id'] != null)
                        DropdownMenuItem<String?>(
                          value: s['profile_user_id'].toString(),
                          child: Text(
                            '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'
                                .trim(),
                          ),
                        ),
                  ],
                  onChanged: (v) => setSheetState(() => assignedTo = v),
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
typedef HomeworkInput = ({String title, String? description, DateTime? dueAt});

/// «Задать ДЗ» sheet. [recentHomeworks] is a best-effort preview list shown
/// under the form. Returns the new homework's fields, or `null` if cancelled.
Future<HomeworkInput?> showAssignHomeworkSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> recentHomeworks,
}) async {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  DateTime? dueAt;

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
                  final date = await showDatePicker(
                    context: sheetContext,
                    initialDate: dueAt ?? now,
                    firstDate: now.subtract(const Duration(days: 1)),
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (date == null || !sheetContext.mounted) return;
                  final time = await showTimePicker(
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
  );
}

/// Compact read-only homework row for the «Последние ДЗ» section in the «Задать
/// ДЗ» sheet (ported from student_detail_screen).
class HomeworkTile extends StatelessWidget {
  final Map<String, dynamic> homework;
  const HomeworkTile({super.key, required this.homework});

  @override
  Widget build(BuildContext context) {
    final title = homework['title']?.toString() ?? '—';
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
