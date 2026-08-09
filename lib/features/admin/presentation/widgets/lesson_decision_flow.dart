import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

enum LessonDecisionOperation {
  reschedule,
  cancel,
  settle,
  plannedSettlement,
  correction,
}

extension on LessonDecisionOperation {
  String get key => switch (this) {
    LessonDecisionOperation.reschedule => 'reschedule',
    LessonDecisionOperation.cancel => 'cancel',
    LessonDecisionOperation.settle => 'settle',
    LessonDecisionOperation.plannedSettlement => 'planned-settlement',
    LessonDecisionOperation.correction => 'settlement-correction',
  };

  String get title => switch (this) {
    LessonDecisionOperation.reschedule => 'Перенос занятия',
    LessonDecisionOperation.cancel => 'Отмена занятия',
    LessonDecisionOperation.settle => 'Результат занятия',
    LessonDecisionOperation.plannedSettlement => 'Изменение расчёта',
    LessonDecisionOperation.correction => 'Корректировка расчёта',
  };

  String get action => switch (this) {
    LessonDecisionOperation.reschedule => 'Перенести',
    LessonDecisionOperation.cancel => 'Отменить занятие',
    LessonDecisionOperation.settle => 'Зафиксировать результат',
    LessonDecisionOperation.plannedSettlement => 'Изменить расчёт',
    LessonDecisionOperation.correction => 'Сохранить корректировку',
  };

  String get catalogContext => switch (this) {
    LessonDecisionOperation.plannedSettlement ||
    LessonDecisionOperation.correction => 'settle',
    _ => key,
  };
}

class LessonDecisionCatalogItem {
  const LessonDecisionCatalogItem({
    required this.key,
    required this.label,
    required this.order,
    this.colorToken,
    this.allowedContexts = const [],
    this.mode,
    this.value = '0',
    this.hourShareBasisPoints = 0,
    this.fixedPenaltyMinor = '0',
  });

  final String key;
  final String label;
  final int order;
  final String? colorToken;
  final List<String> allowedContexts;
  final String? mode;
  final String value;
  final int hourShareBasisPoints;
  final String fixedPenaltyMinor;

  factory LessonDecisionCatalogItem.fromJson(Map<String, dynamic> json) {
    return LessonDecisionCatalogItem(
      key: json['stableKey']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      order: (json['order'] as num?)?.toInt() ?? 0,
      colorToken: json['colorToken']?.toString(),
      allowedContexts: [
        for (final value in json['allowedContexts'] as List? ?? const [])
          value.toString(),
      ],
      mode: json['mode']?.toString(),
      value: json['value']?.toString() ?? '0',
      hourShareBasisPoints:
          (json['hourShareBasisPoints'] as num?)?.toInt() ?? 0,
      fixedPenaltyMinor: json['fixedPenaltyMinor']?.toString() ?? '0',
    );
  }
}

class LessonDecisionCatalog {
  const LessonDecisionCatalog({
    required this.settlementTypes,
    required this.compensationRules,
  });

  final List<LessonDecisionCatalogItem> settlementTypes;
  final List<LessonDecisionCatalogItem> compensationRules;

  factory LessonDecisionCatalog.fromJson(
    Map<String, dynamic> json,
    LessonDecisionOperation operation,
  ) {
    List<LessonDecisionCatalogItem> parse(String key) => [
      for (final item in json[key] as List? ?? const [])
        if (item is Map)
          LessonDecisionCatalogItem.fromJson(Map<String, dynamic>.from(item)),
    ]..sort((left, right) => left.order.compareTo(right.order));

    return LessonDecisionCatalog(
      settlementTypes: parse('settlementTypes')
          .where(
            (item) => item.allowedContexts.contains(operation.catalogContext),
          )
          .toList(),
      compensationRules: parse('teacherCompensationRules'),
    );
  }
}

class LessonDecisionPreview {
  const LessonDecisionPreview(this.raw);

  final Map<String, dynamic> raw;

  bool get canConfirm => raw['canConfirm'] == true;
  String? get token => raw['previewToken']?.toString();
  Map<String, dynamic> get source => _map(raw['source']);
  Map<String, dynamic> get successor => _map(raw['successor']);
  Map<String, dynamic> get financial => _map(raw['financialPreview']);
  List<Map<String, dynamic>> get violations => _maps(raw['violations']);
  List<String> get warnings => [
    for (final warning in raw['warnings'] as List? ?? const [])
      warning.toString(),
  ];
}

class LessonDecisionController {
  LessonDecisionController({
    required MagicApiClient api,
    required this.operation,
    required this.lesson,
    this.successor,
  }) : _api = api;

  final MagicApiClient _api;
  final LessonDecisionOperation operation;
  final Map<String, dynamic> lesson;
  final Map<String, dynamic>? successor;

  Map<String, dynamic>? _previewPayload;
  MagicMutationIdentity? _commitIdentity;

