import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/notification_bell_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/students_board_providers.dart';
import 'package:magic_music_crm/features/manager/presentation/transfer/lead_transfer_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/transfer/lead_transfer_widgets.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/leads_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_widget.dart';

/// Hosts the «Лиды» and «Ученики» boards behind a segmented toggle AND owns the
/// drag-transfer flow that moves a lead card into the Ученики board, through a
/// branch, into a status column — the seven-screen storyboard in
/// `docs/audits/ui-redesign-2026-06-24/`.
///
/// Both boards stay alive in an [IndexedStack] so a single [Draggable] (started
/// from a lead card's drag handle) keeps the card "in hand" while the segment
/// switches from Лиды to Ученики mid-drag. Flow state lives in
/// [leadTransferControllerProvider]; this widget wires its side effects:
/// switching the segment, loading branches and running the (contract-unchanged)
/// conversion on drop.
class ClientsWidget extends ConsumerStatefulWidget {
  const ClientsWidget({super.key});

  @override
  ConsumerState<ClientsWidget> createState() => _ClientsWidgetState();
}

class _SuccessInfo {
  final String leadId;
  final String? studentId;
  final String message;
  const _SuccessInfo(this.leadId, this.studentId, this.message);
}

class _ClientsWidgetState extends ConsumerState<ClientsWidget> {
  int _segment = 0;
  bool _converting = false;
  _SuccessInfo? _success;
  Timer? _successTimer;

  @override
  void initState() {
    super.initState();
    // Wire the shared controller's side effects to this host and preload the
    // branch list so the strip is ready the instant the students phase opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(leadTransferControllerProvider);
      controller.configure(
        onEnterStudents: () {
          if (mounted) setState(() => _segment = 1);
        },
        onCommit: _commitTransfer,
      );
      _loadBranches();
    });
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final branches =
          await ref.read(magicCrmServiceProvider).listBranches(limit: 100);
      if (!mounted) return;
      ref.read(leadTransferControllerProvider).setBranches(branches);
    } catch (_) {
      // The strip falls back to «Без филиала» only; non-fatal.
    }
  }

  /// Runs the conversion when a card is dropped on a column. Uses the existing
  /// `createStudent` contract (status = column, branch/discipline/sourceLeadId
  /// in `customDataPatch`) — no backend contract is added or changed.
  Future<void> _commitTransfer(TransferDropResult result) async {
    final lead = result.lead;
    if (lead == null || _converting) return;
    final leadId = lead['id']?.toString() ?? '';
    if (leadId.isEmpty) return;
    if ((lead['linked_student_id']?.toString() ?? '').isNotEmpty) {
      _showError('Лид уже связан с учеником');
      return;
    }

    setState(() => _converting = true);
    final controller = ref.read(leadTransferControllerProvider);
    // Optimistic: drop the lead out of the funnel at once (LeadsWidget filters
    // controller.hiddenLeadIds), keeping the dragged context intact for undo.
    controller.addHiddenLead(leadId);

    final firstName = (lead['name'] ?? '').toString().trim();
    final lastName = (lead['last_name'] ?? '').toString().trim();
    final phone = (lead['phone'] ?? '').toString().trim();
    final email = (lead['email'] ?? '').toString().trim();
    final custom = lead['custom_data'];
    final discipline =
        custom is Map ? (custom['discipline']?.toString().trim() ?? '') : '';

    final patch = <String, dynamic>{'sourceLeadId': leadId};
    if (result.branchId != null && result.branchId!.isNotEmpty) {
      patch['branchId'] = result.branchId;
    }
    if (discipline.isNotEmpty) patch['discipline'] = discipline;

    try {
      final student = await ref.read(magicCrmServiceProvider).createStudent(
            firstName: firstName.isEmpty ? 'Без имени' : firstName,
            lastName: lastName.isEmpty ? null : lastName,
            phone: phone.isEmpty ? null : phone,
            email: email.isEmpty ? null : email,
            status: result.columnStatus ?? 'active',
            leadId: leadId,
            customDataPatch: patch,
          );
      // Refresh the destination board so the new student card appears in its
      // column; the leads funnel relies on hiddenLeadIds for the optimistic
      // removal so «Отменить» can cleanly restore the card.
      ref.invalidate(studentBoardProvider);
      if (!mounted) return;
      final branchLabel = result.branchName ?? 'Без филиала';
      final columnLabel = result.columnName ?? result.columnStatus ?? '';
      _showSuccess(
        leadId,
        student['id']?.toString(),
        'Лид перенесён в Ученики · $branchLabel · $columnLabel',
      );
    } catch (e) {
      controller.removeHiddenLead(leadId);
      _showError('Не удалось перенести в ученики: $e');
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  void _showSuccess(String leadId, String? studentId, String message) {
    _successTimer?.cancel();
    setState(() => _success = _SuccessInfo(leadId, studentId, message));
    _successTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _success = null);
    });
  }

  /// Real undo: soft-delete the created student (DELETE /crm/students/:id) and
  /// restore the lead card in the funnel.
  Future<void> _undoTransfer() async {
    final info = _success;
    if (info == null) return;
    _successTimer?.cancel();
    final controller = ref.read(leadTransferControllerProvider);
    final crm = ref.read(magicCrmServiceProvider);
    setState(() => _success = null);
    controller.removeHiddenLead(info.leadId); // bring the lead card back

    final studentId = info.studentId;
    if (studentId == null || studentId.isEmpty) {
      _toast('Карточка лида возвращена.');
      return;
    }
    try {
      await crm.deleteStudent(studentId);
      ref.invalidate(studentBoardProvider); // drop the student card
      _toast('Перенос отменён: ученик удалён, лид возвращён.');
    } catch (e) {
      _toast('Лид возвращён, но удалить ученика не удалось: $e');
    }
  }

  Future<void> _returnStudentToLead(Map<String, dynamic> student) async {
    if (_converting) return;
    final studentId = student['id']?.toString() ?? '';
    if (studentId.isEmpty) return;
    setState(() => _converting = true);
    try {
      final result =
          await ref.read(magicCrmServiceProvider).returnStudentToLead(studentId);
      ref.invalidate(studentBoardProvider);
      if (!mounted) return;
      final leadId = result['leadId']?.toString() ?? '';
      setState(() {
        _segment = 0;
        _success = null;
      });
      _toast(
        leadId.isEmpty
            ? 'Ученик возвращён в лиды.'
            : 'Ученик возвращён в лиды: $leadId',
      );
    } catch (e) {
      _showError('Не удалось вернуть ученика в лиды: $e');
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppColor.danger),
    );
  }

  void _selectSegment(int value) {
    if (ref.read(leadTransferControllerProvider).isActive) return;
    setState(() => _segment = value);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(leadTransferControllerProvider);
    return Column(
      children: [
        _Header(
          segment: _segment,
          controller: controller,
          success: _success,
          onSelectSegment: _selectSegment,
          onReturnStudentToLead: _returnStudentToLead,
          onUndo: _undoTransfer,
          onDismissSuccess: () {
            _successTimer?.cancel();
            setState(() => _success = null);
          },
        ),
        Expanded(
          child: IndexedStack(
            index: _segment,
            children: const [LeadsWidget(), StudentsBoardWidget()],
          ),
        ),
      ],
    );
  }
}

