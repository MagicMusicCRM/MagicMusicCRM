import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_controller.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';

export 'lesson_decision/lesson_decision_controller.dart';
export 'lesson_decision/lesson_decision_models.dart';

Future<bool?> showLessonDecisionFlow(
  BuildContext context, {
  required MagicCrmService crm,
  required LessonDecisionOperation operation,
  required Map<String, dynamic> lesson,
  Map<String, dynamic>? successor,
  String? initialSettlementTypeKey,
  String? initialCompensationRuleKey,
  String? initialCompensationValueMinor,
}) {
  final controller = LessonDecisionController(
    crm: crm,
    operation: operation,
    lesson: lesson,
    successor: successor,
    initialSettlementTypeKey: initialSettlementTypeKey,
    initialCompensationRuleKey: initialCompensationRuleKey,
    initialCompensationValueMinor: initialCompensationValueMinor,
  );
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.quickView,
    title: operation.title,
    subtitle: 'Сначала расчёт, затем подтверждение',
    icon: Icons.rule_rounded,
    builder: (_) => LessonDecisionForm(controller: controller),
  );
}

class LessonDecisionForm extends StatefulWidget {
  const LessonDecisionForm({super.key, required this.controller});

  final LessonDecisionController controller;

  @override
  State<LessonDecisionForm> createState() => _LessonDecisionFormState();
}

