import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'lesson_decision_models.dart';
import 'lesson_decision_sections.dart';
import '../lesson_editor/lesson_financial_autofill.dart';

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
  final _teacherDurationController = TextEditingController();
  final Map<String, String?> _clientSettlementKeys = {};
  final Map<String, int?> _clientDurationMinutes = {};
  final Map<String, String?> _payerIds = {};
  final Map<String, String?> _payerNames = {};
  final Map<String, String?> _subscriptionIds = {};
  final Map<String, List<LessonDecisionSubscription>> _subscriptions = {};
  final Set<String> _loadingSubscriptions = {};

  LessonDecisionCatalog? _catalog;
  LessonDecisionPreview? _preview;
  String? _settlementKey;
  String? _compensationKey;
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  bool _commitAttempted = false;
  bool _compensationTouched = false;
  String? _teacherCompensationSource;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _compensationValueController.dispose();
    _teacherDurationController.dispose();
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

  LessonDecisionCatalogItem? get _settlement {
    final key = _settlementKey;
    if (key == null) return null;
    return _catalogItem(_catalog?.settlementTypes ?? const [], key);
  }

  int get _lessonDurationMinutes {
    final value =
        widget.controller.successor?['durationMinutes'] ??
        widget.controller.lesson['duration_minutes'] ??
        widget.controller.lesson['durationMinutes'] ??
        _catalog?.defaultDurationMinutes;
    return value is num && value > 0 ? value.toInt() : 60;
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await widget.controller.loadCatalog();
      final defaults = _resolveDefaults(widget.controller, catalog);
      final settlement = _catalogItem(
        catalog.settlementTypes,
        defaults.settlementKey ?? '',
      );
      final initialSource = widget.controller.initialTeacherCompensationSource;
      final recommendation =
          settlement?.defaultTeacherCompensationRuleKey == null
          ? null
          : const LessonFinancialAutofill().apply(
              settlement: settlement!,
              durationMinutes: _lessonDurationMinutes,
              compensationTouched: initialSource == 'manual',
              currentRuleKey: defaults.compensationKey,
              currentTeacherMinutes:
                  widget.controller.initialTeacherCreditedDurationMinutes,
            );
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _settlementKey = defaults.settlementKey;
        _compensationKey =
            recommendation?.compensationRuleKey ?? defaults.compensationKey;
        _compensationValueController.text = recommendation == null
            ? defaults.compensationValue
            : _recommendedCompensationInput(catalog, recommendation);
        _teacherDurationController.text =
            recommendation?.teacherCreditedDurationMinutes?.toString() ??
            widget.controller.initialTeacherCreditedDurationMinutes
                ?.toString() ??
            '';
        _teacherCompensationSource = recommendation?.source ?? initialSource;
        _compensationTouched = initialSource == 'manual';
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
    setState(() {
      _settlementKey = value;
      final settlement = _settlement;
      if (settlement?.defaultTeacherCompensationRuleKey != null) {
        final recommendation = const LessonFinancialAutofill().apply(
          settlement: settlement!,
          durationMinutes: _lessonDurationMinutes,
          compensationTouched: _compensationTouched,
          currentRuleKey: _compensationKey,
          currentTeacherMinutes: int.tryParse(_teacherDurationController.text),
        );
        _applyRecommendation(
          recommendation,
          preserveCompensationValue: _compensationTouched,
        );
        final clientMinutes = const LessonFinancialAutofill()
            .recommendedClientMinutes(
              settlement: settlement,
              durationMinutes: _lessonDurationMinutes,
            );
        for (final participant in widget.controller.settlementClients) {
          if (_clientSettlementKeys[participant.id] == null) {
            _clientDurationMinutes[participant.id] = clientMinutes;
          }
        }
      }
      _clearPreview();
    });
  }

  void _selectCompensation(String? key) {
    setState(() {
      _compensationKey = key;
      _preview = null;
      _error = null;
      _commitAttempted = false;
      _compensationTouched = true;
      _teacherCompensationSource = 'manual';
      final rule = _compensationRule;
      _compensationValueController.text = rule == null ? '' : _valueInput(rule);
    });
  }

  void _selectClientSettlement(String clientId, String? settlementKey) {
    setState(() {
      _clientSettlementKeys[clientId] = settlementKey;
      final settlement = _catalogItem(
        _catalog?.settlementTypes ?? const [],
        settlementKey ?? _settlementKey ?? '',
      );
      if (settlement != null) {
        _clientDurationMinutes[clientId] = const LessonFinancialAutofill()
            .recommendedClientMinutes(
              settlement: settlement,
              durationMinutes: _lessonDurationMinutes,
            );
      }
      _clearPreview();
    });
  }

  void _selectClientDuration(String clientId, String value) {
    setState(() {
      _clientDurationMinutes[clientId] = int.tryParse(value);
      _clearPreview();
    });
  }

  void _selectTeacherDuration(String value) {
    setState(() {
      _compensationTouched = true;
      _teacherCompensationSource = 'manual';
      _clearPreview();
    });
  }

  void _changeCompensationValue(String _) {
    setState(() {
      _compensationTouched = true;
      _teacherCompensationSource = 'manual';
      _clearPreview();
    });
  }

  void _restoreRecommendation() {
    final settlement = _settlement;
    if (settlement == null) return;
    setState(() {
      _compensationTouched = false;
      _applyRecommendation(
        const LessonFinancialAutofill().restoreRecommendation(
          settlement: settlement,
          durationMinutes: _lessonDurationMinutes,
        ),
      );
      _clearPreview();
    });
  }

  void _applyRecommendation(
    LessonFinancialRecommendation recommendation, {
    bool preserveCompensationValue = false,
  }) {
    _compensationKey = recommendation.compensationRuleKey;
    _teacherDurationController.text =
        recommendation.teacherCreditedDurationMinutes?.toString() ?? '';
    _teacherCompensationSource = recommendation.source;
    final catalog = _catalog;
    if (catalog != null && !preserveCompensationValue) {
      _compensationValueController.text = _recommendedCompensationInput(
        catalog,
        recommendation,
      );
    }
  }

  void _clearPreview() {
    _preview = null;
    _error = null;
    _commitAttempted = false;
  }

  Future<void> _selectPayer(
    String clientId,
    LessonDecisionParticipant? payer,
  ) async {
    final payerId = payer?.id;
    setState(() {
      _payerIds[clientId] = payerId;
      _payerNames[clientId] = payer?.name;
      _subscriptionIds.remove(clientId);
      _subscriptions.remove(clientId);
      _loadingSubscriptions.remove(clientId);
      if (payerId != null) _loadingSubscriptions.add(clientId);
    });
    _invalidatePreview();
    if (payerId == null) return;
    try {
      final subscriptions = await widget.controller.loadSubscriptions(payerId);
      if (!mounted || _payerIds[clientId] != payerId) return;
      setState(() => _subscriptions[clientId] = subscriptions);
    } catch (error) {
      if (!mounted || _payerIds[clientId] != payerId) return;
      setState(() {
        _subscriptions[clientId] = const [];
        _error = error;
      });
    } finally {
      if (mounted && _payerIds[clientId] == payerId) {
        setState(() => _loadingSubscriptions.remove(clientId));
      }
    }
  }

  void _selectSubscription(String clientId, String? subscriptionId) {
    setState(() => _subscriptionIds[clientId] = subscriptionId);
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
        compensationRuleKey: widget.controller.canManageTeacherCompensation
            ? _compensationKey!
            : '',
        compensationValueMinor: _compensationValueMinor(
          _compensationRule,
          _compensationValueController.text,
        ),
        teacherCreditedDurationMinutes:
            widget.controller.canManageTeacherCompensation
            ? int.tryParse(_teacherDurationController.text)
            : null,
        teacherCompensationSource:
            widget.controller.canManageTeacherCompensation
            ? _teacherCompensationSource
            : null,
        clientDecisions: _clientDecisions(
          widget.controller.settlementClients,
          _clientSettlementKeys,
          _payerIds,
          _subscriptionIds,
          _clientDurationMinutes,
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
      teacherDurationController: _teacherDurationController,
      catalog: catalog,
      settlementKey: _settlementKey,
      compensationKey: _compensationKey,
      compensationRule: _compensationRule,
      participants: widget.controller.settlementClients,
      participantNames: widget.controller.participantNames,
      clientSettlementKeys: _clientSettlementKeys,
      clientDurationMinutes: _clientDurationMinutes,
      payerIds: _payerIds,
      payerNames: _payerNames,
      subscriptionIds: _subscriptionIds,
      subscriptions: _subscriptions,
      loadingSubscriptions: _loadingSubscriptions,
      groupLesson: widget.controller.isGroupLesson,
      completedReschedule: completedReschedule,
      canManageTeacherCompensation:
          widget.controller.canManageTeacherCompensation,
      busy: _busy,
      preview: _preview,
      error: _error,
      commitAttempted: _commitAttempted,
      onReasonChanged: (_) => _invalidatePreview(),
      onSettlementChanged: _selectSettlement,
      onCompensationChanged: _selectCompensation,
      onCompensationValueChanged: _changeCompensationValue,
      onTeacherDurationChanged: _selectTeacherDuration,
      onRestoreRecommendation: _restoreRecommendation,
      onClientSettlementChanged: _selectClientSettlement,
      onClientDurationChanged: _selectClientDuration,
      searchPayers: widget.controller.searchPayers,
      onPayerChanged: _selectPayer,
      onSubscriptionChanged: _selectSubscription,
      compensationValidator: (_) =>
          widget.controller.canManageTeacherCompensation &&
              _compensationValueMinor(
                    _compensationRule,
                    _compensationValueController.text,
                  ) ==
                  null
          ? 'Введите корректное значение'
          : null,
      durationMinutes: _lessonDurationMinutes,
      compensationTouched: _compensationTouched,
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
  Map<String, String?> payerIds,
  Map<String, String?> subscriptionIds,
  Map<String, int?> durationMinutes,
) => [
  for (final participant in participants)
    if (selectedKeys[participant.id] != null ||
        payerIds[participant.id] != null ||
        durationMinutes[participant.id] != null)
      {
        'clientId': participant.id,
        'settlementTypeKey': ?selectedKeys[participant.id],
        'payerStudentId': ?payerIds[participant.id],
        'subscriptionId': ?subscriptionIds[participant.id],
        'chargeDurationMinutes': ?durationMinutes[participant.id],
      },
];

String _recommendedCompensationInput(
  LessonDecisionCatalog catalog,
  LessonFinancialRecommendation recommendation,
) {
  final rule = _catalogItem(
    catalog.compensationRules,
    recommendation.compensationRuleKey ?? '',
  );
  return rule == null ? '' : _valueInput(rule);
}

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
