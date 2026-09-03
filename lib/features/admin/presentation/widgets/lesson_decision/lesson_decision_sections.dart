import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/utils/money_format.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

import 'lesson_decision_models.dart';

class LessonDecisionReasonField extends StatelessWidget {
  const LessonDecisionReasonField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: const Key('lesson-decision-reason'),
    controller: controller,
    enabled: enabled,
    minLines: 2,
    maxLines: 4,
    maxLength: 500,
    decoration: const InputDecoration(
      labelText: 'Причина *',
      hintText: 'Что произошло и почему выбран этот расчёт',
      helperText: 'Будет видна сотрудникам в истории действий',
    ),
    validator: (value) =>
        (value ?? '').trim().isEmpty ? 'Укажите причину' : null,
    onChanged: onChanged,
  );
}

class LessonDecisionFormContent extends StatelessWidget {
  const LessonDecisionFormContent({
    required this.formKey,
    required this.operation,
    required this.sourceScheduledAt,
    required this.successorScheduledAt,
    required this.completedSourceScheduledAt,
    required this.completedSuccessorScheduledAt,
    required this.reasonController,
    required this.compensationValueController,
    required this.catalog,
    required this.settlementKey,
    required this.compensationKey,
    required this.compensationRule,
    required this.participants,
    required this.participantNames,
    required this.clientSettlementKeys,
    required this.payerIds,
    required this.payerNames,
    required this.subscriptionIds,
    required this.subscriptions,
    required this.loadingSubscriptions,
    required this.groupLesson,
    required this.completedReschedule,
    required this.canManageTeacherCompensation,
    required this.busy,
    required this.preview,
    required this.error,
    required this.commitAttempted,
    required this.onReasonChanged,
    required this.onSettlementChanged,
    required this.onCompensationChanged,
    required this.onCompensationValueChanged,
    required this.onClientSettlementChanged,
    required this.searchPayers,
    required this.onPayerChanged,
    required this.onSubscriptionChanged,
    required this.compensationValidator,
    required this.onClose,
    required this.onSubmit,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final LessonDecisionOperation operation;
  final Object? sourceScheduledAt;
  final Object? successorScheduledAt;
  final DateTime completedSourceScheduledAt;
  final DateTime completedSuccessorScheduledAt;
  final TextEditingController reasonController;
  final TextEditingController compensationValueController;
  final LessonDecisionCatalog catalog;
  final String? settlementKey;
  final String? compensationKey;
  final LessonDecisionCatalogItem? compensationRule;
  final List<LessonDecisionParticipant> participants;
  final Map<String, String> participantNames;
  final Map<String, String?> clientSettlementKeys;
  final Map<String, String?> payerIds;
  final Map<String, String?> payerNames;
  final Map<String, String?> subscriptionIds;
  final Map<String, List<LessonDecisionSubscription>> subscriptions;
  final Set<String> loadingSubscriptions;
  final bool groupLesson;
  final bool completedReschedule;
  final bool canManageTeacherCompensation;
  final bool busy;
  final LessonDecisionPreview? preview;
  final Object? error;
  final bool commitAttempted;
  final ValueChanged<String> onReasonChanged;
  final ValueChanged<String?> onSettlementChanged;
  final ValueChanged<String?> onCompensationChanged;
  final ValueChanged<String> onCompensationValueChanged;
  final void Function(String clientId, String? settlementKey)
  onClientSettlementChanged;
  final Future<List<LessonDecisionParticipant>> Function(String query)
  searchPayers;
  final void Function(String clientId, LessonDecisionParticipant? payer)
  onPayerChanged;
  final void Function(String clientId, String? subscriptionId)
  onSubscriptionChanged;
  final FormFieldValidator<String> compensationValidator;
  final VoidCallback onClose;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Form(
    key: formKey,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LessonDecisionMoveSummary(
          operation: operation,
          sourceScheduledAt: sourceScheduledAt,
          successorScheduledAt: successorScheduledAt,
        ),
        const SizedBox(height: AppSpace.lg),
        LessonDecisionReasonField(
          controller: reasonController,
          enabled: !busy,
          onChanged: onReasonChanged,
        ),
        const SizedBox(height: AppSpace.md),
        if (completedReschedule)
          LessonDecisionCompletedNotice(
            sourceScheduledAt: completedSourceScheduledAt,
            successorScheduledAt: completedSuccessorScheduledAt,
          )
        else
          LessonDecisionOptionsSection(
            catalog: catalog,
            settlementKey: settlementKey,
            compensationKey: compensationKey,
            participants: participants,
            clientSettlementKeys: clientSettlementKeys,
            payerIds: payerIds,
            payerNames: payerNames,
            subscriptionIds: subscriptionIds,
            subscriptions: subscriptions,
            loadingSubscriptions: loadingSubscriptions,
            groupLesson: groupLesson,
            canManageTeacherCompensation: canManageTeacherCompensation,
            enabled: !busy,
            onSettlementChanged: onSettlementChanged,
            onCompensationChanged: onCompensationChanged,
            onClientSettlementChanged: onClientSettlementChanged,
            searchPayers: searchPayers,
            onPayerChanged: onPayerChanged,
            onSubscriptionChanged: onSubscriptionChanged,
          ),
        if (canManageTeacherCompensation)
          LessonDecisionCompensationSection(
            completedReschedule: completedReschedule,
            rule: compensationRule,
            controller: compensationValueController,
            enabled: !busy,
            validator: compensationValidator,
            onChanged: onCompensationValueChanged,
          ),
        if (preview case final value?) ...[
          const SizedBox(height: AppSpace.lg),
          LessonDecisionPreviewCard(
            preview: value,
            participantNames: participantNames,
          ),
        ],
        if (error case final value?) ...[
          const SizedBox(height: AppSpace.md),
          LessonDecisionError(error: value),
        ],
        const SizedBox(height: AppSpace.xl),
        LessonDecisionActions(
          busy: busy,
          hasPreview: preview != null,
          canConfirm: preview?.canConfirm == true,
          commitAttempted: commitAttempted,
          actionLabel: operation.actionLabel,
          onClose: onClose,
          onSubmit: onSubmit,
        ),
      ],
    ),
  );
}

