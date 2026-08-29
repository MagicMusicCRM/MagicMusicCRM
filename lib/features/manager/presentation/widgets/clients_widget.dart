import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/notification_bell_widget.dart';
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

class _ClientsWidgetState extends ConsumerState<ClientsWidget> {
  int _segment = 0;
  // Captured in initState so dispose can unhook without touching ref.
  LeadTransferController? _transferController;

  @override
  void initState() {
    super.initState();
    // Wire the shared controller's side effects to this host and preload the
    // branch list so the strip is ready the instant the students phase opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(leadTransferControllerProvider);
      _transferController = controller;
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
    // Unhook this State's closures from the app-scoped controller — otherwise
    // it retains a disposed State and a late onCommit would setState on it.
    _transferController?.configure();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await ref
          .read(magicCrmServiceProvider)
          .listBranches(limit: 100);
      if (!mounted) return;
      ref.read(leadTransferControllerProvider).setBranches(branches);
    } catch (_) {
      // The strip falls back to «Без филиала» only; non-fatal.
    }
  }

  /// Legacy drag-to-student callbacks must not create a student directly.
  /// New conversions are atomic and start from «Продать абонемент» in the lead
  /// card, so a stale drag gesture is cancelled with a clear operator hint.
  Future<void> _commitTransfer(TransferDropResult result) async {
    if (!mounted) return;
    final lead = result.lead;
    if (lead == null) return;
    final leadId = lead['id']?.toString() ?? '';
    if (leadId.isEmpty) return;
    final controller = ref.read(leadTransferControllerProvider);
    controller.removeHiddenLead(leadId);
    setState(() => _segment = 0);
    _toast(
      'Лид станет учеником только после выдачи абонемента. '
      'Откройте карточку лида → «Продать абонемент».',
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
          onSelectSegment: _selectSegment,
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
/// strip while a transfer is in flight.
class _Header extends StatelessWidget {
  final int segment;
  final LeadTransferController controller;
  final ValueChanged<int> onSelectSegment;

  const _Header({
    required this.segment,
    required this.controller,
    required this.onSelectSegment,
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
            if (!active)
              Row(
                children: [
                  Expanded(
                    child: _CompactTabs(
                      segment: segment,
                      onSelect: onSelectSegment,
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

  const _CompactTabs({required this.segment, required this.onSelect});

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
            _pill('Лиды', Icons.people_outline_rounded, 0),
            _pill('Ученики', Icons.school_outlined, 1),
          ],
        ),
      ),
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
            : Border.all(color: active ? AppColor.goldLine : AppColor.divider),
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
          name: b['name']?.toString() ?? 'Не указано',
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
    final selected = isNone ? selectedValue == null : selectedValue == id;
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
              color: selected
                  ? color.withValues(alpha: 0.16)
                  : AppColor.surface,
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
