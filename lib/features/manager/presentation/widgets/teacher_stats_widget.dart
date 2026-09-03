import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/crm_nav_rbac.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/teacher_stats_view.dart';

/// KVA-238: teacher payroll report shell.
class TeacherStatsWidget extends ConsumerStatefulWidget {
  const TeacherStatsWidget({super.key, this.filterRange, this.branchId});

  final DateTimeRange? filterRange;
  final String? branchId;

  @override
  ConsumerState<TeacherStatsWidget> createState() => _TeacherStatsWidgetState();
}

class _TeacherStatsWidgetState extends ConsumerState<TeacherStatsWidget>
    with AutomaticKeepAliveClientMixin {
  late final TeacherStatsController _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = TeacherStatsController(
      crm: ref.read(magicCrmServiceProvider),
      settings: ref.read(magicSettingsServiceProvider),
      reportFileOpener: ref.read(reportFileOpenerProvider),
      filterRange: widget.filterRange,
      branchId: widget.branchId,
      canManageTeacherRates: _canManageRates(
        ref.read(capabilitySnapshotProvider).asData?.value,
      ),
    )..addListener(_refresh);
    unawaited(_controller.initialize());
  }

  @override
  void didUpdateWidget(covariant TeacherStatsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterRange != widget.filterRange ||
        oldWidget.branchId != widget.branchId) {
      unawaited(
        _controller.updateSharedFilter(widget.filterRange, widget.branchId),
      );
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool _canManageRates(CapabilitySnapshot? snapshot) =>
      snapshot != null && crmCanManageTeacherRates(snapshot);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final snapshot = ref.watch(capabilitySnapshotProvider).asData?.value;
    _controller.updateCorrectionPolicy(_canManageRates(snapshot));
    return TeacherStatsView(controller: _controller);
  }
}
