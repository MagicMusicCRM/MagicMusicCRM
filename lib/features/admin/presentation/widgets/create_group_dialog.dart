import 'package:magic_music_crm/core/widgets/form_feedback.dart';
import 'package:magic_music_crm/core/widgets/app_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/navigation/crm_nav_rbac.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'lesson_decision/lesson_decision_models.dart';

Future<bool?> showCreateGroupSurface(
  BuildContext context, {
  Map<String, dynamic>? group,
}) {
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.selection,
    title: group == null ? 'Новая учебная группа' : 'Настройки группы',
    subtitle: 'Преподаватель, филиал и аудитория',
    icon: Icons.groups_2_outlined,
    scrollBody: false,
    builder: (_) => CreateGroupDialog(group: group),
  );
}

class CreateGroupDialog extends ConsumerStatefulWidget {
  const CreateGroupDialog({super.key, this.group});
  final Map<String, dynamic>? group;

  @override
  ConsumerState<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends ConsumerState<CreateGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  LessonDecisionCatalog? _catalog;
  String? _settlementKey;
  String? _compensationKey;
  bool _catalogLoading = false;
  String? _catalogError;
  int _catalogRevision = 0;

  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _rooms = [];
  String? _teacherId;
  String? _branchId;
  String? _roomId;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    if (group != null) {
      _nameController.text = group['name']?.toString() ?? '';
      _branchId = group['branch_id']?.toString();
      _teacherId = group['teacher_id']?.toString();
      _roomId = group['room_id']?.toString();
      _settlementKey = group['settlement_type_key']?.toString();
      _compensationKey = group['teacher_compensation_rule_key']?.toString();
    }
    _loadReferences();
  }

  @override
  void dispose() {
    _nameController.dispose();

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
      if (_branchId != null) await _loadCatalog();
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
    if (!validateAndRevealForm(_formKey)) return;
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
      final snapshot = ref.read(capabilitySnapshotProvider).asData?.value;
      final canManageRate =
          snapshot != null && crmCanManageTeacherRates(snapshot);
      if (_settlementKey == null ||
          _compensationKey == null ||
          _catalogError != null) {
        throw StateError('Выберите тип списания и тип оплаты преподавателю.');
      }
      final crm = ref.read(magicCrmServiceProvider);
      if (widget.group == null) {
        await crm.createGroup(
          name: _nameController.text,
          teacherId: _teacherId!,
          branchId: _branchId!,
          roomId: _roomId!,
          settlementTypeKey: _settlementKey,
          teacherCompensationRuleKey: canManageRate ? _compensationKey : null,
        );
      } else {
        await crm.updateGroup(
          widget.group!['id'].toString(),
          name: _nameController.text,
          teacherId: _teacherId!,
          branchId: _branchId!,
          roomId: _roomId!,
          settlementTypeKey: _settlementKey,
          teacherCompensationRuleKey: canManageRate ? _compensationKey : null,
          expectedVersion: (widget.group!['version'] as num).toInt(),
        );
      }
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

  Future<void> _loadCatalog() async {
    final branchId = _branchId;
    final revision = ++_catalogRevision;
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
      _catalog = null;
    });
    try {
      final raw = await ref
          .read(magicCrmServiceProvider)
          .getLessonDecisionCatalog(branchId: branchId);
      if (!mounted || revision != _catalogRevision) return;
      final catalog = LessonDecisionCatalog.fromJson(
        raw,
        LessonDecisionOperation.settle,
      );
      setState(() {
        _catalog = catalog;
        if (!catalog.settlementTypes.any(
          (item) => item.key == _settlementKey,
        )) {
          _settlementKey =
              catalog.settlementTypes
                  .where((item) => item.key == 'lesson')
                  .firstOrNull
                  ?.key ??
              catalog.settlementTypes.firstOrNull?.key;
        }
        if (!catalog.compensationRules.any(
          (item) => item.key == _compensationKey,
        )) {
          _compensationKey = catalog.settlementTypes
              .where((item) => item.key == _settlementKey)
              .firstOrNull
              ?.defaultTeacherCompensationRuleKey;
        }
        _catalogLoading = false;
      });
    } catch (error) {
      if (!mounted || revision != _catalogRevision) return;
      setState(() {
        _catalogLoading = false;
        _catalogError = userErrorMessage(
          error,
          fallback: 'Не удалось загрузить типы расчёта.',
        );
      });
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
    final snapshot = ref.watch(capabilitySnapshotProvider).asData?.value;
    final canManageRate =
        snapshot != null && crmCanManageTeacherRates(snapshot);
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
    final fields = Form(
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
          AppDropdownButtonFormField<String>(
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
              _loadCatalog();
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
          if (_branchId != null) ...[
            if (_catalogLoading) const LinearProgressIndicator(),
            if (_catalogError != null) Text(_catalogError!),
            AppDropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: ValueKey('group-settlement-$_settlementKey'),
              initialValue: _settlementKey,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Тип списания *'),
              items: [
                for (final item
                    in _catalog?.settlementTypes ??
                        <LessonDecisionCatalogItem>[])
                  DropdownMenuItem(value: item.key, child: Text(item.label)),
              ],
              onChanged: _catalogLoading
                  ? null
                  : (key) => setState(() {
                      _settlementKey = key;
                      _compensationKey = _catalog?.settlementTypes
                          .where((item) => item.key == key)
                          .firstOrNull
                          ?.defaultTeacherCompensationRuleKey;
                    }),
              validator: (value) =>
                  value == null ? 'Выберите тип списания' : null,
            ),
            const SizedBox(height: 12),
            AppDropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: ValueKey('group-compensation-$_compensationKey'),
              initialValue: _compensationKey,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Тип оплаты преподавателю *',
              ),
              items: [
                for (final item
                    in _catalog?.compensationRules ??
                        <LessonDecisionCatalogItem>[])
                  DropdownMenuItem(value: item.key, child: Text(item.label)),
              ],
              onChanged: canManageRate && !_catalogLoading
                  ? (key) => setState(() => _compensationKey = key)
                  : null,
              validator: (value) =>
                  value == null ? 'Выберите тип оплаты' : null,
            ),
          ],
        ],
      ),
    );
    return MagicFormBody(
      hasChanges: () =>
          _nameController.text.isNotEmpty ||
          _teacherId != null ||
          _branchId != null ||
          _roomId != null ||
          _settlementKey != null,
      busy: () => _saving,
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.maybePop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving || _catalogLoading ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.group == null ? 'Создать группу' : 'Сохранить'),
        ),
      ],
      child: fields,
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
