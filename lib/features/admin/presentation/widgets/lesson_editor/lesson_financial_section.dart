import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import '../lesson_decision/lesson_decision_models.dart';
import '../lesson_decision/lesson_decision_sections.dart';
import '../lesson_form_rules.dart';
import 'lesson_client_funding_fields.dart';
import 'lesson_editor_feedback.dart';
import 'lesson_editor_models.dart';
import 'lesson_financial_autofill.dart';

class LessonFinancialSectionModel {
  const LessonFinancialSectionModel({
    required this.session,
    required this.draft,
    required this.references,
    required this.isSaving,
    required this.requiresCompensationValue,
    required this.compensationNeedsReason,
    required this.canManageTeacherCompensation,
    this.allowsNoFunding = false,
  });

  final LessonEditorSession session;
  final LessonEditorDraft draft;
  final LessonEditorReferenceState references;
  final bool isSaving;
  final bool requiresCompensationValue;
  final bool compensationNeedsReason;
  final bool canManageTeacherCompensation;
  final bool allowsNoFunding;
}

class LessonFinancialSection extends StatelessWidget {
  const LessonFinancialSection({
    required this.model,
    required this.actions,
    this.fundingFields,
    this.funding,
    this.knownPayers = const [],
    this.financialPreview,
    super.key,
  });

  final LessonFinancialSectionModel model;
  final LessonEditorActions actions;
  final Widget? fundingFields;
  final LessonDecisionFormLifecycle? funding;
  final List<LessonDecisionParticipant> knownPayers;
  final LessonDecisionPreview? financialPreview;

  Widget? _fundingFields() {
    final controller = funding;
    final client = model.draft.client;
    if (controller == null || client == null) return null;
    return LessonClientFundingFields(
      key: ValueKey('lesson-funding-${client.key}'),
      participants: model.session.isGroupEdit
          ? controller.groupParticipants
          : [
              LessonDecisionParticipant(
                id: client.id,
                name: client.label,
                isStudent: client.type == 'student',
              ),
            ],
      decisions: model.draft.clientDecisions,
      enabled: !model.isSaving,
      allowsNoFunding: model.allowsNoFunding,
      searchPayers: controller.searchPayers,
      loadSubscriptions: controller.loadSubscriptions,
      subscriptionsByPayer: _subscriptionCache(client),
      knownPayers: knownPayers,
      onChanged: (value) => actions.edit(LessonClientDecisionsEdit(value)),
    );
  }

  List<LessonDecisionParticipant> _participants() {
    final client = model.draft.client;
    if (client == null) return const [];
    if (model.session.isGroupEdit) {
      return funding?.groupParticipants ?? const [];
    }
    return [
      LessonDecisionParticipant(
        id: client.id,
        name: client.label,
        isStudent: client.type == 'student',
      ),
    ];
  }

  Map<String, List<LessonDecisionSubscription>> _subscriptionCache(
    LessonClientRef client,
  ) {
    if (client.type != 'student') return const {};
    final current = model.draft.clientDecisions
        .where((row) => row['clientId'] == client.id)
        .firstOrNull;
    final selected = current?['subscriptionId'] ?? model.draft.subscriptionId;
    final items = model.references.subscriptions;
    // A missing historical selection must be resolved by the funding loader.
    if (selected != null && !items.any((item) => item.id == selected)) {
      return const {};
    }
    return {
      client.id: [
        for (final item in items)
          if (item.id == selected ||
              (num.tryParse(
                        (item.raw['lessons_remaining'] ??
                                    item.raw['lessonsRemaining'])
                                ?.toString() ??
                            '',
                      ) ??
                      0) >
                  0)
            LessonDecisionSubscription(id: item.id, label: item.label),
      ],
    };
  }

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
        if (model.canManageTeacherCompensation)
          _CompensationOverride(model: model, actions: actions),
        const SizedBox(height: 16),
        ?fundingFields ?? _fundingFields(),
        _PartialDurationControls(
          model: model,
          participants: _participants(),
          actions: actions,
        ),
        if (model.session.isEdit) ...[
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('lesson-edit-reason'),
            initialValue: model.draft.plannedSettlementReason,
            enabled: !model.isSaving,
            minLines: 2,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Причина изменения *',
              helperText: 'Сохранится в истории занятия',
            ),
            onChanged: (value) => actions.edit(
              LessonTextEdit(LessonTextTarget.settlementReason, value),
            ),
          ),
        ],
        if (financialPreview case final preview?)
          LessonDecisionPreviewCard(
            preview: preview,
            participantNames: funding?.participantNames ?? const {},
          ),
      ],
    );
  }
}

class _PartialDurationControls extends StatelessWidget {
  const _PartialDurationControls({
    required this.model,
    required this.participants,
    required this.actions,
  });

  final LessonFinancialSectionModel model;
  final List<LessonDecisionParticipant> participants;
  final LessonEditorActions actions;

