import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/utils/status_color.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';

/// v7 board column editor for the **lead board** funnel.
///
/// Backed by the existing [MagicCrmService] lead-status methods only:
///   * [MagicCrmService.createLeadStatus] — add a column (UpsertLeadStatusDto:
///     label / key / color / sortOrder).
///   * [MagicCrmService.reorderLeadStatuses] — drag-to-reorder columns.
///   * [MagicCrmService.deleteLeadStatus] — remove a column.
///
/// Scope note: there is no client-side *update* endpoint for an existing
/// lead-status, so renaming / recoloring an already-created column is not
/// persisted here — it is offered only while adding a new column. The
/// "dual-target student board" likewise has no backing endpoint, so this editor
/// is intentionally scoped to the lead board. All service / provider / realtime
/// / RBAC wiring is preserved exactly as before; this is a presentation reskin
/// on top of the same calls.
class ManageStatusesDialog extends ConsumerStatefulWidget {
  const ManageStatusesDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showMagicSheet<void>(
      context,
      title: 'Колонки воронки',
      subtitle: 'Лид-борд · добавление, порядок, удаление',
      icon: Icons.view_week_rounded,
      builder: (_) => const ManageStatusesDialog(),
    );
  }

  @override
  ConsumerState<ManageStatusesDialog> createState() =>
      _ManageStatusesDialogState();
}

