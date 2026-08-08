import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_room_dialog.dart';

String _utcOffsetLabel(int minutes) {
  final sign = minutes >= 0 ? '+' : '-';
  final abs = minutes.abs();
  final h = abs ~/ 60;
  final m = abs % 60;
  final timeStr = m == 0
      ? 'UTC$sign$h'
      : 'UTC$sign$h:${m.toString().padLeft(2, '0')}';
  return switch (minutes) {
    180 => 'МСК ($timeStr)',
    120 => 'EET ($timeStr)',
    60 => 'CET ($timeStr)',
    0 => 'UTC',
    _ => timeStr,
  };
}

class BranchFormDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? branch;

  const BranchFormDialog({super.key, this.branch});

  @override
  ConsumerState<BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends ConsumerState<BranchFormDialog> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  int _utcOffsetMinutes = 180;
  bool _saving = false;
  bool _loadingRooms = false;
  String? _roomsError;
  List<Map<String, dynamic>> _rooms = const [];
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
          .listRooms(branchId: id);
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loadingRooms = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingRooms = false;
        _roomsError = '$error';
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
        crm.listBranchDisciplines(id),
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
        _disciplinesError = '$error';
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
              child: Text(discipline['name']?.toString() ?? '—'),
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
        SnackBar(content: Text('Не удалось добавить дисциплину: $error')),
      );
    }
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

    setState(() => _saving = true);
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final address = _addressController.text.trim();

      if (widget.branch == null) {
        await crm.createBranch(
          name: name,
          address: address.isEmpty ? null : address,
          utcOffsetMinutes: _utcOffsetMinutes,
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
          SnackBar(content: Text('Не удалось сохранить филиал: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                        Chip(
                          label: Text(
                            discipline['name']?.toString() ?? 'Дисциплина',
                          ),
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
                      leading: const Icon(Icons.meeting_room_outlined),
                      title: Text(room['name']?.toString() ?? 'Аудитория'),
                      subtitle: Text(
                        'Вместимость: ${room['capacity']?.toString() ?? 'не указана'}',
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _openRoom(room),
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
