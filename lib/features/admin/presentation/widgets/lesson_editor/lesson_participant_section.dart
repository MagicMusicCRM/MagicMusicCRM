import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';

import 'lesson_editor_models.dart';

class LessonParticipantSectionModel {
  const LessonParticipantSectionModel({
    required this.session,
    required this.draft,
    required this.references,
  });

  final LessonEditorSession session;
  final LessonEditorDraft draft;
  final LessonEditorReferenceState references;

  bool get isGroupEdit => session.isGroupEdit;

  bool get isClientLocked => session.isEdit || session.seededClient != null;

  List<LessonEditorReferenceItem> get eligibleTeachers => [
    for (final teacher in references.teachers)
      if (teacher.status == 'active' &&
          teacher.assignedBranchIds.contains(draft.branchId))
        teacher,
  ];

  List<LessonEditorReferenceItem> get eligibleRooms => [
    for (final room in references.rooms)
      if (room.branchId == draft.branchId && room.status != 'archived') room,
  ];
}

class LessonParticipantSection extends StatelessWidget {
  const LessonParticipantSection({
    required this.model,
    required this.onSearchClients,
    required this.onClientChanged,
    required this.onBranchChanged,
    required this.onRoomChanged,
    required this.onTeacherChanged,
    super.key,
  });

  final LessonParticipantSectionModel model;
  final Future<List<LessonClientRef>> Function(String query) onSearchClients;
  final ValueChanged<LessonClientRef?> onClientChanged;
  final ValueChanged<String?> onBranchChanged;
  final ValueChanged<String?> onRoomChanged;
  final ValueChanged<String?> onTeacherChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ClientField(
          model: model,
          onSearch: onSearchClients,
          onChanged: onClientChanged,
        ),
        const SizedBox(height: 16),
        _BranchRoomFields(
          model: model,
          onBranchChanged: onBranchChanged,
          onRoomChanged: onRoomChanged,
        ),
        const SizedBox(height: 16),
        _TeacherFields(model: model, onChanged: onTeacherChanged),
      ],
    );
  }
}

class _ClientField extends StatelessWidget {
  const _ClientField({
    required this.model,
    required this.onSearch,
    required this.onChanged,
  });

  final LessonParticipantSectionModel model;
  final Future<List<LessonClientRef>> Function(String query) onSearch;
  final ValueChanged<LessonClientRef?> onChanged;

  @override
  Widget build(BuildContext context) {
    final client = model.draft.client;
    if (model.isGroupEdit) {
      return InputDecorator(
        key: const ValueKey('lesson-group-field'),
        decoration: const InputDecoration(
          labelText: 'Группа *',
          enabled: false,
          helperText: 'Группа и замороженный состав сохраняются при переносе',
        ),
        child: Text(client?.label ?? 'Группа'),
      );
    }
    return SearchablePickerField(
      key: const ValueKey('lesson-client-field'),
      label: 'Клиент *',
      placeholder: 'Не выбран',
      hintText: 'Введите имя или ФИО клиента',
      selectedId: client?.key,
      selectedLabel: client == null
          ? null
          : '${client.label} · ${client.type == 'lead' ? 'Lead' : 'Student'}',
      items: [
        for (final item in model.references.clients)
          SearchableSelectItem(
            id: item.id,
            label: item.label,
            subtitle: _clientType(item) == 'lead' ? 'Lead' : 'Student',
            data: item.raw,
          ),
      ],
      onSearch: (query) async => [
        for (final client in await onSearch(query))
          SearchableSelectItem(
            id: client.key,
            label: client.label,
            subtitle: client.type == 'lead' ? 'Lead' : 'Student',
            data: {
              'ref': {'type': client.type, 'id': client.id},
              if (client.branchId != null) 'branchId': client.branchId,
            },
          ),
      ],
      isNullable: false,
      enabled: !model.isClientLocked,
      onSelected: (item) => onChanged(
        item == null ? null : _clientReference(item, model.references.clients),
      ),
    );
  }
}

class _BranchRoomFields extends StatelessWidget {
  const _BranchRoomFields({
    required this.model,
    required this.onBranchChanged,
    required this.onRoomChanged,
  });

  final LessonParticipantSectionModel model;
  final ValueChanged<String?> onBranchChanged;
  final ValueChanged<String?> onRoomChanged;

