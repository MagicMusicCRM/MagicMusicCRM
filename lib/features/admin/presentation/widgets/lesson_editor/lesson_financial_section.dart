import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

import '../lesson_decision/lesson_decision_models.dart';
import '../lesson_form_rules.dart';
import 'lesson_editor_feedback.dart';
import 'lesson_editor_models.dart';

class LessonFinancialSectionModel {
  const LessonFinancialSectionModel({
    required this.session,
    required this.draft,
    required this.references,
    required this.isSaving,
    required this.requiresCompensationValue,
    required this.compensationNeedsReason,
    this.allowsNoFunding = false,
  });

  final LessonEditorSession session;
  final LessonEditorDraft draft;
  final LessonEditorReferenceState references;
  final bool isSaving;
  final bool requiresCompensationValue;
  final bool compensationNeedsReason;
  final bool allowsNoFunding;
}

class LessonFinancialSection extends StatelessWidget {
  const LessonFinancialSection({
    required this.model,
    required this.actions,
    super.key,
  });

  final LessonFinancialSectionModel model;
  final LessonEditorActions actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _TrialControl(model: model, actions: actions),
        _CompletionControl(model: model, actions: actions),
        const SizedBox(height: 16),
        _DecisionFields(model: model, actions: actions),
        _CompensationOverride(model: model, actions: actions),
        const SizedBox(height: 16),
        _FundingField(model: model, actions: actions),
        _SubscriptionField(model: model, actions: actions),
      ],
    );
  }
}

class _TrialControl extends StatelessWidget {
  const _TrialControl({required this.model, required this.actions});

  final LessonFinancialSectionModel model;
  final LessonEditorActions actions;

  @override
  Widget build(BuildContext context) {
    final locked = model.session.isEdit;
    return SwitchListTile(
      key: const ValueKey('lesson-trial-toggle'),
      value: model.draft.isTrial,
      activeThumbColor: AppTheme.primaryGold,
      contentPadding: EdgeInsets.zero,
      title: const Text('Пробное занятие'),
      subtitle: Text(
        locked
            ? 'Маркер зафиксирован при создании'
            : 'Не зависит от типа клиента и способа списания',
      ),
      onChanged: locked ? null : actions.selectTrial,
    );
  }
}

class _CompletionControl extends StatelessWidget {
  const _CompletionControl({required this.model, required this.actions});

  final LessonFinancialSectionModel model;
  final LessonEditorActions actions;

  @override
  Widget build(BuildContext context) {
    final draft = model.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 28),
        Text(
          'Результат и расчёты',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (model.session.isEdit)
          InputDecorator(
            key: const ValueKey('lesson-completion-type-field'),
            decoration: const InputDecoration(
              labelText: 'Автозавершение *',
              enabled: false,
              helperText: 'Результат зафиксирован при создании',
            ),
            child: Text(
              draft.completionType == 'standard.success'
                  ? 'Успешно завершить'
                  : draft.completionType,
            ),
          )
        else
          DropdownButtonFormField<String>(
            menuMaxHeight: 256,
            key: const ValueKey('lesson-completion-type-field'),
            initialValue: draft.completionType,
            decoration: const InputDecoration(
              labelText: 'Автозавершение *',
              helperText: 'Результат формируется сервером после окончания',
            ),
            items: const [
              DropdownMenuItem(
                value: 'standard.success',
                child: Text('Успешно завершить'),
              ),
            ],
            onChanged: (value) =>
                actions.selectCompletion(value ?? 'standard.success'),
          ),
      ],
    );
  }
}

class _DecisionFields extends StatelessWidget {
  const _DecisionFields({required this.model, required this.actions});

  final LessonFinancialSectionModel model;
  final LessonEditorActions actions;

  @override
  Widget build(BuildContext context) {
    final draft = model.draft;
    final catalog = model.references.catalog;
    return _ResponsivePair(
      first: DropdownButtonFormField<String>(
        menuMaxHeight: 256,
        key: const ValueKey('lesson-settlement-type-field'),
        initialValue: draft.settlementTypeKey,
        decoration: const InputDecoration(
          labelText: 'Тип списания *',
          helperText: 'Выбирается до назначения занятия',
        ),
        items: [
          for (final item in catalog?.settlementTypes ?? const [])
            DropdownMenuItem(value: item.key, child: Text(item.label)),
        ],
        onChanged: model.session.isEdit ? null : actions.selectSettlement,
      ),
      second: DropdownButtonFormField<String>(
        menuMaxHeight: 256,
        key: const ValueKey('lesson-compensation-rule-field'),
        initialValue: draft.compensationRuleKey,
        decoration: const InputDecoration(
          labelText: 'Правило оплаты преподавателю *',
          helperText: 'Значение можно задать отдельно для этого занятия',
        ),
        items: [
          for (final item in catalog?.compensationRules ?? const [])
            DropdownMenuItem(value: item.key, child: Text(item.label)),
        ],
        onChanged: model.isSaving ? null : actions.selectCompensationRule,
      ),
    );
  }
}

