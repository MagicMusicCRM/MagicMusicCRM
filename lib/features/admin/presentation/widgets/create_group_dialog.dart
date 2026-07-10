import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';

class CreateGroupDialog extends ConsumerStatefulWidget {
  const CreateGroupDialog({super.key});

  @override
  ConsumerState<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends ConsumerState<CreateGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _rooms = [];
  String? _teacherId;
  String? _branchId;
  String? _roomId;
  // KVA-238: переопределение ставки педагога; null = брать ставку педагога.
  num? _teacherRate;

  @override
  void initState() {
    super.initState();
    _loadReferences();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _loadReferences() async {
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final results = await Future.wait([
        crm.listTeachers(limit: 100),
        crm.listBranches(limit: 100),
        crm.listRooms(limit: 100),
      ]);
      if (!mounted) return;
      setState(() {
        _teachers = results[0];
        _branches = results[1];
        _rooms = results[2];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final rawPrice = _priceController.text.trim().replaceAll(',', '.');
      await ref
          .read(magicCrmServiceProvider)
          .createGroup(
            name: _nameController.text,
            teacherId: _teacherId,
            branchId: _branchId,
            roomId: _roomId,
            pricePerLesson: rawPrice.isEmpty ? null : num.parse(rawPrice),
            teacherRate: _teacherRate,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleRooms = _branchId == null
        ? _rooms
        : _rooms
              .where((room) => room['branch_id']?.toString() == _branchId)
              .toList();

    return AlertDialog(
      title: const Text('Новая группа'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: _loading
          ? const SizedBox(
              width: 320,
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            )
          : SizedBox(
              width: 420,
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Название группы *',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Введите название группы';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('teacher-$_teacherId'),
                        initialValue: _teacherId,
                        decoration: const InputDecoration(
                          labelText: 'Преподаватель',
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Без преподавателя'),
                          ),
                          ..._teachers.map(
                            (teacher) => DropdownMenuItem<String>(
                              value: teacher['id']?.toString(),
                              child: Text(_personName(teacher)),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _teacherId = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('branch-$_branchId'),
                        initialValue: _branchId,
                        decoration: const InputDecoration(labelText: 'Филиал'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Без филиала'),
                          ),
                          ..._branches.map(
                            (branch) => DropdownMenuItem<String>(
                              value: branch['id']?.toString(),
                              child: Text(
                                branch['name']?.toString() ?? 'Филиал',
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          final nextRooms = value == null
                              ? _rooms
                              : _rooms
                                    .where(
                                      (room) =>
                                          room['branch_id']?.toString() ==
                                          value,
                                    )
                                    .toList();
                          setState(() {
                            _branchId = value;
                            if (_roomId != null &&
                                !nextRooms.any(
                                  (room) => room['id']?.toString() == _roomId,
                                )) {
                              _roomId = null;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('room-$_branchId-$_roomId'),
                        initialValue: _roomId,
                        decoration: const InputDecoration(
                          labelText: 'Аудитория',
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Без аудитории'),
                          ),
                          ...visibleRooms.map(
                            (room) => DropdownMenuItem<String>(
                              value: room['id']?.toString(),
                              child: Text(
                                room['name']?.toString() ?? 'Аудитория',
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _roomId = value),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Цена за занятие',
                        ),
                        validator: (value) {
                          final text = value?.trim().replaceAll(',', '.') ?? '';
                          if (text.isEmpty) return null;
                          final parsed = num.tryParse(text);
                          if (parsed == null || parsed < 0) {
                            return 'Введите корректную цену';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      // KVA-238: ставка педагога по группе (переопределение).
                      TeacherRateSelector(
                        allowInherit: true,
                        label: 'Ставка педагога по группе',
                        onChanged: (rate) => _teacherRate = rate,
                      ),
                    ],
                  ),
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _loading || _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryGold,
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Создать'),
        ),
      ],
    );
  }

  String _personName(Map<String, dynamic> person) {
    final first = person['first_name']?.toString() ?? '';
    final last = person['last_name']?.toString() ?? '';
    final email = person['email']?.toString() ?? '';
    final name = '$first $last'.trim();
    return name.isEmpty ? (email.isEmpty ? 'Без имени' : email) : name;
  }
}
