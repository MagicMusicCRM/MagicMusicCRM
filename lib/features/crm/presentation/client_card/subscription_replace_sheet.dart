import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/subscription.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

import 'client_card_ui.dart';

class SubscriptionReplacementConfirmation {
  const SubscriptionReplacementConfirmation({
    required this.input,
    required this.identity,
  });

  final ReplaceSubscriptionInput input;
  final MagicMutationIdentity identity;
}

typedef SubscriptionReplacementConfirm =
    Future<void> Function(SubscriptionReplacementConfirmation confirmation);

Future<bool?> showSubscriptionReplacementSheet(
  BuildContext context, {
  required Subscription oldSubscription,
  required SubscriptionReplacementPreview preview,
  required SubscriptionReplacementConfirm onConfirm,
}) {
  return showMagicSheet<bool>(
    context,
    title: 'Подтвердите замену',
    subtitle: 'Проверьте использование, будущие занятия и новый расчёт',
    icon: Icons.swap_horiz_rounded,
    builder: (_) => SubscriptionReplacementForm(
      oldSubscription: oldSubscription,
      preview: preview,
      onConfirm: onConfirm,
    ),
  );
}

class SubscriptionReplacementForm extends StatefulWidget {
  const SubscriptionReplacementForm({
    super.key,
    required this.oldSubscription,
    required this.preview,
    required this.onConfirm,
  });

  final Subscription oldSubscription;
  final SubscriptionReplacementPreview preview;
  final SubscriptionReplacementConfirm onConfirm;

  @override
  State<SubscriptionReplacementForm> createState() =>
      _SubscriptionReplacementFormState();
}

