import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

import 'client_card_ui.dart';

class SubscriptionCancellationConfirmation {
  const SubscriptionCancellationConfirmation({
    required this.input,
    required this.identity,
  });

  final CancelSubscriptionInput input;
  final MagicMutationIdentity identity;
}

typedef SubscriptionCancellationConfirm =
    Future<void> Function(SubscriptionCancellationConfirmation confirmation);

Future<bool?> showSubscriptionCancellationSheet(
  BuildContext context, {
  required SubscriptionCancellationPreview preview,
  required SubscriptionCancellationConfirm onConfirm,
}) {
  return showMagicSheet<bool>(
    context,
    title: 'Отменить абонемент',
    subtitle: 'Проверьте финансовую историю и будущие занятия',
    icon: Icons.cancel_outlined,
    builder: (_) =>
        SubscriptionCancellationForm(preview: preview, onConfirm: onConfirm),
  );
}

class SubscriptionCancellationForm extends StatefulWidget {
  const SubscriptionCancellationForm({
    super.key,
    required this.preview,
    required this.onConfirm,
  });

  final SubscriptionCancellationPreview preview;
  final SubscriptionCancellationConfirm onConfirm;

  @override
  State<SubscriptionCancellationForm> createState() =>
      _SubscriptionCancellationFormState();
}