class LessonDecisionCompensationSection extends StatelessWidget {
  const LessonDecisionCompensationSection({
    required this.completedReschedule,
    required this.rule,
    required this.controller,
    required this.enabled,
    required this.validator,
    required this.onChanged,
    super.key,
  });

  final bool completedReschedule;
  final LessonDecisionCatalogItem? rule;
  final TextEditingController controller;
  final bool enabled;
  final FormFieldValidator<String> validator;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedRule = rule;
    if (completedReschedule ||
        selectedRule == null ||
        selectedRule.mode == 'none' ||
        selectedRule.mode == 'standard') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: LessonDecisionCompensationValueField(
        rule: selectedRule,
        controller: controller,
        enabled: enabled,
        validator: validator,
        onChanged: onChanged,
      ),
    );
  }
}

class LessonDecisionOptionsSection extends StatelessWidget {
  const LessonDecisionOptionsSection({
    required this.catalog,
    required this.settlementKey,
    required this.compensationKey,
    required this.participants,
    required this.clientSettlementKeys,
    required this.payerIds,
    required this.payerNames,
    required this.subscriptionIds,
    required this.subscriptions,
    required this.loadingSubscriptions,
    required this.groupLesson,
    required this.canManageTeacherCompensation,
    required this.enabled,
    required this.onSettlementChanged,
    required this.onCompensationChanged,
    required this.onClientSettlementChanged,
    required this.searchPayers,
    required this.onPayerChanged,
    required this.onSubscriptionChanged,
    super.key,
  });

