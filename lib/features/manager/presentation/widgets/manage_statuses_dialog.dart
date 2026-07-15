import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/utils/status_color.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';

part 'manage_statuses_widgets.dart';

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