class _SubscriptionCancellationFormState
    extends State<SubscriptionCancellationForm> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  late final MagicMutationIdentity _identity;
  late final DirtyFormExitController _exitController;

  bool _confirmed = false;
  bool _busy = false;
  bool _attempted = false;
  String? _error;

  bool get _fieldsEnabled => !_attempted;

  @override
  void initState() {
    super.initState();
    _identity = MagicMutationIdentity.create('subscription-cancel');
    _exitController = DirtyFormExitController(
      onSave: () => _submit(closeOnSuccess: false),
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  String? _validateReason(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return 'Укажите код причины';
    if (value.length > 120 || !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
      return 'Разрешены латиница, цифры и символы . _ : -';
    }
    return null;
  }

  Future<bool> _submit({bool closeOnSuccess = true}) async {
    if (_busy) return false;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return false;
    if (!_confirmed) {
      setState(() => _error = 'Подтвердите последствия отмены.');
      return false;
    }

    final confirmation = SubscriptionCancellationConfirmation(
      input: CancelSubscriptionInput(
        expectedVersion: widget.preview.expectedVersion,
        previewToken: widget.preview.previewToken,
        reason: _reasonController.text,
      ),
      identity: _identity,
    );
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    _exitController.setBusy(true);
    try {
      await widget.onConfirm(confirmation);
      _exitController.setBusy(false);
      _exitController.markClean();
      if (closeOnSuccess && mounted) Navigator.pop(context, true);
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _busy = false;
        _error = '$error';
      });
      _exitController.setBusy(false);
      return false;
    }
  }

  void _requestClose() {
    _exitController.requestExit(
      context,
      reason: DirtyFormExitReason.appBack,
      savedResult: true,
      discardedResult: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    return DirtyFormExitScope(
      controller: _exitController,
      savedResult: true,
      discardedResult: false,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        onChanged: _exitController.markDirty,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CancellationPackageSummary(preview: preview),
            const SizedBox(height: AppSpace.md),
            _CancellationFinancialSummary(financial: preview.financial),
            const SizedBox(height: AppSpace.md),
            _CancellationFutureSummary(future: preview.future),
            const SizedBox(height: AppSpace.md),
            _CancellationWarning(warnings: preview.warnings),
            const SizedBox(height: AppSpace.md),
            Text(
              'Расчёт действителен до '
              '${DateFormat('dd.MM.yyyy HH:mm').format(preview.expiresAt.toLocal())}',
              style: const TextStyle(color: AppColor.text2, fontSize: 11.5),
            ),
            const SizedBox(height: AppSpace.lg),
            TextFormField(
              key: const Key('subscription-cancel-reason'),
              controller: _reasonController,
              enabled: _fieldsEnabled,
              maxLength: 120,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._:-]')),
              ],
              decoration: clientCardInputDecoration(
                Theme.of(context).colorScheme,
                label: 'Код причины',
                hint: 'Например: client.requested_cancel',
                helperText: 'Код попадёт в журнал действий',
                isDense: true,
              ),
              validator: _validateReason,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: AppSpace.sm),
            Container(
              decoration: BoxDecoration(
                color: AppColor.input,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(
                  color: _confirmed ? AppColor.danger : AppColor.divider,
                ),
              ),
              child: CheckboxListTile(
                key: const Key('subscription-cancel-confirmation'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                ),
                value: _confirmed,
                enabled: _fieldsEnabled,
                activeColor: AppColor.danger,
                checkColor: Colors.white,
                title: const Text(
                  'Подтверждаю отмену',
                  style: TextStyle(
                    color: AppColor.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: const Text(
                  'Абонемент исчезнет из активных. Платежи, списания, баланс '
                  'и сами занятия не изменятся.',
                  style: TextStyle(color: AppColor.text2, fontSize: 11.5),
                ),
                onChanged: _fieldsEnabled
                    ? (value) => setState(() {
                        _confirmed = value == true;
                        _error = null;
                        _exitController.markDirty();
                      })
                    : null,
              ),
            ),
            if (_attempted) ...[
              const SizedBox(height: AppSpace.md),
              const _CancellationRetryNotice(),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpace.md),
              _CancellationError(message: _error!),
            ],
            const SizedBox(height: AppSpace.xl),
            Row(
              children: [
                Expanded(
                  child: clientCardGhostButton(
                    'Назад',
                    _busy ? null : _requestClose,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: FilledButton(
                    key: const Key('subscription-cancel-submit'),
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColor.danger,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColor.dangerSoft,
                      disabledForegroundColor: AppColor.text2,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_attempted ? 'Повторить' : 'Отменить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CancellationPackageSummary extends StatelessWidget {
  const _CancellationPackageSummary({required this.preview});

  final SubscriptionCancellationPreview preview;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('subscription-cancel-package'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.input,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.card_membership_outlined, color: AppColor.gold),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview.package.name,
                  style: const TextStyle(
                    color: AppColor.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '${preview.package.unitCount} ч · использовано '
                  '${preview.usage.usedUnits} ч · '
                  '${_formatCancellationMinor(preview.financial.finalMinor, preview.financial.currencyCode)}',
                  style: const TextStyle(color: AppColor.text2, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CancellationFinancialSummary extends StatelessWidget {
  const _CancellationFinancialSummary({required this.financial});

  final SubscriptionCancellationFinancial financial;

  @override
  Widget build(BuildContext context) {
    return _CancellationSummaryBox(
      key: const Key('subscription-cancel-financial'),
      title: 'Финансовая история не изменится',
      icon: Icons.account_balance_wallet_outlined,
      rows: [
        (
          'Фактически оплачено',
          _formatCancellationMinor(
            financial.actualPaidMinor,
            financial.currencyCode,
          ),
        ),
        (
          'Списано за занятия',
          _formatCancellationMinor(
            financial.writeoffMinor,
            financial.currencyCode,
          ),
        ),
        (
          'Текущий баланс',
          _formatCancellationMinor(
            financial.balanceMinor,
            financial.currencyCode,
          ),
        ),
      ],
    );
  }
}

class _CancellationFutureSummary extends StatelessWidget {
  const _CancellationFutureSummary({required this.future});

  final SubscriptionCancellationFuture future;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('subscription-cancel-future'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.input,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.event_repeat_rounded, size: 17, color: AppColor.gold),
              SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  'Будущие занятия сохранятся',
                  style: TextStyle(
                    color: AppColor.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          _CancellationSummaryRow(
            label: 'Будущие занятия',
            value: '${future.lessonCount}',
          ),
          _CancellationSummaryRow(
            label: 'Покрыто резервом',
            value: '${future.reservedLessonCount} · ${future.reservedUnits} ч',
          ),
          if (future.lessons.isNotEmpty) ...[
            const Divider(height: AppSpace.lg, color: AppColor.divider),
            for (final lesson in future.lessons.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat(
                          'dd.MM.yyyy HH:mm',
                        ).format(lesson.scheduledAt.toLocal()),
                        style: const TextStyle(
                          color: AppColor.text2,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    Text(
                      '${lesson.units} ч',
                      style: const TextStyle(
                        color: AppColor.text,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Icon(
                      lesson.reserved
                          ? Icons.bookmark_added_outlined
                          : Icons.bookmark_border_rounded,
                      size: 16,
                      color: lesson.reserved ? AppColor.gold : AppColor.text2,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CancellationSummaryBox extends StatelessWidget {
  const _CancellationSummaryBox({
    super.key,
    required this.title,
    required this.icon,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.input,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppColor.gold),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColor.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          for (final row in rows)
            _CancellationSummaryRow(label: row.$1, value: row.$2),
        ],
      ),
    );
  }
}

class _CancellationSummaryRow extends StatelessWidget {
  const _CancellationSummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColor.text2, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColor.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CancellationWarning extends StatelessWidget {
  const _CancellationWarning({required this.warnings});

  final List<SubscriptionCancellationWarning> warnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('subscription-cancel-warning'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.danger.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: AppColor.warning,
              ),
              SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  'Занятия не удалятся. Покрытие будущих резервов этим '
                  'абонементом будет снято; при завершении применяется '
                  'сохранённое правило списания.',
                  style: TextStyle(color: AppColor.text, fontSize: 12),
                ),
              ),
            ],
          ),
          for (final warning in warnings) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                warning.message,
                style: const TextStyle(color: AppColor.text2, fontSize: 11.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CancellationRetryNotice extends StatelessWidget {
  const _CancellationRetryNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.goldSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.goldLine),
      ),
      child: const Text(
        'Расчёт, причина и ключ операции зафиксированы. Повтор не создаст '
        'вторую отмену.',
        style: TextStyle(color: AppColor.text2, fontSize: 12),
      ),
    );
  }
}

class _CancellationError extends StatelessWidget {
  const _CancellationError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('subscription-cancel-error'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.danger.withValues(alpha: 0.5)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColor.menuDanger, fontSize: 12),
      ),
    );
  }
}

String _formatCancellationMinor(BigInt minor, String currencyCode) {
  final amount = minor.toInt() / 100;
  final formatted = NumberFormat('#,##0.##', 'ru').format(amount);
  final symbol = currencyCode == 'RUB' ? '₽' : currencyCode;
  return '$formatted $symbol';
}
