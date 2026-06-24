import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Phase of the Лид → Ученик drag-transfer flow (the seven-screen storyboard in
/// `docs/audits/ui-redesign-2026-06-24/`).
///
/// ```
/// idle ──drag handle──▶ onLeads ──hover «Ученики» 2s──▶ students ──drop column──▶ idle
///                          │                               │
///                          └──────── cancel ───────────────┘  (no side effects)
/// ```
enum LeadTransferPhase {
  /// No transfer in progress.
  idle,

  /// A lead card is in hand; the user is still on the Лиды kanban. The top
  /// `Лиды / Ученики` tabs are expanded into drop fields.
  onLeads,

  /// The «Ученики» confirmation completed: the UI switched to the Ученики board,
  /// the branch strip is open, and the card is still in hand awaiting a branch +
  /// column drop.
  students,
}

/// Kind of registered drop zone, so the controller can hit-test the right set of
/// targets for the current [LeadTransferPhase].
enum TransferZoneKind { leadsTab, studentsTab, branch, column }

/// The decision produced when the pointer is released ([LeadTransferController.endDrag]).
class TransferDropResult {
  /// True when the card was released over a valid student column and the
  /// conversion should run. False means "cancel, leave data unchanged".
  final bool committed;
  final Map<String, dynamic>? lead;
  final String? branchId;
  final String? branchName;
  final String? columnStatus;
  final String? columnName;

  const TransferDropResult({
    required this.committed,
    this.lead,
    this.branchId,
    this.branchName,
    this.columnStatus,
    this.columnName,
  });

  static const TransferDropResult cancelled =
      TransferDropResult(committed: false);
}

class _ZoneReg {
  final GlobalKey key;
  final TransferZoneKind kind;

  /// For branch/column zones: the branch id / status sent to the backend.
  final String? value;

  /// For branch/column zones: the human label shown in the success strip.
  final String? label;

  const _ZoneReg(this.key, this.kind, {this.value, this.label});
}

/// Confirmation hold durations (visual-only — nothing touches the backend until
/// the final column drop).
const Duration kStudentsConfirmDuration = Duration(seconds: 2);
const Duration kBranchConfirmDuration = Duration(milliseconds: 1200);

/// Sentinel branch value for the "Без филиала" drop chip — a student created
/// without a branch (the `branchId` patch is simply omitted).
const String kNoBranchValue = '__none__';

/// Orchestrates the Лид → Ученик drag transfer across [LeadsWidget],
/// [StudentsBoardWidget] and their host (`ClientsWidget`).
///
/// It is a shared, cross-widget piece of state, so it lives in Riverpod
/// ([leadTransferControllerProvider]) rather than a single widget's `State`,
/// per the project's state-management rule. Widgets read flow state to render
/// the expanded tabs / branch strip / column highlights, and feed it pointer
/// positions from the single [Draggable] that carries the card.
class LeadTransferController extends ChangeNotifier {
  LeadTransferPhase _phase = LeadTransferPhase.idle;
  LeadTransferPhase get phase => _phase;

  /// True while a card is in hand (any non-idle phase).
  bool get isActive => _phase != LeadTransferPhase.idle;

  Map<String, dynamic>? _lead;
  Map<String, dynamic>? get lead => _lead;
  String? get leadId => _lead?['id']?.toString();

  /// 0‥1 fill of the currently-hovered confirmation zone (Ученики tab / branch).
  /// A dedicated notifier so progress bars repaint without rebuilding the board.
  final ValueNotifier<double> progress = ValueNotifier<double>(0);

  /// Id of the confirmation zone the pointer currently rests on (or null).
  String? _confirmingZoneId;
  String? get confirmingZoneId => _confirmingZoneId;

  /// Status of the student column the pointer currently hovers (phase students).
  String? _hoverColumnStatus;
  String? get hoverColumnStatus => _hoverColumnStatus;

  /// Branch currently chosen for the in-flight transfer (drives the board).
  String? _selectedBranchId;
  String? get selectedBranchId => _selectedBranchId;
  String? _selectedBranchName;
  String? get selectedBranchName => _selectedBranchName;

  List<Map<String, dynamic>> _branches = const [];
  List<Map<String, dynamic>> get branches => _branches;

  /// Leads optimistically removed from the funnel after a successful transfer.
  /// [LeadsWidget] also filters these so the converted card disappears at once.
  final Set<String> hiddenLeadIds = <String>{};

  final Map<String, _ZoneReg> _zones = <String, _ZoneReg>{};
  Timer? _confirmTimer;

  // ── Side-effect hooks wired by the host (ClientsWidget) ───────────────────
  /// Called when the «Ученики» 2-second confirmation completes — the host
  /// switches the segment to Ученики and reveals the branch strip.
  VoidCallback? onEnterStudents;

  /// Called when a branch confirmation completes — the host can react if needed
  /// (the board itself reads [selectedBranchId]).
  void Function(String? branchId)? onBranchSelected;

  /// Called when the card is released over a valid column — the host runs the
  /// contract-safe conversion and shows the success strip.
  void Function(TransferDropResult result)? onCommit;

  void configure({
    VoidCallback? onEnterStudents,
    void Function(String? branchId)? onBranchSelected,
    void Function(TransferDropResult result)? onCommit,
  }) {
    this.onEnterStudents = onEnterStudents;
    this.onBranchSelected = onBranchSelected;
    this.onCommit = onCommit;
  }

  void setBranches(List<Map<String, dynamic>> branches) {
    _branches = branches;
    // Adopt the first branch as the default selection if none chosen yet.
    if (_selectedBranchId == null && branches.isNotEmpty) {
      _selectedBranchId = branches.first['id']?.toString();
      _selectedBranchName = branches.first['name']?.toString();
    }
    notifyListeners();
  }

  // ── Zone registry ─────────────────────────────────────────────────────────

  void registerZone(
    String id,
    GlobalKey key,
    TransferZoneKind kind, {
    String? value,
    String? label,
  }) {
    _zones[id] = _ZoneReg(key, kind, value: value, label: label);
  }

  void unregisterZone(String id) {
    _zones.remove(id);
  }

  // ── Drag lifecycle ──────────────────────────────────────────────────────--

  /// Begin a transfer from a lead card (called by the card's drag handle).
  void startFromLead(Map<String, dynamic> lead) {
    _cancelTimer();
    _lead = lead;
    _phase = LeadTransferPhase.onLeads;
    _confirmingZoneId = null;
    _hoverColumnStatus = null;
    progress.value = 0;
    notifyListeners();
  }

  /// Feed the current global pointer position (from `Draggable.onDragUpdate`).
  /// Resolves which zone is under the pointer and drives the confirm timers.
  void updatePointer(Offset global) {
    if (!isActive) return;
    if (_phase == LeadTransferPhase.onLeads) {
      // Only the «Ученики» tab field can be confirmed from the leads board.
      final hit = _hitZone(global, const {TransferZoneKind.studentsTab});
      _setConfirmingZone(hit);
    } else {
      // Branch chips confirm with a hold; columns highlight and accept on drop.
      final branchHit = _hitZone(global, const {TransferZoneKind.branch});
      final columnHit = _hitZone(global, const {TransferZoneKind.column});
      // Don't re-run the confirmation on a branch that is already selected —
      // otherwise resting on the active chip would re-fill the bar every cycle.
      final branchValue = branchHit == null ? null : _zones[branchHit]?.value;
      final alreadySelected =
          branchValue != null && branchValue == _selectedBranchId;
      _setConfirmingZone(alreadySelected ? null : branchHit);
      final status = columnHit == null ? null : _zones[columnHit]?.value;
      if (status != _hoverColumnStatus) {
        _hoverColumnStatus = status;
        notifyListeners();
      }
    }
  }

  String? _hitZone(Offset global, Set<TransferZoneKind> kinds) {
    for (final entry in _zones.entries) {
      if (!kinds.contains(entry.value.kind)) continue;
      final ctx = entry.value.key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;
      if (rect.contains(global)) return entry.key;
    }
    return null;
  }

  void _setConfirmingZone(String? zoneId) {
    if (zoneId == _confirmingZoneId) return;
    _cancelTimer();
    _confirmingZoneId = zoneId;
    progress.value = 0;
    if (zoneId != null) {
      final kind = _zones[zoneId]?.kind;
      final duration = kind == TransferZoneKind.studentsTab
          ? kStudentsConfirmDuration
          : kBranchConfirmDuration;
      _startConfirmTimer(zoneId, duration);
    }
    notifyListeners();
  }

  void _startConfirmTimer(String zoneId, Duration duration) {
    const tick = Duration(milliseconds: 16);
    final step = tick.inMilliseconds / duration.inMilliseconds;
    _confirmTimer = Timer.periodic(tick, (_) {
      final next = progress.value + step;
      if (next >= 1.0) {
        progress.value = 1.0;
        _cancelTimer();
        _completeConfirm(zoneId);
      } else {
        progress.value = next;
      }
    });
  }

  void _cancelTimer() {
    _confirmTimer?.cancel();
    _confirmTimer = null;
  }

  void _completeConfirm(String zoneId) {
    final zone = _zones[zoneId];
    if (zone == null) return;
    _confirmingZoneId = null;
    progress.value = 0;
    if (zone.kind == TransferZoneKind.studentsTab) {
      enterStudents();
    } else if (zone.kind == TransferZoneKind.branch) {
      selectBranch(zone.value, zone.label);
    }
  }

  /// Transition onLeads → students (after the «Ученики» hold completes).
  void enterStudents() {
    if (_phase == LeadTransferPhase.students) return;
    _phase = LeadTransferPhase.students;
    _hoverColumnStatus = null;
    if (_selectedBranchId == null && _branches.isNotEmpty) {
      _selectedBranchId = _branches.first['id']?.toString();
      _selectedBranchName = _branches.first['name']?.toString();
    }
    onEnterStudents?.call();
    notifyListeners();
  }

  /// Mark a branch as the active selection for the in-flight transfer. The
  /// «Без филиала» sentinel is carried verbatim in [selectedBranchId] so the
  /// board can load the no-branch view ([kNoBranchBoardId]); it is mapped to a
  /// null branch only at commit time.
  void selectBranch(String? value, String? name) {
    _selectedBranchId = value;
    _selectedBranchName = value == kNoBranchValue ? 'Без филиала' : name;
    onBranchSelected?.call(value == kNoBranchValue ? null : value);
    notifyListeners();
  }

  /// Pointer released. Decides commit (over a column in the students phase) vs
  /// cancel, resets the flow and returns the decision for the host to execute.
  ///
  /// Idempotent: the carrying [Draggable] has no [DragTarget], so it fires both
  /// `onDragEnd` and `onDraggableCanceled` — the second call is a no-op.
  TransferDropResult endDrag() {
    if (_phase == LeadTransferPhase.idle) return TransferDropResult.cancelled;
    final result = resolveDrop();
    _cancelTimer();
    _phase = LeadTransferPhase.idle;
    _lead = null;
    _confirmingZoneId = null;
    _hoverColumnStatus = null;
    progress.value = 0;
    notifyListeners();
    if (result.committed) onCommit?.call(result);
    return result;
  }

  /// Pure decision used by [endDrag] (and unit tests): a drop only commits when
  /// a card is in hand, the students phase is active and a column is hovered.
  TransferDropResult resolveDrop() {
    if (_phase != LeadTransferPhase.students ||
        _lead == null ||
        _hoverColumnStatus == null) {
      return TransferDropResult.cancelled;
    }
    _ZoneReg? columnZone;
    for (final zone in _zones.values) {
      if (zone.kind == TransferZoneKind.column &&
          zone.value == _hoverColumnStatus) {
        columnZone = zone;
        break;
      }
    }
    final isNoBranch = _selectedBranchId == kNoBranchValue;
    return TransferDropResult(
      committed: true,
      lead: _lead,
      branchId: isNoBranch ? null : _selectedBranchId,
      branchName: isNoBranch ? 'Без филиала' : _selectedBranchName,
      columnStatus: _hoverColumnStatus,
      columnName: columnZone?.label,
    );
  }

  /// Hard reset (e.g. drag cancelled by the framework) — no side effects.
  void cancel() {
    _cancelTimer();
    _phase = LeadTransferPhase.idle;
    _lead = null;
    _confirmingZoneId = null;
    _hoverColumnStatus = null;
    progress.value = 0;
    notifyListeners();
  }

  void addHiddenLead(String id) {
    if (id.isEmpty) return;
    hiddenLeadIds.add(id);
    notifyListeners();
  }

  void removeHiddenLead(String id) {
    if (hiddenLeadIds.remove(id)) notifyListeners();
  }

  // ── Test seams ────────────────────────────────────────────────────────────
  @visibleForTesting
  void debugSetHoverColumn(String? status) => _hoverColumnStatus = status;

  @visibleForTesting
  void debugSetPhase(LeadTransferPhase phase) => _phase = phase;

  @override
  void dispose() {
    _cancelTimer();
    progress.dispose();
    super.dispose();
  }
}

/// Shared transfer controller. Cross-widget flow state lives here (Riverpod)
/// rather than in any single widget's `State`.
final leadTransferControllerProvider =
    ChangeNotifierProvider<LeadTransferController>(
  (ref) => LeadTransferController(),
);
