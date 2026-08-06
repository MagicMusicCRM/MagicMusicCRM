import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/navigation/app_back_policy.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_conflicts_api.dart';
import 'package:magic_music_crm/features/admin/presentation/providers/schedule_navigation_provider.dart';

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
  String _teacherCompensationType = 'none';
  final _clientChargeController = TextEditingController(text: '0');
  final _teacherCompensationController = TextEditingController(text: '0');

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
      _teacherCompensationType =
          lesson['teacher_compensation_type']?.toString() ??
          _teacherCompensationType;
      _clientChargeController.text =
          lesson['client_charge_value']?.toString() ?? '0';
      _teacherCompensationController.text =
          lesson['teacher_compensation_value']?.toString() ?? '0';
      _selectedSubscriptionId = lesson['subscription_id']?.toString();
    }
    _loadData();
  }

  @override
  void dispose() {
    _clientChargeController.dispose();
    _teacherCompensationController.dispose();
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
        if (mounted) setState(() => _selectedBranchId ??= branchId);
        await _loadRooms(branchId);
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

  Future<void> _loadSubscriptions() async {
    final studentId = _clientType == 'student' ? _clientId : null;
    if (studentId == null) {
      if (mounted) {
        setState(() {
          _subscriptions = [];
          _selectedSubscriptionId = null;
          if (_clientChargeType == 'subscription') {
            _clientChargeType = 'none';
            _clientChargeController.text = '0';
          }
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
        _subscriptions = rows;
        if (_selectedSubscriptionId != null &&
            !rows.any(
              (row) => row['id']?.toString() == _selectedSubscriptionId,
            )) {
          _selectedSubscriptionId = null;
        }
      });
    } catch (error) {
      debugPrint('Error loading subscriptions: $error');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final clientId = _clientId;
    final clientType = _clientType;
    final chargeValue = _parseAmount(_clientChargeController.text);
    final compensationValue = _parseAmount(_teacherCompensationController.text);
    final missingSubscription =
        _clientChargeType == 'subscription' && _selectedSubscriptionId == null;
    final version = (widget.lesson?['version'] as num?)?.toInt();

    if (clientId == null ||
        clientType == null ||
        _selectedTeacherId == null ||
        _selectedBranchId == null ||
        _selectedRoomId == null ||
        chargeValue == null ||
        compensationValue == null ||
        missingSubscription ||
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
      final canSave = await _previewConstraintsBeforeSave(
        startsAt,
        clientType,
        clientId,
      );
      if (!canSave || !mounted) return;

      final payload = _lessonPayload(
        scheduledAt: startsAt.toIso8601String(),
        chargeValue: chargeValue,
        compensationValue: compensationValue,
        expectedVersion: version,
      );
      final api = ref.read(magicApiClientProvider);
      try {
        if (_isEdit) {
          await api.updateLessonRaw(widget.lesson!['id'].toString(), payload);
        } else {
          await api.createLessonRaw(payload);
        }
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

  num? _parseAmount(String raw) {
    final value = num.tryParse(raw.trim().replaceAll(',', '.'));
    return value == null || value < 0 ? null : value;
  }

  Map<String, dynamic> _lessonPayload({
    required String scheduledAt,
    required num chargeValue,
    required num compensationValue,
    required int? expectedVersion,
  }) {
    final mutable = <String, dynamic>{
      'teacherId': _selectedTeacherId,
      'branchId': _selectedBranchId,
      'roomId': _selectedRoomId,
      'scheduledAt': scheduledAt,
      'durationMinutes': _durationMinutes,
    };
    if (_isEdit) {
      return {...mutable, 'expectedVersion': expectedVersion};
    }
    return {
      ...mutable,
      'clientRef': {'type': _clientType, 'id': _clientId},
      'isTrial': _isTrial,
      'completionType': _completionType,
      'clientChargeType': _clientChargeType,
      'clientChargeValue': chargeValue,
      'teacherCompensationType': _teacherCompensationType,
      'teacherCompensationValue': compensationValue,
      if (_clientChargeType == 'subscription')
        'subscriptionId': _selectedSubscriptionId,
      if (_clientType == 'lead' && widget.leadName?.trim().isNotEmpty == true)
        'notes': 'Занятие по лиду: ${widget.leadName!.trim()}',
    };
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
                  TextButton.icon(
                    key: ValueKey('conflict-lesson-$lessonId'),
                    onPressed: () {
                      ref
                          .read(scheduleNavigationProvider.notifier)
                          .focus(_selectedDate, lessonId);
                      Navigator.pop(dialogContext);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    label: const Text('Открыть конфликтующее занятие'),
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
              body: loading,
            )
          : const AlertDialog(content: loading);
    }

    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSelectionField(
                key: const ValueKey('lesson-client-field'),
                label: 'Клиент *',
                value: _selectedClient?['label']?.toString() ?? 'Не выбран',
                badge: _clientType == null ? null : _clientBadge(_clientType!),
                enabled:
                    !_snapshotLocked &&
                    widget.leadId == null &&
                    widget.clientId == null,
                onTap: _pickClient,
              ),
              const SizedBox(height: 16),
              _buildSelectionField(
                key: const ValueKey('lesson-teacher-field'),
                label: 'Преподаватель *',
                value: _getTeacherName(_selectedTeacherId),
                onTap: _pickTeacher,
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
                      _selectedRoomId = null;
                      _rooms = [];
                    });
                    if (value != null) _loadRooms(value);
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
                  key: const ValueKey('lesson-charge-type-field'),
                  initialValue: _clientChargeType,
                  decoration: const InputDecoration(
                    labelText: 'Списание клиента *',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'none',
                      child: Text('Без списания'),
                    ),
                    const DropdownMenuItem(
                      value: 'personal_account',
                      child: Text('Личный счёт'),
                    ),
                    if (_clientType == 'student')
                      const DropdownMenuItem(
                        value: 'subscription',
                        child: Text('Абонемент'),
                      ),
                  ],
                  onChanged: _snapshotLocked
                      ? null
                      : (value) {
                          setState(() {
                            _clientChargeType = value ?? 'none';
                            if (_clientChargeType == 'none') {
                              _clientChargeController.text = '0';
                              _selectedSubscriptionId = null;
                            }
                          });
                        },
                ),
                _amountField(
                  key: const ValueKey('lesson-charge-value-field'),
                  controller: _clientChargeController,
                  label: _clientChargeType == 'subscription'
                      ? 'Единиц списания *'
                      : 'Стоимость / списание *',
                  enabled: !_snapshotLocked && _clientChargeType != 'none',
                ),
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
              const SizedBox(height: 16),
              _responsivePair(
                DropdownButtonFormField<String>(
                  key: const ValueKey('lesson-compensation-type-field'),
                  initialValue: _teacherCompensationType,
                  decoration: const InputDecoration(
                    labelText: 'Оплата преподавателя *',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'none',
                      child: Text('Без начисления'),
                    ),
                    DropdownMenuItem(
                      value: 'fixed',
                      child: Text('Фиксированная'),
                    ),
                    DropdownMenuItem(value: 'hourly', child: Text('Почасовая')),
                  ],
                  onChanged: _snapshotLocked
                      ? null
                      : (value) {
                          setState(() {
                            _teacherCompensationType = value ?? 'none';
                            if (_teacherCompensationType == 'none') {
                              _teacherCompensationController.text = '0';
                            }
                          });
                        },
                ),
                _amountField(
                  key: const ValueKey('lesson-compensation-value-field'),
                  controller: _teacherCompensationController,
                  label: 'Сумма / ставка *',
                  enabled:
                      !_snapshotLocked && _teacherCompensationType != 'none',
                ),
              ),
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

  Widget _amountField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required bool enabled,
  }) {
    return TextField(
      key: key,
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }

  Future<void> _pickClient() async {
    SearchableSelect.show(
      context: context,
      title: 'Выберите клиента',
      hintText: 'Поиск Lead или Student по ФИО...',
      items: [for (final row in _clients) _clientItem(row)],
      onSearch: (query) async {
        final rows = await _crm.searchClientRefs(q: query, limit: 50);
        return [for (final row in rows) _clientItem(row)];
      },
      selectedId: _clientKey,
      isNullable: false,
      onSelected: (item) async {
        final row = item?.data;
        if (row == null) return;
        setState(() => _selectedClient = row);
        await _loadSubscriptions();
      },
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

  void _pickTeacher() {
    SearchableSelect.show(
      context: context,
      title: 'Выберите преподавателя',
      hintText: 'Поиск по имени...',
      items: [
        for (final teacher in _teachers)
          SearchableSelectItem(
            id: teacher['id'].toString(),
            label: _getTeacherNameFromData(teacher),
          ),
      ],
      selectedId: _selectedTeacherId,
      isNullable: false,
      onSelected: (item) => setState(() => _selectedTeacherId = item?.id),
    );
  }

  Widget _buildSelectionField({
    Key? key,
    required String label,
    required String value,
    required VoidCallback onTap,
    Widget? badge,
    bool enabled = true,
  }) {
    return InkWell(
      key: key,
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          suffixIcon: enabled
              ? const Icon(Icons.arrow_drop_down)
              : const Icon(Icons.lock_outline_rounded, size: 18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value == 'Не выбран'
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
            ?badge,
          ],
        ),
      ),
    );
  }

  Widget _clientBadge(String type) {
    final isLead = type == 'lead';
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (isLead ? AppColor.gold : AppColor.infoViolet).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isLead ? 'Lead' : 'Student',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isLead ? AppColor.gold : AppColor.infoViolet,
        ),
      ),
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
