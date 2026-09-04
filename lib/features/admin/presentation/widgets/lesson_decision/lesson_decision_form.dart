import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface_kind.dart';

import 'lesson_decision_models.dart';
import 'lesson_decision_sections.dart';
import '../lesson_editor/lesson_financial_autofill.dart';
import '../lesson_editor/lesson_transition_error.dart';
import '../lesson_editor/lesson_editor_dismiss_guard.dart';

class GuardedLessonDecisionForm extends StatefulWidget {
  const GuardedLessonDecisionForm({required this.controller, super.key});

  final LessonDecisionFormLifecycle controller;

  @override
  State<GuardedLessonDecisionForm> createState() =>
      _GuardedLessonDecisionFormState();
}

class _GuardedLessonDecisionFormState extends State<GuardedLessonDecisionForm> {
  bool _dirty = false;

  @override
  Widget build(BuildContext context) => LessonEditorDismissGuard(
    isDirty: _dirty,
    child: LessonDecisionForm(
      controller: widget.controller,
      onDirtyChanged: (dirty) {
        if (dirty != _dirty) setState(() => _dirty = dirty);
      },
    ),
  );
}

class LessonDecisionForm extends StatefulWidget {
  const LessonDecisionForm({
    required this.controller,
    this.onDirtyChanged,
    super.key,
  });

  final LessonDecisionFormLifecycle controller;
  final ValueChanged<bool>? onDirtyChanged;

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
  final Map<String, String?> _chargeTypes = {};
  final Map<String, String?> _preferredChargeTypes = {};
  final Map<String, Map<String, dynamic>> _clientDecisionsById = {};
  final Map<String, List<LessonDecisionSubscription>> _subscriptions = {};
  final Set<String> _loadingSubscriptions = {};
  final Set<String> _clientDecisionTouched = {};
  final Set<String> _clientDurationTouched = {};