  @override
  Widget build(BuildContext context) {
    final draft = model.draft;
    final catalog = model.references.catalog;
    final commonSettlement = _catalogItem(
      catalog?.settlementTypes,
      draft.settlementTypeKey,
    );
    final teacherManual =
        model.canManageTeacherCompensation &&
        commonSettlement?.teacherDurationMode == 'manual';
    final clientFields = <Widget>[];
    for (final participant in participants) {
      final decision = draft.clientDecisions
          .where((row) => row['clientId'] == participant.id)
          .firstOrNull;
      final settlement = _catalogItem(
        catalog?.settlementTypes,
        decision?['settlementTypeKey']?.toString() ?? draft.settlementTypeKey,
      );
      if (settlement?.clientDurationMode != 'manual') continue;
      final minutes = lessonDecisionIntegerMinutes(
        decision?['chargeDurationMinutes'],
      );
      clientFields.add(
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: KeyedSubtree(
            key: ValueKey(
              'lesson-client-duration-model-${participant.id}-'
              '${settlement?.key}-${draft.recommendationRevision}',
            ),
            child: TextFormField(
              key: ValueKey('lesson-client-duration-${participant.id}'),
              initialValue: minutes?.toString() ?? '',
              enabled: !model.isSaving,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: participants.length > 1
                    ? 'Списать с клиента ${participant.name}, мин *'
                    : 'Списать с клиента, мин *',
                helperText: minutes == null
                    ? 'Укажите от 0 до ${draft.durationMinutes} мин'
                    : formatLessonMinutes(minutes),
              ),
              validator: (value) => partialDurationError(
                value,
                lessonDurationMinutes: draft.durationMinutes,
              ),
              onChanged: (value) => actions.edit(
                LessonClientDurationEdit(participant.id, int.tryParse(value)),
              ),
            ),
          ),
        ),
      );
    }
    if (clientFields.isEmpty && !teacherManual && !draft.compensationTouched) {
      return const SizedBox.shrink();
    }
    final teacherMinutes = draft.teacherCreditedDurationMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...clientFields,
        if (teacherManual) ...[
          const SizedBox(height: 16),
          KeyedSubtree(
            key: ValueKey(
              'teacher-duration-model-${commonSettlement?.key}-'
              '${draft.recommendationRevision}',
            ),
            child: TextFormField(
              key: const ValueKey('teacher-credited-duration-minutes'),
              initialValue: teacherMinutes?.toString() ?? '',
              enabled: !model.isSaving,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Засчитать преподавателю, мин *',
                helperText: teacherMinutes == null
                    ? 'Укажите от 0 до ${draft.durationMinutes} мин'
                    : formatLessonMinutes(teacherMinutes),
              ),
              validator: (value) => partialDurationError(
                value,
                lessonDurationMinutes: draft.durationMinutes,
              ),
              onChanged: (value) =>
                  actions.edit(LessonTeacherDurationEdit(int.tryParse(value))),
            ),
          ),
        ],
        if (draft.compensationTouched) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('lesson-restore-financial-recommendation'),
              onPressed: model.isSaving
                  ? null
                  : () => actions.edit(const LessonRestoreRecommendationEdit()),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Применить рекомендуемое правило'),
            ),
          ),
        ],
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
      onChanged: locked
          ? null
          : (value) => actions.edit(LessonTrialEdit(value)),
    );
  }
}

class _CompletionControl extends StatelessWidget {
  const _CompletionControl({required this.model, required this.actions});

  final LessonFinancialSectionModel model;
  final LessonEditorActions actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 28),
        Text(
          'Результат и расчёты',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        const InputDecorator(
          key: ValueKey('lesson-completion-type-field'),
          decoration: InputDecoration(
            labelText: 'Завершение',
            helperText: 'Занятие завершается автоматически после окончания',
          ),
          child: Text('Автозавершение'),
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
    final settlement = DropdownButtonFormField<String>(
      menuMaxHeight: 256,
      isExpanded: true,
      key: const ValueKey('lesson-settlement-type-field'),
      initialValue: draft.settlementTypeKey,
      decoration: const InputDecoration(
        labelText: 'Тип списания *',
        helperText: 'Изменение сохраняется после проверки расчёта',
      ),
      items: [
        for (final item in catalog?.settlementTypes ?? const [])
          DropdownMenuItem(
            value: item.key,
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: model.session.isEdit && model.isSaving
          ? null
          : (value) => actions.edit(
              LessonReferenceEdit(LessonReferenceTarget.settlement, value),
            ),
    );
    if (!model.canManageTeacherCompensation) return settlement;
    return _ResponsivePair(
      first: settlement,
      second: DropdownButtonFormField<String>(
        menuMaxHeight: 256,
        isExpanded: true,
        key: const ValueKey('lesson-compensation-rule-field'),
        initialValue: draft.compensationRuleKey,
        decoration: const InputDecoration(
          labelText: 'Правило оплаты преподавателю *',
          helperText: 'Значение можно задать отдельно для этого занятия',
        ),
        items: [
          for (final item in catalog?.compensationRules ?? const [])
            DropdownMenuItem(
              value: item.key,
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: model.isSaving
            ? null
            : (value) => actions.edit(
                LessonReferenceEdit(
                  LessonReferenceTarget.compensationRule,
                  value,
                ),
              ),
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
            onChanged: (value) => actions.edit(
              LessonTextEdit(LessonTextTarget.compensationValue, value),
            ),
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
              onChanged: (value) => actions.edit(
                LessonTextEdit(LessonTextTarget.settlementReason, value),
              ),
            ),
          ),
        ],
      ],
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
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 520 * textScale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 12), second],
          );
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
