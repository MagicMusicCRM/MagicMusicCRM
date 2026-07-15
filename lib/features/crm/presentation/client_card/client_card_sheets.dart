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

/// Single-text-field «Отмена/Сохранить» dialog. Returns the field text on save
/// (unchanged/untrimmed), or `null` if cancelled.
Future<String?> showSingleFieldDialog(
  BuildContext context, {
  required String title,
  String? label,
  String? hint,
  String? initialValue,
  TextInputType? keyboardType,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/// «Контактное лицо» dialog. [relationOptions] pre-includes the current value
/// if custom. Returns the collected person map (blank fields stripped), or
/// `null` if dismissed.
Future<Map<String, dynamic>?> showEditContactPersonDialog(
  BuildContext context, {
  required Map<String, dynamic> existing,
  required List<String> relationOptions,
  required bool isNew,
}) async {
  final nameCtrl = TextEditingController(
    text: existing['name']?.toString() ?? '',
  );
  final phoneCtrl = TextEditingController(
    text: existing['phone']?.toString() ?? '',
  );
  final emailCtrl = TextEditingController(
    text: existing['email']?.toString() ?? '',
  );
  String relation = existing['relation']?.toString() ?? '';
  final cs = Theme.of(context).colorScheme;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(isNew ? 'Новое контактное лицо' : 'Контактное лицо'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: clientCardInputDecoration(
                cs,
                label: 'Имя',
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            DropdownButtonFormField<String>(
              initialValue: relationOptions.contains(relation) ? relation : '',
              isExpanded: true,
              decoration: clientCardInputDecoration(
                cs,
                label: 'Кем приходится',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('Не выбрано')),
                ...relationOptions.map(
                  (option) =>
                      DropdownMenuItem(value: option, child: Text(option)),
                ),
              ],
              onChanged: (value) => relation = value ?? '',
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: clientCardInputDecoration(
                cs,
                label: 'Телефон',
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: clientCardInputDecoration(
                cs,
                label: 'Email',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColor.gold,
            foregroundColor: AppColor.onGold,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  Map<String, dynamic>? person;
  if (saved == true) {
    person = <String, dynamic>{
      'name': nameCtrl.text.trim(),
      'relation': relation,
      'phone': phoneCtrl.text.trim(),
      'email': emailCtrl.text.trim(),
    }..removeWhere((_, value) => (value as String).isEmpty);
  }
  nameCtrl.dispose();
  phoneCtrl.dispose();
  emailCtrl.dispose();
  return person;
}

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

/// «Выдать абонемент» sheet. [packages] must be non-empty (the caller guards).
/// Returns the selected package map, or `null` if dismissed.
Future<Map<String, dynamic>?> showIssueSubscriptionSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> packages,
}) {
  return showMagicSheet<Map<String, dynamic>>(
    context,
    title: 'Выдать абонемент',
    subtitle: 'Выберите пакет занятий',
    icon: Icons.card_membership_rounded,
    builder: (sheetContext) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final pkg in packages) ...[
            SubscriptionPackageTile(
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

/// Selectable subscription-package row inside the «Выдать абонемент» sheet
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
    final lessons = package['lessons_total'] ?? package['lessonsTotal'];
    final price = package['price'];
    final validity = package['validity_days'] ?? package['validityDays'];
    final meta = [
      if (lessons != null) '$lessons ч.',
      if (price != null) '$price ₽',
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

/// Collected values from [showScheduleTrialDialog].
typedef TrialLessonInput = ({
  String teacherId,
  String? roomId,
  DateTime scheduledAt,
});

/// «Пробное занятие» dialog (teacher/room/date/time picker). [teachers] must be
/// non-empty (the caller guards). Returns the chosen slot, or `null` on cancel.
Future<TrialLessonInput?> showScheduleTrialDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> teachers,
  required List<Map<String, dynamic>> rooms,
}) async {
  String? selectedTeacher = teachers.first['id']?.toString();
  String? selectedRoom = rooms.isNotEmpty ? rooms.first['id']?.toString() : null;
  DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocalState) => AlertDialog(
        title: const Text('Пробное занятие'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedTeacher,
              decoration: const InputDecoration(labelText: 'Учитель'),
              items: teachers
                  .map(
                    (t) => DropdownMenuItem(
                      value: t['id'].toString(),
                      child: Text('${t['first_name']} ${t['last_name']}'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setLocalState(() => selectedTeacher = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedRoom,
              decoration: const InputDecoration(labelText: 'Кабинет'),
              items: rooms
                  .map(
                    (r) => DropdownMenuItem(
                      value: r['id'].toString(),
                      child: Text(r['name']),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setLocalState(() => selectedRoom = v),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: Text(
                'Дата: ${DateFormat('dd.MM.yyyy').format(selectedDate)}',
              ),
              trailing: const Icon(Icons.calendar_today_rounded),
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: selectedDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (picked != null) {
                  setLocalState(() => selectedDate = picked);
                }
              },
            ),
            ListTile(
              title: Text('Время: ${selectedTime.format(ctx)}'),
              trailing: const Icon(Icons.access_time_rounded),
              onTap: () async {
                final picked = await showTimePicker(
                  context: ctx,
                  initialTime: selectedTime,
                );
                if (picked != null) {
                  setLocalState(() => selectedTime = picked);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Назначить'),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true || selectedTeacher == null) return null;
  final scheduledAt = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
    selectedTime.hour,
    selectedTime.minute,
  );
  return (
    teacherId: selectedTeacher!,
    roomId: selectedRoom,
    scheduledAt: scheduledAt,
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