  LessonDecisionCatalog? _catalog;
  LessonDecisionPreview? _preview;
  String? _settlementKey;
  String? _compensationKey;
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  bool _commitAttempted = false;
  bool _compensationTouched = false;
  bool _dirty = false;
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
      final storedClientDecisions = widget.controller.initialClientDecisions;
      final cancellationDraft =
          widget.controller.operation == LessonDecisionOperation.cancel
          ? LessonDecisionDraft.forCancel(
              catalog: catalog,
              lesson: widget.controller.lesson,
              clients: widget.controller.settlementClients,
              existingClientDecisions: storedClientDecisions,
            )
          : null;
      final defaults = cancellationDraft == null
          ? _resolveDefaults(widget.controller, catalog)
          : (
              settlementKey: cancellationDraft.settlementTypeKey,
              compensationKey: cancellationDraft.teacherCompensationRuleKey,
              compensationValue: '',
            );
      final settlement = _catalogItem(
        catalog.settlementTypes,
        defaults.settlementKey ?? '',
      );
      final initialSource = cancellationDraft == null
          ? widget.controller.initialTeacherCompensationSource
          : 'automatic';
      final initialTeacherMinutes = cancellationDraft == null
          ? widget.controller.initialTeacherCreditedDurationMinutes
          : cancellationDraft.teacherCreditedDurationMinutes;
      final initialClientDecisions = cancellationDraft == null
          ? storedClientDecisions
          : [
              for (final decision in cancellationDraft.clientDecisions)
                decision.toJson(),
            ];
      final participants = {
        for (final participant in widget.controller.settlementClients)
          participant.id: participant,
      };
      final initialById = <String, Map<String, dynamic>>{
        for (final row in initialClientDecisions)
          if (row['clientId']?.toString() case final String id
              when participants.containsKey(id))
            id: Map<String, dynamic>.from(row),
      };
      final initialSubscriptions = <String, List<LessonDecisionSubscription>>{};
      await Future.wait([
        for (final entry in initialById.entries)
          if ((entry.value['chargeType'] == 'subscription' ||
                  entry.value['preferredChargeType'] == 'subscription' ||
                  (entry.value['chargeType'] == null &&
                      entry.value['subscriptionId'] != null)) &&
              entry.value['payerStudentId'] != null)
            () async {
              final payerId = entry.value['payerStudentId'].toString();
              final subscriptionId = entry.value['subscriptionId']?.toString();
              try {
                final values = await widget.controller.loadSubscriptions(
                  payerId,
                );
                initialSubscriptions[entry.key] = _withStoredSubscription(
                  values,
                  subscriptionId,
                );
              } catch (_) {
                initialSubscriptions[entry.key] = _withStoredSubscription(
                  const [],
                  subscriptionId,
                );
              }
            }(),
      ]);
      final recommendation =
          settlement?.defaultTeacherCompensationRuleKey == null
          ? null
          : const LessonFinancialAutofill().apply(
              settlement: settlement!,
              durationMinutes: _lessonDurationMinutes,
              compensationTouched: initialSource == 'manual',
              currentRuleKey: defaults.compensationKey,
              currentTeacherMinutes: initialTeacherMinutes,
            );
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _settlementKey = defaults.settlementKey;
        _compensationKey =
            recommendation?.compensationRuleKey ?? defaults.compensationKey;
        _compensationValueController.text =
            recommendation == null || initialSource == 'manual'
            ? defaults.compensationValue
            : _recommendedCompensationInput(catalog, recommendation);
        _teacherDurationController.text =
            recommendation?.teacherCreditedDurationMinutes?.toString() ??
            initialTeacherMinutes?.toString() ??
            '';
        _teacherCompensationSource = recommendation?.source ?? initialSource;
        _compensationTouched = initialSource == 'manual';
        _clientDecisionsById
          ..clear()
          ..addAll(initialById);
        _clientSettlementKeys
          ..clear()
          ..addEntries(
            initialById.entries.map(
              (entry) => MapEntry(
                entry.key,
                entry.value['settlementTypeKey']?.toString(),
              ),
            ),
          );
        _clientDurationMinutes
          ..clear()
          ..addEntries(
            initialById.entries.map(
              (entry) => MapEntry(
                entry.key,
                lessonDecisionIntegerMinutes(
                  entry.value['chargeDurationMinutes'],
                ),
              ),
            ),
          );
        _payerIds
          ..clear()
          ..addEntries(
            initialById.entries.map(
              (entry) => MapEntry(
                entry.key,
                entry.value['payerStudentId']?.toString(),
              ),
            ),
          );
        _payerNames
          ..clear()
          ..addEntries(
            initialById.entries.map((entry) {
              final payerId = entry.value['payerStudentId']?.toString();
              return MapEntry(
                entry.key,
                payerId == null
                    ? null
                    : participants[payerId]?.name ?? 'Другой плательщик',
              );
            }),
          );
        _subscriptionIds
          ..clear()
          ..addEntries(
            initialById.entries.map(
              (entry) => MapEntry(
                entry.key,
                entry.value['subscriptionId']?.toString(),
              ),
            ),
          );
        _chargeTypes
          ..clear()
          ..addEntries(
            initialById.entries.map(
              (entry) =>
                  MapEntry(entry.key, entry.value['chargeType']?.toString()),
            ),
          );
        _preferredChargeTypes
          ..clear()
          ..addEntries(
            initialById.entries.map(
              (entry) => MapEntry(
                entry.key,
                entry.value['preferredChargeType']?.toString() ??
                    (entry.value['chargeType'] == 'subscription' ||
                            entry.value['chargeType'] == 'personal_account'
                        ? entry.value['chargeType']?.toString()
                        : null),
              ),
            ),
          );
        _subscriptions
          ..clear()
          ..addAll(initialSubscriptions);
        _clientDecisionTouched.clear();
        _clientDurationTouched.clear();
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

  void _markDirty() {
    if (_dirty) return;
    _dirty = true;
    widget.onDirtyChanged?.call(true);
  }

