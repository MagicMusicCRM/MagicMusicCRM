import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/security/capability_snapshot_model.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/admin_overview_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/clients_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/finance_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/manager_overview_widget.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_schedule_widget.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_students_widget.dart';

Widget? buildStaffWorkspacePrimaryDestination({
  required int selectedTab,
  required CapabilitySnapshot snapshot,
  required WorkspaceTabState tab,
  required bool isDesktop,
  required void Function(int index, int? subIndex) onOverviewTabChange,
}) {
  if (snapshot.role == 'teacher') {
    return switch (selectedTab) {
      1 => const TeacherScheduleWidget(),
      2 => const TeacherStudentsWidget(),
      _ => null,
    };
  }

  final route = tab.currentRoute;
  final isAdminRole =
      snapshot.role == 'admin' || snapshot.role == 'system_admin';
  return switch (selectedTab) {
    1
        when snapshot.allows('report.status.read') ||
            snapshot.allows('system.settings.manage') =>
      isAdminRole
          ? AdminOverviewWidget(onTabChange: onOverviewTabChange)
          : ManagerOverviewWidget(
              role: snapshot.role,
              onTabChange: onOverviewTabChange,
            ),
    2 when snapshot.allows('schedule.lesson.read.assigned') => ScheduleWidget(
      initialLink: route.link,
      initialViewState: route.viewState,
      canWrite: snapshot.allows('schedule.lesson.write'),
    ),
    3 when snapshot.allows('crm.client.read.basic') => const ClientsWidget(),
    5 when isDesktop && snapshot.allows('commerce.school_finance.read') =>
      const FinanceWidget(),
    _ => null,
  };
}
