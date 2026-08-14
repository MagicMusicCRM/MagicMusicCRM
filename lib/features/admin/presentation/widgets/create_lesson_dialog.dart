import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/navigation/app_back_policy.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_conflicts_api.dart';
import 'package:magic_music_crm/features/admin/presentation/providers/schedule_navigation_provider.dart';

import 'lesson_decision_flow.dart';

/// Unified v4 create/edit form.
///
/// A lesson always points at exactly one typed ClientRef. Trial is an
/// independent marker, while the completion/financial/compensation snapshot is
/// chosen explicitly on create and becomes read-only on edit.
class CreateLessonDialog extends ConsumerStatefulWidget {
  final DateTime? initialDate;
  final String? initialRoomId;
  final String? initialBranchId;
  final int? initialDurationMinutes;
  final Map<String, dynamic>? lesson;
  final String? leadId;
  final String? leadName;
  final String? clientType;
  final String? clientId;
  final String? clientName;
  final bool initialIsTrial;
  final bool pageMode;

  const CreateLessonDialog({
    super.key,
    this.initialDate,
    this.initialRoomId,
    this.initialBranchId,
    this.initialDurationMinutes,
    this.lesson,
    this.leadId,
    this.leadName,
    this.clientType,
    this.clientId,
    this.clientName,
    this.initialIsTrial = false,
    this.pageMode = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    DateTime? initialDate,
    String? initialRoomId,
    String? initialBranchId,
    int? initialDurationMinutes,
    Map<String, dynamic>? lesson,
    String? leadId,
    String? leadName,
    String? clientType,
    String? clientId,
    String? clientName,
    bool initialIsTrial = false,
  }) {
    if (WorkspaceNavigationScope.maybeOf(context)?.isDesktop == true) {
      return showDialog<bool>(
        context: context,
        builder: (_) => CreateLessonDialog(
          initialDate: initialDate,
          initialRoomId: initialRoomId,
          initialBranchId: initialBranchId,
          initialDurationMinutes: initialDurationMinutes,
          lesson: lesson,
          leadId: leadId,
          leadName: leadName,
          clientType: clientType,
          clientId: clientId,
          clientName: clientName,
          initialIsTrial: initialIsTrial,
        ),
      );
    }
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        settings: const RouteSettings(name: 'lesson-editor'),
        builder: (ctx) => CreateLessonDialog(
          initialDate: initialDate,
          initialRoomId: initialRoomId,
          initialBranchId: initialBranchId,
          initialDurationMinutes: initialDurationMinutes,
          lesson: lesson,
          leadId: leadId,
          leadName: leadName,
          clientType: clientType,
          clientId: clientId,
          clientName: clientName,
          initialIsTrial: initialIsTrial,
          pageMode: true,
        ),
      ),
    );
  }

  @override
  ConsumerState<CreateLessonDialog> createState() => _CreateLessonDialogState();
}

class _CreateLessonDialogState extends ConsumerState<CreateLessonDialog> {
  final _scrollController = ScrollController(keepScrollOffset: false);
  final _compensationValueController = TextEditingController();
  final _plannedSettlementReasonController = TextEditingController();
  bool _loading = false;
  bool _saving = false;
  bool _analyzingSchedule = false;
  String? _validationMessage;
  String? _scheduleAnalysisError;
  LessonScheduleAnalysis? _scheduleAnalysis;

  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _subscriptions = [];

  Map<String, dynamic>? _selectedClient;
  String? _selectedTeacherId;
  String? _selectedBranchId;
  String? _selectedRoomId;
  String? _selectedSubscriptionId;

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _durationMinutes = 60;
  bool _isTrial = false;

  String _completionType = 'standard.success';
  String _clientChargeType = 'none';
  LessonDecisionCatalog? _decisionCatalog;
  String? _settlementTypeKey;
  String? _compensationRuleKey;
  String? _initialCompensationValueMinor;
  String? _financialBaselineRuleKey;
  String? _financialBaselineValueMinor;
  bool _financialBaselineCaptured = false;

  bool get _isEdit => widget.lesson != null;
  String? get _groupId {
    final value = widget.lesson?['group_id'] ?? widget.lesson?['groupId'];
    final id = value?.toString();
    return id == null || id.isEmpty ? null : id;
  }

  bool get _isGroupEdit => _isEdit && _groupId != null;
  String get _groupName {
    final value =
        widget.lesson?['group_name'] ?? widget.lesson?['groupName'] ?? 'Группа';
    final name = value.toString().trim();
    return name.isEmpty ? 'Группа' : name;
  }

  bool get _snapshotLocked => _isEdit;
  MagicCrmService get _crm => ref.read(magicCrmServiceProvider);
  List<int> get _durationOptions {
    final values = <int>{30, 45, 60, 90, 120, _durationMinutes}.toList()
      ..sort();
    return values;
  }

  String? get _clientType {
    final ref = _selectedClient?['ref'];
    return ref is Map ? ref['type']?.toString() : null;
  }

  String? get _clientId {
    final ref = _selectedClient?['ref'];
    return ref is Map ? ref['id']?.toString() : null;
  }

  String get _clientKey {
    final type = _clientType;
    final id = _clientId;
    return type == null || id == null ? '' : '$type:$id';
  }

  String? _clientBranchId(Map<String, dynamic>? client) {
    final value = client?['branchId'] ?? client?['branch_id'];
    final branchId = value?.toString();
    return branchId == null || branchId.isEmpty ? null : branchId;
  }

  bool _hasBranch(String? branchId) =>
      branchId != null &&
      _branches.any((branch) => branch['id']?.toString() == branchId);