class _LessonDecisionFormState extends State<LessonDecisionForm> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _compensationValueController = TextEditingController();
  final Map<String, String?> _clientSettlementKeys = {};

  LessonDecisionCatalog? _catalog;
  LessonDecisionPreview? _preview;
  String? _settlementKey;
  String? _compensationKey;
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  bool _commitAttempted = false;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _compensationValueController.dispose();
    super.dispose();
  }

  LessonDecisionCatalogItem? get _compensationRule {
    final key = _compensationKey;
    if (key == null) return null;
    for (final rule in _catalog?.compensationRules ?? const []) {
      if (rule.key == key) return rule;
    }
    return null;
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await widget.controller.loadCatalog();
      final completedReschedule = widget.controller.isCompletedReschedule;
      final reversalSettlement = completedReschedule
          ? _catalogItem(catalog.settlementTypes, 'free_lesson')
          : null;
      final reversalCompensation = completedReschedule
          ? _catalogItem(catalog.compensationRules, 'none')
          : null;
      if (completedReschedule &&
          (reversalSettlement == null || reversalCompensation == null)) {
        throw StateError(
          'Не удалось подготовить безопасную отмену расчёта. Обновите настройки занятия.',
        );
      }
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        if (completedReschedule) {
          _settlementKey = reversalSettlement!.key;
          _compensationKey = reversalCompensation!.key;
        } else {
          _settlementKey = _catalogItem(
            catalog.settlementTypes,
            widget.controller.initialSettlementTypeKey ?? '',
          )?.key;
          final compensation = _catalogItem(
            catalog.compensationRules,
            widget.controller.initialCompensationRuleKey ?? '',
          );
          _compensationKey = compensation?.key;
          if (compensation != null) {
            _compensationValueController.text = _valueInput(
              compensation,
              value: widget.controller.initialCompensationValueMinor,
            );
          }
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  void _invalidatePreview() {
    if (_preview == null && _error == null) return;
    setState(() {
      _preview = null;
      _error = null;
      _commitAttempted = false;
    });
  }

  void _selectCompensation(String? key) {
    setState(() {
      _compensationKey = key;
      _preview = null;
      _error = null;
      _commitAttempted = false;
      final rule = _compensationRule;
      _compensationValueController.text = rule == null ? '' : _valueInput(rule);
    });
  }

  String _valueInput(LessonDecisionCatalogItem rule, {String? value}) {
    final parsed = BigInt.tryParse(value ?? rule.value) ?? BigInt.zero;
    if (rule.mode == 'percent') {
      final whole = parsed ~/ BigInt.from(100);
      final fraction = (parsed % BigInt.from(100)).toString().padLeft(2, '0');
      return fraction == '00' ? '$whole' : '$whole,$fraction';
    }
    return _minorInput(parsed);
  }

  String? _compensationValueMinor() {
    final mode = _compensationRule?.mode;
    if (mode == null || mode == 'none' || mode == 'standard') return null;
    final raw = _compensationValueController.text
        .trim()
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    final value = double.tryParse(raw);
    if (value == null || value < 0) return null;
    if (mode == 'percent') {
      if (value > 200) return null;
      return (value * 100).round().toString();
    }
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(raw)) return null;
    final parts = raw.split('.');
    return (BigInt.parse(parts.first) * BigInt.from(100) +
            BigInt.parse(parts.length == 1 ? '0' : parts.last.padRight(2, '0')))
        .toString();
  }

  List<Map<String, dynamic>> _clientDecisions() => [
    for (final participant in widget.controller.groupParticipants)
      if (_clientSettlementKeys[participant.id] case final settlementKey?)
        {'clientId': participant.id, 'settlementTypeKey': settlementKey},
  ];

  Future<void> _calculate() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _commitAttempted = false;
    });
    try {
      final preview = await widget.controller.preview(
        reason: _reasonController.text,
        settlementTypeKey: _settlementKey!,
        compensationRuleKey: _compensationKey!,
        compensationValueMinor: _compensationValueMinor(),
        clientDecisions: _clientDecisions(),
      );
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final preview = _preview;
    if (_busy || preview == null || !preview.canConfirm) return;
    setState(() {
      _busy = true;
      _error = null;
      _commitAttempted = true;
    });
    try {
      await widget.controller.commit(preview);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        final recovered = widget.controller.recoverStaleCommit(error);
        setState(() {
          _error = recovered ?? error;
          if (recovered != null) {
            _preview = null;
            _commitAttempted = false;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpace.xl),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final catalog = _catalog;
    if (catalog == null) {
      return _LoadError(error: _error, onRetry: _loadCatalog);
    }
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LessonMoveSummary(controller: widget.controller),
          const SizedBox(height: AppSpace.lg),
          TextFormField(
            key: const Key('lesson-decision-reason'),
            controller: _reasonController,
            enabled: !_busy,
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
            onChanged: (_) => _invalidatePreview(),
          ),
          const SizedBox(height: AppSpace.md),
          if (widget.controller.isCompletedReschedule)
            const _CompletedRescheduleNotice()
          else ...[
            DropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: const Key('lesson-decision-settlement'),
              initialValue: _settlementKey,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Списание *'),
              items: [
                for (final item in catalog.settlementTypes)
                  DropdownMenuItem(
                    value: item.key,
                    child: _CatalogLabel(item: item),
                  ),
              ],
              validator: (value) => value == null ? 'Выберите списание' : null,
              onChanged: _busy
                  ? null
                  : (value) {
                      setState(() => _settlementKey = value);
                      _invalidatePreview();
                    },
            ),
            const SizedBox(height: AppSpace.md),
            if (widget.controller.isGroupLesson &&
                widget.controller.groupParticipants.isNotEmpty) ...[
              _GroupClientOverrides(
                participants: widget.controller.groupParticipants,
                settlementTypes: catalog.settlementTypes,
                selectedKeys: _clientSettlementKeys,
                enabled: !_busy,
                onChanged: (clientId, settlementKey) {
                  setState(() {
                    _clientSettlementKeys[clientId] = settlementKey;
                  });
                  _invalidatePreview();
                },
              ),
              const SizedBox(height: AppSpace.md),
            ],
            DropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: const Key('lesson-decision-compensation'),
              initialValue: _compensationKey,
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
              onChanged: _busy ? null : _selectCompensation,
            ),
          ],
          if (!widget.controller.isCompletedReschedule)
            if (_compensationRule case final rule?
                when rule.mode != 'none' && rule.mode != 'standard') ...[
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const Key('lesson-decision-compensation-value'),
                controller: _compensationValueController,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,. ]')),
                ],
                decoration: InputDecoration(
                  labelText: rule.mode == 'percent'
                      ? 'Процент ставки *'
                      : rule.mode == 'hourly'
                      ? 'Ставка за час, ₽ *'
                      : 'Сумма, ₽ *',
                ),
                validator: (_) => _compensationValueMinor() == null
                    ? 'Введите корректное значение'
                    : null,
                onChanged: (_) => _invalidatePreview(),
              ),
            ],
          if (_preview case final preview?) ...[
            const SizedBox(height: AppSpace.lg),
            _PreviewCard(
              preview: preview,
              participantNames: widget.controller.participantNames,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpace.md),
            _DecisionError(error: _error!),
          ],
          const SizedBox(height: AppSpace.xl),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  child: const Text('Закрыть'),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: FilledButton(
                  key: const Key('lesson-decision-submit'),
                  onPressed: _busy
                      ? null
                      : _preview?.canConfirm == true
                      ? _commit
                      : _calculate,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _preview?.canConfirm == true
                              ? _commitAttempted
                                    ? 'Повторить'
                                    : widget.controller.operation.actionLabel
                              : _preview == null
                              ? 'Рассчитать'
                              : 'Повторить расчёт',
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _commonSettlementOverride = '__common_settlement__';

class _GroupClientOverrides extends StatelessWidget {
  const _GroupClientOverrides({
    required this.participants,
    required this.settlementTypes,
    required this.selectedKeys,
    required this.enabled,
    required this.onChanged,
  });

  final List<LessonDecisionParticipant> participants;
  final List<LessonDecisionCatalogItem> settlementTypes;
  final Map<String, String?> selectedKeys;
  final bool enabled;
  final void Function(String clientId, String? settlementKey) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          const Text(
            'Индивидуальные условия участников',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Общее списание применяется ко всей группе. Здесь можно изменить его только для конкретного ученика; источник средств берётся из закреплённого плана ученика.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          for (var index = 0; index < participants.length; index++) ...[
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
                    child: _CatalogLabel(item: item),
                  ),
              ],
              onChanged: !enabled
                  ? null
                  : (value) => onChanged(
                      participants[index].id,
                      value == _commonSettlementOverride ? null : value,
                    ),
            ),
            if (index != participants.length - 1)
              const SizedBox(height: AppSpace.sm),
          ],
        ],
      ),
    );
  }
}

