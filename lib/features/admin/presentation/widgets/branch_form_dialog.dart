import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_room_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/room_lifecycle_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/reference_catalog_lifecycle_dialog.dart';

String _utcOffsetLabel(int minutes) {
  final sign = minutes >= 0 ? '+' : '-';
  final abs = minutes.abs();
  final h = abs ~/ 60;
  final m = abs % 60;
  final offset = m == 0 ? '$sign$h ч' : '$sign$h ч $m мин';
  return switch (minutes) {
    180 => 'Москва ($offset)',
    120 => 'Калининград ($offset)',
    60 => 'Центральная Европа ($offset)',
    0 => 'Всемирное время',
    _ => 'Смещение $offset',
  };
}

class BranchFormDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? branch;

  const BranchFormDialog({super.key, this.branch});

  @override
  ConsumerState<BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends ConsumerState<BranchFormDialog> {
  static const _dayNames = <int, String>{
    1: 'Понедельник',
    2: 'Вторник',
    3: 'Среда',
    4: 'Четверг',
    5: 'Пятница',
    6: 'Суббота',
    7: 'Воскресенье',
  };

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final Map<int, Map<String, dynamic>> _weeklyHours = {};
  int _utcOffsetMinutes = 180;
  bool _saving = false;
  bool _loadingRooms = false;
  String? _roomsError;
  List<Map<String, dynamic>> _rooms = const [];
  bool _showArchivedRooms = false;
  bool _loadingDisciplines = false;
  String? _disciplinesError;
  List<Map<String, dynamic>> _disciplines = const [];
  List<Map<String, dynamic>> _allDisciplines = const [];

  static final List<int> _offsetOptions = List.generate(
    (14 * 60 + 12 * 60) ~/ 30 + 1,
    (i) => -12 * 60 + i * 30,
  );

  @override
  void initState() {
    super.initState();
    if (widget.branch != null) {
      _nameController.text = widget.branch!['name'] as String? ?? '';
      _addressController.text = widget.branch!['address'] as String? ?? '';
      _utcOffsetMinutes =
          (widget.branch!['utc_offset_minutes'] as num?)?.toInt() ?? 180;
      _loadRooms();
      _loadDisciplines();
    }
  }

  Future<void> _loadRooms() async {
    final id = widget.branch?['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() {
      _loadingRooms = true;
      _roomsError = null;
    });
    try {
      final rooms = await ref
          .read(magicCrmServiceProvider)
          .listRooms(branchId: id, includeArchived: _showArchivedRooms);
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loadingRooms = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingRooms = false;
        _roomsError = userErrorMessage(
          error,
          fallback: 'Не удалось загрузить аудитории.',
        );
      });
    }
  }

  Future<void> _openRoom([Map<String, dynamic>? room]) async {
    final id = widget.branch?['id']?.toString();
    if (id == null || id.isEmpty) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CreateRoomDialog(
        room: room,
        branchId: id,
        branchName: _nameController.text.trim(),
      ),
    );
    if (saved == true) await _loadRooms();
  }

  Future<void> _openRoomLifecycle(Map<String, dynamic> room) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => RoomLifecycleDialog(room: room),
    );
    if (changed == true) await _loadRooms();
  }

  Future<void> _loadDisciplines() async {
    final id = widget.branch?['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() {
      _loadingDisciplines = true;
      _disciplinesError = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final values = await Future.wait([
        crm.listBranchDisciplines(id, includeArchived: true),
        crm.listDisciplines(),
      ]);
      if (!mounted) return;
      setState(() {
        _disciplines = values[0];
        _allDisciplines = values[1];
        _loadingDisciplines = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingDisciplines = false;
        _disciplinesError = userErrorMessage(
          error,
          fallback: 'Не удалось загрузить дисциплины.',
        );
      });
    }
  }

  Future<void> _addDiscipline() async {
    final branchId = widget.branch?['id']?.toString();
    if (branchId == null || branchId.isEmpty) return;
    final assigned = _disciplines
        .map((item) => item['discipline_id']?.toString())
        .toSet();
    final available = _allDisciplines
        .where((item) => !assigned.contains(item['id']?.toString()))
        .toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Все доступные дисциплины уже добавлены')),
      );
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Добавить дисциплину'),
        children: [
          for (final discipline in available)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(context, discipline['id']?.toString()),
              child: Text(discipline['name']?.toString() ?? 'Не указано'),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await ref
          .read(magicCrmServiceProvider)
          .assignBranchDiscipline(branchId: branchId, disciplineId: selected);
      await _loadDisciplines();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(
              error,
              fallback: 'Не удалось добавить дисциплину.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openDisciplineLifecycle(Map<String, dynamic> discipline) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => ReferenceCatalogLifecycleDialog(
        entityType: 'branch_discipline',
        item: discipline,
      ),
    );
    if (changed == true) await _loadDisciplines();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Введите название филиала')));
      return;
    }
    if (widget.branch == null && _weeklyHours.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Укажите рабочие часы хотя бы для одного дня'),
        ),
      );
      return;
    }
    if (_weeklyHours.values.any(
      (value) =>
          (value['open']?.toString() ?? '').compareTo(
            value['close']?.toString() ?? '',
          ) >=
          0,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Время закрытия должно быть позже времени открытия'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final address = _addressController.text.trim();

      if (widget.branch == null) {
        await crm.createBranch(
          name: name,
          address: address.isEmpty ? null : address,
          utcOffsetMinutes: _utcOffsetMinutes,
          weeklyHours: [
            for (final entry
                in _weeklyHours.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key)))
              {
                'weekday': entry.key,
                'open': entry.value['open'],
                'close': entry.value['close'],
              },
          ],
        );
      } else {
        final id = widget.branch!['id']?.toString();
        if (id == null || id.isEmpty) return;
        await crm.updateBranch(
          id,
          name: name,
          address: address,
          utcOffsetMinutes: _utcOffsetMinutes,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось сохранить филиал.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _pickTime(String current) async {
    final parts = current.split(':').map(int.tryParse).toList();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: parts.firstOrNull ?? 9,
        minute: parts.elementAtOrNull(1) ?? 0,
      ),
    );
    return picked == null
        ? null
        : '${picked.hour.toString().padLeft(2, '0')}:'
              '${picked.minute.toString().padLeft(2, '0')}';
  }

  Widget _workingHoursEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Рабочие часы *',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text('Занятия можно создавать только внутри этого графика.'),
        const SizedBox(height: 8),
        for (final day in _dayNames.entries)
          Row(
            children: [
              Semantics(
                label:
                    '${day.value}: ${_weeklyHours.containsKey(day.key) ? 'включено' : 'выключено'}',
                toggled: _weeklyHours.containsKey(day.key),
                child: ExcludeSemantics(
                  child: Switch(
                    value: _weeklyHours.containsKey(day.key),
                    onChanged: (enabled) => setState(() {
                      if (enabled) {
                        _weeklyHours[day.key] = {
                          'open': '09:00',
                          'close': '21:00',
                        };
                      } else {
                        _weeklyHours.remove(day.key);
                      }
                    }),
                  ),
                ),
              ),
              Expanded(child: Text(day.value)),
              if (_weeklyHours[day.key] case final hours?) ...[
                TextButton(
                  onPressed: () async {
                    final value = await _pickTime(
                      hours['open']?.toString() ?? '09:00',
                    );
                    if (value != null && mounted) {
                      setState(() => hours['open'] = value);
                    }
                  },
                  child: Text(hours['open']?.toString() ?? '09:00'),
                ),
                const Text('Не указано'),
                TextButton(
                  onPressed: () async {
                    final value = await _pickTime(
                      hours['close']?.toString() ?? '21:00',
                    );
                    if (value != null && mounted) {
                      setState(() => hours['close'] = value);
                    }
                  },
                  child: Text(hours['close']?.toString() ?? '21:00'),
                ),
              ],
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.branch != null;
    return AlertDialog(
      title: Text(isEdit ? 'Редактировать филиал' : 'Новый филиал'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Название *'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Адрес'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                menuMaxHeight: 256,
                initialValue: _utcOffsetMinutes,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Часовой пояс'),
                items: _offsetOptions
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(_utcOffsetLabel(m)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _utcOffsetMinutes = v);
                },
              ),
              if (!isEdit) ...[
                const SizedBox(height: 20),
                _workingHoursEditor(),
              ],
              if (isEdit) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Дисциплины филиала',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _loadingDisciplines ? null : _addDiscipline,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Добавить'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loadingDisciplines)
                  const Center(child: CircularProgressIndicator())
                else if (_disciplinesError != null)
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Не удалось загрузить дисциплины.'),
                      ),
                      TextButton(
                        onPressed: _loadDisciplines,
                        child: const Text('Повторить'),
                      ),
                    ],
                  )
                else if (_disciplines.isEmpty)
                  const Text('Дисциплин пока нет.')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final discipline in _disciplines)
                        InputChip(
                          avatar: Icon(
                            discipline['lifecycle_state'] == 'archived'
                                ? Icons.restore_rounded
                                : Icons.school_outlined,
                            size: 18,
                          ),
                          label: Text(
                            '${discipline['name']?.toString() ?? 'Дисциплина'}'
                            '${discipline['lifecycle_state'] == 'archived' ? ' (в архиве)' : ''}',
                          ),
                          tooltip: discipline['lifecycle_state'] == 'archived'
                              ? 'Восстановить привязку'
                              : 'Проверить связи и отвязать',
                          onPressed: () => _openDisciplineLifecycle(discipline),
                        ),
                    ],
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Аудитории филиала',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _loadingRooms
                          ? null
                          : () {
                              setState(
                                () => _showArchivedRooms = !_showArchivedRooms,
                              );
                              _loadRooms();
                            },
                      icon: Icon(
                        _showArchivedRooms
                            ? Icons.visibility_off_outlined
                            : Icons.inventory_2_outlined,
                      ),
                      label: Text(
                        _showArchivedRooms ? 'Скрыть архив' : 'Архив',
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _openRoom,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Добавить'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loadingRooms)
                  const Center(child: CircularProgressIndicator())
                else if (_roomsError != null)
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Не удалось загрузить аудитории.'),
                      ),
                      TextButton(
                        onPressed: _loadRooms,
                        child: const Text('Повторить'),
                      ),
                    ],
                  )
                else if (_rooms.isEmpty)
                  const Text('Аудиторий пока нет.')
                else
                  for (final room in _rooms)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        room['lifecycle_state'] == 'archived'
                            ? Icons.inventory_2_outlined
                            : Icons.meeting_room_outlined,
                      ),
                      title: Text(room['name']?.toString() ?? 'Аудитория'),
                      subtitle: Text(
                        room['lifecycle_state'] == 'archived'
                            ? 'В архиве${room['archive_reason'] == null ? '' : ' • ${room['archive_reason']}'}'
                            : 'Вместимость: ${room['capacity']?.toString() ?? 'не указана'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (room['lifecycle_state'] != 'archived')
                            IconButton(
                              tooltip: 'Редактировать',
                              onPressed: () => _openRoom(room),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          IconButton(
                            tooltip: room['lifecycle_state'] == 'archived'
                                ? 'Восстановить'
                                : 'Проверить связи и архивировать',
                            onPressed: () => _openRoomLifecycle(room),
                            icon: Icon(
                              room['lifecycle_state'] == 'archived'
                                  ? Icons.restore_rounded
                                  : Icons.archive_outlined,
                            ),
                          ),
                        ],
                      ),
                      onTap: room['lifecycle_state'] == 'archived'
                          ? () => _openRoomLifecycle(room)
                          : () => _openRoom(room),
                    ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
