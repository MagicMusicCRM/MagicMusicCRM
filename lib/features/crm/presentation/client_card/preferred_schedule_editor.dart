import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

class PreferredScheduleDraft {
  const PreferredScheduleDraft({
    required this.branchId,
    required this.weekdays,
    required this.beginTime,
    required this.durationMinutes,
    required this.lessonsPerDay,
    required this.validFrom,
    required this.validUntil,
    required this.teacherId,
    required this.roomId,
    required this.notes,
  });

  final String branchId;
  final Set<int> weekdays;
  final String beginTime;
  final int durationMinutes;
  final int lessonsPerDay;
  final DateTime validFrom;
  final DateTime validUntil;
  final String teacherId;
  final String roomId;
  final String notes;
}

class PreferredScheduleEditor extends StatefulWidget {
  const PreferredScheduleEditor({
    required this.branches,
    required this.teachers,
    required this.rooms,
    required this.defaultBranchId,
    this.series,
    super.key,
  });

  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> rooms;
  final String? defaultBranchId;
  final Map<String, dynamic>? series;

  @override
  State<PreferredScheduleEditor> createState() =>
      _PreferredScheduleEditorState();
}

class _PreferredScheduleEditorState extends State<PreferredScheduleEditor> {
  static const _weekdayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  late final DirtyFormExitController _exitController;
  late final TextEditingController _notesController;
  late String _branchId;
  late Set<int> _weekdays;
  late String _beginTime;
  late int _durationMinutes;
  late int _lessonsPerDay;
  late DateTime _validFrom;
  late DateTime _validUntil;
  String? _teacherId;
  String? _roomId;
  String? _error;

  bool get _isEdit => widget.series != null;

  @override
  void initState() {
    super.initState();
    final series = widget.series;
    final availableBranchIds = widget.branches
        .map((branch) => branch['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final seriesBranch = series?['branch_id']?.toString();
    final preferredBranch = seriesBranch ?? widget.defaultBranchId;
    _branchId = availableBranchIds.contains(preferredBranch)
        ? preferredBranch!
        : (availableBranchIds.isEmpty ? '' : availableBranchIds.first);
    _weekdays = {
      (series?['weekday'] as num?)?.toInt() ?? DateTime.now().weekday,
    };
    _beginTime = series?['begin_time']?.toString() ?? '15:00';
    _durationMinutes = (series?['duration_minutes'] as num?)?.toInt() ?? 60;
    _lessonsPerDay = 1;
    _validFrom =
        _date(series?['valid_from']) ??
        DateUtils.dateOnly(DateTime.now().add(const Duration(days: 1)));
    _validUntil =
        _date(series?['valid_until']) ??
        _validFrom.add(const Duration(days: 90));
    _teacherId = series?['teacher_id']?.toString();
    _roomId = series?['room_id']?.toString();
    if (!widget.rooms.any(
      (room) =>
          room['id']?.toString() == _roomId &&
          room['branch_id']?.toString() == _branchId,
    )) {
      _roomId = null;
    }
    _notesController = TextEditingController(
      text: series?['notes']?.toString() ?? '',
    );
    _exitController = DirtyFormExitController(onSave: _validate);
  }

  @override
  void dispose() {
    _exitController.dispose();
    _notesController.dispose();
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
  );

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
    } else if (_weekdays.isEmpty) {
      error = 'Выберите хотя бы один день недели.';
    } else if (_teacherId == null || _teacherId!.isEmpty) {
      error = 'Выберите педагога.';
    } else if (_roomId == null || _roomId!.isEmpty) {
      error = 'Выберите аудиторию.';
    } else if (_validUntil.isBefore(_validFrom)) {
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
    return DirtyFormExitScope(
      controller: _exitController,
      savedResult: _draft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('preferred-schedule-branch'),
            initialValue: _branchId.isEmpty ? null : _branchId,
            decoration: const InputDecoration(
              labelText: 'Филиал',
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
                      _roomId = null;
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
            label: 'Педагог',
            placeholder: 'Выберите педагога',
            selectedId: _teacherId,
            items: [
              for (final teacher in widget.teachers)
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
            label: 'Аудитория',
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
              if (constraints.maxWidth < 520) {
                return Column(
                  children: [
                    start,
                    const SizedBox(height: AppSpace.md),
                    end,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: start),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: end),
                ],
              );
            },
          ),
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