class _CompensationOverride extends StatelessWidget {
  const _CompensationOverride({required this.model, required this.actions});

  final LessonFinancialSectionModel model;
  final LessonEditorActions actions;

  @override
  Widget build(BuildContext context) {
    if (!model.requiresCompensationValue) return const SizedBox.shrink();
    final draft = model.draft;
    final selectedRule = _catalogItem(
      model.references.catalog?.compensationRules,
      draft.compensationRuleKey,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        KeyedSubtree(
          key: ValueKey(
            'lesson-compensation-value-rule-${draft.compensationRuleKey}',
          ),
          child: TextFormField(
            key: const ValueKey('lesson-compensation-value-field'),
            initialValue: formatCompensationMinorInput(
              draft.compensationValueMinor ?? selectedRule?.value,
            ),
            enabled: !model.isSaving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,. ]')),
            ],
            decoration: InputDecoration(
              labelText: _compensationInputLabel(selectedRule?.mode),
              helperText: 'Действует только для этого занятия',
            ),
            onChanged: actions.changeCompensationValue,
          ),
        ),
        if (!model.session.isEdit && model.compensationNeedsReason) ...[
          const SizedBox(height: 16),
          KeyedSubtree(
            key: ValueKey(
              'lesson-compensation-reason-rule-${draft.compensationRuleKey}',
            ),
            child: TextFormField(
              key: const ValueKey('lesson-compensation-override-reason-field'),
              initialValue: draft.plannedSettlementReason,
              enabled: !model.isSaving,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Причина индивидуального значения *',
                helperText: 'Причина сохранится в истории расчёта',
              ),
              onChanged: actions.changePlannedSettlementReason,
            ),
          ),
        ],
      ],
    );
  }
}

class _FundingField extends StatelessWidget {
  const _FundingField({required this.model, required this.actions});

  final LessonFinancialSectionModel model;
  final LessonEditorActions actions;

  @override
  Widget build(BuildContext context) {
    final draft = model.draft;
    final locked = model.session.isEdit;
    final subscriptions = model.references.subscriptions;
    return DropdownButtonFormField<String>(
      menuMaxHeight: 256,
      key: const ValueKey('lesson-charge-type-field'),
      initialValue: draft.clientChargeType,
      decoration: const InputDecoration(
        labelText: 'Источник средств *',
        helperText: 'Сумму и долю определяет выбранный тип списания',
      ),
      items: [
        if (draft.client?.type == 'student' &&
            (subscriptions.isNotEmpty ||
                draft.clientChargeType == 'subscription'))
          const DropdownMenuItem(
            value: 'subscription',
            child: Text('С абонемента'),
          ),
        const DropdownMenuItem(
          value: 'personal_account',
          child: Text('С личного счёта'),
        ),
        if (model.allowsNoFunding ||
            (locked && draft.clientChargeType == 'none'))
          const DropdownMenuItem(value: 'none', child: Text('Без списания')),
      ],
      onChanged: locked
          ? null
          : (value) => actions.selectFunding(value ?? 'none'),
    );
  }
}

class _SubscriptionField extends StatelessWidget {
  const _SubscriptionField({required this.model, required this.actions});

  final LessonFinancialSectionModel model;
  final LessonEditorActions actions;

  @override
  Widget build(BuildContext context) {
    if (model.draft.clientChargeType != 'subscription') {
      return const SizedBox.shrink();
    }
    final subscriptions = model.references.subscriptions;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SearchablePickerField(
        label: 'Абонемент *',
        placeholder: subscriptions.isEmpty
            ? 'Нет активных абонементов'
            : 'Выберите абонемент',
        enabled: !model.session.isEdit && subscriptions.isNotEmpty,
        selectedId: model.draft.subscriptionId,
        items: [
          for (final subscription in subscriptions)
            SearchableSelectItem(
              id: subscription.id,
              label: subscription.label,
            ),
        ],
        onSelected: (item) => actions.selectSubscription(item?.id),
      ),
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

LessonDecisionCatalogItem? _catalogItem(
  List<LessonDecisionCatalogItem>? items,
  String? key,
) {
  for (final item in items ?? const <LessonDecisionCatalogItem>[]) {
    if (item.key == key) return item;
  }
  return null;
}

String _compensationInputLabel(String? mode) => switch (mode) {
  'percent' => 'Процент от стандартной ставки, % *',
  'hourly' => 'Почасовая ставка, ₽ *',
  _ => 'Фиксированная сумма за занятие, ₽ *',
};
