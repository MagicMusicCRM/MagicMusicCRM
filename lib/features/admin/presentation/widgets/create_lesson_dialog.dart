import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  bool _loading = false;
  bool _saving = false;

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

  bool get _isEdit => widget.lesson != null;
  bool get _snapshotLocked => _isEdit;
  MagicCrmService get _crm => ref.read(magicCrmServiceProvider);

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
    }
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String get _dialogTitle => _isEdit
      ? 'Редактировать занятие'
      : widget.leadId != null
      ? 'Пробное занятие'
      : 'Новое занятие';

  String get _savedMessage => _isEdit ? 'Занятие обновлено' : 'Занятие создано';

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
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
        if (_selectedClient case final selected?
            when !_clients.any(
              (row) => _clientKeyFor(row) == _clientKeyFor(selected),
            )) {
          _clients = [selected, ..._clients];
        }
        _loading = false;
      });
      final branchId =
          _selectedBranchId ?? _branches.firstOrNull?['id']?.toString();
      if (branchId != null) {
        if (mounted) {
          setState(() {
            _selectedBranchId ??= branchId;
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

  Future<void> _loadRooms(String branchId) async {
    try {
      final rooms = await _crm.listRooms(branchId: branchId, limit: 100);
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        if (_selectedRoomId != null &&
            !_rooms.any((room) => room['id'].toString() == _selectedRoomId)) {
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
    setState(() {
      _decisionCatalog = catalog;
      if (!catalog.settlementTypes.any(
        (item) => item.key == _settlementTypeKey,
      )) {
        _settlementTypeKey = catalog.settlementTypes.firstOrNull?.key;
      }
      if (!catalog.compensationRules.any(
        (item) => item.key == _compensationRuleKey,
      )) {
        _compensationRuleKey = catalog.compensationRules.firstOrNull?.key;
      }
      _applyFundingDefault();
    });
  }

  Future<void> _loadSubscriptions() async {
    final studentId = _clientType == 'student' ? _clientId : null;
    if (studentId == null) {
      if (mounted) {
        setState(() {
          _subscriptions = [];
          _selectedSubscriptionId = null;
          _clientChargeType = 'none';
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
    } else if (_clientType == 'student') {
      _clientChargeType = 'personal_account';
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final clientId = _clientId;
    final clientType = _clientType;
    final missingSubscription =
        !_isEdit &&
        _clientChargeType == 'subscription' &&
        _selectedSubscriptionId == null;
    final version = (widget.lesson?['version'] as num?)?.toInt();

    if (clientId == null ||
        clientType == null ||
        _selectedTeacherId == null ||
        _selectedBranchId == null ||
        _selectedRoomId == null ||
        missingSubscription ||
        (!_isEdit && _settlementTypeKey == null) ||
        (!_isEdit && _compensationRuleKey == null) ||
        (_isEdit && version == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEdit && version == null
                ? 'Обновите расписание: версия занятия не получена'
                : 'Заполните обязательные поля корректно',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final startsAt = DateTime.utc(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour - 3,
        _selectedTime.minute,
      );
      final payload = _lessonPayload(scheduledAt: startsAt.toIso8601String());
      final api = ref.read(magicApiClientProvider);
      if (_isEdit) {
        final changed = await showLessonDecisionFlow(
          context,
          api: api,
          operation: LessonDecisionOperation.reschedule,
          lesson: widget.lesson!,
          successor: payload,
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
        clientType,
        clientId,
      );
      if (!canSave || !mounted) return;
      try {
        await api.createLessonRaw(payload);
      } on MagicApiException catch (error) {
        final violations = lessonConstraintViolations(error);
        if (violations == null || violations.isEmpty) rethrow;
        if (mounted) await _showConstraintViolations(violations);
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
      },
      if (_clientChargeType == 'subscription')
        'subscriptionId': _selectedSubscriptionId,
      if (_clientType == 'lead' && widget.leadName?.trim().isNotEmpty == true)
        'notes': 'Занятие по лиду: ${widget.leadName!.trim()}',
    };
  }

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

  Future<bool> _previewConstraintsBeforeSave(
    DateTime startsAt,
    String clientType,
    String clientId,
  ) async {
    try {
      final violations = await ref
          .read(magicApiClientProvider)
          .previewLessonConstraints(
            clientType: clientType,
            clientId: clientId,
            teacherId: _selectedTeacherId!,
            branchId: _selectedBranchId!,
            roomId: _selectedRoomId!,
            scheduledAt: startsAt.toIso8601String(),
            durationMinutes: _durationMinutes,
            excludeLessonId: _isEdit ? widget.lesson!['id']?.toString() : null,
          );
      if (violations.isEmpty) return true;
      if (!mounted) return false;
      await _showConstraintViolations(violations);
      return false;
    } catch (error) {
      // The write repeats the same engine inside its transaction and still
      // fails closed if this read-only preview is temporarily unavailable.
      debugPrint('Schedule constraints preview failed: $error');
      return true;
    }
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
    required BuildContext dialogContext,
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
                      Navigator.pop(dialogContext);
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
                  final rows = await _crm.searchClientRefs(q: query, limit: 50);
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
                  setState(() => _selectedClient = row);
                  _loadSubscriptions();
                },
              ),
              const SizedBox(height: 16),
              _responsivePair(
                DropdownButtonFormField<String>(
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
                  placeholder: _rooms.isEmpty
                      ? 'Нет доступных'
                      : 'Выберите аудиторию',
                  enabled: _rooms.isNotEmpty,
                  selectedId: _selectedRoomId,
                  items: [
                    for (final room in _rooms)
                      SearchableSelectItem(
                        id: room['id'].toString(),
                        label: room['name']?.toString() ?? '—',
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
              const SizedBox(height: 16),
              _responsivePair(_dateButton(), _timeButton()),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                key: const ValueKey('lesson-duration-field'),
                initialValue: _durationMinutes,
                decoration: const InputDecoration(labelText: 'Длительность *'),
                items: [
                  for (final minutes in const [30, 45, 60, 90, 120])
                    DropdownMenuItem(
                      value: minutes,
                      child: Text('$minutes мин'),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _durationMinutes = value ?? 60),
              ),
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
                  key: const ValueKey('lesson-compensation-rule-field'),
                  initialValue: _compensationRuleKey,
                  decoration: const InputDecoration(
                    labelText: 'Правило оплаты преподавателю *',
                    helperText: 'Не выводится автоматически из списания',
                  ),
                  items: [
                    for (final item
                        in _decisionCatalog?.compensationRules ?? const [])
                      DropdownMenuItem(
                        value: item.key,
                        child: Text(item.label),
                      ),
                  ],
                  onChanged: _snapshotLocked
                      ? null
                      : (value) => setState(() => _compensationRuleKey = value),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
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
              if (_snapshotLocked) ...[
                const SizedBox(height: 10),
                Text(
                  'Клиент, пробный маркер и расчётный snapshot неизменяемы. '
                  'Для переноса меняются только ресурсы и время.',
                  style: Theme.of(context).textTheme.bodySmall,
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
              : Text(_isEdit ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
    return widget.pageMode ? SafeArea(child: dialog) : dialog;
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