  final LessonDecisionCatalog catalog;
  final String? settlementKey;
  final String? compensationKey;
  final List<LessonDecisionParticipant> participants;
  final Map<String, String?> clientSettlementKeys;
  final Map<String, String?> payerIds;
  final Map<String, String?> payerNames;
  final Map<String, String?> subscriptionIds;
  final Map<String, List<LessonDecisionSubscription>> subscriptions;
  final Set<String> loadingSubscriptions;
  final bool groupLesson;
  final bool canManageTeacherCompensation;
  final bool enabled;
  final ValueChanged<String?> onSettlementChanged;
  final ValueChanged<String?> onCompensationChanged;
  final void Function(String clientId, String? settlementKey)
  onClientSettlementChanged;
  final Future<List<LessonDecisionParticipant>> Function(String query)
  searchPayers;
  final void Function(String clientId, LessonDecisionParticipant? payer)
  onPayerChanged;
  final void Function(String clientId, String? subscriptionId)
  onSubscriptionChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        menuMaxHeight: 256,
        key: const Key('lesson-decision-settlement'),
        initialValue: settlementKey,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Списание *'),
        items: [
          for (final item in catalog.settlementTypes)
            DropdownMenuItem(
              value: item.key,
              child: LessonDecisionCatalogLabel(item: item),
            ),
        ],
        validator: (value) => value == null ? 'Выберите списание' : null,
        onChanged: enabled ? onSettlementChanged : null,
      ),
      const SizedBox(height: AppSpace.md),
      if (participants.isNotEmpty) ...[
        LessonDecisionClientOverrides(
          participants: participants,
          settlementTypes: catalog.settlementTypes,
          selectedKeys: clientSettlementKeys,
          payerIds: payerIds,
          payerNames: payerNames,
          subscriptionIds: subscriptionIds,
          subscriptions: subscriptions,
          loadingSubscriptions: loadingSubscriptions,
          showSettlementOverrides: groupLesson,
          enabled: enabled,
          onChanged: onClientSettlementChanged,
          searchPayers: searchPayers,
          onPayerChanged: onPayerChanged,
          onSubscriptionChanged: onSubscriptionChanged,
        ),
        const SizedBox(height: AppSpace.md),
      ],
      if (canManageTeacherCompensation)
        DropdownButtonFormField<String>(
          menuMaxHeight: 256,
          key: const Key('lesson-decision-compensation'),
          initialValue: compensationKey,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Оплата преподавателю *',
            helperText: 'Выбирается сотрудником независимо от списания',
          ),
          items: [
            for (final item in catalog.compensationRules)
              DropdownMenuItem(value: item.key, child: Text(item.label)),
          ],
          validator: (value) => value == null ? 'Выберите оплату' : null,
          onChanged: enabled ? onCompensationChanged : null,
        ),
    ],
  );
}

class LessonDecisionCompensationValueField extends StatelessWidget {
  const LessonDecisionCompensationValueField({
    required this.rule,
    required this.controller,
    required this.enabled,
    required this.validator,
    required this.onChanged,
    super.key,
  });

  final LessonDecisionCatalogItem rule;
  final TextEditingController controller;
  final bool enabled;
  final FormFieldValidator<String> validator;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: const Key('lesson-decision-compensation-value'),
    controller: controller,
    enabled: enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,. ]'))],
    decoration: InputDecoration(
      labelText: switch (rule.mode) {
        'percent' => 'Процент ставки *',
        'hourly' => 'Ставка за час, ₽ *',
        _ => 'Сумма, ₽ *',
      },
    ),
    validator: validator,
    onChanged: onChanged,
  );
}

const _commonSettlementOverride = '__common_settlement__';

class LessonDecisionClientOverrides extends StatelessWidget {
  const LessonDecisionClientOverrides({
    required this.participants,
    required this.settlementTypes,
    required this.selectedKeys,
    required this.payerIds,
    required this.payerNames,
    required this.subscriptionIds,
    required this.subscriptions,
    required this.loadingSubscriptions,
    required this.showSettlementOverrides,
    required this.enabled,
    required this.onChanged,
    required this.searchPayers,
    required this.onPayerChanged,
    required this.onSubscriptionChanged,
    super.key,
  });

