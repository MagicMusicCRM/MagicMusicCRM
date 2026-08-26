import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';

Future<bool?> showCreateGroupSurface(BuildContext context) {
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.selection,
    title: 'Новая учебная группа',
    subtitle: 'Преподаватель, филиал и аудитория',
    icon: Icons.groups_2_outlined,
    builder: (_) => const CreateGroupDialog(),
  );
}

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
  String? _loadError;
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _rooms = [];
  String? _teacherId;
  String? _branchId;
  String? _roomId;
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
    setState(() {
      _loading = true;
      _loadError = null;
    });
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
      setState(() {
        _loading = false;
        _loadError = userErrorMessage(
          e,
          fallback: 'Не удалось загрузить данные для группы.',
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_branchId == null || _teacherId == null || _roomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Выберите филиал, преподавателя и аудиторию.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);

    try {
      final rawPrice = _priceController.text.trim().replaceAll(',', '.');
      await ref
          .read(magicCrmServiceProvider)
          .createGroup(
            name: _nameController.text,
            teacherId: _teacherId!,
            branchId: _branchId!,
            roomId: _roomId!,
            pricePerLesson: rawPrice.isEmpty ? null : num.parse(rawPrice),
            teacherRate: _teacherRate,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось создать группу.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _selectedTeacherName() {
    for (final teacher in _teachers) {
      if (teacher['id']?.toString() == _teacherId) return _personName(teacher);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Column(
        key: const ValueKey('create-group-load-error'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Не удалось загрузить данные для создания группы.'),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _loadReferences,
            child: const Text('Повторить'),
          ),
        ],
      );
    }

    final visibleRooms = _branchId == null
        ? const <Map<String, dynamic>>[]
        : _rooms
              .where((room) => room['branch_id']?.toString() == _branchId)
              .toList();
    final visibleTeachers = _branchId == null
        ? const <Map<String, dynamic>>[]
        : _teachers.where((teacher) {
            final status = teacher['status']?.toString().toLowerCase();
            if (status != 'active' &&
                status != 'working' &&
                status != 'активен' &&
                status != 'работает') {
              return false;
            }
            final assigned = teacher['assigned_branches'];
            return assigned is List &&
                assigned.any(
                  (branch) =>
                      branch is Map && branch['id']?.toString() == _branchId,
                );
          }).toList();
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('create-group-form'),
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Название группы *'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Введите название группы'
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            menuMaxHeight: 256,
            key: ValueKey('group-branch-$_branchId'),
            initialValue: _branchId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Филиал *'),
            items: [
              for (final branch in _branches)
                DropdownMenuItem<String>(
                  value: branch['id']?.toString(),
                  child: Text(branch['name']?.toString() ?? 'Филиал'),
                ),
            ],
            onChanged: (value) {
              setState(() {
                _branchId = value;
                _teacherId = null;
                _roomId = null;
              });
            },
            validator: (value) => value == null ? 'Выберите филиал' : null,
          ),
          const SizedBox(height: 12),
          SearchablePickerField(
            key: const ValueKey('group-teacher-field'),
            label: 'Преподаватель *',
            placeholder: _branchId == null
                ? 'Сначала выберите филиал'
                : visibleTeachers.isEmpty
                ? 'Нет назначенных преподавателей'
                : 'Выберите преподавателя',
            hintText: 'Введите имя или ФИО преподавателя',
            enabled: _branchId != null && visibleTeachers.isNotEmpty,
            selectedId: _teacherId,
            selectedLabel: _selectedTeacherName(),
            isNullable: false,
            items: [
              for (final teacher in visibleTeachers)
                SearchableSelectItem(
                  id: teacher['id']?.toString() ?? '',
                  label: _personName(teacher),
                ),
            ],
            onSelected: (item) => setState(() => _teacherId = item?.id),
          ),
          const SizedBox(height: 12),
          SearchablePickerField(
            key: const ValueKey('group-room-field'),
            label: 'Аудитория *',
            placeholder: _branchId == null
                ? 'Сначала выберите филиал'
                : visibleRooms.isEmpty
                ? 'Нет аудиторий. Добавьте их в филиале'
                : 'Выберите аудиторию',
            selectedId: _roomId,
            items: [
              for (final room in visibleRooms)
                SearchableSelectItem(
                  id: room['id'].toString(),
                  label: room['name']?.toString() ?? 'Аудитория',
                ),
            ],
            onSelected: (item) => setState(() => _roomId = item?.id),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Цена за занятие'),
            validator: (value) {
              final text = value?.trim().replaceAll(',', '.') ?? '';
              if (text.isEmpty) return null;
              final parsed = num.tryParse(text);
              return parsed == null || parsed < 0
                  ? 'Введите корректную цену'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          TeacherRateSelector(
            allowInherit: true,
            label: 'Ставка педагога по группе',
            onChanged: (rate) => _teacherRate = rate,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Создать группу'),
                ),
              ),
            ],
          ),
        ],
      ),
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
