import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/providers/crm_section_focus_provider.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:magic_music_crm/features/admin/presentation/providers/schedule_navigation_provider.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/no_open_tasks_highlight.dart';
import 'package:magic_music_crm/core/utils/status_color.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/core/providers/chat_providers.dart';
import 'package:magic_music_crm/core/services/hollihop_service.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_desktop_scrollbar.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/shared_tasks_v4_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/transfer/lead_transfer_controller.dart';
import 'manage_statuses_dialog.dart';
import 'package:magic_music_crm/core/models/lead.dart';
import 'lead_dialogs.dart';
import 'lead_board_filters.dart';
import 'leads_board_states.dart';

part 'kanban_column.dart';
part 'lead_card.dart';
part 'filters_button.dart';
part 'lead_badges.dart';
part 'leads_actions.dart';

class LeadsWidget extends ConsumerStatefulWidget {
  const LeadsWidget({super.key});

  @override
  ConsumerState<LeadsWidget> createState() => _LeadsWidgetState();
}

class _LeadsWidgetState extends ConsumerState<LeadsWidget>
    with AutomaticKeepAliveClientMixin {
  static final _uuidRegExp = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  // D5: keep this board alive across tab/segment switches so the horizontal
  // scroll position, loaded-more pages and active filters survive navigation.
  @override
  bool get wantKeepAlive => true;
  final _searchCtrl = TextEditingController();
  final _boardScrollController = ScrollController();
  List<StatusRecord> _activeStatuses = [];
  // P3-7: status id → whether moving a lead here needs a loss/pause reason.
  final Map<String, bool> _statusRequiresReason = {};
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _disciplines = [];
  List<Map<String, dynamic>> _levels = [];
  List<Map<String, dynamic>> _categories = [];
  LeadBoardFilters _filters = const LeadBoardFilters();
  // Desktop: the secondary filters drop down as an inline panel below the
  // «Фильтры» button. On phones they still open in the side drawer.
  bool _filtersOpen = false;
  Timer? _searchDebounce;
  // D1 real-time search: the live (un-debounced) query typed into the toolbar
  // field. Used to client-side filter the already-loaded cards instantly while
  // the debounced server refetch is still in flight. Empty == no live filter.
  String _liveQuery = '';
  // True between a keystroke and the moment the matching server board lands —
  // drives a small inline «идёт поиск…» hint (never a full-board skeleton).
  bool _searchInFlight = false;
  final Map<String, String> _optimisticLeadStatuses = {};
  final Set<String> _hiddenLeadIds = {};
  final Set<String> _pendingLeadIds = {};
  final Map<String, List<Map<String, dynamic>>> _extraLeadsByStatus = {};
  // Each row_number partition owns its cursor and in-flight state. Sharing a
  // scalar cursor across columns skips leads when their timestamp thresholds
  // diverge.
  final Map<String, String?> _nextCursorByStatus = {};
  final Set<String> _loadingMoreStatuses = {};
  // Horizontal board auto-scroll while dragging a card near an edge.
  Timer? _autoScrollTimer;
  double _autoScrollDir = 0;
  // D3: per-tick scroll speed, eased from ~8 px near the activation threshold
  // up to ~24 px at the very edge (0 when outside the active band).
  double _autoScrollSpeed = 0;
  // D3: a small drag-start threshold — the card must travel this far from
  // where the long-press began before autoscroll is allowed to engage, so a
  // stationary press near an edge never triggers an unwanted scroll.
  Offset? _dragStartPosition;
  bool _dragMovedEnough = false;
  static const double _dragStartThreshold = 12.0;
  static const double _autoScrollMinSpeed = 8.0;
  static const double _autoScrollMaxSpeed = 24.0;
  static const double _autoScrollEdge = 110.0;

  /// Column config (add/reorder/delete, incl. «Без статуса») is a system
  /// setting → управляющий/директор/сисадмин only, not a branch admin.
  bool get _canManageColumns {
    final role = ref.watch(releaseGateStatusProvider).asData?.value.role;
    return role == 'manager' || role == 'director' || role == 'system_admin';
  }

  bool get _canManageClientConfiguration =>
      ref
          .watch(capabilitySnapshotProvider)
          .asData
          ?.value
          .allows('system.settings.manage') ==
      true;

  @override
  void initState() {
    super.initState();
    // Deep-link from the overview «Новые лиды» tile: open the board already
    // filtered to new (no-status) leads. Consumed once; the board's provider
    // watches _filters, so setting it here is enough — no manual refetch.
    final focus = ref.read(crmSectionFocusProvider.notifier).consume('leads');
    if (focus != null && focus.filters['status'] == 'new') {
      _filters = _filters.copyWith(quick: 'new');
    }
    _loadStatuses();
    _loadFilterMetadata();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _autoScrollTimer?.cancel();
    _searchCtrl.dispose();
    _boardScrollController.dispose();
    super.dispose();
  }

  // While a card is dragged near the left/right edge of the board, scroll the
  // horizontal view so columns out of sight can be reached without dropping.
  //
  // D3 tuning: the speed eases from ~8 px/tick at the activation threshold up
  // to ~24 px/tick at the very edge (not a constant rate), a small drag-start

  void _emitState(void Function() fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // D5: required by AutomaticKeepAliveClientMixin.
    // Rebuild when the transfer flow hides a converted lead (optimistic) so the
    // dragged card leaves the funnel the instant the drop completes.
    ref.watch(leadTransferControllerProvider);
    // Realtime: refresh when another staff member changes a lead.
    ref.listen(crmRealtimeProvider, (prev, next) {
      final event = next.value;
      if (event == null || event.entity != 'lead' || !mounted) return;
      if (event.isFallbackPoll) return;
      _refreshBoard();
    });
    final boardAsync = ref.watch(leadBoardProvider(_filters));

    // D1: keep the PREVIOUS board visible during a (debounced) refetch instead
    // of flashing a full-board skeleton. Only the very first load — when there
    // is no value to fall back on — shows the skeleton.
    if (boardAsync.isLoading && !boardAsync.hasValue) {
      return const KanbanSkeleton();
    }
    if (boardAsync.hasError && !boardAsync.hasValue) {
      return LeadsBoardError(onRetry: _refreshBoard);
    }

    final board = boardAsync.value ?? const <String, dynamic>{};

    // D1: once the matching server result has landed, drop the in-flight hint.
    // Done after this frame so we never call setState during build.
    if (_searchInFlight && !boardAsync.isLoading && _filters.q == _liveQuery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchInFlight) {
          _emitState(() => _searchInFlight = false);
        }
      });
    }

    return _buildBoard(board);
  }
}
