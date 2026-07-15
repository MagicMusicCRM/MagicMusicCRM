import 'package:flutter/material.dart';
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
