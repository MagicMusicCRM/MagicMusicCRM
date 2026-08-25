import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'lesson_decision_models.dart';
import 'lesson_decision_sections.dart';

class LessonDecisionForm extends StatefulWidget {
  const LessonDecisionForm({required this.controller, super.key});

  final LessonDecisionFormLifecycle controller;

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
      final defaults = _resolveDefaults(widget.controller, catalog);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _settlementKey = defaults.settlementKey;
        _compensationKey = defaults.compensationKey;
        _compensationValueController.text = defaults.compensationValue;
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

  void _selectSettlement(String? value) {
    setState(() => _settlementKey = value);
    _invalidatePreview();
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

  void _selectClientSettlement(String clientId, String? settlementKey) {
    setState(() => _clientSettlementKeys[clientId] = settlementKey);
    _invalidatePreview();
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
        compensationValueMinor: _compensationValueMinor(
          _compensationRule,
          _compensationValueController.text,
        ),
        clientDecisions: _clientDecisions(
          widget.controller.groupParticipants,
          _clientSettlementKeys,
        ),
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
      return LessonDecisionLoadError(error: _error, onRetry: _loadCatalog);
    }
    final completedReschedule = widget.controller.isCompletedReschedule;
    final sourceScheduledAt =
        widget.controller.lesson['scheduled_at'] ??
        widget.controller.lesson['scheduledAt'];
    final successorScheduledAt = widget.controller.successor?['scheduledAt'];
    return LessonDecisionFormContent(
      formKey: _formKey,
      operation: widget.controller.operation,
      sourceScheduledAt: sourceScheduledAt,
      successorScheduledAt: successorScheduledAt,
      completedSourceScheduledAt: _requiredLessonTime(sourceScheduledAt),
      completedSuccessorScheduledAt: _requiredLessonTime(successorScheduledAt),
      reasonController: _reasonController,
      compensationValueController: _compensationValueController,
      catalog: catalog,
      settlementKey: _settlementKey,
      compensationKey: _compensationKey,
      compensationRule: _compensationRule,
      participants: widget.controller.groupParticipants,
      participantNames: widget.controller.participantNames,
      clientSettlementKeys: _clientSettlementKeys,
      groupLesson: widget.controller.isGroupLesson,
      completedReschedule: completedReschedule,
      busy: _busy,
      preview: _preview,
      error: _error,
      commitAttempted: _commitAttempted,
      onReasonChanged: (_) => _invalidatePreview(),
      onSettlementChanged: _selectSettlement,
      onCompensationChanged: _selectCompensation,
      onCompensationValueChanged: (_) => _invalidatePreview(),
      onClientSettlementChanged: _selectClientSettlement,
      compensationValidator: (_) =>
          _compensationValueMinor(
                _compensationRule,
                _compensationValueController.text,
              ) ==
              null
          ? 'Введите корректное значение'
          : null,
      onClose: () => Navigator.pop(context, false),
      onSubmit: _preview?.canConfirm == true ? _commit : _calculate,
    );
  }
}

({String? settlementKey, String? compensationKey, String compensationValue})
_resolveDefaults(
  LessonDecisionFormLifecycle controller,
  LessonDecisionCatalog catalog,
) {
  if (controller.isCompletedReschedule) {
    final settlement = _catalogItem(catalog.settlementTypes, 'free_lesson');
    final compensation = _catalogItem(catalog.compensationRules, 'none');
    if (settlement == null || compensation == null) {
      throw StateError(
        'Не удалось подготовить безопасную отмену расчёта. Обновите настройки занятия.',
      );
    }
    return (
      settlementKey: settlement.key,
      compensationKey: compensation.key,
      compensationValue: '',
    );
  }
  final settlement = _catalogItem(
    catalog.settlementTypes,
    controller.initialSettlementTypeKey ?? '',
  );
  final compensation = _catalogItem(
    catalog.compensationRules,
    controller.initialCompensationRuleKey ?? '',
  );
  return (
    settlementKey: settlement?.key,
    compensationKey: compensation?.key,
    compensationValue: compensation == null
        ? ''
        : _valueInput(
            compensation,
            value: controller.initialCompensationValueMinor,
          ),
  );
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

String? _compensationValueMinor(LessonDecisionCatalogItem? rule, String input) {
  final mode = rule?.mode;
  if (mode == null || mode == 'none' || mode == 'standard') return null;
  final raw = input.trim().replaceAll(' ', '').replaceAll(',', '.');
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

List<Map<String, dynamic>> _clientDecisions(
  List<LessonDecisionParticipant> participants,
  Map<String, String?> selectedKeys,
) => [
  for (final participant in participants)
    if (selectedKeys[participant.id] case final settlementKey?)
      {'clientId': participant.id, 'settlementTypeKey': settlementKey},
];

LessonDecisionCatalogItem? _catalogItem(
  List<LessonDecisionCatalogItem> items,
  String key,
) {
  for (final item in items) {
    if (item.key == key) return item;
  }
  return null;
}

String _minorInput(BigInt value) {
  final rubles = value ~/ BigInt.from(100);
  final kopecks = (value % BigInt.from(100)).toString().padLeft(2, '0');
  return kopecks == '00' ? '$rubles' : '$rubles,$kopecks';
}

DateTime _requiredLessonTime(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '') ??
    DateTime.fromMillisecondsSinceEpoch(0);
