import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

/// «Причина» loss-reason picker sheet. Returns (reasonId, comment) on confirm,
/// or null if cancelled. Extracted from _LeadsWidgetState — pure (context+ref
/// only, no board state).
Future<(String?, String?)?> pickLossReason(
  BuildContext context,
  WidgetRef ref,
) async {
  List<Map<String, dynamic>> reasons = const [];
  try {
    reasons = await ref.read(magicCrmServiceProvider).listLossReasons();
  } catch (_) {
    // Reasons failed to load — still allow confirming with a free comment.
  }
  if (!context.mounted) return null;
  String? selectedId;
  final commentController = TextEditingController();
  final confirmed = await showMagicSheet<bool>(
    context,
    title: 'Причина',
    builder: (sheetContext) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final cs = Theme.of(ctx).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: () => setSheet(() => selectedId = r['id']?.toString()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                      vertical: AppSpace.sm,
                    ),
                    decoration: BoxDecoration(
                      color: r['id']?.toString() == selectedId
                          ? AppColor.goldSoft
                          : cs.surface,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(
                        color: r['id']?.toString() == selectedId
                            ? AppColor.gold
                            : cs.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          r['id']?.toString() == selectedId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                          color: r['id']?.toString() == selectedId
                              ? AppColor.gold
                              : cs.outline,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(r['name']?.toString() ?? 'Не указано'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: commentController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Комментарий (необязательно)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColor.gold,
                      foregroundColor: AppColor.onGold,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ),
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: const Text('Подтвердить'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
  final comment = commentController.text.trim();
  commentController.dispose();
  if (confirmed != true) return null;
  return (selectedId, comment.isEmpty ? null : comment);
}
