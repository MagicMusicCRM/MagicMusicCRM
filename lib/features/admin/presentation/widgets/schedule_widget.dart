import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/providers/crm_section_focus_provider.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/admin/presentation/providers/schedule_navigation_provider.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

import 'create_lesson_dialog.dart';
import 'schedule_day_canvas.dart';
import 'lesson_details_sheet.dart';
import 'lesson_decision_flow.dart';
import 'schedule_legends.dart';
import 'schedule_shared.dart';
import 'schedule_month_view.dart';
import 'schedule_day_mode_toggle.dart';
import 'schedule_timezone_dialog.dart';
import 'schedule_filters_sheet.dart';
import 'schedule_search_dialog.dart';
import 'schedule_teacher_timeline.dart';

part 'schedule_widget_widgets.dart';
part 'schedule_widget_actions.dart';
part 'schedule_widget_views_a.dart';
part 'schedule_widget_views_b.dart';

// ── Color palette for rooms / teachers ──────────────────────────────────────
// Muted, token-aligned palette (gold + status hues, no neon) so room dots read
// as «Flat Magic» chrome rather than vivid web colors.
const List<Color> _roomColors = [
  AppColor.gold, // золото (бренд)
  AppColor.gold2, // золото-2 (тёплый)
  AppColor.success, // зелёный (статус)
  Color(0xFF5B8DB8), // приглушённый синий
  Color(0xFFB58DB8), // приглушённый сиреневый
  Color(0xFF6FB0A6), // приглушённый бирюзовый
  Color(0xFFC58A5B), // приглушённый терракотовый
  AppColor.danger, // красный (статус)
];

// ── Enums ───────────────────────────────────────────────────────────────────

// ── Russian month names ─────────────────────────────────────────────────────

// ═══════════════════════════════════════════════════════════════════════════
//  Main Widget
// ═══════════════════════════════════════════════════════════════════════════
class ScheduleWidget extends ConsumerStatefulWidget {
  const ScheduleWidget({
    super.key,
    this.initialLink,
    this.initialViewState,
    this.initialBranchId,
    this.clientType,
    this.clientId,
    this.clientName,
    this.fixedTeacherId,
    this.canWrite = true,
    this.allowMonth = true,
    this.active = true,
    this.title = 'Расписание',
    this.onViewStateChanged,
  });

  final EntityLink? initialLink;
  final ContextViewState? initialViewState;
  final String? initialBranchId;
  final String? clientType;
  final String? clientId;
  final String? clientName;
  final String? fixedTeacherId;
  final bool canWrite;
  final bool allowMonth;
  final bool active;
  final String title;
  final ValueChanged<ContextViewState>? onViewStateChanged;

  @override
  ConsumerState<ScheduleWidget> createState() => _ScheduleWidgetState();
}

class _ScheduleWidgetState extends ConsumerState<ScheduleWidget> {
  bool _isLoading = true;
  // True once the first successful load has populated the grid. After that we
  // keep the existing calendar visible during re-fetches (branch/date/view
  // changes) instead of flashing the skeleton — so interaction feels instant.
  bool _hasLoadedOnce = false;
  Object? _loadError;
  // Guards the one-shot "auto-pick a branch with data" re-fetch so it can never
  // loop when every branch is genuinely empty (KVA-166).
  bool _autoBranchRetried = false;
  bool _restoredPendingClientFocus = false;

  // Data
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _lessons = [];
  List<Map<String, dynamic>> _scheduleConflicts = [];
  List<Map<String, dynamic>> _roomAvailability = [];
  Map<String, String> _teacherNames = {};
  Map<String, String> _studentNames = {};
  Map<String, Color> _roomColorMap = {};
  Map<String, String> _roomNames = {};
  // Per-branch UTC offset (minutes) so lesson times render in the branch's
  // local zone. Defaults to 180 (Moscow / UTC+3). Russia has no DST, so a fixed
  // offset is correct.
  Map<String, int> _branchOffsets = {};
  // Per-day month aggregate keyed by 'YYYY-MM-DD' -> {count, room_ids}. Lets the
  // month calendar show full-month counts without fetching every lesson.
  Map<String, Map<String, dynamic>> _monthDaySummary = {};
  bool _availabilityLoading = false;