  List<Map<String, dynamic>> get _eligibleTeachers {
    final branchId = _selectedBranchId;
    if (branchId == null) return const [];
    return _teachers
        .where((teacher) {
          if (teacher['status']?.toString() != 'active') return false;
          final assignments = teacher['assigned_branches'];
          return assignments is List &&
              assignments.whereType<Map>().any(
                (branch) => branch['id']?.toString() == branchId,
              );
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> get _eligibleRooms {
    final branchId = _selectedBranchId;
    if (branchId == null) return const [];
    return _rooms
        .where(
          (room) =>
              (room['branch_id'] ?? room['branchId'])?.toString() == branchId &&
              room['lifecycle_state']?.toString() != 'archived',
        )
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _isTrial = widget.initialIsTrial;
    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!;
      _selectedTime = widget.initialIsTrial
          ? const TimeOfDay(hour: 10, minute: 0)
          : TimeOfDay.fromDateTime(widget.initialDate!);
    }
    _selectedRoomId = widget.initialRoomId;
    _selectedBranchId = widget.initialBranchId;
    if (widget.initialDurationMinutes case final minutes? when minutes > 0) {
      _durationMinutes = minutes;
    }

    if (widget.clientId != null) {
      _selectedClient = _clientRow(
        type: widget.clientType == 'lead' ? 'lead' : 'student',
        id: widget.clientId!,
        label: widget.clientName ?? 'Клиент без имени',
      );
    } else if (widget.leadId != null) {
      _selectedClient = _clientRow(
        type: 'lead',
        id: widget.leadId!,
        label: widget.leadName ?? 'Лид без имени',
      );
    }

    final lesson = widget.lesson;
    if (lesson != null) {
      final leadId = lesson['lead_id']?.toString();
      final studentId = lesson['student_id']?.toString();
      if (leadId != null && leadId.isNotEmpty) {
        _selectedClient = _clientRow(
          type: 'lead',
          id: leadId,
          label: lesson['lead_name']?.toString() ?? 'Лид без имени',
        );
      } else if (studentId != null && studentId.isNotEmpty) {
        _selectedClient = _clientRow(
          type: 'student',
          id: studentId,
          label: lesson['student_name']?.toString() ?? 'Ученик без имени',
        );
      }
      _selectedTeacherId = lesson['teacher_id']?.toString();
      _selectedBranchId = lesson['branch_id']?.toString() ?? _selectedBranchId;
      _selectedRoomId = lesson['room_id']?.toString() ?? _selectedRoomId;
      _durationMinutes =
          (lesson['duration_minutes'] as num?)?.toInt() ?? _durationMinutes;
      final raw = lesson['scheduled_at']?.toString();
      final parsed = raw == null ? null : DateTime.tryParse(raw);
      if (parsed != null) {
        final local = parsed.toUtc().add(const Duration(hours: 3));
        _selectedDate = DateTime(local.year, local.month, local.day);
        _selectedTime = TimeOfDay(hour: local.hour, minute: local.minute);
      }
      _isTrial = lesson['snapshot_trial'] == true || lesson['is_trial'] == true;
      _completionType =
          lesson['completion_type']?.toString() ?? _completionType;
      _clientChargeType =
          lesson['client_charge_type']?.toString() ?? _clientChargeType;
      _selectedSubscriptionId = lesson['subscription_id']?.toString();
      _settlementTypeKey =
          (lesson['settlement_type_key'] ?? lesson['settlementTypeKey'])
              ?.toString();
      _compensationRuleKey =
          (lesson['teacher_compensation_rule_key'] ??
                  lesson['teacherCompensationRuleKey'])
              ?.toString();
      _initialCompensationValueMinor =
          (lesson['teacher_compensation_value_minor'] ??
                  lesson['teacherCompensationValueMinor'])
              ?.toString();
    }
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _compensationValueController.dispose();
    _plannedSettlementReasonController.dispose();
    super.dispose();
  }

  String get _dialogTitle => _isEdit
      ? 'Перенести или изменить занятие'
      : widget.leadId != null
      ? 'Пробное занятие'
      : 'Новое занятие';

  String get _savedMessage =>
      _isEdit ? 'Изменения занятия применены' : 'Занятие создано';

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      Map<String, dynamic>? resolvedClient;
      if (!_isEdit && _selectedClient != null) {
        try {
          resolvedClient = await _crm.resolveClientRef(
            type: _clientType!,
            id: _clientId!,
          );
        } catch (error) {
          debugPrint('Error resolving selected client: $error');
        }
      }
      final results = await Future.wait([
        _crm.listTeachers(limit: 100),
        _crm.listBranches(limit: 100),
        _crm.searchClientRefs(limit: 50),
      ]);
      if (!mounted) return;
      setState(() {
        _teachers = results[0];
        _branches = results[1];
        _clients = results[2];
        if (resolvedClient != null) {
          _selectedClient = resolvedClient;
        }
        if (_selectedClient case final selected?
            when !_clients.any(
              (row) => _clientKeyFor(row) == _clientKeyFor(selected),
            )) {
          _clients = [selected, ..._clients];
        }
        _loading = false;
      });
      final clientBranchId = _clientBranchId(_selectedClient);
      final previousBranchId = _selectedBranchId;
      final branchId = !_isEdit && _hasBranch(clientBranchId)
          ? clientBranchId
          : _hasBranch(_selectedBranchId)
          ? _selectedBranchId
          : _branches.firstOrNull?['id']?.toString();
      if (branchId != null) {
        if (mounted) {
          setState(() {
            _selectedBranchId = branchId;
            if (!_isEdit &&
                clientBranchId == branchId &&
                previousBranchId != branchId) {
              _selectedRoomId = null;
            }
            if (!_eligibleTeachers.any(
              (teacher) => teacher['id']?.toString() == _selectedTeacherId,
            )) {
              _selectedTeacherId = null;
            }
          });
        }
        await Future.wait([
          _loadRooms(branchId),
          _loadDecisionCatalog(branchId),
        ]);
      }
      await _loadSubscriptions();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка загрузки данных: $error')));
      Navigator.pop(context);
    }
  }

  Future<void> _selectClient(Map<String, dynamic> row) async {
    final branchId = _clientBranchId(row);
    final switchBranch = _hasBranch(branchId) && branchId != _selectedBranchId;
    setState(() {
      _selectedClient = row;
      if (switchBranch) {
        _selectedBranchId = branchId;
        _selectedTeacherId = null;
        _selectedRoomId = null;
        _rooms = [];
        _decisionCatalog = null;
        _settlementTypeKey = null;
        _compensationRuleKey = null;
      }
    });
    if (switchBranch) {
      await Future.wait([
        _loadRooms(branchId!),
        _loadDecisionCatalog(branchId),
      ]);
    }
    await _loadSubscriptions();
  }

