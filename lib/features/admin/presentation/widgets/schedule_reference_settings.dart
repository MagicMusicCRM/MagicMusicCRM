import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import 'schedule_reference_controller.dart';
import 'schedule_reference_models.dart';
import 'schedule_reference_view.dart';

export 'schedule_reference_models.dart' show ScheduleReferenceSection;

class ScheduleReferenceSettings extends ConsumerStatefulWidget {
  const ScheduleReferenceSettings({
    super.key,
    required this.canEdit,
    required this.section,
    this.initialBranchId,
    this.initialTeacherId,
    this.lockedTeacherId,
    this.lockedBranchId,
    this.inline = false,
    this.onChanged,
  });

  final bool canEdit;
  final ScheduleReferenceSection section;
  final String? initialBranchId;
  final String? initialTeacherId;
  final String? lockedTeacherId;
  final String? lockedBranchId;
  final bool inline;
  final VoidCallback? onChanged;

  @override
  ConsumerState<ScheduleReferenceSettings> createState() =>
      ScheduleReferenceSettingsState();
}

class ScheduleReferenceSettingsState
    extends ConsumerState<ScheduleReferenceSettings> {
  late ScheduleReferenceController _controller;
  bool get hasChanges => widget.section == ScheduleReferenceSection.branchHours
      ? _controller.hasBranchHoursChanges
      : _controller.hasAvailabilityChanges;
  bool get saving => _controller.state.saving;

  Future<void> saveChanges() async {
    if (!hasChanges) return;
    if (widget.section == ScheduleReferenceSection.branchHours) {
      await _controller.saveBranchHours();
    } else {
      await _controller.saveAvailability();
    }
  }

  void _onChanged() {
    if (!_controller.state.loading) widget.onChanged?.call();
  }

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    unawaited(_controller.loadCatalogs());
  }

  @override
  void didUpdateWidget(covariant ScheduleReferenceSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.canEdit == widget.canEdit &&
        oldWidget.section == widget.section &&
        oldWidget.initialBranchId == widget.initialBranchId &&
        oldWidget.initialTeacherId == widget.initialTeacherId &&
        oldWidget.lockedTeacherId == widget.lockedTeacherId &&
        oldWidget.lockedBranchId == widget.lockedBranchId) {
      return;
    }
    _controller.dispose();
    _controller = _createController();
    unawaited(_controller.loadCatalogs());
  }

  ScheduleReferenceController _createController() =>
      ScheduleReferenceController(
        crm: ref.read(magicCrmServiceProvider),
        section: widget.section,
        canEdit: widget.canEdit,
        initialBranchId: widget.initialBranchId,
        initialTeacherId: widget.initialTeacherId,
        lockedTeacherId: widget.lockedTeacherId,
        lockedBranchId: widget.lockedBranchId,
      )..addListener(_onChanged);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScheduleReferenceView(
    controller: _controller,
    onRetry: _controller.loadCatalogs,
    inline: widget.inline,
  );
}
