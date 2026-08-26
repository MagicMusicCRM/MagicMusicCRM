import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/forms/dirty_form_exit.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';

import 'preferred_schedule_draft.dart';

export 'preferred_schedule_draft.dart';

class PreferredScheduleEditor extends StatefulWidget {
  const PreferredScheduleEditor({
    required this.branches,
    required this.teachers,
    required this.rooms,
    required this.defaultBranchId,
    this.series,
    this.planMode = false,
    this.initialTitle,
    this.initialDraft,
    this.subscriptionOptions = const [],
    this.initialSubscriptionId,
    this.requireSubscription = false,
    this.allowOpenEnded = false,
    this.showPeriod = true,
    this.decisionCatalogs = const {},
    this.requireFinancialDecision = false,
    super.key,
  });

  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> rooms;
  final String? defaultBranchId;
  final Map<String, dynamic>? series;
  final bool planMode;
  final String? initialTitle;
  final PreferredScheduleDraft? initialDraft;
  final List<Map<String, dynamic>> subscriptionOptions;
  final String? initialSubscriptionId;
  final bool requireSubscription;
  final bool allowOpenEnded;
  final bool showPeriod;
  final Map<String, LessonDecisionCatalog> decisionCatalogs;
  final bool requireFinancialDecision;

  @override
  State<PreferredScheduleEditor> createState() =>
      _PreferredScheduleEditorState();
}

class _PreferredScheduleEditorState extends State<PreferredScheduleEditor> {
  static const _weekdayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  late final DirtyFormExitController _exitController;
  late final TextEditingController _notesController;
  late final TextEditingController _titleController;
  late String _branchId;
  late Set<int> _weekdays;
  late String _beginTime;
  late int _durationMinutes;
  late int _lessonsPerDay;
  late DateTime _validFrom;
  late DateTime _validUntil;
  String? _teacherId;
  String? _roomId;
  String? _subscriptionId;
  String? _settlementTypeKey;
  String? _teacherCompensationRuleKey;
  late bool _openEnded;
  String? _error;

  bool get _isEdit => widget.series != null;