  final List<LessonDecisionParticipant> participants;
  final List<LessonDecisionCatalogItem> settlementTypes;
  final Map<String, String?> selectedKeys;
  final Map<String, String?> payerIds;
  final Map<String, String?> payerNames;
  final Map<String, String?> subscriptionIds;
  final Map<String, List<LessonDecisionSubscription>> subscriptions;
  final Set<String> loadingSubscriptions;
  final bool showSettlementOverrides;
  final bool enabled;
  final void Function(String clientId, String? settlementKey) onChanged;
  final Future<List<LessonDecisionParticipant>> Function(String query)
  searchPayers;
  final void Function(String clientId, LessonDecisionParticipant? payer)
  onPayerChanged;
  final void Function(String clientId, String? subscriptionId)
  onSubscriptionChanged;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('lesson-decision-client-overrides'),
    padding: const EdgeInsets.all(AppSpace.md),
    decoration: BoxDecoration(
      color: AppColor.input,
      border: Border.all(color: AppColor.divider),
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          showSettlementOverrides
              ? 'Индивидуальные условия участников'
              : 'Оплата занятия',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          showSettlementOverrides
              ? 'Для каждого ученика можно изменить списание или плательщика.'
              : 'Если платит другой ученик, выберите его абонемент.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        for (var index = 0; index < participants.length; index++) ...[
          if (showSettlementOverrides) ...[
            DropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: Key('lesson-decision-client-${participants[index].id}'),
              initialValue:
                  selectedKeys[participants[index].id] ??
                  _commonSettlementOverride,
              isExpanded: true,
              decoration: InputDecoration(labelText: participants[index].name),
              items: [
                const DropdownMenuItem(
                  value: _commonSettlementOverride,
                  child: Text('Как у всей группы'),
                ),
                for (final item in settlementTypes)
                  DropdownMenuItem(
                    value: item.key,
                    child: LessonDecisionCatalogLabel(item: item),
                  ),
              ],
              onChanged: !enabled
                  ? null
                  : (value) => onChanged(
                      participants[index].id,
                      value == _commonSettlementOverride ? null : value,
                    ),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          SearchablePickerField(
            key: Key('lesson-decision-payer-${participants[index].id}'),
            label: showSettlementOverrides
                ? 'Плательщик для ${participants[index].name}'
                : 'Плательщик',
            placeholder: 'По плану ученика',
            hintText: 'Найдите ученика по имени',
            selectedId: payerIds[participants[index].id],
            selectedLabel: payerNames[participants[index].id],
            items: const [],
            enabled: enabled,
            onSearch: (query) async => [
              for (final payer in await searchPayers(query))
                if (payer.id != participants[index].id)
                  SearchableSelectItem(id: payer.id, label: payer.name),
            ],
            onSelected: (item) => onPayerChanged(
              participants[index].id,
              item == null
                  ? null
                  : LessonDecisionParticipant(id: item.id, name: item.label),
            ),
          ),
          if (payerIds[participants[index].id] != null) ...[
            const SizedBox(height: AppSpace.sm),
            DropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: Key(
                'lesson-decision-subscription-${participants[index].id}',
              ),
              initialValue: subscriptionIds[participants[index].id],
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Абонемент',
                suffixIcon:
                    loadingSubscriptions.contains(participants[index].id)
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpace.sm),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              items: [
                for (final subscription
                    in subscriptions[participants[index].id] ?? const [])
                  DropdownMenuItem(
                    value: subscription.id,
                    child: Text(subscription.label),
                  ),
              ],
              validator: (value) {
                if (value != null) return null;
                return loadingSubscriptions.contains(participants[index].id)
                    ? 'Дождитесь загрузки'
                    : (subscriptions[participants[index].id]?.isEmpty ?? true)
                    ? 'Нет доступного абонемента'
                    : 'Выберите абонемент';
              },
              onChanged:
                  !enabled ||
                      loadingSubscriptions.contains(participants[index].id)
                  ? null
                  : (value) =>
                        onSubscriptionChanged(participants[index].id, value),
            ),
          ],
          if (index != participants.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.md),
              child: Divider(height: 1),
            ),
        ],
      ],
    ),
  );
}

