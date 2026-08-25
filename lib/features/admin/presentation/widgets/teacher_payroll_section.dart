import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_model.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_dialogs.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_entry_dialogs.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_payroll_history.dart';

class TeacherPayrollSection extends StatefulWidget {
  const TeacherPayrollSection({
    super.key,
    required this.controller,
    required this.canManageHistory,
  });

  final TeacherPayrollController controller;
  final bool canManageHistory;

  @override
  State<TeacherPayrollSection> createState() => _TeacherPayrollSectionState();
}

class _TeacherPayrollSectionState extends State<TeacherPayrollSection> {
  final _money = NumberFormat('#,##0', 'ru');

  Future<void> _payAllDebt() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Оплатить всю задолженность'),
        content: Text('Выплатить ${_money.format(widget.controller.debt)} ₽?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Выплатить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.controller.payAllDebt();
    _showMutationError();
  }

  Future<void> _addBonusOrDeduction() async {
    final draft = await showTeacherBonusDeductionDialog(context);
    if (draft == null || !mounted) return;
    await widget.controller.createPayout(
      kind: draft.kind,
      amount: draft.amount,
      reasonText: draft.reasonText,
      comment: draft.reasonText,
    );
    _showMutationError();
  }

  Future<void> _editRate(Map<String, dynamic> row) async {
    if (!widget.canManageHistory || row['id'] == null) return;
    final edit = await showTeacherRateEditDialog(context, row);
    if (edit == null || !mounted) return;
    await widget.controller.updateRateEntry(
      entryId: row['id'].toString(),
      rate: edit.rate,
      effectiveFrom: DateFormat('yyyy-MM-dd').format(edit.effectiveFrom),
      reasonText: edit.reasonText,
    );
    _showMutationError();
  }

  Future<void> _editPayout(Map<String, dynamic> row) async {
    if (!widget.canManageHistory || row['id'] == null) return;
    final edit = await showTeacherPayoutEditDialog(context, row);
    if (edit == null || !mounted) return;
    await widget.controller.updatePayoutEntry(
      entryId: row['id'].toString(),
      kind: edit.kind,
      amount: edit.amount,
      paidAt: DateFormat('yyyy-MM-dd').format(edit.paidAt),
      reasonText: edit.reasonText,
      comment: edit.comment,
    );
    _showMutationError();
  }

  Future<void> _delete(Map<String, dynamic> row, {required bool rate}) async {
    if (!widget.canManageHistory || row['id'] == null) return;
    final reason = await showTeacherPayrollDeleteDialog(context, rate: rate);
    if (reason == null || !mounted) return;
    await widget.controller.deleteEntry(
      entryId: row['id'].toString(),
      rate: rate,
      reasonText: reason,
    );
    _showMutationError();
  }

  void _showMutationError() {
    final error = widget.controller.mutationError;
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userErrorMessage(error, fallback: 'Не удалось сохранить изменение.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.primaryGold.withAlpha(16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primaryGold.withAlpha(60)),
        ),
        child: _buildState(context),
      ),
    );
  }

  Widget _buildState(BuildContext context) {
    final controller = widget.controller;
    if (controller.error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Не удалось загрузить расчёты преподавателя.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            controller.error.toString(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: controller.load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Повторить'),
            ),
          ),
        ],
      );
    }
    final payroll = controller.payroll;
    if (payroll == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final debt = controller.debt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Оплаты преподавателю',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Задолженность: ${_money.format(debt)} ₽',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: debt > 0 ? AppTheme.warning : AppTheme.success,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Начислено ${_money.format(teacherDetailNum(payroll['accruedTotal']))} ₽ '
          '(${teacherDetailNum(payroll['hoursTotal'])} астр.ч.) · '
          'выплачено ${_money.format(teacherDetailNum(payroll['paidTotal']))} ₽',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Завершено ${teacherDetailInt(payroll['completedLessons'])} · '
          'оплачиваемых ${teacherDetailInt(payroll['payableLessons'])} · '
          'без поурочного начисления '
          '${teacherDetailInt(payroll['noAccrualLessons'])}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: debt > 0 && !controller.mutating ? _payAllDebt : null,
              child: const Text('Оплатить всю задолженность'),
            ),
            OutlinedButton(
              onPressed: controller.mutating ? null : _addBonusOrDeduction,
              child: const Text('Доплата / Вычет'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TeacherPayrollHistory(
          payroll: payroll,
          canManage: widget.canManageHistory,
          mutating: controller.mutating,
          onEditRate: _editRate,
          onEditPayout: _editPayout,
          onDelete: _delete,
        ),
      ],
    );
  }
}