  Future<void> _finishSuccessfulCommit() async {
    if (!mounted) return;
    _dirty = false;
    widget.onDirtyChanged?.call(false);
    if (widget.onDirtyChanged != null) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _selectSettlement(String? value) async {
    if (value == null || value == _settlementKey) return;
    var applyRecommendation = true;
    if (widget.controller.operation == LessonDecisionOperation.cancel &&
        (_compensationTouched || _clientDecisionTouched.isNotEmpty)) {
      final choice = await _confirmSettlementRecommendation(context);
      if (!mounted || choice == null) return;
      applyRecommendation = choice;
    }
    _markDirty();
    setState(() {
      _settlementKey = value;
      final settlement = _settlement;
      if (settlement?.defaultTeacherCompensationRuleKey != null) {
        if (applyRecommendation) {
          _compensationTouched = false;
        }
        final recommendation = const LessonFinancialAutofill().apply(
          settlement: settlement!,
          durationMinutes: _lessonDurationMinutes,
          compensationTouched: !applyRecommendation && _compensationTouched,
          currentRuleKey: _compensationKey,
          currentTeacherMinutes: int.tryParse(_teacherDurationController.text),
        );
        _applyRecommendation(
          recommendation,
          preserveCompensationValue:
              !applyRecommendation && _compensationTouched,
        );
        final clientMinutes = const LessonFinancialAutofill()
            .recommendedClientMinutes(
              settlement: settlement,
              durationMinutes: _lessonDurationMinutes,
            );
        for (final participant in widget.controller.settlementClients) {
          if (applyRecommendation) {
            _clientSettlementKeys[participant.id] = null;
            _writeClientDecision(participant.id, 'settlementTypeKey', null);
          }
          final preserveClientMinutes =
              !applyRecommendation &&
              (_clientSettlementKeys[participant.id] != null ||
                  _clientDurationTouched.contains(participant.id));
          if (!preserveClientMinutes) {
            _clientDurationMinutes[participant.id] = clientMinutes;
            _writeClientDecision(
              participant.id,
              'chargeDurationMinutes',
              clientMinutes,
            );
          }
          if (applyRecommendation) {
            _applyFundingRecommendation(participant.id, settlement);
          }
        }
        if (applyRecommendation) {
          _clientDecisionTouched.clear();
          _clientDurationTouched.clear();
        }
      }
      _clearPreview();
    });
  }

  void _selectCompensation(String? key) {
    _markDirty();
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
    _markDirty();
    setState(() {
      _clientDecisionTouched.add(clientId);
      _clientSettlementKeys[clientId] = settlementKey;
      _writeClientDecision(clientId, 'settlementTypeKey', settlementKey);
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
        _writeClientDecision(
          clientId,
          'chargeDurationMinutes',
          _clientDurationMinutes[clientId],
        );
        _applyFundingRecommendation(clientId, settlement);
      }
      _clearPreview();
    });
  }

  void _selectClientDuration(String clientId, String value) {
    _markDirty();
    setState(() {
      _clientDecisionTouched.add(clientId);
      _clientDurationTouched.add(clientId);
      _clientDurationMinutes[clientId] = int.tryParse(value);
      _writeClientDecision(
        clientId,
        'chargeDurationMinutes',
        _clientDurationMinutes[clientId],
      );
      _clearPreview();
    });
  }

  void _selectTeacherDuration(String value) {
    _markDirty();
    setState(() {
      _compensationTouched = true;
      _teacherCompensationSource = 'manual';
      _clearPreview();
    });
  }

  void _changeCompensationValue(String _) {
    _markDirty();
    setState(() {
      _compensationTouched = true;
      _teacherCompensationSource = 'manual';
      _clearPreview();
    });
  }

