import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';
import 'package:intl/intl.dart';

class CreateLessonDialog extends ConsumerStatefulWidget {
  final DateTime? initialDate;
  final String? initialRoomId;
  final String? initialBranchId;
  final int? initialDurationMinutes;
  // When provided, the dialog edits this existing lesson instead of creating a
  // new one (pre-filled fields, "Сохранить" updates via PATCH).
  final Map<String, dynamic>? lesson;

  /// Пробное занятие по лиду (✔ решение владельца 17.07: «это просто готовый
  /// пресет под создание нового занятия, поэтому можно не дублировать
  /// функционал»). Когда задан — занятие вешается на лида, а не на ученика или
  /// группу, и пикеры «Группа»/«Ученик» уступают место строке с именем лида.
  final String? leadId;
  final String? leadName;

  /// Предустановка «это пробное». ✔ Владелец 17.07: индивидуальный пробный —
  /// это обычное занятие с пометкой «пробное»; списание с личного счёта админ
  /// или менеджер назначает сам.
  final bool initialIsTrial;

  const CreateLessonDialog({
    super.key,
    this.initialDate,
    this.initialRoomId,
    this.initialBranchId,
    this.initialDurationMinutes,
    this.lesson,
    this.leadId,
    this.leadName,
    this.initialIsTrial = false,
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
    bool initialIsTrial = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => CreateLessonDialog(
        initialDate: initialDate,
        initialRoomId: initialRoomId,
        initialBranchId: initialBranchId,
        initialDurationMinutes: initialDurationMinutes,
        lesson: lesson,
        leadId: leadId,
        leadName: leadName,
        initialIsTrial: initialIsTrial,
      ),
    );
  }

  /// Пресет «Пробное занятие»: тот же диалог, что и «Новое занятие», но с
  /// предзаполненными полями по логике пробного.
  ///
  /// Раньше пробное было отдельным окном (`showScheduleTrialDialog`) на четыре
  /// поля — без филиала, а аудитории в нём не фильтровались по филиалу, потому
  /// что фильтровать было не по чему. Здесь всё это уже есть.
  static Future<bool?> showTrialPreset(
    BuildContext context, {
    required String leadId,
    required String leadName,
  }) {
    return show(
      context,
      leadId: leadId,
      leadName: leadName,
      initialIsTrial: true,
      // Завтра в 10:00 — то же умолчание, что было у прежнего окна пробного.
      initialDate: DateTime.now().add(const Duration(days: 1)),
    );
  }

  @override
  ConsumerState<CreateLessonDialog> createState() => _CreateLessonDialogState();
}

class _CreateLessonDialogState extends ConsumerState<CreateLessonDialog> {
  bool _loading = false;
  bool _saving = false;

  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _rooms = [];

  String? _selectedTeacherId;
  String? _selectedGroupId;
  String? _selectedStudentId;
  String? _selectedBranchId;
  String? _selectedRoomId;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _durationMinutes = 60;
  // Поурочная ставка педагога (₽/астр.ч.): null — по умолчанию (ставка группы/
  // педагога), 0 — «входит в оклад», иначе фикс за это занятие.
  num? _teacherRate;

  /// «Это пробное занятие». Влияет только на пометку `is_trial`: списание с
  /// личного счёта за пробное админ/менеджер назначает руками (✔ владелец
  /// 17.07), автоматики здесь нет и не задумано.
  bool _isTrial = false;

  bool get _isEdit => widget.lesson != null;

  /// Занятие вешается на лида (пресет пробного), а не на ученика/группу.
  bool get _isLeadLesson => widget.leadId != null;