  @override
  void initState() {
    super.initState();
    final series = widget.series;
    final initial = widget.initialDraft;
    final availableBranchIds = widget.branches
        .map((branch) => branch['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final seriesBranch = series?['branch_id']?.toString();
    final preferredBranch =
        seriesBranch ?? initial?.branchId ?? widget.defaultBranchId;
    _branchId = availableBranchIds.contains(preferredBranch)
        ? preferredBranch!
        : (availableBranchIds.isEmpty ? '' : availableBranchIds.first);
    _weekdays = series == null
        ? Set.of(initial?.weekdays ?? {DateTime.now().weekday})
        : {(series['weekday'] as num?)?.toInt() ?? DateTime.now().weekday};
    _beginTime =
        series?['begin_time']?.toString() ?? initial?.beginTime ?? '15:00';
    _durationMinutes =
        (series?['duration_minutes'] as num?)?.toInt() ??
        initial?.durationMinutes ??
        60;
    _lessonsPerDay = initial?.lessonsPerDay ?? 1;
    final today = DateUtils.dateOnly(DateTime.now());
    final requestedStart =
        _date(series?['valid_from']) ??
        initial?.validFrom ??
        today.add(const Duration(days: 1));
    _validFrom = _isEdit && requestedStart.isBefore(today)
        ? today
        : requestedStart;
    _validUntil =
        _date(series?['valid_until']) ??
        initial?.validUntil ??
        _validFrom.add(const Duration(days: 90));
    if (_validUntil.isBefore(_validFrom)) {
      _validUntil = _validFrom.add(const Duration(days: 90));
    }
    _teacherId = series?['teacher_id']?.toString() ?? initial?.teacherId;
    _roomId = series?['room_id']?.toString() ?? initial?.roomId;
    _subscriptionId = widget.initialSubscriptionId ?? initial?.subscriptionId;
    if (!widget.subscriptionOptions.any(
      (option) => option['id']?.toString() == _subscriptionId,
    )) {
      _subscriptionId = widget.subscriptionOptions.isEmpty
          ? null
          : widget.subscriptionOptions.first['id']?.toString();
    }
    final seriesDecision = Map<String, dynamic>.from(
      series?['financial_decision'] as Map? ?? const {},
    );
    _settlementTypeKey =
        seriesDecision['settlementTypeKey']?.toString() ??
        initial?.settlementTypeKey;
    _teacherCompensationRuleKey =
        seriesDecision['teacherCompensationRuleKey']?.toString() ??
        initial?.teacherCompensationRuleKey;
    _syncDecisionForBranch();
    _openEnded =
        widget.allowOpenEnded &&
        (series == null
            ? initial?.openEnded ?? true
            : series['valid_until'] == null);
    if (!widget.rooms.any(
      (room) =>
          room['id']?.toString() == _roomId &&
          room['branch_id']?.toString() == _branchId,
    )) {
      _roomId = null;
    }
    if (!_teachersForBranch.any(
      (teacher) => teacher['id']?.toString() == _teacherId,
    )) {
      _teacherId = null;
    }
    _notesController = TextEditingController(
      text: series?['notes']?.toString() ?? initial?.notes ?? '',
    );
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _exitController = DirtyFormExitController(onSave: _validate);
  }

  @override
  void dispose() {
    _exitController.dispose();
    _notesController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  DateTime? _date(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null ? null : DateUtils.dateOnly(parsed);
  }

  PreferredScheduleDraft get _draft => PreferredScheduleDraft(
    branchId: _branchId,
    weekdays: Set.unmodifiable(_weekdays),
    beginTime: _beginTime,
    durationMinutes: _durationMinutes,
    lessonsPerDay: _lessonsPerDay,
    validFrom: _validFrom,
    validUntil: _validUntil,
    teacherId: _teacherId ?? '',
    roomId: _roomId ?? '',
    notes: _notesController.text.trim(),
    seriesId: widget.initialDraft?.seriesId ?? widget.series?['id']?.toString(),
    title: widget.planMode ? _titleController.text.trim() : null,
    subscriptionId: _subscriptionId,
    settlementTypeKey: _settlementTypeKey ?? '',
    teacherCompensationRuleKey: _teacherCompensationRuleKey ?? '',
    openEnded: _openEnded,
  );

  LessonDecisionCatalog? get _decisionCatalog =>
      widget.decisionCatalogs[_branchId];

  List<Map<String, dynamic>> get _teachersForBranch => widget.teachers
      .where((teacher) {
        if (teacher['status']?.toString() != 'active') return false;
        final assignments = teacher['assigned_branches'];
        return assignments is List &&
            assignments.whereType<Map>().any(
              (branch) => branch['id']?.toString() == _branchId,
            );
      })
      .toList(growable: false);

  void _syncDecisionForBranch() {
    final catalog = _decisionCatalog;
    if (catalog == null) return;
    if (!catalog.settlementTypes.any(
      (item) => item.key == _settlementTypeKey,
    )) {
      _settlementTypeKey = catalog.settlementTypes.firstOrNull?.key;
    }
    if (!catalog.compensationRules.any(
      (item) => item.key == _teacherCompensationRuleKey,
    )) {
      _teacherCompensationRuleKey = catalog.compensationRules.firstOrNull?.key;
    }
  }

  void _changed(VoidCallback change) {
    setState(() {
      change();
      _error = null;
    });
    _exitController.markDirty();
  }

  Future<bool> _validate() async {
    String? error;
    if (_branchId.isEmpty) {
      error = 'Выберите филиал.';
    } else if (widget.planMode && _titleController.text.trim().isEmpty) {
      error = 'Укажите название расписания.';
    } else if (widget.requireSubscription && _subscriptionId == null) {
      error = 'Выберите абонемент.';
    } else if (_weekdays.isEmpty) {
      error = 'Выберите хотя бы один день недели.';
    } else if (_teacherId == null || _teacherId!.isEmpty) {
      error = 'Выберите педагога.';
    } else if (_roomId == null || _roomId!.isEmpty) {
      error = 'Выберите аудиторию.';
    } else if ((widget.planMode || widget.requireFinancialDecision) &&
        (_settlementTypeKey == null || _settlementTypeKey!.isEmpty)) {
      error = 'Выберите тип списания.';
    } else if ((widget.planMode || widget.requireFinancialDecision) &&
        (_teacherCompensationRuleKey == null ||
            _teacherCompensationRuleKey!.isEmpty)) {
      error = 'Выберите оплату преподавателю.';
    } else if (!_openEnded && _validUntil.isBefore(_validFrom)) {
      error = 'Дата окончания не может быть раньше даты начала.';
    } else {
      final parts = _beginTime.split(':');
      final minutes =
          (int.tryParse(parts.first) ?? 0) * 60 +
          (int.tryParse(parts.last) ?? 0);
      if (minutes + _durationMinutes * _lessonsPerDay > 24 * 60) {
        error = 'Последнее занятие выходит за границы выбранного дня.';
      }
    }
    if (mounted) setState(() => _error = error);
    return error == null;
  }

  Future<void> _submit() async {
    if (!await _validate() || !mounted) return;
    _exitController.markClean();
    Navigator.of(context).pop(_draft);
  }

  Future<void> _cancel() => _exitController.requestExit(
    context,
    reason: DirtyFormExitReason.appBack,
    savedResult: _draft,
  );

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _validFrom : _validUntil,
      firstDate: start ? DateUtils.dateOnly(DateTime.now()) : _validFrom,
      lastDate: DateUtils.dateOnly(
        DateTime.now().add(const Duration(days: 730)),
      ),
    );
    if (picked == null) return;
    _changed(() {
      if (start) {
        _validFrom = picked;
        if (_validUntil.isBefore(picked)) _validUntil = picked;
      } else {
        _validUntil = picked;
      }
    });
  }

  Future<void> _pickTime() async {
    final parts = _beginTime.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 15,
        minute: int.tryParse(parts.last) ?? 0,
      ),
    );
    if (picked == null) return;
    _changed(
      () => _beginTime =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final branchRooms = widget.rooms
        .where((room) => room['branch_id']?.toString() == _branchId)
        .toList(growable: false);
    final branchTeachers = _teachersForBranch;
    return DirtyFormExitScope(
      controller: _exitController,
      savedResult: _draft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.planMode || widget.requireFinancialDecision) ...[
            TextField(
              key: const ValueKey('schedule-plan-title'),
              controller: _titleController,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Название'),
              onChanged: (_) => _changed(() {}),
            ),
            if (widget.requireSubscription) ...[
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<String>(
                menuMaxHeight: 256,
                key: const ValueKey('schedule-plan-subscription'),
                initialValue: _subscriptionId,
                decoration: const InputDecoration(labelText: 'Абонемент'),
                items: [
                  for (final option in widget.subscriptionOptions)
                    DropdownMenuItem(
                      value: option['id']?.toString(),
                      child: Text(option['label']?.toString() ?? 'Абонемент'),
                    ),
                ],
                onChanged: (value) => _changed(() => _subscriptionId = value),
              ),
            ],
            const SizedBox(height: AppSpace.md),
          ],
          DropdownButtonFormField<String>(
            menuMaxHeight: 256,
            key: const ValueKey('preferred-schedule-branch'),
            initialValue: _branchId.isEmpty ? null : _branchId,
            decoration: const InputDecoration(
              labelText: 'Филиал *',
              helperText: 'Постоянная серия всегда привязана к филиалу',
            ),
            items: [
              for (final branch in widget.branches)
                DropdownMenuItem(
                  value: branch['id']?.toString(),
                  child: Text(branch['name']?.toString() ?? 'Филиал'),
                ),
            ],
            onChanged: _isEdit
                ? null
                : (value) {
                    if (value == null) return;
                    _changed(() {
                      _branchId = value;
                      _teacherId = null;
                      _roomId = null;
                      _syncDecisionForBranch();
                    });
                  },
          ),
          const SizedBox(height: AppSpace.md),
          const Text(
            'Дни недели',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  key: ValueKey('preferred-schedule-weekday-$day'),
                  label: Text(_weekdayLabels[day - 1]),
                  selected: _weekdays.contains(day),
                  onSelected: _isEdit
                      ? null
                      : (selected) => _changed(
                          () => selected
                              ? _weekdays.add(day)
                              : _weekdays.remove(day),
                        ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final fields = [
                InkWell(
                  key: const ValueKey('preferred-schedule-time'),
                  onTap: _pickTime,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Время'),
                    child: Text(_beginTime),
                  ),
                ),
                DropdownButtonFormField<int>(
                  menuMaxHeight: 256,
                  key: const ValueKey('preferred-schedule-duration'),
                  initialValue: _durationMinutes,
                  decoration: const InputDecoration(labelText: 'Длительность'),
                  items: const [30, 45, 60, 90, 120]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value мин'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _changed(() => _durationMinutes = value);
                    }
                  },
                ),
                DropdownButtonFormField<int>(
                  menuMaxHeight: 256,
                  key: const ValueKey('preferred-schedule-lessons-per-day'),
                  initialValue: _lessonsPerDay,
                  decoration: const InputDecoration(
                    labelText: 'Занятий в день',
                    helperText: 'Идут подряд',
                  ),
                  items: const [1, 2, 3, 4]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value'),
                        ),
                      )
                      .toList(),
                  onChanged: _isEdit
                      ? null
                      : (value) {
                          if (value != null) {
                            _changed(() => _lessonsPerDay = value);
                          }
                        },
                ),
              ];
              if (constraints.maxWidth < 520) {
                return Column(
                  children: [
                    for (final field in fields) ...[
                      field,
                      const SizedBox(height: AppSpace.md),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < fields.length; index++) ...[
                    if (index > 0) const SizedBox(width: AppSpace.sm),
                    Expanded(child: fields[index]),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppSpace.md),
          SearchablePickerField(
            key: const ValueKey('preferred-schedule-teacher'),
            label: 'Педагог *',
            placeholder: branchTeachers.isEmpty
                ? 'Нет назначенных в этот филиал педагогов'
                : 'Выберите педагога',
            enabled: branchTeachers.isNotEmpty,
            selectedId: _teacherId,
            items: [
              for (final teacher in branchTeachers)
                SearchableSelectItem(
                  id: teacher['id'].toString(),
                  label:
                      '${teacher['first_name'] ?? ''} ${teacher['last_name'] ?? ''}'
                          .trim(),
                ),
            ],
            onSelected: (item) => _changed(() => _teacherId = item?.id),
          ),
          const SizedBox(height: AppSpace.md),
          SearchablePickerField(
            key: const ValueKey('preferred-schedule-room'),
            label: 'Аудитория *',
            placeholder: branchRooms.isEmpty
                ? 'В филиале нет доступных аудиторий'
                : 'Выберите аудиторию',
            selectedId: _roomId,
            items: [
              for (final room in branchRooms)
                SearchableSelectItem(
                  id: room['id'].toString(),
                  label: room['name']?.toString() ?? 'Аудитория',
                ),
            ],
            onSelected: (item) => _changed(() => _roomId = item?.id),
          ),
          if (widget.planMode) ...[
            const SizedBox(height: AppSpace.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final catalog = _decisionCatalog;
                final fields = [
                  DropdownButtonFormField<String>(
                    menuMaxHeight: 256,
                    key: const ValueKey('schedule-plan-settlement-type'),
                    initialValue: _settlementTypeKey,
                    decoration: const InputDecoration(
                      labelText: 'Тип списания *',
                      helperText: 'Применится после окончания занятия',
                    ),
                    items: [
                      for (final item in catalog?.settlementTypes ?? const [])
                        DropdownMenuItem(
                          value: item.key,
                          child: Text(item.label),
                        ),
                    ],
                    onChanged: (value) =>
                        _changed(() => _settlementTypeKey = value),
                  ),
                  DropdownButtonFormField<String>(
                    menuMaxHeight: 256,
                    key: const ValueKey('schedule-plan-compensation-rule'),
                    initialValue: _teacherCompensationRuleKey,
                    decoration: const InputDecoration(
                      labelText: 'Оплата преподавателю *',
                      helperText: 'Сотрудник выбирает правило явно',
                    ),
                    items: [
                      for (final item in catalog?.compensationRules ?? const [])
                        DropdownMenuItem(
                          value: item.key,
                          child: Text(item.label),
                        ),
                    ],
                    onChanged: (value) =>
                        _changed(() => _teacherCompensationRuleKey = value),
                  ),
                ];
                if (constraints.maxWidth < 520) {
                  return Column(
                    children: [
                      fields.first,
                      const SizedBox(height: AppSpace.md),
                      fields.last,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: fields.first),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(child: fields.last),
                  ],
                );
              },
            ),
          ],
          if (widget.showPeriod) ...[
            const SizedBox(height: AppSpace.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final start = _dateField(
                  key: const ValueKey('preferred-schedule-start'),
                  label: _isEdit ? 'Применить с даты' : 'Дата начала',
                  value: _validFrom,
                  onTap: () => _pickDate(start: true),
                );
                final end = _dateField(
                  key: const ValueKey('preferred-schedule-end'),
                  label: 'Дата окончания',
                  value: _validUntil,
                  onTap: () => _pickDate(start: false),
                );
                final fields = [start, if (!_openEnded) end];
                if (constraints.maxWidth < 520) {
                  return Column(
                    children: [
                      for (var index = 0; index < fields.length; index++) ...[
                        if (index > 0) const SizedBox(height: AppSpace.md),
                        fields[index],
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    for (var index = 0; index < fields.length; index++) ...[
                      if (index > 0) const SizedBox(width: AppSpace.sm),
                      Expanded(child: fields[index]),
                    ],
                  ],
                );
              },
            ),
          ],
          if (widget.showPeriod && widget.allowOpenEnded) ...[
            const SizedBox(height: AppSpace.sm),
            SwitchListTile.adaptive(
              key: const ValueKey('schedule-plan-open-ended'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Без даты окончания'),
              value: _openEnded,
              onChanged: (value) => _changed(() => _openEnded = value),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const ValueKey('preferred-schedule-notes'),
            controller: _notesController,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Описание',
              hintText: 'Пожелания клиента и важные условия',
            ),
            onChanged: (_) => _changed(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              _error!,
              key: const ValueKey('preferred-schedule-error'),
              style: TextStyle(color: cs.error, fontSize: 13),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancel,
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('preferred-schedule-save'),
                  onPressed: _submit,
                  child: Text(_isEdit ? 'Применить' : 'Создать'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateField({
    required Key key,
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(DateFormat('dd.MM.yyyy').format(value)),
      ),
    );
  }
}
