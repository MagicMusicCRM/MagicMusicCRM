import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/widgets/magic_picker.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface_kind.dart';
import 'package:magic_music_crm/core/widgets/magic_toast.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_launcher.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';

import 'finance_controller.dart';
import 'finance_widget_widgets.dart';

typedef _ExpenseDialogCopy = ({
  String title,
  String subtitle,
  IconData icon,
  String successMessage,
  String errorMessage,
});

_ExpenseDialogCopy _expenseDialogCopy(bool editing) => editing
    ? (
        title: 'Изменить расход',
        subtitle: 'Исправьте сумму, категорию или комментарий',
        icon: Icons.edit_rounded,
        successMessage: 'Расход изменён',
        errorMessage: 'Не удалось изменить расход',
      )
    : (
        title: 'Добавить расход',
        subtitle: 'Сумма, категория и комментарий',
        icon: Icons.receipt_long_rounded,
        successMessage: 'Расход добавлен',
        errorMessage: 'Не удалось добавить расход',
      );

class FinanceWidget extends ConsumerStatefulWidget {
  const FinanceWidget({super.key, this.filterRange, this.branchId});

  /// Shared filter from the unified Analytics shell. When present, the local
  /// period picker is hidden so Finance and Summary cannot drift apart.
  final DateTimeRange? filterRange;
  final String? branchId;

  @override
  ConsumerState<FinanceWidget> createState() => _FinanceWidgetState();
}

class _FinanceWidgetState extends ConsumerState<FinanceWidget> {
  late final FinanceController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FinanceController(
      crm: ref.read(magicCrmServiceProvider),
      reportFileOpener: ref.read(reportFileOpenerProvider),
      filterRange: widget.filterRange,
      branchId: widget.branchId,
    );
    unawaited(_controller.load());
  }

  @override
  void didUpdateWidget(covariant FinanceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldRange = oldWidget.filterRange;
    final range = widget.filterRange;
    final rangeChanged =
        oldRange?.start != range?.start || oldRange?.end != range?.end;
    if (rangeChanged || oldWidget.branchId != widget.branchId) {
      unawaited(_controller.updateExternalQuery(range, widget.branchId));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final picked = await showMagicDateRangePicker(
      context: context,
      firstDate: DateTime(2018),
      lastDate: DateTime.now(),
      initialDateRange: _controller.state.customRange,
    );
    if (picked != null && mounted) await _controller.setCustomRange(picked);
  }

  Future<void> _saveExpense([Map<String, dynamic>? expense]) async {
    final copy = _expenseDialogCopy(expense != null);
    final identity = MagicMutationIdentity.create(
      expense == null ? 'expense-create' : 'expense-update',
    );
    final saved = await showMagicAdaptiveSurface<bool>(
      context,
      kind: AppSurfaceKind.quickView,
      title: copy.title,
      subtitle: copy.subtitle,
      icon: copy.icon,
      builder: (_) => ExpenseSheetForm(
        initialExpense: expense,
        onSubmit: (data) => _persistExpense(expense, data, identity),
      ),
    );
    if (saved == true && mounted) {
      MagicToast.show(
        context,
        copy.successMessage,
        type: MagicToastType.success,
      );
    }
  }

  Future<bool> _persistExpense(
    Map<String, dynamic>? expense,
    Map<String, dynamic> result,
    MagicMutationIdentity identity,
  ) async {
    if (expense == null) {
      await _controller.createExpense(
        amount: result['amount'] as num,
        category: result['category'] as String,
        occurredAt: result['occurredAt'] as String?,
        identity: identity,
        description: result['description'] as String?,
        branchId: result['branchId'] as String?,
      );
      return true;
    }
    final expenseId = expense['id'];
    if (expenseId is! String || expenseId.trim().isEmpty) return false;
    await _controller.updateExpense(
      expenseId: expenseId,
      expectedVersion: (expense['version'] as num).toInt(),
      amount: result['amount'] as num,
      category: result['category'] as String,
      occurredAt: result['occurredAt'] as String?,
      identity: identity,
      description: result['description'] as String?,
      branchId: expense['branchId'] as String? ?? result['branchId'] as String?,
    );
    return true;
  }

  Future<void> _deleteExpense(Map<String, dynamic> expense) async {
    final expenseId = expense['id']?.toString();
    if (expenseId == null || expenseId.isEmpty) return;
    final confirmed = await showMagicDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить расход?'),
        content: const Text(
          'Запись перестанет учитываться в итогах и аналитике, '
          'но аудит операции сохранится.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-expense'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColor.danger),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _controller.deleteExpense(
        expenseId,
        expectedVersion: (expense['version'] as num).toInt(),
      );
      if (mounted) {
        MagicToast.show(context, 'Расход удалён', type: MagicToastType.success);
      }
    } catch (error) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось удалить расход',
        detail: userErrorMessage(error),
        type: MagicToastType.danger,
      );
    }
  }

  Future<void> _export(String format) async {
    try {
      final result = await _controller.export(format);
      if (!mounted || result == null) return;
      MagicToast.show(
        context,
        'Файл сохранён',
        detail: result.filename,
        type: MagicToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Ошибка экспорта',
        detail: FinanceController.exportErrorMessage(error),
        type: MagicToastType.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(crmRealtimeProvider, (previous, next) {
      final event = next.value;
      if (event == null || event.isFallbackPoll) return;
      if (event.entity == 'finance' || event.entity == 'expense') {
        _controller.queueRealtimeRefresh();
      }
    });
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => FinanceView(
        state: _controller.state,
        onPickRange: _pickRange,
        onClearRange: () => _controller.setCustomRange(null),
        onPeriodChanged: _controller.setPeriod,
        onExportCsv: () => _export('csv'),
        onExportXlsx: () => _export('xlsx'),
        onAddExpense: _saveExpense,
        onEditExpense: _saveExpense,
        onDeleteExpense: _deleteExpense,
        onLoadMorePayments: _controller.loadMorePayments,
        onLoadMoreExpenses: _controller.loadMoreExpenses,
        onRetryPayments: _controller.loadPayments,
        onRetryExpenses: _controller.loadExpenses,
        onRefreshPayments: _controller.loadPayments,
        onOpenStudent: (id, name) async {
          await showClientCard(
            context,
            entityType: 'student',
            entityId: id,
            presentationLabel: name,
          );
          if (mounted) await _controller.loadPayments();
        },
      ),
    );
  }
}