  Future<LessonDecisionCatalog> loadCatalog() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/configuration/lesson-decisions',
      queryParameters: {'branchId': lesson['branch_id']?.toString()},
    );
    return LessonDecisionCatalog.fromJson(response, operation);
  }

  Future<LessonDecisionPreview> preview({
    required String reason,
    required String settlementTypeKey,
    required String compensationRuleKey,
    String? compensationValueMinor,
  }) async {
    final expectedVersion = (lesson['version'] as num?)?.toInt();
    if (expectedVersion == null || expectedVersion < 1) {
      throw StateError('Обновите расписание: версия занятия не получена.');
    }
    final payload = <String, dynamic>{
      'expectedVersion': expectedVersion,
      if (operation != LessonDecisionOperation.plannedSettlement &&
          operation != LessonDecisionOperation.correction)
        'reasonCode': 'manual',
      'reasonText': reason.trim(),
      'financialDecision': {
        'settlementTypeKey': settlementTypeKey,
        'teacherCompensationRuleKey': compensationRuleKey,
        'teacherCompensationValueMinor': ?compensationValueMinor,
      },
      if (operation == LessonDecisionOperation.reschedule)
        'successor': successor ?? const <String, dynamic>{},
    };
    final response = await _api.post<Map<String, dynamic>>(
      '/crm/lessons/${lesson['id']}/${operation.key}/preview',
      data: payload,
    );
    _previewPayload = payload;
    _commitIdentity = MagicMutationIdentity.create(
      'lesson-${operation.key}-${lesson['id']}',
    );
    return LessonDecisionPreview(response);
  }

  Future<Map<String, dynamic>> commit(LessonDecisionPreview preview) {
    final payload = _previewPayload;
    final identity = _commitIdentity;
    final token = preview.token;
    if (payload == null ||
        identity == null ||
        token == null ||
        !preview.canConfirm) {
      throw StateError('Сначала получите актуальный расчёт.');
    }
    final data = {...payload, 'previewToken': token, 'confirm': true};
    if (operation == LessonDecisionOperation.plannedSettlement) {
      return _api.request<Map<String, dynamic>>(
        'PUT',
        '/crm/lessons/${lesson['id']}/${operation.key}',
        data: data,
        mutationIdentity: identity,
      );
    }
    return _api.postIdempotent<Map<String, dynamic>>(
      '/crm/lessons/${lesson['id']}/${operation.key}',
      identity: identity,
      data: data,
    );
  }
}

Future<bool?> showLessonDecisionFlow(
  BuildContext context, {
  required MagicApiClient api,
  required LessonDecisionOperation operation,
  required Map<String, dynamic> lesson,
  Map<String, dynamic>? successor,
}) {
  final controller = LessonDecisionController(
    api: api,
    operation: operation,
    lesson: lesson,
    successor: successor,
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
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
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

  String _valueInput(LessonDecisionCatalogItem rule) {
    final value = BigInt.tryParse(rule.value) ?? BigInt.zero;
    if (rule.mode == 'percent') {
      final whole = value ~/ BigInt.from(100);
      final fraction = (value % BigInt.from(100)).toString().padLeft(2, '0');
      return fraction == '00' ? '$whole' : '$whole,$fraction';
    }
    return _minorInput(value);
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
      if (mounted) setState(() => _error = error);
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
            _PreviewCard(preview: preview),
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
                                    : widget.controller.operation.action
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

class _LessonMoveSummary extends StatelessWidget {
  const _LessonMoveSummary({required this.controller});

  final LessonDecisionController controller;

  @override
  Widget build(BuildContext context) {
    final source = _lessonTime(controller.lesson['scheduled_at']);
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
  const _PreviewCard({required this.preview});

  final LessonDecisionPreview preview;

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
                      ? 'Расчёт готов к подтверждению'
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
              'Клиент: ${fact['settlementLabel'] ?? fact['settlementTypeKey'] ?? '—'} · '
              '${fact['units'] ?? '0'} ч · ${_formatMinor(fact['amountMinor'])}',
            ),
          ],
          if (teacherFact.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              'Преподаватель: ${teacherFact['compensationRuleLabel'] ?? teacherFact['compensationRuleKey'] ?? '—'} · '
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
        'Не удалось выполнить действие. Введённые данные сохранены; '
        'повторите расчёт или подтверждение.\n$error',
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
      ? '—'
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
  'SUCCESSOR_MAY_CHARGE_AGAIN' =>
    'Перенос завершает текущее занятие. Новое занятие может создать отдельное списание.',
  _ => value,
};

String _violationLabel(Map<String, dynamic> value) =>
    switch (value['code']?.toString()) {
      'TEACHER_OVERLAP' => 'У преподавателя уже есть занятие в это время',
      'CLIENT_OVERLAP' => 'У клиента уже есть занятие в это время',
      'ROOM_OVERLAP' => 'Аудитория уже занята',
      'TEACHER_UNAVAILABLE' => 'Преподаватель недоступен',
      'OUTSIDE_BRANCH_HOURS' => 'Филиал закрыт в это время',
      final code? => code,
      _ => 'Ограничение расписания',
    };
