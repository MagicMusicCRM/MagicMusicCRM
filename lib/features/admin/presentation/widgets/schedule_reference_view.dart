import 'dart:async';

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/widgets/magic_toast.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

import 'schedule_reference_cards.dart';
import 'schedule_reference_controller.dart';
import 'schedule_reference_models.dart';

class ScheduleReferenceView extends StatelessWidget {
  const ScheduleReferenceView({
    super.key,
    required this.controller,
    required this.onRetry,
  });

  final ScheduleReferenceController controller;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    if (controller.state.error != null) return _errorView();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              Text(
                _subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              _selector(),
            ],
          ),
        ),
        if (controller.state.loading) const LinearProgressIndicator(),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _errorView() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          controller.section == ScheduleReferenceSection.branchHours
              ? 'Не удалось загрузить часы работы филиала.'
              : 'Не удалось загрузить график преподавателя.',
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Повторить')),
      ],
    ),
  );

  Widget _body(BuildContext context) {
    if (!controller.canLoadReference) {
      return Center(
        child: Text(
          controller.section == ScheduleReferenceSection.branchHours
              ? 'Сначала добавьте филиал.'
              : 'Нужны хотя бы один филиал и преподаватель.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (controller.section == ScheduleReferenceSection.branchHours)
          BranchHoursCard(
            controller: controller,
            onSave: () => _save(
              context,
              controller.saveBranchHours,
              'Рабочие часы сохранены',
            ),
          )
        else ...[
          TeacherAssignmentsCard(
            controller: controller,
            onSave: () => _save(
              context,
              controller.saveAssignments,
              'Назначения сохранены',
            ),
          ),
          const SizedBox(height: 12),
          TeacherAvailabilityCard(
            controller: controller,
            onSave: () => _save(
              context,
              controller.saveAvailability,
              'Доступность сохранена',
            ),
          ),
        ],
      ],
    );
  }

  Widget _selector() {
    if (controller.section == ScheduleReferenceSection.branchHours) {
      return SearchablePickerField(
        key: ValueKey('settings-branch-${controller.state.branchId}'),
        label: 'Филиал',
        selectedId: controller.state.branchId,
        isNullable: false,
        items: _branchPickerItems(),
        onSelected: (item) {
          final value = item?.id;
          if (value != null) unawaited(controller.selectBranch(value));
        },
      );
    }
    return SearchablePickerField(
      key: ValueKey('settings-teacher-${controller.state.teacherId}'),
      label: 'Преподаватель',
      hintText: 'Введите имя или ФИО преподавателя',
      selectedId: controller.state.teacherId,
      isNullable: false,
      items: _teacherPickerItems(),
      onSelected: (item) {
        final value = item?.id;
        if (value != null) unawaited(controller.selectTeacher(value));
      },
    );
  }

  List<SearchableSelectItem> _branchPickerItems() {
    final items = <SearchableSelectItem>[];
    for (final branch in controller.state.branches) {
      final id = scheduleReferenceId(branch);
      if (id == null) continue;
      items.add(
        SearchableSelectItem(
          id: id,
          label: branch['name']?.toString() ?? 'Филиал',
        ),
      );
    }
    return items;
  }

  List<SearchableSelectItem> _teacherPickerItems() {
    final items = <SearchableSelectItem>[];
    for (final teacher in controller.state.teachers) {
      final id = scheduleReferenceId(teacher);
      if (id == null) continue;
      items.add(SearchableSelectItem(id: id, label: _teacherName(teacher)));
    }
    return items;
  }

  Future<void> _save(
    BuildContext context,
    Future<void> Function() action,
    String success,
  ) async {
    try {
      await action();
      if (context.mounted) MagicToast.show(context, success);
    } catch (error) {
      if (!context.mounted) return;
      MagicToast.show(
        context,
        'Не удалось сохранить',
        detail: userErrorMessage(error),
        type: MagicToastType.danger,
      );
    }
  }

  String _teacherName(Map<String, dynamic> teacher) {
    final profile = teacher['profiles'] as Map<String, dynamic>?;
    final name = [
      profile?['last_name'] ?? teacher['last_name'],
      profile?['first_name'] ?? teacher['first_name'],
    ].where((part) => part?.toString().trim().isNotEmpty == true).join(' ');
    return name.isEmpty ? 'Преподаватель' : name;
  }

  String get _title =>
      controller.section == ScheduleReferenceSection.branchHours
      ? 'Часы работы филиала'
      : 'Рабочий график преподавателя';

  String get _subtitle {
    if (!controller.canEdit) {
      return 'Только просмотр. Редактирование выдаёт директор.';
    }
    return controller.section == ScheduleReferenceSection.branchHours
        ? 'Еженедельные часы и исключения для выбранного филиала'
        : 'Назначения по филиалам, рабочие часы и недоступность';
  }
}