class _ManageStatusesDialogState extends ConsumerState<ManageStatusesDialog> {
  List<Map<String, dynamic>> _statuses = [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(leadStatusesProvider.future);
      if (!mounted) return;
      setState(() {
        _statuses = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  // ── Add ────────────────────────────────────────────────────────────────────
  // Collects label/key/color via the v7 edit sheet and creates the column with
  // the EXACT UpsertLeadStatusDto fields the service accepts.
  Future<void> _addStatus() async {
    final existingKeys = _statuses
        .map((s) => s['key']?.toString().toLowerCase() ?? '')
        .where((k) => k.isNotEmpty)
        .toSet();

    final result = await showMagicSheet<_StatusDraft>(
      context,
      title: 'Новая колонка',
      subtitle: 'Название, ключ и цвет колонки воронки',
      icon: Icons.add_rounded,
      builder: (_) => _StatusEditForm(takenKeys: existingKeys),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createLeadStatus(
            key: result.key,
            label: result.label,
            color: result.color,
            sortOrder: _statuses.length,
          );
      ref.invalidate(leadStatusesProvider);
      await _loadStatuses();
      if (mounted) {
        MagicToast.show(
          context,
          'Колонка добавлена',
          detail: result.label,
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось добавить колонку',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Reorder ─────────────────────────────────────────────────────────────────
  // Optimistic reorder with rollback — behaviour preserved from the original.
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    // ReorderableListView passes newIndex assuming the item is still present,
    // so adjust when moving an item further down the list.
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final previous = List<Map<String, dynamic>>.from(_statuses);
    final reordered = List<Map<String, dynamic>>.from(_statuses);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    // Optimistic update: reflect the new order immediately.
    setState(() => _statuses = reordered);

    final idsInOrder = reordered.map((s) => s['id'].toString()).toList();
    try {
      await ref.read(magicCrmServiceProvider).reorderLeadStatuses(idsInOrder);
      ref.invalidate(leadStatusesProvider);
    } catch (e) {
      // Revert to the previous order on failure.
      if (mounted) {
        setState(() => _statuses = previous);
        MagicToast.show(
          context,
          'Не удалось изменить порядок колонок',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    }
  }

  // ── Delete ──────────────────────────────────────────────────────────────────
  Future<void> _deleteStatus(Map<String, dynamic> status) async {
    final id = status['id'].toString();
    final label = status['label']?.toString() ?? 'Колонка';

    final confirmed = await showMagicSheet<bool>(
      context,
      title: 'Удалить колонку?',
      subtitle: label,
      icon: Icons.delete_outline_rounded,
      builder: (sheetCtx) => Text(
        'Колонка воронки «$label» будет удалена. Лиды в ней останутся, но '
        'потеряют привязку к этой колонке.',
        style: TextStyle(
          color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
          fontSize: 13.5,
          height: 1.4,
        ),
      ),
      actions: [
        _GhostButton(
          label: 'Отмена',
          onPressed: () => Navigator.pop(context, false),
        ),
        _DangerButton(
          label: 'Удалить',
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(magicCrmServiceProvider).deleteLeadStatus(id);
      ref.invalidate(leadStatusesProvider);
      await _loadStatuses();
      if (mounted) {
        MagicToast.show(
          context,
          'Колонка удалена',
          detail: label,
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось удалить колонку',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Constrain height so the reorderable list scrolls inside the sheet body.
    final maxHeight = MediaQuery.of(context).size.height * 0.52;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(child: _buildContent()),
          const SizedBox(height: AppSpace.md),
          _GoldButton(
            label: 'Добавить колонку',
            icon: Icons.add_rounded,
            onPressed: (_loading || _busy) ? null : _addStatus,
          ),
        ],
      ),
    );
  }

  // Explicit loading / error / empty / list states so the editor body is never
  // an unexplained blank panel (Windows audit P1).
  Widget _buildContent() {
    if (_loading) {
      return const _StatusListSkeleton();
    }
    if (_error != null) {
      return _StatusMessage(
        icon: Icons.error_outline_rounded,
        accent: AppColor.danger,
        title: 'Не удалось загрузить колонки',
        body: '$_error',
        actionLabel: 'Повторить',
        onAction: _loadStatuses,
      );
    }
    if (_statuses.isEmpty) {
      return _StatusMessage(
        icon: Icons.view_column_outlined,
        accent: AppColor.gold,
        title: 'Колонок воронки пока нет',
        body: 'Добавьте первую колонку, чтобы выстроить воронку лидов.',
        actionLabel: 'Добавить колонку',
        onAction: _addStatus,
      );
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _statuses.length,
      onReorder: _onReorder,
      proxyDecorator: (child, index, animation) {
        // Lifted drag card: gold-line ring + sh-lift, per v7 `--sh-lift`.
        return Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColor.goldLine),
              boxShadow: AppShadow.shLift,
            ),
            child: child,
          ),
        );
      },
      itemBuilder: (context, index) {
        final s = _statuses[index];
        return _StatusRow(
          key: ValueKey(s['id'].toString()),
          index: index,
          status: s,
          enabled: !_busy,
          onDelete: () => _deleteStatus(s),
        );
      },
    );
  }
}

// ── Row ───────────────────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    super.key,
    required this.index,
    required this.status,
    required this.enabled,
    required this.onDelete,
  });

  final int index;
  final Map<String, dynamic> status;
  final bool enabled;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = statusColorFromValue(status['color']);
    final label = status['label']?.toString() ?? 'Без названия';
    final key = status['key']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColor.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                enabled: enabled,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              // Color swatch — gold-line ring keeps light/dark swatches legible.
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColor.goldLine, width: 1),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (key.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Ключ: $key',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Удалить колонку',
                onPressed: enabled ? onDelete : null,
                icon: const Icon(Icons.delete_outline_rounded),
                color: AppColor.danger,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── States ────────────────────────────────────────────────────────────────────

class _StatusListSkeleton extends StatelessWidget {
  const _StatusListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (_) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Row(
            children: [
              const SkeletonBox(width: 18, height: 18, radius: AppRadius.pill),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 140, height: 12, radius: AppRadius.sm),
                    SizedBox(height: 6),
                    SkeletonBox(width: 90, height: 10, radius: AppRadius.sm),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.md),
              const SkeletonBox(width: 24, height: 24, radius: AppRadius.sm),
            ],
          ),
        );
      }),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.icon),
                border: Border.all(color: accent.withValues(alpha: 0.34)),
              ),
              child: Icon(icon, size: 24, color: accent),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            _GoldButton(
              label: actionLabel,
              icon: Icons.refresh_rounded,
              onPressed: onAction,
              fullWidth: false,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add/edit form (new columns only — see scope note above) ──────────────────

class _StatusDraft {
  const _StatusDraft({
    required this.label,
    required this.key,
    required this.color,
  });

  final String label;
  final String key;
  final String color;
}

class _StatusEditForm extends StatefulWidget {
  const _StatusEditForm({required this.takenKeys});

  final Set<String> takenKeys;

  @override
  State<_StatusEditForm> createState() => _StatusEditFormState();
}

class _StatusEditFormState extends State<_StatusEditForm> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _keyEditedManually = false;

  String _selectedHex = 'C5A059'; // v7 gold default.

  // v7-aligned column palette (recolor source).
  static const List<String> _colors = [
    'C5A059', // Gold
    '8B5CF6', // Purple
    '3B82F6', // Blue
    '10B981', // Green
    'F59E0B', // Amber
    'E53935', // Red
    'A1A1AA', // Gray
  ];

  @override
  void dispose() {
    _labelCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  // Derive a slug key from the label until the user types a key themselves.
  void _onLabelChanged(String value) {
    if (_keyEditedManually) return;
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    _keyCtrl.value = TextEditingValue(
      text: slug,
      selection: TextSelection.collapsed(offset: slug.length),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      _StatusDraft(
        label: _labelCtrl.text.trim(),
        key: _keyCtrl.text.trim().toLowerCase(),
        color: '#$_selectedHex',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _labelCtrl,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onChanged: _onLabelChanged,
            decoration: _fieldDecoration(
              context,
              label: 'Название',
              hint: 'Напр. Переговоры',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Введите название' : null,
          ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            controller: _keyCtrl,
            onChanged: (_) => _keyEditedManually = true,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
            ],
            decoration: _fieldDecoration(
              context,
              label: 'Ключ',
              hint: 'латиницей, без пробелов',
            ),
            validator: (v) {
              final key = (v ?? '').trim().toLowerCase();
              if (key.isEmpty) return 'Введите ключ';
              if (widget.takenKeys.contains(key)) {
                return 'Такой ключ уже используется';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            'Цвет',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.md,
            children: _colors.map((hex) {
              final color = statusColorFromValue(hex);
              final selected = _selectedHex == hex;
              return GestureDetector(
                onTap: () => setState(() => _selectedHex = hex),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColor.gold : AppColor.divider,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: AppColor.onGold,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: _GhostButton(
                  label: 'Отмена',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: _GoldButton(label: 'Сохранить', onPressed: _submit),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    String? hint,
  }) {
    final scheme = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderSide: BorderSide(color: c),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      enabledBorder: border(AppColor.divider),
      focusedBorder: border(AppColor.gold),
    );
  }
}

// ── Buttons (flat gold / ghost / danger — no shadow) ─────────────────────────

class _GoldButton extends StatelessWidget {
  const _GoldButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: AppColor.gold,
      foregroundColor: AppColor.onGold,
      disabledBackgroundColor: AppColor.gold.withValues(alpha: 0.4),
      disabledForegroundColor: AppColor.onGold.withValues(alpha: 0.7),
      elevation: 0,
      shadowColor: Colors.transparent,
      minimumSize: Size(fullWidth ? double.infinity : 0, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    );
    if (icon == null) {
      return FilledButton(style: style, onPressed: onPressed, child: Text(label));
    }
    return FilledButton.icon(
      style: style,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: const BorderSide(color: AppColor.divider),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColor.danger,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}
