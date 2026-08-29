import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/security/capability_snapshot_model.dart';

typedef ClientCardSection = (IconData, String, String);

class ClientCardAccessProjection {
  ClientCardAccessProjection({
    required this.canReadClientFinance,
    required this.canReadSchedule,
    required this.canWriteSchedule,
    required this.canReadTasks,
    required List<ClientCardSection> sections,
  }) : sections = UnmodifiableListView(sections);

  final bool canReadClientFinance;
  final bool canReadSchedule;
  final bool canWriteSchedule;
  final bool canReadTasks;
  final List<ClientCardSection> sections;

  int selectedIndexFor(String section) {
    final index = sections.indexWhere((item) => item.$3 == section);
    return index < 0 ? 0 : index;
  }
}

abstract final class ClientCardAccessPolicy {
  static const List<ClientCardSection> _leadSections = [
    (Icons.dashboard_outlined, 'Обзор', 'overview'),
    (Icons.people_alt_outlined, 'Контакты', 'contacts'),
    (Icons.event_note_rounded, 'Занятия', 'lessons'),
    (Icons.confirmation_number_outlined, 'Абонементы', 'subscriptions'),
    (Icons.insights_rounded, 'Прогресс', 'progress'),
    (Icons.history_rounded, 'История и задачи', 'history_tasks'),
  ];

  static const List<ClientCardSection> _studentSections = [
    (Icons.dashboard_outlined, 'Обзор', 'overview'),
    (Icons.people_alt_outlined, 'Контакты', 'contacts'),
    (Icons.event_note_rounded, 'Занятия', 'lessons'),
    (Icons.confirmation_number_outlined, 'Абонементы', 'subscriptions'),
    (Icons.insights_rounded, 'Прогресс', 'progress'),
    (Icons.account_balance_wallet_rounded, 'Оплаты', 'payments'),
    (Icons.history_rounded, 'История и задачи', 'history_tasks'),
  ];

  static ClientCardAccessProjection project({
    required String actorRole,
    required CapabilitySnapshot? capabilitySnapshot,
    required bool hasStudentHalf,
  }) {
    final snapshotRole = capabilitySnapshot?.role.trim();
    final effectiveRole = snapshotRole == null || snapshotRole.isEmpty
        ? actorRole
        : snapshotRole;
    final managerAccess = const {
      'admin',
      'manager',
      'director',
      'system_admin',
    }.contains(effectiveRole);
    final canReadClientFinance = managerAccess;
    final canWriteSchedule =
        capabilitySnapshot?.allows('schedule.lesson.write') ?? managerAccess;
    final canReadSchedule = capabilitySnapshot == null
        ? managerAccess
        : capabilitySnapshot.allows('schedule.lesson.read.assigned') ||
              canWriteSchedule;
    final canReadTasks =
        capabilitySnapshot?.allows('workflow.task.read') ??
        const {
          'teacher',
          'manager',
          'director',
          'system_admin',
        }.contains(effectiveRole);
    final source = !hasStudentHalf
        ? _leadSections
        : canReadClientFinance
        ? _studentSections
        : _studentSections.where(
            (section) =>
                section.$3 != 'payments' && section.$3 != 'subscriptions',
          );
    final sections = [
      for (final section in source)
        if (section.$3 == 'history_tasks' && !canReadTasks)
          (section.$1, 'История', section.$3)
        else
          section,
    ];
    return ClientCardAccessProjection(
      canReadClientFinance: canReadClientFinance,
      canReadSchedule: canReadSchedule,
      canWriteSchedule: canWriteSchedule,
      canReadTasks: canReadTasks,
      sections: sections,
    );
  }
}