  @override
  Widget build(BuildContext context) {
    final draft = model.draft;
    final rooms = model.eligibleRooms;
    return _ResponsivePair(
      first: DropdownButtonFormField<String>(
        menuMaxHeight: 256,
        key: ValueKey('lesson-branch-field:${draft.branchId}'),
        initialValue: draft.branchId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Филиал *'),
        items: [
          for (final branch in model.references.branches)
            DropdownMenuItem(value: branch.id, child: Text(branch.label)),
        ],
        onChanged: onBranchChanged,
      ),
      second: SearchablePickerField(
        key: const ValueKey('lesson-room-field'),
        label: 'Аудитория *',
        placeholder: rooms.isEmpty
            ? 'Нет аудиторий в филиале'
            : 'Выберите аудиторию',
        enabled: rooms.isNotEmpty,
        selectedId: draft.roomId,
        items: [
          for (final room in rooms)
            SearchableSelectItem(
              id: room.id,
              label: room.label,
              subtitle: 'Аудитория выбранного филиала',
            ),
        ],
        onSelected: (item) => onRoomChanged(item?.id),
      ),
    );
  }
}

class _TeacherFields extends StatelessWidget {
  const _TeacherFields({required this.model, required this.onChanged});

  final LessonParticipantSectionModel model;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final draft = model.draft;
    final teachers = model.eligibleTeachers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchablePickerField(
          key: const ValueKey('lesson-teacher-field'),
          label: 'Преподаватель *',
          placeholder: 'Выберите преподавателя',
          hintText: 'Введите имя или ФИО преподавателя',
          selectedId: draft.teacherId,
          selectedLabel: _labelById(model.references.teachers, draft.teacherId),
          items: [
            for (final teacher in teachers)
              SearchableSelectItem(
                id: teacher.id,
                label: teacher.label,
                subtitle: 'Назначен в выбранный филиал',
              ),
          ],
          isNullable: false,
          enabled: teachers.isNotEmpty,
          onSelected: (item) => onChanged(item?.id),
        ),
        if (draft.branchId != null && teachers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'В выбранный филиал не назначен ни один активный преподаватель.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        if (draft.branchId != null) ...[
          const SizedBox(height: 8),
          Text(
            key: const ValueKey('lesson-replacement-availability-hint'),
            'Занятость проверим перед сохранением.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
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
}

LessonClientRef _clientReference(
  SearchableSelectItem selected,
  List<LessonEditorReferenceItem> references,
) {
  final selectedReference = _selectedClientReference(selected);
  if (selectedReference != null) return selectedReference;
  final reference = references.firstWhere(
    (item) => item.id == selected.id,
    orElse: () => LessonEditorReferenceItem(
      id: selected.id,
      label: selected.label,
      raw: selected.data ?? const {},
      branchId: selected.data?['branchId']?.toString(),
    ),
  );
  return _storedClientReference(reference);
}

LessonClientRef? _selectedClientReference(SearchableSelectItem selected) {
  final data = selected.data;
  final ref = data?['ref'];
  if (ref is! Map || ref['type'] == null || ref['id'] == null) return null;
  return LessonClientRef(
    type: ref['type'].toString(),
    id: ref['id'].toString(),
    label: selected.label,
    branchId: data?['branchId']?.toString(),
  );
}

LessonClientRef _storedClientReference(LessonEditorReferenceItem reference) {
  final ref = reference.raw['ref'];
  final type = ref is Map ? ref['type']?.toString() : null;
  final id = ref is Map ? ref['id']?.toString() : null;
  final keyParts = reference.id.split(':');
  return LessonClientRef(
    type: type ?? (keyParts.length > 1 ? keyParts.first : 'student'),
    id: id ?? (keyParts.length > 1 ? keyParts.skip(1).join(':') : reference.id),
    label: reference.label,
    branchId: reference.branchId,
  );
}

String _clientType(LessonEditorReferenceItem item) {
  final ref = item.raw['ref'];
  if (ref is Map && ref['type'] != null) return ref['type'].toString();
  final separator = item.id.indexOf(':');
  return separator < 0 ? 'student' : item.id.substring(0, separator);
}

String? _labelById(List<LessonEditorReferenceItem> items, String? id) {
  if (id == null) return null;
  for (final item in items) {
    if (item.id == id) return item.label;
  }
  return 'Не выбран';
}
