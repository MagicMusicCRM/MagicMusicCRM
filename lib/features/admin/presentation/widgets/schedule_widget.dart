import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/providers/crm_section_focus_provider.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/features/admin/presentation/providers/schedule_navigation_provider.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

import 'create_lesson_dialog.dart';
import 'schedule_day_canvas.dart';
import 'lesson_details_sheet.dart';
import 'schedule_legends.dart';
import 'schedule_shared.dart';
import 'schedule_year_view.dart';
import 'schedule_month_view.dart';
import 'schedule_day_mode_toggle.dart';
import 'schedule_timezone_dialog.dart';
import 'schedule_filters_sheet.dart';
import 'teacher_lesson_card.dart';
import 'schedule_search_dialog.dart';

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
  const ScheduleWidget({super.key});

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

  // Data
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _lessons = [];
  List<Map<String, dynamic>> _teachers = [];
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

  // ── Year view (KVA-195) ─────────────────────────────────────────────────────
  // Per-month aggregate for the selected year, derived from the lightweight
  // whole-year `getScheduleMonthSummary` (per-day counts) so the year overview
  // shows real load without fetching every lesson. Keyed by month 1..12.
  int _displayedYear = DateTime.now().year;
  Map<int, ({int count, int activeDays})> _yearMonths = {};
  bool _yearLoading = false;
  int? _yearLoadedFor; // (year ^ branch) guard so we fetch once per year/branch

  // UI state
  String? _selectedBranchId;
  ScheduleView _currentView = ScheduleView.month;
  DayViewMode _dayViewMode = DayViewMode.byRoom;
  // Extra schedule filters (applied client-side over already-loaded lessons —
  // is_trial / conflict_types / teacher_id all ride along in the matrix).
  bool _onlyTrial = false;
  bool _onlyConflicts = false;
  String? _filterTeacherId;
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
  // Auto-clears the gold highlight a few seconds after it lands.
  Timer? _highlightClearTimer;

  // Guards against overlapping move/resize requests (double-drop / refetch in
  // flight); also drives the optimistic in-place patch + rollback (KVA-195).
  bool _movingLesson = false;

  // Debounce for realtime refetches: a burst of lesson events from other staff
  // would otherwise trigger one full refetch each. Coalesce them into a single
  // refetch ~350ms after the last event.
  Timer? _realtimeDebounce;

  @override
  void initState() {
    super.initState();
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
    _fetchAll();
    // The client card sets the focus BEFORE this widget mounts (it sets focus,
    // closes the card and routes here). `ref.listen` in build only catches
    // *changes*, so pick up an already-set focus once on first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focus = ref.read(scheduleNavigationProvider);
      if (focus != null) _applyScheduleFocus(focus);
    });
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _highlightClearTimer?.cancel();
    super.dispose();
  }

  void _emitState(void Function() fn) {
    if (mounted) setState(fn);
  }
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // Realtime: refresh when another staff member changes a lesson.
    ref.listen(crmRealtimeProvider, (prev, next) {
      final event = next.value;
      if (event == null || event.entity != 'lesson' || !mounted) return;
      // Don't refetch while loading or while an optimistic move/resize is in
      // flight — a mid-flight reload would clobber the in-place patch (the move
      // refetches itself on completion).
      if (_isLoading || _movingLesson) return;
      // Debounce: coalesce a burst of lesson events into one refetch so we don't
      // fire a full reload per event.
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 350), () {
        if (!mounted || _isLoading || _movingLesson) return;
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
          _buildHeader(),
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
          if (!firstLoad) _buildViewSwitcher(),
          if (!firstLoad) ...[
            _buildBranchSelector(),
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
          _buildDateNavigation(),
          if (!firstLoad && _currentView == ScheduleView.day) ...[
            const ScheduleDayLegend(),
            _buildAvailabilitySummary(),
          ],
          Expanded(child: _buildScheduleContent()),
        ],
      ),
      floatingActionButton: firstLoad
          ? null
          : FloatingActionButton(
              onPressed: () => _showAddLessonDialog(
                _currentView == ScheduleView.day
                    ? _selectedDate
                    : DateTime.now(),
                null,
              ),
              backgroundColor: AppColor.gold,
              child: Icon(Icons.add_rounded, color: Colors.white),
            ),
    );
  }
}