  // UI state
  String? _selectedBranchId;
  ScheduleView _currentView = ScheduleView.month;
  DayViewMode _dayViewMode = DayViewMode.byRoom;
  // Extra schedule filters (applied client-side over already-loaded lessons —
  // is_trial / conflict_types / teacher_id all ride along in the matrix).
  bool _onlyTrial = false;
  bool _onlyConflicts = false;
  bool _filtersExpanded = false;
  String? _filterTeacherId;
  String? _filterRoomId;
  String? _filterClientType;
  String? _filterClientId;
  String? _filterClientName;
  bool _hideOtherClientLessons = true;
  String _scheduleSearchQuery = '';
  bool _scheduleSearchLoading = false;
  // The user's own branch (staff assignment), resolved once, used as the
  // default instead of «the first branch in the system».
  String? _homeBranchId;
  bool _homeBranchResolved = false;
  DateTime _selectedDate = DateTime.now();
  DateTime _displayedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  String? _selectedTeacherId;

  // ── Focus-on-lesson (Phase 5) ───────────────────────────────────────────────
  // When the «Карточка клиента» taps a lesson, [scheduleNavigationProvider]
  // carries the day + lesson id here. We switch to that day's day view and
  // render a transient gold pulse on the matched lesson (by `id`). The day
  // canvas owns its own scroll, so no scroll controller lives here anymore.
  String? _highlightLessonId;
  bool _highlightUnavailableShown = false;
  double _dayScrollOffset = 0;
  // Auto-clears the gold highlight a few seconds after it lands.
  Timer? _highlightClearTimer;

  // Guards against overlapping move/resize requests (double-drop / refetch in
  // flight); also drives the optimistic in-place patch + rollback (KVA-195).

  // Debounce for realtime refetches: a burst of lesson events from other staff
  // would otherwise trigger one full refetch each. Coalesce them into a single
  // refetch ~350ms after the last event.
  Timer? _realtimeDebounce;

