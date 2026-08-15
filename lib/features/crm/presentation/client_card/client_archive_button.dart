import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'client_card_v4_api.dart';

bool clientRoleCanArchive(String role) =>
    role == 'director' || role == 'system_admin';

class ClientArchiveButton extends ConsumerStatefulWidget {
  const ClientArchiveButton({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.allowed,
    required this.onArchived,
  });

  final String entityType;
  final String entityId;
  final bool allowed;
  final VoidCallback onArchived;

  @override
  ConsumerState<ClientArchiveButton> createState() =>
      _ClientArchiveButtonState();
}

class _ClientArchiveButtonState extends ConsumerState<ClientArchiveButton> {
  bool _busy = false;

  Future<void> _openPreview() async {
    setState(() => _busy = true);
    try {
      final preview = await ref
          .read(clientCardV4ApiProvider)
          .previewArchive(
            entityType: widget.entityType,
            entityId: widget.entityId,
          );
      if (!mounted) return;
      final confirmed = await showDialog<String>(
        context: context,
        builder: (_) => _ArchivePreviewDialog(preview: preview),
      );
      if (confirmed == null || !mounted) return;
      await ref
          .read(clientCardV4ApiProvider)
          .archive(
            entityType: widget.entityType,
            entityId: widget.entityId,
            expectedVersion: _asInt(preview['version']),
            reason: confirmed,
          );
      if (!mounted) return;
      widget.onArchived();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(
              error,
              fallback: 'Не удалось архивировать карточку.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.allowed) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: const ValueKey('client-archive-open'),
      onPressed: _busy ? null : _openPreview,
      style: OutlinedButton.styleFrom(foregroundColor: AppColor.danger),
      icon: _busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.archive_outlined, size: 18),
      label: const Text('В архив'),
    );
  }
}

class _ArchivePreviewDialog extends StatefulWidget {
  const _ArchivePreviewDialog({required this.preview});

  final Map<String, dynamic> preview;

  @override
  State<_ArchivePreviewDialog> createState() => _ArchivePreviewDialogState();
}

class _ArchivePreviewDialogState extends State<_ArchivePreviewDialog> {
  String _reason = 'crm.client.archive.inactive';

  @override
  Widget build(BuildContext context) {
    final warnings = (widget.preview['warnings'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final links = (widget.preview['links'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final label = widget.preview['label']?.toString() ?? 'Клиент';
    final alreadyArchived = widget.preview['tombstone'] == true;
    return AlertDialog(
      key: const ValueKey('client-archive-preview'),
      title: Text(alreadyArchived ? 'Карточка уже в архиве' : 'Архивировать?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label),
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                for (final warning in warnings)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColor.warning,
                    ),
                    title: Text(
                      userErrorText(
                        warning['message']?.toString() ?? '',
                        fallback: 'Есть связанная запись.',
                      ),
                    ),
                    trailing: Text('${warning['count'] ?? 0}'),
                  ),
              ],
              if (links.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                Text(
                  'Связанные карточки: ${links.length}. Они не будут архивированы.',
                ),
              ],
              if (!alreadyArchived) ...[
                const SizedBox(height: AppSpace.md),
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  key: const ValueKey('client-archive-reason'),
                  initialValue: _reason,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Причина'),
                  items: const [
                    DropdownMenuItem(
                      value: 'crm.client.archive.inactive',
                      child: Text('Клиент больше не активен'),
                    ),
                    DropdownMenuItem(
                      value: 'crm.client.archive.duplicate',
                      child: Text('Дубликат'),
                    ),
                    DropdownMenuItem(
                      value: 'crm.client.archive.created_in_error',
                      child: Text('Создано по ошибке'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _reason = value ?? _reason),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        if (!alreadyArchived)
          FilledButton(
            key: const ValueKey('client-archive-confirm'),
            style: FilledButton.styleFrom(backgroundColor: AppColor.danger),
            onPressed: () => Navigator.of(context).pop(_reason),
            child: const Text('Архивировать'),
          ),
      ],
    );
  }
}

int _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 1;