  @override
  void initState() {
    super.initState();
    _isTrial = widget.initialIsTrial;
    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!;
      // У пресета пробного дата — «завтра», но время из неё брать нельзя:
      // получилось бы «завтра в момент, когда открыли диалог». Прежнее окно
      // пробного предлагало 10:00 — оставляем его.
      _selectedTime = widget.initialIsTrial
          ? const TimeOfDay(hour: 10, minute: 0)
          : TimeOfDay.fromDateTime(widget.initialDate!);
    }
    if (widget.initialRoomId != null) {
      _selectedRoomId = widget.initialRoomId;
    }
    if (widget.initialBranchId != null) {
      _selectedBranchId = widget.initialBranchId;
      _loadRooms(widget.initialBranchId!);
    }
    if (widget.initialDurationMinutes != null &&
        widget.initialDurationMinutes! > 0) {
      _durationMinutes = widget.initialDurationMinutes!;
    }
    // Pre-fill from the lesson being edited.
    final lesson = widget.lesson;
    if (lesson != null) {
      _selectedTeacherId = lesson['teacher_id']?.toString();
      _selectedGroupId = lesson['group_id']?.toString();
      _selectedStudentId = lesson['student_id']?.toString();
      _selectedBranchId = lesson['branch_id']?.toString() ?? _selectedBranchId;
      _selectedRoomId = lesson['room_id']?.toString() ?? _selectedRoomId;
      final raw = lesson['scheduled_at']?.toString();
      final parsed = raw == null ? null : DateTime.tryParse(raw);
      if (parsed != null) {
        // Stored as UTC; show in Moscow time (UTC+3) to match the schedule.
        final local = parsed.toUtc().add(const Duration(hours: 3));
        _selectedDate = DateTime(local.year, local.month, local.day);
        _selectedTime = TimeOfDay(hour: local.hour, minute: local.minute);
      }
      if (_selectedBranchId != null) _loadRooms(_selectedBranchId!);
      _isTrial = lesson['is_trial'] == true;
      final rawRate = lesson['teacher_rate'];
      if (rawRate is num) {
        _teacherRate = rawRate;
      } else if (rawRate != null) {
        _teacherRate = num.tryParse(rawRate.toString());
      }
    }
    _loadData();
  }

  MagicCrmService get _crm => ref.read(magicCrmServiceProvider);

  String get _dialogTitle {
    if (_isEdit) return 'Редактировать занятие';
    if (_isLeadLesson) return 'Пробное занятие';
    return 'Новое занятие';
  }

  String get _savedMessage {
    if (_isEdit) return 'Занятие обновлено';
    if (_isLeadLesson) return 'Пробное занятие назначено';
    return 'Занятие создано';
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _crm.listTeachers(limit: 100),
        _crm.listGroups(limit: 100),
        _crm.listStudents(limit: 100),
        _crm.listBranches(limit: 100),
      ]);

      setState(() {
        _teachers = results[0];
        _groups = results[1];
        _students = results[2];
        _branches = results[3];
        _loading = false;
      });
      final branchId =
          _selectedBranchId ?? _branches.firstOrNull?['id']?.toString();
      if (branchId != null) {
        if (mounted) setState(() => _selectedBranchId ??= branchId);
        await _loadRooms(branchId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка загрузки данных: $e')));
        Navigator.pop(context);
      }
    }
  }

  Future<void> _loadRooms(String branchId) async {
    try {
      final rooms = await _crm.listRooms(branchId: branchId, limit: 100);
      setState(() {
        _rooms = rooms;
        if (_selectedRoomId != null &&
            !_rooms.any((room) => room['id'].toString() == _selectedRoomId)) {
          _selectedRoomId = null;
        }
      });
    } catch (e) {
      debugPrint('Error loading rooms: $e');
    }
  }

  Future<void> _save() async {
    // Занятие всегда чьё-то: группы, ученика или — у пробного — лида.
    final hasSubject =
        _isLeadLesson || _selectedGroupId != null || _selectedStudentId != null;
    if (_selectedTeacherId == null ||
        !hasSubject ||
        _selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните обязательные поля')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // We want to save this as a timestamp with the correct offset (+03:00)
      // or convert to UTC. Given the user wants UTC+3, let's treat selected time as Moscow time.
      // If we use DateTime.toIso8601String() on a local time, it's missing the offset.
      // Let's create a UTC time that represents the same instant.
      final moscowTime = DateTime.utc(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour - 3, // Subtract 3 to get UTC
        _selectedTime.minute,
      );

      final scheduledAt = moscowTime.toIso8601String();

      // KVA-154: pre-save soft conflict check. Ask the backend whether the
      // chosen room is free at this slot; if it reports a busy/overlapping room
      // we surface a confirmable warning instead of silently creating a clashing
      // lesson. This is a soft warn — the manager may still proceed.
      final proceed = await _confirmIfConflicting(
        slotStartUtc: moscowTime,
      );
      if (!proceed) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      if (_isEdit) {
        await _crm.updateLesson(
          widget.lesson!['id'].toString(),
          teacherId: _selectedTeacherId,
          groupId: _selectedGroupId,
          studentId: _selectedStudentId,
          branchId: _selectedBranchId,
          roomId: _selectedRoomId,
          scheduledAt: scheduledAt,
          durationMinutes: _durationMinutes,
          teacherRate: _teacherRate,
          isTrial: _isTrial,
        );
      } else {
        await _crm.createLesson(
          teacherId: _selectedTeacherId,
          groupId: _selectedGroupId,
          studentId: _selectedStudentId,
          leadId: widget.leadId,
          branchId: _selectedBranchId,
          roomId: _selectedRoomId,
          scheduledAt: scheduledAt,
          durationMinutes: _durationMinutes,
          status: 'scheduled',
          teacherRate: _teacherRate,
          isTrial: _isTrial,
          notes: _isLeadLesson
              ? 'Пробное занятие по лиду: ${widget.leadName ?? ''}'.trim()
              : null,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_savedMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // KVA-154: returns true if it's safe to proceed with the save. Queries room
  // availability for the chosen slot and, on a detected conflict (room busy or a
  // listed conflict type), prompts the user with a confirmable soft warning.
  // Any read failure is treated as "proceed" — the conflict check must never
  // hard-block lesson creation if the backend is momentarily unreachable.
  Future<bool> _confirmIfConflicting({required DateTime slotStartUtc}) async {
    final branchId = _selectedBranchId;
    final roomId = _selectedRoomId;
    // No room selected → nothing to conflict on (the lesson has no room).
    if (branchId == null || roomId == null || roomId.isEmpty) return true;

    final durationMinutes = _durationMinutes;

    List<String> conflictTypes = const [];
    try {
      final dayUtc = DateTime.utc(
        slotStartUtc.year,
        slotStartUtc.month,
        slotStartUtc.day,
      );
      final availability = await _crm.listRoomAvailability(
        branchId: branchId,
        roomId: roomId,
        date:
            '${dayUtc.year.toString().padLeft(4, '0')}-'
            '${dayUtc.month.toString().padLeft(2, '0')}-'
            '${dayUtc.day.toString().padLeft(2, '0')}',
        from: slotStartUtc.toIso8601String(),
        durationMinutes: durationMinutes,
        limit: 100,
      );
      final items = availability['items'];
      if (items is List) {
        for (final raw in items) {
          if (raw is! Map) continue;
          if (raw['room_id']?.toString() != roomId) continue;
          // NB: is_available == false only means the room already has a lesson
          // in this window — that is normal, NOT a conflict. We warn solely on
          // real conflict_types (room_overlap/teacher_overlap/…), mirroring the
          // schedule grid's own conflict semantics. Reading is_available as a
          // block is what made «Создать» silently no-op on any busy room.
          final ct = raw['conflict_types'];
          if (ct is List) {
            conflictTypes = ct.map((e) => e.toString()).toList();
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('Room availability pre-check failed: $e');
      return true; // soft-fail open — never block on a read error.
    }

    if (conflictTypes.isEmpty) return true;

    if (!mounted) return true;
    final labels = _conflictLabels(conflictTypes);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        icon: const Icon(Icons.warning_amber_rounded, color: AppColor.danger),
        title: const Text('Возможен конфликт'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('В выбранное время возможны конфликты:'),
            const SizedBox(height: 12),
            for (final label in labels)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColor.dangerSoft,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: const Color(0x52E53935)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: AppColor.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
            const Text('Создать занятие всё равно?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.gold,
              foregroundColor: AppColor.onGold,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Создать всё равно'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// All four matrix conflict types surfaced at booking time (P2-4). Mirrors the
  /// schedule's `_conflictLabel` mapping; falls back to a generic label.
  List<String> _conflictLabels(List<String> conflictTypes) {
    final labels = <String>[];
    for (final type in conflictTypes) {
      switch (type) {
        case 'room_overlap':
          labels.add('Аудитория занята в это время');
          break;
        case 'teacher_overlap':
          labels.add('Преподаватель занят в это время');
          break;
        case 'missing_teacher':
          labels.add('Не назначен преподаватель');
          break;
        case 'branch_mismatch':
          labels.add('Филиал комнаты не совпадает');
          break;
      }
    }
    // Reached only for a genuine (but unmapped) conflict_type — stay generic
    // rather than wrongly claiming the room is busy.
    if (labels.isEmpty) labels.add('Возможен конфликт расписания');
    return labels;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryGold),
            SizedBox(height: 16),
            Text('Загрузка данных...'),
          ],
        ),
      );
    }

    return AlertDialog(
      title: Text(_dialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Пробное по лиду: «кто» уже известен и менять его здесь нечем —
            // диалог открыт из карточки именно этого лида.
            if (_isLeadLesson) ...[
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Лид'),
                child: Text(
                  widget.leadName?.trim().isNotEmpty == true
                      ? widget.leadName!
                      : 'Без имени',
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Teacher Selection
            _buildSelectionField(
              label: 'Преподаватель *',
              value: _getTeacherName(_selectedTeacherId),
              onTap: () {
                final items = _teachers.map((t) {
                  final name = _getTeacherNameFromData(t);
                  return SearchableSelectItem(
                    id: t['id'].toString(),
                    label: name,
                  );
                }).toList();

                SearchableSelect.show(
                  context: context,
                  title: 'Выберите преподавателя',
                  hintText: 'Поиск по имени...',
                  items: items,
                  selectedId: _selectedTeacherId,
                  isNullable: false,
                  onSelected: (item) =>
                      setState(() => _selectedTeacherId = item?.id),
                );
              },
            ),
            const SizedBox(height: 16),

            // У пробного по лиду занятие уже привязано к нему — группы и
            // ученика у него нет.
            if (!_isLeadLesson) ...[
              // Group Selection
              SearchablePickerField(
                label: 'Группа',
                placeholder: 'Индивидуально',
                selectedId: _selectedGroupId,
                items: [
                  for (final g in _groups)
                    SearchableSelectItem(
                      id: g['id'].toString(),
                      label: g['name']?.toString() ?? 'Без названия',
                    ),
                ],
                onSelected: (item) => setState(() {
                  _selectedGroupId = item?.id;
                  // A group lesson has no single student.
                  if (item != null) _selectedStudentId = null;
                }),
              ),

              if (_selectedGroupId == null) ...[
                const SizedBox(height: 16),
                // Student Selection
                _buildSelectionField(
                  label: 'Ученик *',
                  value: _getStudentName(_selectedStudentId),
                  onTap: () {
                    final items = _students.map((s) {
                      final name = _getStudentNameFromData(s);
                      return SearchableSelectItem(
                        id: s['id'].toString(),
                        label: name,
                      );
                    }).toList();

                    SearchableSelect.show(
                      context: context,
                      title: 'Выберите ученика',
                      hintText: 'Поиск по ФИО...',
                      items: items,
                      selectedId: _selectedStudentId,
                      isNullable: false,
                      onSelected: (item) =>
                          setState(() => _selectedStudentId = item?.id),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
            ],

            // Branch & Room
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedBranchId,
                    isExpanded: true,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    decoration: const InputDecoration(labelText: 'Филиал *'),
                    items: _branches
                        .map(
                          (b) => DropdownMenuItem(
                            value: b['id'].toString(),
                            child: Text(b['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedBranchId = val;
                        _selectedRoomId = null;
                        _rooms = [];
                      });
                      if (val != null) _loadRooms(val);
                    },
                  ),
                ),
                if (_selectedBranchId != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: SearchablePickerField(
                      label: 'Аудитория',
                      placeholder: _rooms.isEmpty
                          ? 'Нет доступных'
                          : 'Выберите аудиторию',
                      enabled: _rooms.isNotEmpty,
                      selectedId: _selectedRoomId,
                      items: [
                        for (final r in _rooms)
                          SearchableSelectItem(
                            id: r['id'].toString(),
                            label: r['name']?.toString() ?? '—',
                          ),
                      ],
                      onSelected: (item) =>
                          setState(() => _selectedRoomId = item?.id),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 30),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) setState(() => _selectedDate = d);
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(
                      DateFormat('dd.MM.yyyy', 'ru').format(_selectedDate),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                        builder: (BuildContext context, Widget? child) {
                          return MediaQuery(
                            data: MediaQuery.of(
                              context,
                            ).copyWith(alwaysUse24HourFormat: true),
                            child: child!,
                          );
                        },
                      );
                      if (t != null) setState(() => _selectedTime = t);
                    },
                    icon: const Icon(Icons.access_time_rounded, size: 18),
                    label: Text(_selectedTime.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ✔ Решение владельца 17.07: «индивидуальный пробный» — это не
            // отдельный тип занятия, а пометка «пробное» на обычном занятии.
            // Списание с личного счёта за него админ/менеджер назначает сам:
            // автоматики здесь нет, и она не задумана.
            SwitchListTile(
              value: _isTrial,
              activeThumbColor: AppTheme.primaryGold,
              contentPadding: EdgeInsets.zero,
              title: const Text('Пробное занятие'),
              subtitle: Text(
                _isTrial
                    ? 'Списание с личного счёта назначается вручную'
                    : 'Обычное занятие',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              // У пресета пробного галочку не снимают: диалог открыт кнопкой
              // «На пробный», и снятая пометка сделала бы её ложью.
              onChanged: _isLeadLesson
                  ? null
                  : (value) => setState(() => _isTrial = value),
            ),
            const SizedBox(height: 8),
            // #6: поурочная ставка педагога (по умолчанию — ставка группы/
            // педагога, «Входит в оклад» = 0 для пробных).
            TeacherRateSelector(
              label: 'Ставка за занятие (₽/астр.ч.)',
              allowInherit: true,
              initialRate: _teacherRate,
              onChanged: (v) => setState(() => _teacherRate = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Отмена',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
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

  String _getTeacherName(String? id) {
    if (id == null) return 'Не выбран';
    final t = _teachers.firstWhere(
      (element) => element['id'].toString() == id,
      orElse: () => {},
    );
    if (t.isEmpty) return 'Не выбран';
    return _getTeacherNameFromData(t);
  }

  String _getTeacherNameFromData(Map<String, dynamic> t) {
    final fn = t['first_name']?.toString() ?? '';
    final ln = t['last_name']?.toString() ?? '';
    final p = t['profiles'] as Map<String, dynamic>?;

    var name = '$fn $ln'.trim();
    if (name.isEmpty && p != null) {
      name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    }
    return name.isEmpty ? 'Без имени' : name;
  }

  String _getStudentName(String? id) {
    if (id == null) return 'Не выбран';
    final s = _students.firstWhere(
      (element) => element['id'].toString() == id,
      orElse: () => {},
    );
    if (s.isEmpty) return 'Не выбран';
    return _getStudentNameFromData(s);
  }

  String _getStudentNameFromData(Map<String, dynamic> s) {
    final fn = s['first_name']?.toString() ?? '';
    final ln = s['last_name']?.toString() ?? '';
    final p = s['profiles'] as Map<String, dynamic>?;

    var name = '$fn $ln'.trim();
    if (name.isEmpty && p != null) {
      name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    }
    return name.isEmpty ? 'Без имени' : name;
  }

  Widget _buildSelectionField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.transparent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      color: value == 'Не выбран'
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