  Future<void> _loadRooms(String branchId) async {
    try {
      final rooms = await _crm.listRooms(branchId: branchId, limit: 100);
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        if (_selectedRoomId != null &&
            !_eligibleRooms.any(
              (room) => room['id'].toString() == _selectedRoomId,
            )) {
          _selectedRoomId = null;
        }
      });
    } catch (error) {
      debugPrint('Error loading rooms: $error');
    }
  }

  Future<void> _loadDecisionCatalog(String branchId) async {
    final response = await ref
        .read(magicApiClientProvider)
        .get<Map<String, dynamic>>(
          '/crm/configuration/lesson-decisions',
          queryParameters: {'branchId': branchId},
        );
    if (!mounted) return;
    final catalog = LessonDecisionCatalog.fromJson(
      response,
      LessonDecisionOperation.settle,
    );
    final configuredDuration =
        (response['defaultLessonDurationMinutes'] as num?)?.toInt();
    final hasExplicitDuration =
        widget.initialDurationMinutes != null &&
        widget.initialDurationMinutes! > 0;
    setState(() {
      _decisionCatalog = catalog;
      if (!_isEdit &&
          !hasExplicitDuration &&
          configuredDuration != null &&
          configuredDuration > 0) {
        _durationMinutes = configuredDuration;
      }
      if (!catalog.settlementTypes.any(
        (item) => item.key == _settlementTypeKey,
      )) {
        _settlementTypeKey = catalog.settlementTypes.firstOrNull?.key;
      }
      if (!catalog.compensationRules.any(
        (item) => item.key == _compensationRuleKey,
      )) {
        final legacyMode = widget.lesson?['teacher_compensation_type']
            ?.toString();
        _compensationRuleKey = catalog.compensationRules
            .where((item) => item.mode == legacyMode)
            .firstOrNull
            ?.key;
        _compensationRuleKey ??= catalog.compensationRules.firstOrNull?.key;
      }
      final rule = _selectedCompensationRule;
      if (rule != null) {
        final initialValue =
            _initialCompensationValueMinor ??
            _legacyCompensationValueMinor(rule);
        _compensationValueController.text = _compensationInput(
          rule,
          valueMinor: initialValue,
        );
      } else {
        _compensationValueController.clear();
      }
      if (!_financialBaselineCaptured) {
        _financialBaselineRuleKey = _compensationRuleKey;
        _financialBaselineValueMinor = _compensationValueMinor();
        _financialBaselineCaptured = true;
      }
      if (!_isEdit) _applyFundingDefault();
    });
  }

  Future<void> _loadSubscriptions() async {
    final studentId = _clientType == 'student' ? _clientId : null;
    if (studentId == null) {
      if (mounted) {
        setState(() {
          _subscriptions = [];
          _selectedSubscriptionId = null;
          if (!_isEdit) _applyFundingDefault();
        });
      }
      return;
    }
    try {
      final rows = await _crm.listSubscriptions(
        studentId: studentId,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _subscriptions = rows
            .where((row) => row['status']?.toString() == 'active')
            .toList(growable: false);
        if (_selectedSubscriptionId != null &&
            !_subscriptions.any(
              (row) => row['id']?.toString() == _selectedSubscriptionId,
            )) {
          _selectedSubscriptionId = null;
        }
        if (!_isEdit) {
          _applyFundingDefault();
        }
      });
    } catch (error) {
      debugPrint('Error loading subscriptions: $error');
    }
  }

  void _applyFundingDefault() {
    final settlement = _decisionCatalog?.settlementTypes
        .where((item) => item.key == _settlementTypeKey)
        .firstOrNull;
    if (settlement?.hourShareBasisPoints == 0 &&
        settlement?.fixedPenaltyMinor == '0') {
      _clientChargeType = 'none';
      _selectedSubscriptionId = null;
      return;
    }
    if (_clientType == 'student' && _subscriptions.isNotEmpty) {
      _clientChargeType = 'subscription';
      _selectedSubscriptionId ??= _subscriptions.first['id']?.toString();
    } else {
      _clientChargeType = 'personal_account';
      _selectedSubscriptionId = null;
    }
  }

  bool get _selectedSettlementIsNoCharge {
    final settlement = _decisionCatalog?.settlementTypes
        .where((item) => item.key == _settlementTypeKey)
        .firstOrNull;
    return settlement?.hourShareBasisPoints == 0 &&
        settlement?.fixedPenaltyMinor == '0';
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_validationMessage != null) {
      setState(() => _validationMessage = null);
    }
    final clientId = _clientId;
    final clientType = _clientType;
    final missingSubscription =
        !_isEdit &&
        _clientChargeType == 'subscription' &&
        _selectedSubscriptionId == null;
    final invalidNoFunding =
        !_isEdit &&
        _clientChargeType == 'none' &&
        !_selectedSettlementIsNoCharge;
    final version = (widget.lesson?['version'] as num?)?.toInt();
    final compensationValueRequired = switch (_selectedCompensationRule?.mode) {
      'percent' || 'fixed' || 'hourly' => true,
      _ => false,
    };
    final compensationValueMinor = _compensationValueMinor();
    final missingCompensationValue =
        compensationValueRequired && compensationValueMinor == null;
    final missingCompensationReason =
        !_isEdit &&
        _compensationNeedsReason &&
        _plannedSettlementReasonController.text.trim().isEmpty;

    final missingClient =
        !_isGroupEdit && (clientId == null || clientType == null);
    if (missingClient ||
        _selectedTeacherId == null ||
        _selectedBranchId == null ||
        _selectedRoomId == null ||
        missingSubscription ||
        invalidNoFunding ||
        (!_isEdit && _settlementTypeKey == null) ||
        (!_isEdit && _compensationRuleKey == null) ||
        missingCompensationValue ||
        missingCompensationReason ||
        (_isEdit && version == null)) {
      setState(() {
        _validationMessage = _isEdit && version == null
            ? 'Обновите расписание: версия занятия не получена'
            : missingCompensationValue
            ? 'Введите корректный процент или сумму оплаты преподавателю'
            : missingCompensationReason
            ? 'Укажите причину индивидуального значения оплаты преподавателю'
            : invalidNoFunding
            ? 'Для платного списания выберите абонемент или личный счёт'
            : 'Заполните обязательные поля корректно';
      });
      return;
    }

    final startsAt = DateTime.utc(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour - 3,
      _selectedTime.minute,
    );
    final payload = _lessonPayload(scheduledAt: startsAt.toIso8601String());
    final scheduleChanged = _isEdit && _hasScheduleChanges(payload);
    final financialChanged = _isEdit && _hasFinancialDecisionChanges;
    if (_isEdit && !scheduleChanged && !financialChanged) {
      setState(() {
        _validationMessage =
            'Измените параметры расписания или оплату преподавателю';
      });
      return;
    }

    setState(() => _saving = true);
    try {
      final api = ref.read(magicApiClientProvider);
      if (_isEdit) {
        final operation = scheduleChanged
            ? LessonDecisionOperation.reschedule
            : _financialEditOperation;
        final changed = await showLessonDecisionFlow(
          context,
          api: api,
          operation: operation,
          lesson: widget.lesson!,
          successor: scheduleChanged ? payload : null,
          initialSettlementTypeKey: _settlementTypeKey,
          initialCompensationRuleKey: _compensationRuleKey,
          initialCompensationValueMinor: compensationValueMinor,
        );
        if (changed != true || !mounted) return;
        Navigator.pop(context, true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_savedMessage)));
        return;
      }

      final canSave = await _previewConstraintsBeforeSave(
        startsAt,
        clientType!,
        clientId!,
      );
      if (!canSave || !mounted) return;
      try {
        await api.createLessonRaw(payload);
      } on MagicApiException catch (error) {
        final violations = lessonConstraintViolations(error);
        if (violations == null || violations.isEmpty) rethrow;
        if (mounted) {
          setState(() {
            _scheduleAnalysis = LessonScheduleAnalysis.fromViolations(
              violations,
            );
          });
          await _showConstraintViolations(violations);
        }
        return;
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_savedMessage)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _lessonPayload({required String scheduledAt}) {
    final compensationValueMinor = _compensationValueMinor();
    final mutable = <String, dynamic>{
      'teacherId': _selectedTeacherId,
      'branchId': _selectedBranchId,
      'roomId': _selectedRoomId,
      'scheduledAt': scheduledAt,
      'durationMinutes': _durationMinutes,
    };
    if (_isEdit) {
      return mutable;
    }
    return {
      ...mutable,
      'clientRef': {'type': _clientType, 'id': _clientId},
      'isTrial': _isTrial,
      'completionType': _completionType,
      'clientChargeType': _clientChargeType,
      'clientChargeValue': _derivedClientChargeValue,
      'teacherCompensationType': _derivedTeacherRate.$1,
      'teacherCompensationValue': _derivedTeacherRate.$2,
      'financialDecision': {
        'settlementTypeKey': _settlementTypeKey,
        'teacherCompensationRuleKey': _compensationRuleKey,
        'teacherCompensationValueMinor': ?compensationValueMinor,
      },
      if (_compensationNeedsReason)
        'plannedSettlementReason': _plannedSettlementReasonController.text
            .trim(),
      if (_clientChargeType == 'subscription')
        'subscriptionId': _selectedSubscriptionId,
      if (_clientType == 'lead' && widget.leadName?.trim().isNotEmpty == true)
        'notes': 'Занятие по лиду: ${widget.leadName!.trim()}',
    };
  }

  bool _hasScheduleChanges(Map<String, dynamic> successor) {
    final lesson = widget.lesson;
    if (lesson == null) return true;
    String? value(String snake, String camel) {
      final raw = lesson[snake] ?? lesson[camel];
      final text = raw?.toString();
      return text == null || text.isEmpty ? null : text;
    }

    final currentStartsAt = DateTime.tryParse(
      value('scheduled_at', 'scheduledAt') ?? '',
    )?.toUtc();
    final nextStartsAt = DateTime.tryParse(
      successor['scheduledAt']?.toString() ?? '',
    )?.toUtc();
    final currentDuration =
        (lesson['duration_minutes'] ?? lesson['durationMinutes']) as num?;
    final teacherChanged =
        successor['teacherId']?.toString() != value('teacher_id', 'teacherId');
    final branchChanged =
        successor['branchId']?.toString() != value('branch_id', 'branchId');
    final roomChanged =
        successor['roomId']?.toString() != value('room_id', 'roomId');
    final scheduledChanged =
        currentStartsAt == null ||
        nextStartsAt == null ||
        !currentStartsAt.isAtSameMomentAs(nextStartsAt);
    final durationChanged =
        (successor['durationMinutes'] as num?)?.toInt() !=
        currentDuration?.toInt();
    return teacherChanged ||
        branchChanged ||
        roomChanged ||
        scheduledChanged ||
        durationChanged;
  }

  LessonDecisionOperation get _financialEditOperation {
    final state =
        (widget.lesson?['lifecycle_state'] ??
                widget.lesson?['lifecycleState'] ??
                widget.lesson?['status'])
            ?.toString()
            .toLowerCase();
    return state == 'successfully_completed' ||
            state == 'completed' ||
            state == 'done'
        ? LessonDecisionOperation.correction
        : LessonDecisionOperation.plannedSettlement;
  }

  bool get _hasFinancialDecisionChanges =>
      _compensationRuleKey != _financialBaselineRuleKey ||
      _compensationValueMinor() != _financialBaselineValueMinor;

  num get _derivedClientChargeValue {
    if (_clientChargeType == 'subscription') {
      return _durationMinutes / 60;
    }
    if (_clientChargeType != 'personal_account') return 0;
    final source = _subscriptions.firstWhere(
      (row) => row['id']?.toString() == _selectedSubscriptionId,
      orElse: () => _subscriptions.firstOrNull ?? const {},
    );
    final price = source['package_price'];
    final units = source['lessons_total'];
    if (price is! num || units is! num || units <= 0) return 0;
    return price / units * (_durationMinutes / 60);
  }

  (String, num) get _derivedTeacherRate {
    final teacher = _teachers.firstWhere(
      (row) => row['id']?.toString() == _selectedTeacherId,
      orElse: () => const {},
    );
    final rate = teacher['current_rate'];
    return rate is num && rate > 0 ? ('hourly', rate) : ('none', 0);
  }

  LessonDecisionCatalogItem? get _selectedSettlementType => _decisionCatalog
      ?.settlementTypes
      .where((item) => item.key == _settlementTypeKey)
      .firstOrNull;

  LessonDecisionCatalogItem? get _selectedCompensationRule => _decisionCatalog
      ?.compensationRules
      .where((item) => item.key == _compensationRuleKey)
      .firstOrNull;

  void _selectCompensationRule(String? key) {
    setState(() {
      _compensationRuleKey = key;
      final rule = _selectedCompensationRule;
      _compensationValueController.text = rule == null
          ? ''
          : _compensationInput(rule);
      _plannedSettlementReasonController.clear();
    });
  }

  String? _legacyCompensationValueMinor(LessonDecisionCatalogItem rule) {
    if (!_isEdit || (rule.mode != 'fixed' && rule.mode != 'hourly')) {
      return null;
    }
    final value = widget.lesson?['teacher_compensation_value'];
    if (value is! num || value < 0) return null;
    return (value * 100).round().toString();
  }

  String _compensationInput(
    LessonDecisionCatalogItem rule, {
    String? valueMinor,
  }) {
    final value = BigInt.tryParse(valueMinor ?? rule.value) ?? BigInt.zero;
    if (rule.mode == 'percent') {
      final whole = value ~/ BigInt.from(100);
      final fraction = (value % BigInt.from(100)).toString().padLeft(2, '0');
      return fraction == '00' ? '$whole' : '$whole,$fraction';
    }
    final whole = value ~/ BigInt.from(100);
    final fraction = (value % BigInt.from(100)).toString().padLeft(2, '0');
    return fraction == '00' ? '$whole' : '$whole,$fraction';
  }

  String? _compensationValueMinor() {
    final mode = _selectedCompensationRule?.mode;
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

  bool get _compensationNeedsReason {
    final rule = _selectedCompensationRule;
    final value = _compensationValueMinor();
    return rule != null && value != null && value != rule.value;
  }

  String _snapshotNumber(num value) =>
      NumberFormat('#,##0.##', 'ru').format(value);

  String get _clientSnapshotValue => switch (_clientChargeType) {
    'subscription' => '${_snapshotNumber(_derivedClientChargeValue)} ч',
    'personal_account' => '${_snapshotNumber(_derivedClientChargeValue)} ₽',
    _ => '0 ₽',
  };

  String get _teacherSnapshotValue {
    final rule = _selectedCompensationRule;
    if (rule == null) return 'Не выбрано';
    if (rule.mode == 'none') return '0 ₽';
    if (rule.mode == 'standard') {
      final rate = _derivedTeacherRate;
      return rate.$1 == 'none'
          ? 'Стандартная ставка преподавателя · 0 ₽'
          : 'Стандартная ставка преподавателя · '
                '${_snapshotNumber(rate.$2)} ₽/ч';
    }
    final input = _compensationValueController.text.trim();
    if (rule.mode == 'percent') return '$input% от стандартной ставки';
    if (rule.mode == 'hourly') return '$input ₽/ч';
    return '$input ₽ за занятие';
  }

  Future<bool> _previewConstraintsBeforeSave(
    DateTime startsAt,
    String clientType,
    String clientId,
  ) async {
    try {
      final analysis = await ref
          .read(magicApiClientProvider)
          .analyzeLessonSchedule(
            clientType: clientType,
            clientId: clientId,
            teacherId: _selectedTeacherId!,
            branchId: _selectedBranchId!,
            roomId: _selectedRoomId!,
            scheduledAt: startsAt.toIso8601String(),
            durationMinutes: _durationMinutes,
            excludeLessonId: _isEdit ? widget.lesson!['id']?.toString() : null,
          );
      if (mounted) {
        setState(() {
          _scheduleAnalysis = analysis;
          _scheduleAnalysisError = null;
        });
      }
      if (analysis.valid) return true;
      if (!mounted) return false;
      await _showConstraintViolations(analysis.violations);
      return false;
    } catch (error) {
      // The write repeats the same engine inside its transaction and still
      // fails closed if this read-only preview is temporarily unavailable.
      debugPrint('Schedule constraints preview failed: $error');
      return true;
    }
  }

  Future<void> _analyzeCurrentSchedule() async {
    final clientType = _clientType;
    final clientId = _clientId;
    if (clientType == null ||
        clientId == null ||
        _selectedTeacherId == null ||
        _selectedBranchId == null ||
        _selectedRoomId == null) {
      setState(() {
        _scheduleAnalysisError =
            'Выберите клиента, филиал, преподавателя и аудиторию.';
      });
      return;
    }
    final startsAt = DateTime.utc(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour - 3,
      _selectedTime.minute,
    );
    setState(() {
      _analyzingSchedule = true;
      _scheduleAnalysisError = null;
    });
    try {
      final analysis = await ref
          .read(magicApiClientProvider)
          .analyzeLessonSchedule(
            clientType: clientType,
            clientId: clientId,
            teacherId: _selectedTeacherId!,
            branchId: _selectedBranchId!,
            roomId: _selectedRoomId!,
            scheduledAt: startsAt.toIso8601String(),
            durationMinutes: _durationMinutes,
            excludeLessonId: _isEdit ? widget.lesson!['id']?.toString() : null,
          );
      if (mounted) setState(() => _scheduleAnalysis = analysis);
    } catch (error) {
      if (mounted) setState(() => _scheduleAnalysisError = '$error');
    } finally {
      if (mounted) setState(() => _analyzingSchedule = false);
    }
  }

  Future<void> _applyScheduleSuggestion(ScheduleSuggestion suggestion) async {
    setState(() {
      if (suggestion.roomId != null) _selectedRoomId = suggestion.roomId;
      if (suggestion.teacherId != null) {
        _selectedTeacherId = suggestion.teacherId;
      }
      if (suggestion.startAt != null) {
        final start = suggestion.startAt!;
        _selectedDate = DateTime(start.year, start.month, start.day);
        _selectedTime = TimeOfDay(hour: start.hour, minute: start.minute);
      }
      _scheduleAnalysis = null;
      _scheduleAnalysisError = null;
    });
    await _analyzeCurrentSchedule();
  }

  Widget _scheduleConflictInspector() {
    final analysis = _scheduleAnalysis;
    final cs = Theme.of(context).colorScheme;
    if (analysis == null && _scheduleAnalysisError == null) {
      return const SizedBox.shrink();
    }
    final valid = analysis?.valid == true;
    return Container(
      key: const ValueKey('lesson-conflict-inspector'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: valid
            ? AppColor.success.withValues(alpha: 0.10)
            : AppColor.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: (valid ? AppColor.success : AppColor.danger).withValues(
            alpha: 0.35,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            valid
                ? 'Schedule Analyzer: конфликтов нет'
                : 'Schedule Analyzer: найдены конфликты',
            style: TextStyle(
              color: valid ? AppColor.success : cs.error,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (_scheduleAnalysisError != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text('Не удалось выполнить проверку: $_scheduleAnalysisError'),
          ],
          for (final violation in analysis?.violations ?? const [])
            _violationCard(
              title: violation.title,
              resource: '${violation.resourceLabel}: ${violation.resourceId}',
              lessonIds: violation.conflictingLessonIds,
            ),
          if ((analysis?.suggestions ?? const []).isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            const Text(
              'Подходящие варианты',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpace.sm),
            for (final suggestion in analysis!.suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: OutlinedButton(
                  key: ValueKey('lesson-suggestion-${suggestion.rank}'),
                  onPressed: _analyzingSchedule
                      ? null
                      : () => _applyScheduleSuggestion(suggestion),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_scheduleSuggestionLabel(suggestion)),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _scheduleSuggestionLabel(ScheduleSuggestion suggestion) {
    final details = <String>[
      if (suggestion.roomName != null) suggestion.roomName!,
      if (suggestion.teacherName != null) suggestion.teacherName!,
      if (suggestion.startAt != null)
        DateFormat('dd.MM · HH:mm', 'ru').format(suggestion.startAt!),
    ];
    return '№${suggestion.rank} · ${suggestion.title}'
        '${details.isEmpty ? '' : ' · ${details.join(' · ')}'}';
  }

  Future<void> _showConstraintViolations(
    List<LessonConstraintViolation> violations,
  ) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.rule_rounded, color: AppColor.danger),
        title: const Text('Занятие не сохранено'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Исправьте все ограничения расписания перед сохранением:',
              ),
              const SizedBox(height: 12),
              for (final violation in violations)
                _violationCard(
                  title: violation.title,
                  resource:
                      '${violation.resourceLabel}: ${violation.resourceId}',
                  lessonIds: violation.conflictingLessonIds,
                  dialogContext: ctx,
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Исправить'),
          ),
        ],
      ),
    );
  }

  Widget _violationCard({
    required String title,
    required String resource,
    required List<String> lessonIds,
    BuildContext? dialogContext,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColor.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.danger.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(resource, style: const TextStyle(fontSize: 12)),
          if (lessonIds.isNotEmpty)
            Wrap(
              spacing: 4,
              children: [
                for (final lessonId in lessonIds)
                  EntityLinkText(
                    key: ValueKey('conflict-lesson-$lessonId'),
                    onPressed: () {
                      ref
                          .read(scheduleNavigationProvider.notifier)
                          .focus(_selectedDate, lessonId);
                      if (dialogContext != null) Navigator.pop(dialogContext);
                      Navigator.pop(context);
                    },
                    text:
                        'Занятие ${lessonId.length <= 8 ? lessonId : lessonId.substring(0, 8)}',
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      const loading = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryGold),
            SizedBox(height: 16),
            Text('Загрузка данных...'),
          ],
        ),
      );
      return widget.pageMode
          ? Scaffold(
              appBar: AppBar(title: Text(_dialogTitle)),
              body: const SafeArea(top: false, child: loading),
            )
          : const AlertDialog(content: loading);
    }

    final width = MediaQuery.sizeOf(context).width;
    final dialog = AlertDialog(
      insetPadding: widget.pageMode ? EdgeInsets.zero : null,
      shape: widget.pageMode
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
          : null,
      title: Row(
        children: [
          if (widget.pageMode) ...[
            const AppBackButton(),
            const SizedBox(width: AppSpace.sm),
          ],
          Expanded(child: Text(_dialogTitle)),
        ],
      ),
      contentPadding: widget.pageMode
          ? const EdgeInsets.fromLTRB(16, 12, 16, 0)
          : null,
      content: SizedBox(
        width: widget.pageMode
            ? double.maxFinite
            : width > 760
            ? 680
            : width - 80,
        height: widget.pageMode ? double.maxFinite : null,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isGroupEdit)
                InputDecorator(
                  key: const ValueKey('lesson-group-field'),
                  decoration: const InputDecoration(
                    labelText: 'Группа *',
                    enabled: false,
                    helperText:
                        'Группа и замороженный состав сохраняются при переносе',
                  ),
                  child: Text(_groupName),
                )
              else
                SearchablePickerField(
                  key: const ValueKey('lesson-client-field'),
                  label: 'Клиент *',
                  placeholder: 'Не выбран',
                  hintText: 'Введите имя или ФИО клиента',
                  selectedId: _clientKey,
                  selectedLabel: _selectedClient == null
                      ? null
                      : '${_selectedClient!['label']} · ${_clientType == 'lead' ? 'Lead' : 'Student'}',
                  items: [for (final row in _clients) _clientItem(row)],
                  onSearch: (query) async {
                    final rows = await _crm.searchClientRefs(
                      q: query,
                      limit: 50,
                    );
                    return [for (final row in rows) _clientItem(row)];
                  },
                  isNullable: false,
                  enabled:
                      !_snapshotLocked &&
                      widget.leadId == null &&
                      widget.clientId == null,
                  onSelected: (item) {
                    final row = item?.data;
                    if (row == null) return;
                    _selectClient(row);
                  },
                ),
              const SizedBox(height: 16),
              _responsivePair(
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  key: ValueKey('lesson-branch-field:$_selectedBranchId'),
                  initialValue: _selectedBranchId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Филиал *'),
                  items: [
                    for (final branch in _branches)
                      DropdownMenuItem(
                        value: branch['id'].toString(),
                        child: Text(branch['name']?.toString() ?? '—'),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedBranchId = value;
                      if (!_eligibleTeachers.any(
                        (teacher) =>
                            teacher['id']?.toString() == _selectedTeacherId,
                      )) {
                        _selectedTeacherId = null;
                      }
                      _selectedRoomId = null;
                      _rooms = [];
                      _decisionCatalog = null;
                      _settlementTypeKey = null;
                      _compensationRuleKey = null;
                    });
                    if (value != null) {
                      _loadRooms(value);
                      _loadDecisionCatalog(value);
                    }
                  },
                ),
                SearchablePickerField(
                  key: const ValueKey('lesson-room-field'),
                  label: 'Аудитория *',
                  placeholder: _eligibleRooms.isEmpty
                      ? 'Нет аудиторий в филиале'
                      : 'Выберите аудиторию',
                  enabled: _eligibleRooms.isNotEmpty,
                  selectedId: _selectedRoomId,
                  items: [
                    for (final room in _eligibleRooms)
                      SearchableSelectItem(
                        id: room['id'].toString(),
                        label: room['name']?.toString() ?? '—',
                        subtitle: 'Аудитория выбранного филиала',
                      ),
                  ],
                  onSelected: (item) =>
                      setState(() => _selectedRoomId = item?.id),
                ),
              ),
              const SizedBox(height: 16),
              SearchablePickerField(
                key: const ValueKey('lesson-teacher-field'),
                label: 'Преподаватель *',
                placeholder: 'Выберите преподавателя',
                hintText: 'Введите имя или ФИО преподавателя',
                selectedId: _selectedTeacherId,
                selectedLabel: _selectedTeacherId == null
                    ? null
                    : _getTeacherName(_selectedTeacherId),
                items: [
                  for (final teacher in _eligibleTeachers)
                    SearchableSelectItem(
                      id: teacher['id'].toString(),
                      label: _getTeacherNameFromData(teacher),
                      subtitle: 'Назначен в выбранный филиал',
                    ),
                ],
                isNullable: false,
                enabled: _eligibleTeachers.isNotEmpty,
                onSelected: (item) =>
                    setState(() => _selectedTeacherId = item?.id),
              ),
              if (_selectedBranchId != null && _eligibleTeachers.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'В выбранный филиал не назначен ни один активный преподаватель.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_selectedBranchId != null) ...[
                const SizedBox(height: 8),
                Text(
                  key: const ValueKey('lesson-replacement-availability-hint'),
                  'Показаны только активные преподаватели и аудитории '
                  'выбранного филиала. Занятость на выбранное время '
                  'проверяется перед сохранением; конфликт будет показан '
                  'с причиной.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _responsivePair(_dateButton(), _timeButton()),
              const SizedBox(height: 16),
              KeyedSubtree(
                key: ValueKey('lesson-duration-selection-$_durationMinutes'),
                child: DropdownButtonFormField<int>(
                  menuMaxHeight: 256,
                  key: const ValueKey('lesson-duration-field'),
                  initialValue: _durationMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Длительность *',
                  ),
                  items: [
                    for (final minutes in _durationOptions)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text('$minutes мин'),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _durationMinutes = value ?? 60),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              OutlinedButton.icon(
                key: const ValueKey('lesson-run-schedule-analyzer'),
                onPressed: _analyzingSchedule ? null : _analyzeCurrentSchedule,
                icon: _analyzingSchedule
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.rule_rounded),
                label: Text(
                  _analyzingSchedule
                      ? 'Проверяем расписание…'
                      : 'Проверить конфликты и варианты',
                ),
              ),
              if (!_saving &&
                  (_scheduleAnalysis != null ||
                      _scheduleAnalysisError != null)) ...[
                const SizedBox(height: AppSpace.md),
                _scheduleConflictInspector(),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('lesson-trial-toggle'),
                value: _isTrial,
                activeThumbColor: AppTheme.primaryGold,
                contentPadding: EdgeInsets.zero,
                title: const Text('Пробное занятие'),
                subtitle: Text(
                  _snapshotLocked
                      ? 'Маркер зафиксирован при создании'
                      : 'Не зависит от типа клиента и способа списания',
                ),
                onChanged: _snapshotLocked
                    ? null
                    : (value) => setState(() => _isTrial = value),
              ),
              const Divider(height: 28),
              Text(
                'Результат и расчёты',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (_snapshotLocked)
                InputDecorator(
                  key: const ValueKey('lesson-completion-type-field'),
                  decoration: const InputDecoration(
                    labelText: 'Автозавершение *',
                    enabled: false,
                    helperText: 'Результат зафиксирован при создании',
                  ),
                  child: Text(
                    _completionType == 'standard.success'
                        ? 'Успешно завершить'
                        : _completionType,
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  key: const ValueKey('lesson-completion-type-field'),
                  initialValue: _completionType,
                  decoration: const InputDecoration(
                    labelText: 'Автозавершение *',
                    helperText:
                        'Результат формируется сервером после окончания',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'standard.success',
                      child: Text('Успешно завершить'),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _completionType = value ?? 'standard.success',
                  ),
                ),
              const SizedBox(height: 16),
              _responsivePair(
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  key: const ValueKey('lesson-settlement-type-field'),
                  initialValue: _settlementTypeKey,
                  decoration: const InputDecoration(
                    labelText: 'Тип списания *',
                    helperText: 'Выбирается до назначения занятия',
                  ),
                  items: [
                    for (final item
                        in _decisionCatalog?.settlementTypes ?? const [])
                      DropdownMenuItem(
                        value: item.key,
                        child: Text(item.label),
                      ),
                  ],
                  onChanged: _snapshotLocked
                      ? null
                      : (value) => setState(() {
                          _settlementTypeKey = value;
                          _applyFundingDefault();
                        }),
                ),
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  key: const ValueKey('lesson-compensation-rule-field'),
                  initialValue: _compensationRuleKey,
                  decoration: const InputDecoration(
                    labelText: 'Правило оплаты преподавателю *',
                    helperText:
                        'Значение можно задать отдельно для этого занятия',
                  ),
                  items: [
                    for (final item
                        in _decisionCatalog?.compensationRules ?? const [])
                      DropdownMenuItem(
                        value: item.key,
                        child: Text(item.label),
                      ),
                  ],
                  onChanged: _saving ? null : _selectCompensationRule,
                ),
              ),
              if (_selectedCompensationRule case final rule?
                  when rule.mode == 'percent' ||
                      rule.mode == 'fixed' ||
                      rule.mode == 'hourly') ...[
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('lesson-compensation-value-field'),
                  controller: _compensationValueController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,. ]')),
                  ],
                  decoration: InputDecoration(
                    labelText: rule.mode == 'percent'
                        ? 'Процент от стандартной ставки, % *'
                        : rule.mode == 'hourly'
                        ? 'Почасовая ставка, ₽ *'
                        : 'Фиксированная сумма за занятие, ₽ *',
                    helperText: 'Действует только для этого занятия',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (!_isEdit && _compensationNeedsReason) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey(
                      'lesson-compensation-override-reason-field',
                    ),
                    controller: _plannedSettlementReasonController,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Причина индивидуального значения *',
                      helperText:
                          'Сохраняется в истории расчёта и нужна только при отклонении от настройки школы',
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                menuMaxHeight: 256,
                key: const ValueKey('lesson-charge-type-field'),
                initialValue: _clientChargeType,
                decoration: const InputDecoration(
                  labelText: 'Источник средств *',
                  helperText: 'Сумму и долю определяет выбранный тип списания',
                ),
                items: [
                  if (_clientType == 'student' &&
                      (_subscriptions.isNotEmpty ||
                          _clientChargeType == 'subscription'))
                    const DropdownMenuItem(
                      value: 'subscription',
                      child: Text('С абонемента'),
                    ),
                  const DropdownMenuItem(
                    value: 'personal_account',
                    child: Text('С личного счёта'),
                  ),
                  if (_selectedSettlementIsNoCharge ||
                      (_snapshotLocked && _clientChargeType == 'none'))
                    const DropdownMenuItem(
                      value: 'none',
                      child: Text('Без списания'),
                    ),
                ],
                onChanged: _snapshotLocked
                    ? null
                    : (value) => setState(() {
                        _clientChargeType = value ?? 'none';
                        if (_clientChargeType == 'subscription') {
                          _selectedSubscriptionId ??= _subscriptions
                              .firstOrNull?['id']
                              ?.toString();
                        }
                      }),
              ),
              if (_clientChargeType == 'subscription') ...[
                const SizedBox(height: 16),
                SearchablePickerField(
                  label: 'Абонемент *',
                  placeholder: _subscriptions.isEmpty
                      ? 'Нет активных абонементов'
                      : 'Выберите абонемент',
                  enabled: !_snapshotLocked && _subscriptions.isNotEmpty,
                  selectedId: _selectedSubscriptionId,
                  items: [
                    for (final subscription in _subscriptions)
                      SearchableSelectItem(
                        id: subscription['id'].toString(),
                        label: _subscriptionLabel(subscription),
                      ),
                  ],
                  onSelected: (item) =>
                      setState(() => _selectedSubscriptionId = item?.id),
                ),
              ],
              if (!_snapshotLocked) ...[
                const SizedBox(height: 16),
                _buildSnapshotPreview(),
              ],
              if (_snapshotLocked) ...[
                const SizedBox(height: 10),
                Text(
                  '${_isGroupEdit ? 'Группа, состав участников' : 'Клиент'}, '
                  'пробный маркер и клиентское списание неизменяемы. '
                  'Ресурсы, время и оплата преподавателю меняются здесь; '
                  'перед применением потребуется причина и подтверждение.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_validationMessage case final message?) ...[
                const SizedBox(height: AppSpace.md),
                Container(
                  key: const ValueKey('lesson-form-validation-error'),
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(
                    color: AppColor.dangerSoft,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(
                      color: AppColor.danger.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'Перейти к расчёту' : 'Создать'),
        ),
      ],
    );
    return widget.pageMode ? SafeArea(child: dialog) : dialog;
  }

  Widget _buildSnapshotPreview() {
    final cs = Theme.of(context).colorScheme;
    final clientLabel = _selectedSettlementType?.label ?? 'Не выбран';
    final compensationLabel = _selectedCompensationRule?.label ?? 'Не выбрано';
    return Container(
      key: const ValueKey('lesson-snapshot-preview'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.gold.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Расчётный snapshot перед созданием',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Проверьте значения: после создания они сохранятся вместе с '
            'занятием и не изменятся при переносе.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.md),
          _snapshotPreviewRow(
            key: const ValueKey('lesson-snapshot-trial'),
            label: 'Тип занятия',
            value: _isTrial ? 'Пробное' : 'Обычное',
          ),
          _snapshotPreviewRow(
            key: const ValueKey('lesson-snapshot-client-charge'),
            label: 'Списание клиента',
            value: '$clientLabel · $_clientSnapshotValue',
          ),
          _snapshotPreviewRow(
            key: const ValueKey('lesson-snapshot-teacher-compensation'),
            label: 'Оплата преподавателю',
            value: '$compensationLabel · $_teacherSnapshotValue',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _snapshotPreviewRow({
    required Key key,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      key: key,
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _responsivePair(Widget first, Widget second) {
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

  Widget _dateButton() {
    return OutlinedButton.icon(
      key: const ValueKey('lesson-date-field'),
      onPressed: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime.now().subtract(const Duration(days: 30)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date != null) setState(() => _selectedDate = date);
      },
      icon: const Icon(Icons.calendar_today_rounded, size: 18),
      label: Text(DateFormat('dd.MM.yyyy', 'ru').format(_selectedDate)),
    );
  }

  Widget _timeButton() {
    return OutlinedButton.icon(
      key: const ValueKey('lesson-time-field'),
      onPressed: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: _selectedTime,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
        if (time != null) setState(() => _selectedTime = time);
      },
      icon: const Icon(Icons.access_time_rounded, size: 18),
      label: Text(_selectedTime.format(context)),
    );
  }

  SearchableSelectItem _clientItem(Map<String, dynamic> row) {
    final type = _clientTypeFor(row);
    return SearchableSelectItem(
      id: _clientKeyFor(row),
      label: row['label']?.toString() ?? 'Клиент без имени',
      subtitle: type == 'lead' ? 'Lead' : 'Student',
      data: row,
    );
  }

  Map<String, dynamic> _clientRow({
    required String type,
    required String id,
    required String label,
  }) => {
    'ref': {'type': type, 'id': id},
    'label': label,
    'lifecycleState': 'active',
    'tombstone': false,
  };

  String _clientTypeFor(Map<String, dynamic> row) {
    final ref = row['ref'];
    return ref is Map ? ref['type']?.toString() ?? '' : '';
  }

  String _clientKeyFor(Map<String, dynamic> row) {
    final ref = row['ref'];
    if (ref is! Map) return '';
    return '${ref['type']}:${ref['id']}';
  }

  String _getTeacherName(String? id) {
    if (id == null) return 'Не выбран';
    final teacher = _teachers.firstWhere(
      (row) => row['id'].toString() == id,
      orElse: () => const {},
    );
    return teacher.isEmpty ? 'Не выбран' : _getTeacherNameFromData(teacher);
  }

  String _getTeacherNameFromData(Map<String, dynamic> teacher) {
    final profile = teacher['profiles'];
    var name = '${teacher['first_name'] ?? ''} ${teacher['last_name'] ?? ''}'
        .trim();
    if (name.isEmpty && profile is Map) {
      name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
          .trim();
    }
    return name.isEmpty ? 'Без имени' : name;
  }

  String _subscriptionLabel(Map<String, dynamic> subscription) {
    final name = subscription['package_name']?.toString().trim();
    final total = subscription['lessons_total'];
    final used = subscription['lessons_used'];
    final balance = total is num && used is num ? total - used : null;
    return [
      if (name != null && name.isNotEmpty) name else 'Абонемент',
      if (balance != null) 'остаток $balance',
    ].join(' · ');
  }
}
