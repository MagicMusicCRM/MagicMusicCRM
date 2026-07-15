import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

import 'client_card_ui.dart';

// Modal dialogs peeled off `_ClientCardState` (family member, contact person,
// single-field editors). Each owns its form controllers and returns the
// collected values; the card keeps the CRM/state wrapper. Presentation only.

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