class _LessonMoveSummary extends StatelessWidget {
  const _LessonMoveSummary({required this.controller});

  final LessonDecisionController controller;

  @override
  Widget build(BuildContext context) {
    final source = _lessonTime(
      controller.lesson['scheduled_at'] ?? controller.lesson['scheduledAt'],
    );
    final successor = _lessonTime(controller.successor?['scheduledAt']);
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
          if (controller.operation == LessonDecisionOperation.reschedule)
            Text('Будет: $successor'),
        ],
      ),
    );
  }
}

class _CompletedRescheduleNotice extends StatelessWidget {
  const _CompletedRescheduleNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('completed-reschedule-notice'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.warning.withValues(alpha: 0.12),
        border: Border.all(color: AppColor.warning),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history_rounded, color: AppColor.warning),
          SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'Это занятие уже завершено. Прежний расчёт будет отменён без удаления истории, а новое занятие сохранит исходный план и рассчитает его после завершения.',
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogLabel extends StatelessWidget {
  const _CatalogLabel({required this.item});

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

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview, required this.participantNames});

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

class _DecisionError extends StatelessWidget {
  const _DecisionError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Container(
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
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DecisionError(error: error ?? 'Каталог недоступен'),
        const SizedBox(height: AppSpace.md),
        FilledButton(onPressed: onRetry, child: const Text('Повторить')),
      ],
    );
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
  return date == null
      ? 'Не указано'
      : DateFormat('dd.MM.yyyy HH:mm', 'ru').format(date.toLocal());
}

String _minorInput(BigInt value) {
  final rubles = value ~/ BigInt.from(100);
  final kopecks = (value % BigInt.from(100)).toString().padLeft(2, '0');
  return kopecks == '00' ? '$rubles' : '$rubles,$kopecks';
}

String _formatMinor(Object? value) {
  final minor = BigInt.tryParse(value?.toString() ?? '') ?? BigInt.zero;
  final rubles = minor.abs() ~/ BigInt.from(100);
  final kopecks = (minor.abs() % BigInt.from(100)).toString().padLeft(2, '0');
  final grouped = NumberFormat.decimalPattern('ru').format(rubles.toInt());
  return '${minor.isNegative ? '−' : ''}$grouped,$kopecks ₽';
}

String _warningLabel(String value) => switch (value) {
  'COMPLETED_LESSON_EFFECTS_WILL_BE_REVERSED' =>
    'Прежние списание и оплата преподавателю будут отменены без удаления истории. Новое занятие рассчитается отдельно после завершения.',
  'SUCCESSOR_MAY_CHARGE_AGAIN' =>
    'Перенос завершает текущее занятие. Новое занятие может создать отдельное списание.',
  _ => value,
};

LessonDecisionCatalogItem? _catalogItem(
  List<LessonDecisionCatalogItem> items,
  String key,
) {
  for (final item in items) {
    if (item.key == key) return item;
  }
  return null;
}

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