  void _restoreRecommendation() {
    final settlement = _settlement;
    if (settlement == null) return;
    _markDirty();
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
    _markDirty();
    setState(() {
      _clientDecisionTouched.add(clientId);
      _payerIds[clientId] = payerId;
      _payerNames[clientId] = payer?.name;
      _subscriptionIds.remove(clientId);
      _subscriptions.remove(clientId);
      _loadingSubscriptions.remove(clientId);
      if (payerId != null) _loadingSubscriptions.add(clientId);
      _writeClientDecision(clientId, 'payerStudentId', payerId);
      _writeClientDecision(clientId, 'subscriptionId', null);
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
    _markDirty();
    setState(() {
      _clientDecisionTouched.add(clientId);
      _subscriptionIds[clientId] = subscriptionId;
      _writeClientDecision(clientId, 'subscriptionId', subscriptionId);
    });
    _invalidatePreview();
  }

  void _selectChargeType(String clientId, String? chargeType) {
    _markDirty();
    setState(() {
      _clientDecisionTouched.add(clientId);
      if (chargeType == 'subscription' || chargeType == 'personal_account') {
        _preferredChargeTypes[clientId] = chargeType;
      } else if (chargeType == 'none') {
        _preferredChargeTypes.remove(clientId);
      }
      _chargeTypes[clientId] = chargeType;
      _writeClientDecision(clientId, 'chargeType', chargeType);
      if (chargeType != 'subscription') {
        _subscriptionIds.remove(clientId);
        _writeClientDecision(clientId, 'subscriptionId', null);
      }
      if (chargeType == 'none') {
        _payerIds.remove(clientId);
        _payerNames.remove(clientId);
        _writeClientDecision(clientId, 'payerStudentId', null);
      }
      _clearPreview();
    });
  }

  void _writeClientDecision(String clientId, String key, Object? value) {
    final decision = _clientDecisionsById.putIfAbsent(
      clientId,
      () => <String, dynamic>{'clientId': clientId},
    );
    if (value == null) {
      decision.remove(key);
    } else {
      decision[key] = value;
    }
    if (decision.length == 1) _clientDecisionsById.remove(clientId);
  }

  void _applyFundingRecommendation(
    String clientId,
    LessonDecisionCatalogItem settlement,
  ) {
    final recommendedChargeType = settlement.clientDurationMode == 'zero'
        ? 'none'
        : _preferredChargeTypes[clientId];
    if (recommendedChargeType == null) return;
    _chargeTypes[clientId] = recommendedChargeType;
    _writeClientDecision(clientId, 'chargeType', recommendedChargeType);
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
        clientDecisions: _clientDecisionsForPreview(),
      );
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (error) {
      if (mounted) {
        final recovered = await widget.controller.recoverStaleCommit(error);
        if (mounted) {
          setState(
            () => _error = recovered ?? mapLessonTransitionFailure(error),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _clientDecisionsForPreview() => [
    for (final decision in _clientDecisions(
      widget.controller.settlementClients,
      _clientDecisionsById,
    ))
      () {
        final result = Map<String, dynamic>.from(decision);
        final clientId = result['clientId']?.toString();
        final settlement = _catalogItem(
          _catalog?.settlementTypes ?? const [],
          (clientId == null ? null : _clientSettlementKeys[clientId]) ??
              _settlementKey ??
              '',
        );
        if (clientId == null ||
            (!_clientDurationTouched.contains(clientId) &&
                settlement?.clientDurationMode != 'manual')) {
          result.remove('chargeDurationMinutes');
        }
        return result;
      }(),
  ];

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
      await _finishSuccessfulCommit();
    } catch (error) {
      if (mounted) {
        final recovered = await widget.controller.recoverStaleCommit(error);
        if (!mounted) return;
        setState(() {
          _error = recovered ?? mapLessonTransitionFailure(error);
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
      chargeTypes: _chargeTypes,
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
      onReasonChanged: (_) {
        _markDirty();
        _invalidatePreview();
      },
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
      onChargeTypeChanged: _selectChargeType,
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

Future<bool?> _confirmSettlementRecommendation(BuildContext context) =>
    showMagicAdaptiveSurface<bool>(
      context,
      kind: AppSurfaceKind.confirmation,
      title: 'Изменить тип списания?',
      builder: (surfaceContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Применить рекомендованные значения для нового типа?'),
          const SizedBox(height: AppSpace.lg),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: AppSpace.sm,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(surfaceContext, false),
                child: const Text('Оставить мои значения'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(surfaceContext, true),
                child: const Text('Применить'),
              ),
            ],
          ),
        ],
      ),
    );

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
  Map<String, Map<String, dynamic>> decisionsById,
) => [
  for (final participant in participants)
    if (decisionsById[participant.id] case final decision?)
      Map<String, dynamic>.from(decision),
];

List<LessonDecisionSubscription> _withStoredSubscription(
  List<LessonDecisionSubscription> values,
  String? storedId,
) => List.unmodifiable([
  ...values,
  if (storedId != null && !values.any((value) => value.id == storedId))
    LessonDecisionSubscription(id: storedId, label: 'Сохранённый абонемент'),
]);

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
