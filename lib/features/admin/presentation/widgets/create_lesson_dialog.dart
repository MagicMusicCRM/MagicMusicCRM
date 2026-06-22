import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:intl/intl.dart';

class CreateLessonDialog extends ConsumerStatefulWidget {
  final DateTime? initialDate;
  final String? initialRoomId;
  final String? initialBranchId;
  // When provided, the dialog edits this existing lesson instead of creating a
  // new one (pre-filled fields, "Сохранить" updates via PATCH).
  final Map<String, dynamic>? lesson;

  const CreateLessonDialog({
    super.key,
    this.initialDate,
    this.initialRoomId,
    this.initialBranchId,
    this.lesson,
  });

  static Future<bool?> show(
    BuildContext context, {
    DateTime? initialDate,
    String? initialRoomId,
    String? initialBranchId,
    Map<String, dynamic>? lesson,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => CreateLessonDialog(
        initialDate: initialDate,
        initialRoomId: initialRoomId,
        initialBranchId: initialBranchId,
        lesson: lesson,
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

  bool get _isEdit => widget.lesson != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!;
      _selectedTime = TimeOfDay.fromDateTime(widget.initialDate!);
    }
    if (widget.initialRoomId != null) {
      _selectedRoomId = widget.initialRoomId;
    }
    if (widget.initialBranchId != null) {
      _selectedBranchId = widget.initialBranchId;
      _loadRooms(widget.initialBranchId!);
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
    }
    _loadData();
  }

  MagicCrmService get _crm => ref.read(magicCrmServiceProvider);

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
    if (_selectedTeacherId == null ||
        (_selectedGroupId == null && _selectedStudentId == null) ||
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
        );
      } else {
        await _crm.createLesson(
          teacherId: _selectedTeacherId,
          groupId: _selectedGroupId,
          studentId: _selectedStudentId,
          branchId: _selectedBranchId,
          roomId: _selectedRoomId,
          scheduledAt: scheduledAt,
          status: 'scheduled',
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'Занятие обновлено' : 'Занятие создано'),
          ),
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

    const durationMinutes = 60; // matches the backend's default lesson length.

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
      title: Text(_isEdit ? 'Редактировать занятие' : 'Новое занятие'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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

            // Group Selection
            DropdownButtonFormField<String>(
              initialValue: _selectedGroupId,
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: const InputDecoration(
                labelText: 'Группа',
                prefixIcon: Icon(Icons.group_rounded),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Индивидуально'),
                ),
                ..._groups.map(
                  (g) => DropdownMenuItem(
                    value: g['id'].toString(),
                    child: Text(g['name']?.toString() ?? 'Без названия'),
                  ),
                ),
              ],
              onChanged: (val) => setState(() {
                _selectedGroupId = val;
                if (val != null) _selectedStudentId = null;
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
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedRoomId,
                      isExpanded: true,
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      decoration: const InputDecoration(labelText: 'Аудитория'),
                      items: _rooms.isEmpty
                          ? [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Нет доступных'),
                              ),
                            ]
                          : _rooms
                                .map(
                                  (r) => DropdownMenuItem(
                                    value: r['id'].toString(),
                                    child: Text(r['name']?.toString() ?? ''),
                                  ),
                                )
                                .toList(),
                      onChanged: (val) => setState(() => _selectedRoomId = val),
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
                    label: Text(DateFormat('dd.MM.yyyy').format(_selectedDate)),
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