/// The animated header: compact pills when idle, expanded drop fields + branch
/// strip while a transfer is in flight, plus the post-drop success strip.
class _Header extends StatelessWidget {
  final int segment;
  final LeadTransferController controller;
  final _SuccessInfo? success;
  final ValueChanged<int> onSelectSegment;
  final ValueChanged<Map<String, dynamic>> onReturnStudentToLead;
  final VoidCallback onUndo;
  final VoidCallback onDismissSuccess;

  const _Header({
    required this.segment,
    required this.controller,
    required this.success,
    required this.onSelectSegment,
    required this.onReturnStudentToLead,
    required this.onUndo,
    required this.onDismissSuccess,
  });

  @override
  Widget build(BuildContext context) {
    final active = controller.isActive;
    return AnimatedSize(
      duration: AppMotion.fast,
      curve: AppMotion.ease,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (success != null) ...[
              _SuccessStrip(
                message: success!.message,
                onUndo: onUndo,
                onDismiss: onDismissSuccess,
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            if (!active)
              Row(
                children: [
                  Expanded(
                    child:
                        _CompactTabs(
                          segment: segment,
                          onSelect: onSelectSegment,
                          onReturnStudentToLead: onReturnStudentToLead,
                        ),
                  ),
                  const SizedBox(width: 8),
                  // D1: the notification center (read + mark-read), surfaced where
                  // the «+1 лид» badge appears — it was built but never mounted.
                  const NotificationBellWidget(),
                ],
              )
            else
              _ExpandedTabs(controller: controller),
            if (controller.phase == LeadTransferPhase.students) ...[
              const SizedBox(height: AppSpace.sm),
              _BranchStrip(controller: controller),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactTabs extends StatelessWidget {
  final int segment;
  final ValueChanged<int> onSelect;
  final ValueChanged<Map<String, dynamic>> onReturnStudentToLead;

  const _CompactTabs({
    required this.segment,
    required this.onSelect,
    required this.onReturnStudentToLead,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColor.input,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColor.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _leadPill(),
            _pill('Ученики', Icons.school_outlined, 1),
          ],
        ),
      ),
    );
  }

  Widget _leadPill() {
    final pill = _pill('Лиды', Icons.people_outline_rounded, 0);
    if (segment != 1) return pill;
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) =>
          (details.data['id']?.toString() ?? '').isNotEmpty,
      onAcceptWithDetails: (details) => onReturnStudentToLead(details.data),
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.ease,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: hovering
                ? Border.all(color: AppColor.transferCyan, width: 1.5)
                : null,
          ),
          child: pill,
        );
      },
    );
  }

  Widget _pill(String label, IconData icon, int value) {
    final selected = segment == value;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColor.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppColor.onGold : AppColor.text2,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColor.onGold : AppColor.text2,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandedTabs extends StatelessWidget {
  final LeadTransferController controller;
  const _ExpandedTabs({required this.controller});

  @override
  Widget build(BuildContext context) {
    final onStudents = controller.phase == LeadTransferPhase.students;
    return Row(
      children: [
        // ── Лиды (return / source) ───────────────────────────────────────────
        Expanded(
          child: _BigField(
            title: 'Лиды',
            subtitle: onStudents ? 'вернуться' : 'отпустить назад',
            active: false,
            dashed: false,
            color: AppColor.text2,
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        // ── Ученики (the 2-second drop confirmation) ─────────────────────────
        Expanded(
          child: TransferDropZone(
            zoneId: 'students_tab',
            kind: TransferZoneKind.studentsTab,
            controller: controller,
            builder: (context, hovering, progress) {
              return _BigField(
                title: 'Ученики',
                subtitle: onStudents
                    ? 'карточка в руках'
                    : (hovering ? 'подтверждение 2 сек.' : 'перенести сюда'),
                active: onStudents,
                dashed: !onStudents,
                color: onStudents ? AppColor.gold : AppColor.transferCyan,
                progress: progress,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BigField extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool active;
  final bool dashed;
  final Color color;
  final double progress;

  const _BigField({
    required this.title,
    required this.subtitle,
    required this.active,
    required this.dashed,
    required this.color,
    this.progress = 0,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: active ? AppColor.goldSoft : AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: dashed
            ? null
            : Border.all(
                color: active ? AppColor.goldLine : AppColor.divider,
              ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              color: active ? AppColor.gold : AppColor.text,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 11),
          ),
          if (progress > 0) ...[
            const SizedBox(height: 6),
            TransferProgressBar(value: progress),
          ],
        ],
      ),
    );
    if (!dashed) return content;
    return DashedRoundedBorder(color: color, child: content);
  }
}

class _BranchStrip extends StatelessWidget {
  final LeadTransferController controller;
  const _BranchStrip({required this.controller});

  @override
  Widget build(BuildContext context) {
    final branches = controller.branches;
    final chips = <Widget>[
      for (final b in branches)
        _branchChip(
          id: b['id']?.toString() ?? '',
          name: b['name']?.toString() ?? '—',
        ),
      _branchChip(id: kNoBranchValue, name: 'Без филиала', isNone: true),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.sm),
                chips[i],
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Ученики / ${controller.selectedBranchName ?? 'Без филиала'}',
          style: const TextStyle(
            color: AppColor.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Text(
          'Перетащите карточку на филиал, затем в нужную колонку.',
          style: TextStyle(color: AppColor.text2, fontSize: 12),
        ),
      ],
    );
  }

  Widget _branchChip({
    required String id,
    required String name,
    bool isNone = false,
  }) {
    final selectedValue = controller.selectedBranchId;
    final selected =
        isNone ? selectedValue == null : selectedValue == id;
    return SizedBox(
      width: 168,
      child: TransferDropZone(
        zoneId: 'branch:$id',
        kind: TransferZoneKind.branch,
        controller: controller,
        value: isNone ? kNoBranchValue : id,
        label: isNone ? null : name,
        builder: (context, hovering, progress) {
          final color = AppColor.transferCyan;
          final field = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.16) : AppColor.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: hovering || selected
                  ? null
                  : Border.all(color: AppColor.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? color : AppColor.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  selected
                      ? 'выбран'
                      : (hovering
                          ? 'подтверждение…'
                          : (isNone ? 'если неизвестен' : 'перенести сюда')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColor.text2, fontSize: 11),
                ),
                const SizedBox(height: 6),
                TransferProgressBar(value: selected ? 1 : progress),
              ],
            ),
          );
          if (hovering || selected) {
            return DashedRoundedBorder(
              color: color,
              radius: AppRadius.control,
              child: field,
            );
          }
          return field;
        },
      ),
    );
  }
}

class _SuccessStrip extends StatelessWidget {
  final String message;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  const _SuccessStrip({
    required this.message,
    required this.onUndo,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColor.success.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.success.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColor.success, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColor.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onUndo,
            style: TextButton.styleFrom(foregroundColor: AppColor.success),
            child: const Text('Отменить'),
          ),
          IconButton(
            tooltip: 'Скрыть',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColor.text2,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
