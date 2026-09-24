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
    this.inline = false,
  });

  final bool canEdit;
  final ScheduleReferenceSection section;
  final String? initialBranchId;
  final String? initialTeacherId;
  final String? lockedTeacherId;
  final bool inline;

  @override
  ConsumerState<ScheduleReferenceSettings> createState() =>
      _ScheduleReferenceSettingsState();
}

class _ScheduleReferenceSettingsState
    extends ConsumerState<ScheduleReferenceSettings> {
  late ScheduleReferenceController _controller;

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
        oldWidget.lockedTeacherId == widget.lockedTeacherId) {
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
      );

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