  @override
  void initState() {
    super.initState();
    _restoreNavigationState();
    _restorePendingClientFocus();
    // A filter deep-linked from the overview («Пробные занятия» / «Конфликты
    // расписания») — consumed once before the first fetch so the grid opens
    // filtered. Day view is what actually renders these filters, so switch to it.
    final focus = ref
        .read(crmSectionFocusProvider.notifier)
        .consume('schedule');
    if (focus != null) {
      if (focus.filters['trial'] == '1') _onlyTrial = true;
      if (focus.filters['conflicts'] == '1') _onlyConflicts = true;
      _currentView = ScheduleView.day;
    }
    if (widget.active) _fetchAll();
    // The client card sets the focus BEFORE this widget mounts (it sets focus,
    // closes the card and routes here). `ref.listen` in build only catches
    // *changes*, so pick up an already-set focus once on first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_restoredPendingClientFocus) {
        ref.read(scheduleNavigationProvider.notifier).clear();
        return;
      }
      final focus = ref.read(scheduleNavigationProvider);
      if (focus != null) _applyScheduleFocus(focus);
    });
  }

  void _restorePendingClientFocus() {
    final focus = ref.read(scheduleNavigationProvider);
    if (focus == null ||
        !focus.openMonth ||
        focus.clientId?.isNotEmpty != true) {
      return;
    }
    final date = focus.focusDate;
    _selectedDate = DateTime(date.year, date.month, date.day);
    _displayedMonth = DateTime(date.year, date.month);
    _currentView = ScheduleView.month;
    _highlightLessonId = null;
    _filterClientType = focus.clientType;
    _filterClientId = focus.clientId;
    _filterClientName = focus.clientName;
    _selectedBranchId = focus.branchId ?? _selectedBranchId;
    _hideOtherClientLessons = false;
    _restoredPendingClientFocus = true;
  }

  @override
  void didUpdateWidget(covariant ScheduleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _fetchAll();
  }

  void _restoreNavigationState() {
    final state = widget.initialViewState;
    final filters = <String, dynamic>{
      ...?state?.filters,
      ...?widget.initialLink?.optionalFocus?.filter,
    };
    _selectedBranchId =
        filters['branchId']?.toString() ??
        filters['clientCalendarBranchId']?.toString() ??
        widget.initialBranchId;
    _filterTeacherId =
        widget.fixedTeacherId ?? filters['teacherId']?.toString();
    _filterRoomId = filters['roomId']?.toString();
    _filterClientType = filters['clientType']?.toString();
    _filterClientId = filters['clientId']?.toString();
    _filterClientName = filters['clientName']?.toString();
    _hideOtherClientLessons = filters['showOtherClientLessons'] != true;
    _scheduleSearchQuery = filters['scheduleQuery']?.toString().trim() ?? '';
    _onlyTrial = filters['trial'] == true || filters['trial'] == '1';
    _onlyConflicts =
        filters['conflicts'] == true || filters['conflicts'] == '1';
    _currentView = ScheduleView.values.firstWhere(
      (value) =>
          value.name ==
          (filters['view'] ?? filters['clientCalendarMode'])?.toString(),
      orElse: () => _currentView,
    );
    if (!widget.allowMonth && _currentView == ScheduleView.month) {
      _currentView = ScheduleView.day;
    }
    _dayViewMode = DayViewMode.values.firstWhere(
      (value) => value.name == filters['dayMode'],
      orElse: () => _dayViewMode,
    );
    final date =
        state?.date ?? DateTime.tryParse(filters['date']?.toString() ?? '');
    if (date != null) {
      _selectedDate = DateTime(date.year, date.month, date.day);
      _displayedMonth = DateTime(date.year, date.month);
      if (widget.initialLink?.optionalFocus?.focus == 'schedule') {
        _currentView = ScheduleView.day;
      }
    }
    _dayScrollOffset = state?.scrollOffset ?? 0;
    _selectedTeacherId = state?.selectedColumn;
    if (widget.initialLink?.entityType == EntityLinkType.lesson) {
      _highlightLessonId = widget.initialLink!.entityId;
      _currentView = ScheduleView.day;
    }
  }

  ContextViewState _scheduleViewState() => ContextViewState(
    filters: {
      'view': _currentView.name,
      'dayMode': _dayViewMode.name,
      if (widget.clientId != null) 'section': 'lessons',
      if (widget.clientId != null) 'clientCalendarMode': _currentView.name,
      if (_selectedBranchId != null) 'branchId': _selectedBranchId,
      if (widget.clientId != null && _selectedBranchId != null)
        'clientCalendarBranchId': _selectedBranchId,
      if (_filterTeacherId != null) 'teacherId': _filterTeacherId,
      if (_filterRoomId != null) 'roomId': _filterRoomId,
      if (_filterClientType != null) 'clientType': _filterClientType,
      if (_filterClientId != null) 'clientId': _filterClientId,
      if (_filterClientName != null) 'clientName': _filterClientName,
      if (_hasClientContext && !_hideOtherClientLessons)
        'showOtherClientLessons': true,
      if (_scheduleSearchQuery.isNotEmpty)
        'scheduleQuery': _scheduleSearchQuery,
      if (_onlyTrial) 'trial': true,
      if (_onlyConflicts) 'conflicts': true,
    },
    date: _selectedDate,
    scrollOffset: _dayScrollOffset,
    selectedColumn: _selectedTeacherId,
  );

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _highlightClearTimer?.cancel();
    super.dispose();
  }

  void _emitState(void Function() fn) {
    if (!mounted) return;
    setState(fn);
    widget.onViewStateChanged?.call(_scheduleViewState());
  }

  bool _isContextClientLesson(Map<String, dynamic> lesson) {
    final clientId = _contextClientId;
    if (clientId == null || clientId.isEmpty) return false;
    final key = _contextClientType == 'lead' ? 'lead_id' : 'student_id';
    return lesson[key]?.toString() == clientId;
  }

  String? get _contextClientId => widget.clientId ?? _filterClientId;
  String? get _contextClientType => widget.clientType ?? _filterClientType;
  String? get _contextClientName => widget.clientName ?? _filterClientName;
  bool get _hasClientContext => _contextClientId?.isNotEmpty == true;

  bool get _hasScheduleSearch => _scheduleSearchQuery.isNotEmpty;

  bool _matchesScheduleSearch(Map<String, dynamic> lesson, [String? query]) {
    final normalized = (query ?? _scheduleSearchQuery).trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final teacherId = lesson['teacher_id']?.toString();
    final studentId = lesson['student_id']?.toString();
    final roomId = lesson['room_id']?.toString();
    final searchable =
        [
              if (teacherId != null) _teacherNames[teacherId],
              if (studentId != null) _studentNames[studentId],
              if (roomId != null) _roomNames[roomId],
              lesson['teacher_name'],
              lesson['student_name'],
              lesson['room_name'],
              lesson['lead_name'],
              lesson['group_name'],
              lesson['status'],
            ]
            .whereType<Object>()
            .map((value) => value.toString().toLowerCase())
            .join(' ');
    return searchable.contains(normalized);
  }

  bool _isRelatedLesson(Map<String, dynamic> lesson) => _hasScheduleSearch
      ? _matchesScheduleSearch(lesson)
      : _isContextClientLesson(lesson);

  void _updateDayScrollOffset(double value) {
    _dayScrollOffset = value;
    widget.onViewStateChanged?.call(_scheduleViewState());
  }

  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    // Realtime: refresh when another staff member changes a lesson.
    ref.listen(crmRealtimeProvider, (prev, next) {
      final event = next.value;
      if (event == null || event.entity != 'lesson' || !mounted) return;
      if (_isLoading) return;
      // Debounce: coalesce a burst of lesson events into one refetch so we don't
      // fire a full reload per event.
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 350), () {
        if (!mounted || _isLoading) return;
        if (_currentView == ScheduleView.day) {
          _fetchDayLessons(_selectedDate);
        } else {
          _fetchAll();
        }
      });
    });
    // Focus-on-lesson: the client card asks us to open a specific day with a
    // lesson highlighted. Switch to that day's day view, store the highlight id,
    // reset the scroll guards and fetch the day so the lesson exists in-memory.
    ref.listen(scheduleNavigationProvider, (prev, next) {
      if (next == null || !mounted) return;
      _applyScheduleFocus(next);
    });
    // Chrome (branch selector, view toggle, availability bar, FAB) is hidden
    // only on the FIRST load (no data yet). Once loaded, it stays visible during
    // re-fetches — a thin progress bar shows the refresh — so the screen never
    // collapses to a bare skeleton when you change branch/date/view.
    final firstLoad = (_isLoading || _loadError != null) && !_hasLoadedOnce;
    final refreshing = _isLoading && _hasLoadedOnce;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildScheduleToolbar(firstLoad: firstLoad),
          SizedBox(
            height: 2,
            child: refreshing
                ? const LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation(AppColor.gold),
                  )
                : null,
          ),
          if (!firstLoad) ...[
            if (_currentView == ScheduleView.day)
              ScheduleDayModeToggle(
                mode: _dayViewMode,
                onModeChanged: (m) {
                  if (_dayViewMode == m) return;
                  _emitState(() => _dayViewMode = m);
                  _fetchAll();
                },
              ),
          ],
          if (!firstLoad && _filterClientId != null) _buildClientFilterBanner(),
          if (!firstLoad && widget.clientId != null)
            _buildClientContextBanner(),
          if (!firstLoad && _hasScheduleSearch) _buildScheduleSearchBanner(),
          if (!firstLoad &&
              widget.canWrite &&
              _currentView != ScheduleView.month) ...[
            ScheduleDayLegend(week: _currentView == ScheduleView.week),
          ],
          if (!firstLoad && _currentView == ScheduleView.day) ...[
            _buildAvailabilitySummary(),
          ],
          Expanded(child: _buildScheduleContent()),
        ],
      ),
    );
  }
}