class LessonDecisionMoveSummary extends StatelessWidget {
  const LessonDecisionMoveSummary({
    required this.operation,
    required this.sourceScheduledAt,
    required this.successorScheduledAt,
    super.key,
  });

  final LessonDecisionOperation operation;
  final Object? sourceScheduledAt;
  final Object? successorScheduledAt;

  @override
  Widget build(BuildContext context) {
    final source = _lessonTime(sourceScheduledAt);
    final successor = _lessonTime(successorScheduledAt);
    return Container(
      key: const Key('lesson-decision-summary'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.input,
        border: Border.all(color: AppColor.divider),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Изменение применяется только после подтверждения',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpace.xs),
          Text('Сейчас: $source'),
          if (operation == LessonDecisionOperation.reschedule)
            Text('Будет: $successor'),
        ],
      ),
    );
  }
}

class LessonDecisionCompletedNotice extends StatelessWidget {
  const LessonDecisionCompletedNotice({
    required this.sourceScheduledAt,
    required this.successorScheduledAt,
    super.key,
  });

  final DateTime sourceScheduledAt;
  final DateTime successorScheduledAt;

  @override
  Widget build(BuildContext context) {
    final source = _formatLessonTime(sourceScheduledAt);
    final successor = _formatLessonTime(successorScheduledAt);
    return Tooltip(
      key: const Key('lesson-decision-completed-notice'),
      message: '$source → $successor',
      child: Container(
        key: const Key('completed-reschedule-notice'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.sm,
        ),
        decoration: BoxDecoration(
          color: AppColor.warning.withValues(alpha: 0.12),
          border: Border.all(color: AppColor.warning),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.history_rounded, color: AppColor.warning),
            const SizedBox(width: AppSpace.sm),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Это занятие уже завершено. Прежний расчёт будет отменён без удаления истории, а новое занятие сохранит исходный план и рассчитает его после завершения.',
                  ),
                  Text(
                    'Текущее занятие: бесплатное; оплата преподавателю отменяется.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LessonDecisionCatalogLabel extends StatelessWidget {
  const LessonDecisionCatalogLabel({required this.item, super.key});

  final LessonDecisionCatalogItem item;

  @override
  Widget build(BuildContext context) {
    final color = lessonDecisionColorToken(item.colorToken);
    return Row(
      children: [
        Icon(Icons.sell_outlined, size: 17, color: color),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text(item.label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class LessonDecisionPreviewCard extends StatelessWidget {
  const LessonDecisionPreviewCard({
    required this.preview,
    required this.participantNames,
    super.key,
  });

  final LessonDecisionPreview preview;
  final Map<String, String> participantNames;

  @override
  Widget build(BuildContext context) {
    final clientFacts = _maps(preview.financial['clientFacts']);
    final teacherFact = _map(preview.financial['teacherFact']);
    return Container(
      key: const Key('lesson-decision-preview'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: preview.canConfirm
            ? AppColor.success.withValues(alpha: 0.14)
            : AppColor.dangerSoft,
        border: Border.all(
          color: preview.canConfirm ? AppColor.success : AppColor.danger,
        ),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                preview.canConfirm
                    ? Icons.check_circle_outline_rounded
                    : Icons.block_rounded,
                color: preview.canConfirm ? AppColor.success : AppColor.danger,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  preview.canConfirm
                      ? 'Изменение готово к подтверждению'
                      : 'Изменение заблокировано',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          for (final violation in preview.violations) ...[
            const SizedBox(height: AppSpace.sm),
            Text('• ${_violationLabel(violation)}'),
          ],
          for (final fact in clientFacts) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              '${participantNames[fact['clientId']?.toString() ?? fact['client_id']?.toString()] ?? 'Клиент'}: '
              '${fact['settlementLabel'] ?? fact['settlementTypeKey'] ?? 'Не указано'} · '
              '${fact['units'] ?? '0'} ч · ${_formatMinor(fact['amountMinor'])}',
            ),
          ],
          if (teacherFact.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              'Преподаватель: ${teacherFact['compensationRuleLabel'] ?? teacherFact['compensationRuleKey'] ?? 'Не указано'} · '
              '${_formatMinor(teacherFact['amountMinor'])}',
            ),
          ],
          for (final warning in preview.warnings) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: AppColor.warning,
                ),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(_warningLabel(warning))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class LessonDecisionError extends StatelessWidget {
  const LessonDecisionError({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('lesson-decision-error'),
    padding: const EdgeInsets.all(AppSpace.md),
    decoration: BoxDecoration(
      color: AppColor.dangerSoft,
      border: Border.all(color: AppColor.danger),
      borderRadius: BorderRadius.circular(AppRadius.control),
    ),
    child: Text(
      userErrorMessage(error, fallback: 'Не удалось обновить расчёт.'),
    ),
  );
}

class LessonDecisionLoadError extends StatelessWidget {
  const LessonDecisionLoadError({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LessonDecisionError(error: error ?? 'Каталог недоступен'),
      const SizedBox(height: AppSpace.md),
      FilledButton(onPressed: onRetry, child: const Text('Повторить')),
    ],
  );
}

class LessonDecisionActions extends StatelessWidget {
  const LessonDecisionActions({
    required this.busy,
    required this.hasPreview,
    required this.canConfirm,
    required this.commitAttempted,
    required this.actionLabel,
    required this.onClose,
    required this.onSubmit,
    super.key,
  });

  final bool busy;
  final bool hasPreview;
  final bool canConfirm;
  final bool commitAttempted;
  final String actionLabel;
  final VoidCallback onClose;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: OutlinedButton(
          onPressed: busy ? null : onClose,
          child: const Text('Закрыть'),
        ),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: FilledButton(
          key: const Key('lesson-decision-submit'),
          onPressed: busy ? null : onSubmit,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_submitLabel()),
        ),
      ),
    ],
  );

  String _submitLabel() {
    if (canConfirm) return commitAttempted ? 'Повторить' : actionLabel;
    return hasPreview ? 'Повторить расчёт' : 'Рассчитать';
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? value) => [
  for (final item in value as List? ?? const [])
    if (item is Map) Map<String, dynamic>.from(item),
];

String _lessonTime(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? 'Не указано' : _formatLessonTime(date);
}

String _formatLessonTime(DateTime value) =>
    DateFormat('dd.MM.yyyy HH:mm', 'ru').format(value.toLocal());

String _formatMinor(Object? value) {
  final minor = BigInt.tryParse(value?.toString() ?? '') ?? BigInt.zero;
  return formatPaymentMinor(minor);
}

String _warningLabel(String value) => switch (value) {
  'COMPLETED_LESSON_EFFECTS_WILL_BE_REVERSED' =>
    'Прежние списание и оплата преподавателю будут отменены без удаления истории. Новое занятие рассчитается отдельно после завершения.',
  'SUCCESSOR_MAY_CHARGE_AGAIN' =>
    'Перенос завершает текущее занятие. Новое занятие может создать отдельное списание.',
  _ => value,
};

String _violationLabel(Map<String, dynamic> value) => switch (value['code']
    ?.toString()) {
  'TEACHER_OVERLAP' => 'У преподавателя уже есть занятие в это время',
  'CLIENT_OVERLAP' => 'У клиента уже есть занятие в это время',
  'ROOM_OVERLAP' => 'Аудитория уже занята',
  'TEACHER_UNAVAILABLE' => 'Преподаватель недоступен',
  'TEACHER_BRANCH_MISMATCH' => 'Преподаватель не назначен в выбранный филиал',
  'ROOM_BRANCH_MISMATCH' => 'Аудитория относится к другому филиалу',
  'OUTSIDE_BRANCH_HOURS' => 'Филиал закрыт в это время',
  'INVALID_INTERVAL' => 'Некорректное время занятия',
  final code? => code,
  _ => 'Ограничение расписания',
};