class _SubscriptionReplacementFormState
    extends State<SubscriptionReplacementForm> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController(
    text: 'client.requested_change',
  );
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
    _identity = MagicMutationIdentity.create('subscription-replace');
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
    if (value.isEmpty) return 'Выберите причину';
    if (value.length > 120 || !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
      return 'Выберите причину из списка';
    }
    return null;
  }

  Future<bool> _submit({bool closeOnSuccess = true}) async {
    if (_busy) return false;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return false;
    if (!_confirmed) {
      setState(() => _error = 'Подтвердите последствия замены.');
      return false;
    }

    final confirmation = SubscriptionReplacementConfirmation(
      input: ReplaceSubscriptionInput(
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
        _error = userErrorMessage(
          error,
          fallback: 'Не удалось заменить абонемент.',
        );
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
            _PackageComparison(
              oldSubscription: widget.oldSubscription,
              preview: preview,
            ),
            const SizedBox(height: AppSpace.md),
            _UsageSummary(usage: preview.usage),
            const SizedBox(height: AppSpace.md),
            _FinancialSummary(financial: preview.financial),
            if (preview.warnings.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              _Warnings(warnings: preview.warnings),
            ],
            const SizedBox(height: AppSpace.md),
            Text(
              'Расчёт действителен до '
              '${DateFormat('dd.MM.yyyy HH:mm').format(preview.expiresAt.toLocal())}',
              style: const TextStyle(color: AppColor.text2, fontSize: 11.5),
            ),
            const SizedBox(height: AppSpace.lg),
            DropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: const Key('subscription-replace-reason'),
              initialValue: _reasonController.text,
              isExpanded: true,
              decoration: clientCardInputDecoration(
                Theme.of(context).colorScheme,
                label: 'Причина замены',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'client.requested_change',
                  child: Text('По просьбе клиента'),
                ),
                DropdownMenuItem(
                  value: 'package.incorrect',
                  child: Text('Исправление пакета'),
                ),
                DropdownMenuItem(
                  value: 'terms.changed',
                  child: Text('Изменение условий'),
                ),
              ],
              validator: _validateReason,
              onChanged: _fieldsEnabled
                  ? (value) {
                      if (value != null) _reasonController.text = value;
                      if (_error != null) setState(() => _error = null);
                    }
                  : null,
            ),
            const SizedBox(height: AppSpace.sm),
            Container(
              decoration: BoxDecoration(
                color: AppColor.input,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(
                  color: _confirmed ? AppColor.goldLine : AppColor.divider,
                ),
              ),
              child: CheckboxListTile(
                key: const Key('subscription-replace-confirmation'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                ),
                value: _confirmed,
                enabled: _fieldsEnabled,
                activeColor: AppColor.gold,
                checkColor: AppColor.onGold,
                title: const Text(
                  'Подтверждаю замену',
                  style: TextStyle(
                    color: AppColor.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: const Text(
                  'Старый абонемент закроется, использованные часы и резервы '
                  'перейдут в новый; фактические оплаты не изменятся.',
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
              const _StableRetryNotice(),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpace.md),
              _ReplaceError(message: _error!),
            ],
            const SizedBox(height: AppSpace.xl),
            Row(
              children: [
                Expanded(
                  child: clientCardGhostButton(
                    'Отмена',
                    _busy ? null : _requestClose,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: FilledButton(
                    key: const Key('subscription-replace-submit'),
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColor.gold,
                      foregroundColor: AppColor.onGold,
                      disabledBackgroundColor: AppColor.goldSoft,
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
                              color: AppColor.onGold,
                            ),
                          )
                        : Text(_attempted ? 'Повторить' : 'Заменить'),
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

class _PackageComparison extends StatelessWidget {
  const _PackageComparison({
    required this.oldSubscription,
    required this.preview,
  });

  final Subscription oldSubscription;
  final SubscriptionReplacementPreview preview;

  @override
  Widget build(BuildContext context) {
    final oldCard = _PackageCard(
      key: const Key('subscription-replace-old'),
      eyebrow: 'Старый',
      name: oldSubscription.packageName ?? 'Текущий абонемент',
      units: oldSubscription.lessonsTotal.toString(),
      amountMinor: preview.financial.oldFinalMinor,
      currencyCode: preview.financial.currencyCode,
    );
    final newCard = _PackageCard(
      key: const Key('subscription-replace-new'),
      eyebrow: 'Новый',
      name: preview.newPackage.name,
      units: preview.newPackage.unitCount.toString(),
      amountMinor: preview.financial.newFinalMinor,
      currencyCode: preview.financial.currencyCode,
      highlighted: true,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              oldCard,
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: Icon(Icons.arrow_downward_rounded, color: AppColor.gold),
              ),
              newCard,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: oldCard),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.sm),
              child: Icon(Icons.arrow_forward_rounded, color: AppColor.gold),
            ),
            Expanded(child: newCard),
          ],
        );
      },
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    super.key,
    required this.eyebrow,
    required this.name,
    required this.units,
    required this.amountMinor,
    required this.currencyCode,
    this.highlighted = false,
  });

  final String eyebrow;
  final String name;
  final String units;
  final BigInt amountMinor;
  final String currencyCode;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: highlighted ? AppColor.goldSoft : AppColor.input,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: highlighted ? AppColor.goldLine : AppColor.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: TextStyle(
              color: highlighted ? AppColor.gold : AppColor.text2,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColor.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            '$units ч · ${_formatReplacementMinor(amountMinor, currencyCode)}',
            style: const TextStyle(color: AppColor.text2, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _UsageSummary extends StatelessWidget {
  const _UsageSummary({required this.usage});

  final SubscriptionReplacementUsage usage;

  @override
  Widget build(BuildContext context) {
    return _SummaryBox(
      key: const Key('subscription-replace-usage'),
      title: 'Использование и будущие занятия',
      icon: Icons.schedule_rounded,
      rows: [
        ('Использовано', '${usage.usedUnits} ч'),
        (
          'Будущие занятия',
          '${usage.futureLessonCount} · ${usage.futureUnits} ч',
        ),
        (
          'Резервы перейдут',
          '${usage.transferableReservationCount} · '
              '${usage.transferableReservationUnits} ч',
        ),
        if (usage.releasedReservationCount > 0)
          (
            'Резервы освободятся',
            '${usage.releasedReservationCount} · '
                '${usage.releasedReservationUnits} ч',
          ),
      ],
    );
  }
}

class _FinancialSummary extends StatelessWidget {
  const _FinancialSummary({required this.financial});

  final SubscriptionReplacementFinancial financial;

  @override
  Widget build(BuildContext context) {
    final position = financial.resultingPosition;
    final (positionLabel, positionColor) = switch (position.kind) {
      SubscriptionFinancialPositionKind.debt => (
        'Долг после замены',
        AppColor.danger,
      ),
      SubscriptionFinancialPositionKind.overpayment => (
        'Переплата после замены',
        AppColor.success,
      ),
      SubscriptionFinancialPositionKind.settled => (
        'После замены',
        AppColor.success,
      ),
    };
    final positionValue =
        position.kind == SubscriptionFinancialPositionKind.settled
        ? 'Расчёт закрыт'
        : _formatReplacementMinor(position.amountMinor, financial.currencyCode);
    final deltaPrefix = financial.obligationDeltaMinor > BigInt.zero ? '+' : '';

    return _SummaryBox(
      key: const Key('subscription-replace-financial'),
      title: 'Финансовый результат',
      icon: Icons.account_balance_wallet_outlined,
      rows: [
        (
          'Фактически оплачено',
          _formatReplacementMinor(
            financial.actualPaidMinor,
            financial.currencyCode,
          ),
        ),
        (
          'Изменение стоимости',
          '$deltaPrefix${_formatReplacementMinor(financial.obligationDeltaMinor, financial.currencyCode)}',
        ),
        (positionLabel, positionValue),
      ],
      lastValueColor: positionColor,
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({
    super.key,
    required this.title,
    required this.icon,
    required this.rows,
    this.lastValueColor,
  });

  final String title;
  final IconData icon;
  final List<(String, String)> rows;
  final Color? lastValueColor;

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
          for (var index = 0; index < rows.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[index].$1,
                      style: const TextStyle(
                        color: AppColor.text2,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    rows[index].$2,
                    style: TextStyle(
                      color: index == rows.length - 1 && lastValueColor != null
                          ? lastValueColor
                          : AppColor.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Warnings extends StatelessWidget {
  const _Warnings({required this.warnings});

  final List<SubscriptionReplacementWarning> warnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('subscription-replace-warnings'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.goldSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.goldLine),
      ),
      child: Column(
        children: [
          for (var index = 0; index < warnings.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == warnings.length - 1 ? 0 : AppSpace.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: AppColor.warning,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      warnings[index].message,
                      style: const TextStyle(
                        color: AppColor.text2,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StableRetryNotice extends StatelessWidget {
  const _StableRetryNotice();

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
        'вторую замену.',
        style: TextStyle(color: AppColor.text2, fontSize: 12),
      ),
    );
  }
}

class _ReplaceError extends StatelessWidget {
  const _ReplaceError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('subscription-replace-error'),
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

String _formatReplacementMinor(BigInt minor, String currencyCode) {
  final amount = minor.toInt() / 100;
  final formatted = NumberFormat('#,##0.##', 'ru').format(amount);
  final symbol = currencyCode == 'RUB' ? '₽' : currencyCode;
  return '$formatted $symbol';
}
