import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/providers/schedule_navigation_provider.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

import 'create_lesson_dialog.dart';
import 'schedule_day_canvas.dart';

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
enum _ScheduleView { year, month, day }

enum _DayViewMode { byRoom, byTeacher }

// ── Russian month names ─────────────────────────────────────────────────────
const _monthNamesGenitive = [
  '',
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

const _monthNamesNominative = [
  '',
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];

const _weekDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

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
  _ScheduleView _currentView = _ScheduleView.month;
  _DayViewMode _dayViewMode = _DayViewMode.byRoom;
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

  // ── Data fetching ─────────────────────────────────────────────────────────
  Future<void> _fetchAll() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final from = DateTime(
        _displayedMonth.year,
        _displayedMonth.month,
        1,
      ).subtract(const Duration(days: 7));
      final to = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
        1,
      ).add(const Duration(days: 7));
      final fromIso = from.toUtc().toIso8601String();
      final toIso = to.toUtc().toIso8601String();

      // Wave 1: branches + rooms only (small, fast).
      // Teachers/students/lessons are NOT loaded separately — the schedule
      // matrix already returns names inline, saving 3 HTTP round-trips.
      final wave1 = await Future.wait([
        crm.listBranches(limit: 100),
        crm.listRooms(limit: 100),
      ]);
      final branches = wave1[0];
      final rooms = wave1[1];

      String? defaultBranch = _selectedBranchId;
      if (defaultBranch == null && branches.isNotEmpty) {
        defaultBranch = branches.first['id'].toString();
      }

      // Per-branch UTC offset map (minutes), for rendering lesson times in the
      // branch's local zone.
      final offsets = <String, int>{};
      for (final b in branches) {
        final bid = b['id']?.toString();
        if (bid == null) continue;
        final raw = b['utc_offset_minutes'];
        offsets[bid] = raw is int
            ? raw
            : int.tryParse(raw?.toString() ?? '') ?? 180;
      }

      // Room color map
      final colorMap = <String, Color>{};
      final nameMap = <String, String>{};
      for (int i = 0; i < rooms.length; i++) {
        final rid = rooms[i]['id'].toString();
        colorMap[rid] = _roomColors[i % _roomColors.length];
        nameMap[rid] = rooms[i]['name']?.toString() ?? 'Аудитория';
      }

      // Wave 2: matrix + availability + month-summary (all parallel).
      var enrichedLessons = <Map<String, dynamic>>[];
      var scheduleConflicts = <Map<String, dynamic>>[];
      var roomAvailability = <Map<String, dynamic>>[];
      final monthSummary = <String, Map<String, dynamic>>{};

      final wave2 = await Future.wait<Object?>([
        crm.getScheduleMatrix(
          from: fromIso,
          to: toIso,
          branchId: defaultBranch,
          groupBy:
              _dayViewMode == _DayViewMode.byTeacher ? 'teacher' : 'room',
          limit: 300,
        ).catchError((e) {
          debugPrint('Error fetching schedule matrix: $e');
          return <String, dynamic>{};
        }),
        crm.listRoomAvailability(
          branchId: defaultBranch,
          date: _dateOnly(_selectedDate),
          from: _slotIso(_selectedDate, 6),
          to: _slotIso(_selectedDate, 23),
          limit: 100,
        ).catchError((e) {
          debugPrint('Error fetching room availability: $e');
          return <String, dynamic>{};
        }),
        crm.getScheduleMonthSummary(
          from: fromIso,
          to: toIso,
          branchId: defaultBranch,
        ).catchError((e) {
          debugPrint('Error fetching month summary: $e');
          return <Map<String, dynamic>>[];
        }),
      ]);

      final matrixResult = wave2[0] as Map<String, dynamic>;
      final availabilityResult = wave2[1] as Map<String, dynamic>;
      final summaryResult = wave2[2] as List<Map<String, dynamic>>;

      final matrixItems = matrixResult['items'];
      if (matrixItems is List && matrixItems.isNotEmpty) {
        enrichedLessons =
            matrixItems.whereType<Map<String, dynamic>>().toList();
      }
      final conflicts = matrixResult['conflicts'];
      if (conflicts is List) {
        scheduleConflicts =
            conflicts.whereType<Map<String, dynamic>>().toList();
      }
      final availabilityItems = availabilityResult['items'];
      if (availabilityItems is List) {
        roomAvailability =
            availabilityItems.whereType<Map<String, dynamic>>().toList();
      }
      for (final item in summaryResult) {
        final day = item['day']?.toString();
        if (day != null) monthSummary[day] = item;
      }

      // Build teacher/student name maps from matrix data (no extra API calls).
      final tNames = <String, String>{};
      final sNames = <String, String>{};
      final teacherSet = <String, Map<String, dynamic>>{};
      for (final lesson in enrichedLessons) {
        final tid = lesson['teacher_id']?.toString();
        if (tid != null && tid.isNotEmpty) {
          final name = lesson['teacher_name']?.toString() ?? '';
          if (name.isNotEmpty) tNames[tid] = name;
          teacherSet.putIfAbsent(tid, () => {'id': tid, 'name': name});
        }
        final sid = lesson['student_id']?.toString();
        if (sid != null && sid.isNotEmpty) {
          final name = lesson['student_name']?.toString() ?? '';
          if (name.isNotEmpty) sNames[sid] = name;
        }
      }

      // If the auto-selected branch returned no lessons, try to pick one that
      // has data (from month-summary which covers all branches). The matrix was
      // fetched for the original branch, so switching here alone would leave the
      // day view empty (lessons belong to the old branch) — we must re-fetch the
      // matrix for the newly chosen branch. Guard with _autoBranchRetried so this
      // happens at most once and never loops (KVA-166).
      var rerunForBranch = false;
      if (enrichedLessons.isEmpty &&
          _selectedBranchId == null &&
          !_autoBranchRetried &&
          branches.length > 1) {
        for (final b in branches) {
          final bid = b['id'].toString();
          if (bid != defaultBranch) {
            defaultBranch = bid;
            rerunForBranch = true;
            break;
          }
        }
      }

      if (rerunForBranch) {
        _autoBranchRetried = true;
        _selectedBranchId = defaultBranch;
        // Re-fetch the full payload for the branch that actually has lessons so
        // the day grid isn't left empty against the original (empty) branch.
        if (mounted) await _fetchAll();
        return;
      }

      setState(() {
        _branches = branches;
        _branchOffsets = offsets;
        _rooms = rooms;
        _lessons = enrichedLessons;
        _teachers = teacherSet.values.toList();
        _scheduleConflicts = scheduleConflicts;
        _roomAvailability = roomAvailability;
        _selectedBranchId = defaultBranch;
        _roomColorMap = colorMap;
        _roomNames = nameMap;
        _monthDaySummary = monthSummary;
        _teacherNames = tNames;
        _studentNames = sNames;
        _isLoading = false;
        _hasLoadedOnce = true;
      });

      // The month-wide matrix is capped at 300 rows; if we're already in the day
      // view, backfill the selected day so it isn't left empty for dates past the
      // cap (e.g. today mid-month).
      if (_currentView == _ScheduleView.day) {
        _fetchDayLessons(_selectedDate);
      } else if (_currentView == _ScheduleView.year) {
        _fetchYearSummary();
      }
    } catch (e) {
      debugPrint('Error fetching schedule: $e');
      setState(() {
        _loadError = e;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchAvailabilityForSelectedDay() async {
    final branchId = _selectedBranchId;
    if (branchId == null || branchId.isEmpty) return;
    setState(() => _availabilityLoading = true);
    try {
      final response = await ref
          .read(magicCrmServiceProvider)
          .listRoomAvailability(
            branchId: branchId,
            date: _dateOnly(_selectedDate),
            from: _slotIso(_selectedDate, 6),
            to: _slotIso(_selectedDate, 23),
            limit: 100,
          );
      final items = response['items'];
      if (!mounted) return;
      setState(() {
        _roomAvailability = items is List
            ? items.whereType<Map<String, dynamic>>().toList()
            : const <Map<String, dynamic>>[];
      });
    } catch (e) {
      debugPrint('Error fetching room availability: $e');
    } finally {
      if (mounted) setState(() => _availabilityLoading = false);
    }
  }

  // Fetch the lessons for ONE day (branch-local) and merge them into _lessons.
  // The month-wide matrix in _fetchAll is capped at limit=300 ordered ascending,
  // so days past the first few are missing from the in-memory list and the day
  // grid renders empty even though the month summary counts them. A day-scoped
  // fetch (≈tens of lessons, well under the cap) backfills the selected day.
  Future<void> _fetchDayLessons(DateTime date) async {
    final branchId = _selectedBranchId;
    if (branchId == null || branchId.isEmpty) return;
    final offset = _branchOffsets[branchId] ?? 180;
    // Branch-local midnight expressed as the corresponding UTC instant.
    final dayStartUtc = DateTime.utc(date.year, date.month, date.day)
        .subtract(Duration(minutes: offset));
    final dayEndUtc = dayStartUtc.add(const Duration(days: 1));
    try {
      final result = await ref.read(magicCrmServiceProvider).getScheduleMatrix(
        from: dayStartUtc.toIso8601String(),
        to: dayEndUtc.toIso8601String(),
        branchId: branchId,
        groupBy: _dayViewMode == _DayViewMode.byTeacher ? 'teacher' : 'room',
        limit: 500,
      );
      final items = result['items'];
      if (items is! List || !mounted) return;
      final dayLessons = items.whereType<Map<String, dynamic>>().toList();

      // Upsert by id so the rest of the loaded window is preserved while the
      // selected day becomes complete.
      final byId = <String, Map<String, dynamic>>{
        for (final l in _lessons)
          if (l['id'] != null) l['id'].toString(): l,
      };
      for (final l in dayLessons) {
        final id = l['id']?.toString();
        if (id != null) byId[id] = l;
      }

      final tNames = Map<String, String>.from(_teacherNames);
      final sNames = Map<String, String>.from(_studentNames);
      for (final l in dayLessons) {
        final tid = l['teacher_id']?.toString();
        final tn = l['teacher_name']?.toString();
        if (tid != null && tid.isNotEmpty && tn != null && tn.isNotEmpty) {
          tNames[tid] = tn;
        }
        final sid = l['student_id']?.toString();
        final sn = l['student_name']?.toString();
        if (sid != null && sid.isNotEmpty && sn != null && sn.isNotEmpty) {
          sNames[sid] = sn;
        }
      }

      setState(() {
        _lessons = byId.values.toList();
        _teacherNames = tNames;
        _studentNames = sNames;
      });
    } catch (e) {
      debugPrint('Error fetching day lessons: $e');
    }
  }

  // ── Filtered helpers ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredRooms {
    if (_selectedBranchId == null) return _rooms;
    return _rooms
        .where((r) => r['branch_id']?.toString() == _selectedBranchId)
        .toList();
  }

  List<Map<String, dynamic>> get _filteredLessons {
    return _lessons.where((l) {
      if (l['scheduled_at'] == null) return false;
      if (_selectedBranchId != null &&
          l['branch_id'] != null &&
          l['branch_id'].toString() != _selectedBranchId) {
        return false;
      }
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> _lessonsForDate(DateTime date) {
    return _filteredLessons.where((l) {
      final dt = _parseLessonTime(l);
      return dt != null &&
          dt.year == date.year &&
          dt.month == date.month &&
          dt.day == date.day;
    }).toList();
  }

  // UTC offset (minutes) for the selected branch, falling back to Moscow.
  int get _selectedBranchOffset =>
      _branchOffsets[_selectedBranchId] ?? 180;

  // Offset for a specific lesson based on its branch, falling back to the
  // selected branch / Moscow.
  int _offsetForLesson(Map<String, dynamic> lesson) {
    final bid = lesson['branch_id']?.toString();
    return _branchOffsets[bid] ?? _selectedBranchOffset;
  }

  DateTime? _parseLessonTime(Map<String, dynamic> lesson) {
    if (lesson['scheduled_at'] == null) return null;
    final dbTime = DateTime.parse(lesson['scheduled_at']).toUtc();
    return dbTime.add(Duration(minutes: _offsetForLesson(lesson)));
  }

  DateTime? _parseServerTime(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return parsed.toUtc().add(Duration(minutes: _selectedBranchOffset));
  }

  String _dateOnly(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _slotIso(DateTime date, int hour) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      hour,
    ).toUtc().toIso8601String();
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _goToToday() {
    setState(() {
      _clearHighlight();
      _selectedDate = DateTime.now();
      _displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
    });
    _fetchAll();
  }

  void _prevMonth() {
    setState(() {
      _clearHighlight();
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
      );
    });
    _fetchAll();
  }

  void _nextMonth() {
    setState(() {
      _clearHighlight();
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
      );
    });
    _fetchAll();
  }

  void _prevYear() {
    setState(() => _displayedYear -= 1);
    _fetchYearSummary();
  }

  void _nextYear() {
    setState(() => _displayedYear += 1);
    _fetchYearSummary();
  }

  // Opening a month from the year overview drops the user into that month.
  void _onYearMonthTap(int month) {
    setState(() {
      _clearHighlight();
      _displayedMonth = DateTime(_displayedYear, month);
      _selectedDate = DateTime(_displayedYear, month, 1);
      _currentView = _ScheduleView.month;
    });
    _fetchAll();
  }

  // Whole-year per-month aggregate from the lightweight day-level month-summary
  // (one HTTP call, ≈365 small rows). Counts/active-days are SERVER-derived; we
  // never invent conflict numbers the summary endpoint doesn't return.
  Future<void> _fetchYearSummary() async {
    final branchId = _selectedBranchId;
    final guard = _displayedYear * 31 + (branchId?.hashCode ?? 0) % 31;
    if (_yearLoadedFor == guard && _yearMonths.isNotEmpty) return;
    setState(() => _yearLoading = true);
    try {
      final from = DateTime.utc(_displayedYear, 1, 1).toIso8601String();
      final to = DateTime.utc(_displayedYear + 1, 1, 1).toIso8601String();
      final summary = await ref
          .read(magicCrmServiceProvider)
          .getScheduleMonthSummary(from: from, to: to, branchId: branchId);
      final months = <int, ({int count, int activeDays})>{};
      for (final item in summary) {
        final day = item['day']?.toString();
        if (day == null) continue;
        final parts = day.split('-');
        if (parts.length < 2) continue;
        final m = int.tryParse(parts[1]);
        if (m == null) continue;
        final c = item['count'] is int
            ? item['count'] as int
            : int.tryParse('${item['count']}') ?? 0;
        final cur = months[m] ?? (count: 0, activeDays: 0);
        months[m] = (
          count: cur.count + c,
          activeDays: cur.activeDays + (c > 0 ? 1 : 0),
        );
      }
      if (!mounted) return;
      setState(() {
        _yearMonths = months;
        _yearLoading = false;
        _yearLoadedFor = guard;
      });
    } catch (e) {
      debugPrint('Error fetching year summary: $e');
      if (mounted) setState(() => _yearLoading = false);
    }
  }

  void _prevDay() {
    setState(() {
      _clearHighlight();
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    });
    _fetchAvailabilityForSelectedDay();
    _fetchDayLessons(_selectedDate);
  }

  void _nextDay() {
    setState(() {
      _clearHighlight();
      _selectedDate = _selectedDate.add(const Duration(days: 1));
    });
    _fetchAvailabilityForSelectedDay();
    _fetchDayLessons(_selectedDate);
  }

  void _onMonthDayTap(DateTime date) {
    setState(() {
      _clearHighlight();
      _selectedDate = date;
      _currentView = _ScheduleView.day;
    });
    _fetchAvailabilityForSelectedDay();
    _fetchDayLessons(_selectedDate);
  }

  void _showAddLessonDialog(DateTime date, String? roomId) async {
    final created = await CreateLessonDialog.show(
      context,
      initialDate: date,
      initialRoomId: roomId,
      initialBranchId: _selectedBranchId,
    );
    if (created == true) _fetchAll();
  }

  Future<void> _showScheduleSearch() async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Поиск в расписании'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Ученик, педагог, аудитория или дата',
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Найти'),
          ),
        ],
      ),
    );
    controller.dispose();

    final normalized = query?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return;

    final dateMatch = RegExp(
      r'^(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?$',
    ).firstMatch(normalized);
    if (dateMatch != null) {
      final day = int.tryParse(dateMatch.group(1)!);
      final month = int.tryParse(dateMatch.group(2)!);
      final rawYear = dateMatch.group(3);
      final year = rawYear == null
          ? _displayedMonth.year
          : int.tryParse(rawYear.length == 2 ? '20$rawYear' : rawYear);
      if (day != null && month != null && year != null) {
        final date = DateTime(year, month, day);
        setState(() {
          _selectedDate = date;
          _displayedMonth = DateTime(date.year, date.month);
          _currentView = _ScheduleView.day;
        });
        // Reload the window for the (possibly new) month; since the view is now
        // day, _fetchAll backfills the selected day's lessons too.
        _fetchAll();
        return;
      }
    }

    Map<String, dynamic>? foundLesson;
    String? foundTeacherId;
    for (final lesson in _filteredLessons) {
      final teacherId = lesson['teacher_id']?.toString();
      final studentId = lesson['student_id']?.toString();
      final roomId = lesson['room_id']?.toString();
      final searchable = [
        if (teacherId != null) _teacherNames[teacherId],
        if (studentId != null) _studentNames[studentId],
        if (roomId != null) _roomNames[roomId],
        lesson['status']?.toString(),
      ].whereType<String>().join(' ').toLowerCase();

      if (searchable.contains(normalized)) {
        foundLesson = lesson;
        foundTeacherId = teacherId;
        break;
      }
    }

    final lessonDate = foundLesson == null
        ? null
        : _parseLessonTime(foundLesson);
    if (lessonDate == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ничего не найдено в текущем диапазоне')),
      );
      return;
    }

    setState(() {
      _selectedDate = lessonDate;
      _displayedMonth = DateTime(lessonDate.year, lessonDate.month);
      _currentView = _ScheduleView.day;
      if (foundTeacherId != null) {
        _dayViewMode = _DayViewMode.byTeacher;
        _selectedTeacherId = foundTeacherId;
      }
    });
    _fetchDayLessons(lessonDate);
  }

  Future<void> _showScheduleFilters() async {
    String? branchId = _selectedBranchId;
    var dayViewMode = _dayViewMode;

    final result =
        await showModalBottomSheet<({String? branchId, _DayViewMode mode})>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => StatefulBuilder(
            builder: (context, setSheetState) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Фильтры расписания',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        title: const Text('Все филиалы'),
                        contentPadding: EdgeInsets.zero,
                        onTap: () => setSheetState(() => branchId = null),
                        trailing: branchId == null
                            ? const Icon(Icons.check_rounded)
                            : null,
                      ),
                      ..._branches.map((branch) {
                        final id = branch['id'].toString();
                        return ListTile(
                          title: Text(branch['name']?.toString() ?? 'Филиал'),
                          contentPadding: EdgeInsets.zero,
                          onTap: () => setSheetState(() => branchId = id),
                          trailing: branchId == id
                              ? const Icon(Icons.check_rounded)
                              : null,
                        );
                      }),
                      if (_currentView == _ScheduleView.day) ...[
                        const Divider(),
                        ListTile(
                          title: const Text('День по аудиториям'),
                          contentPadding: EdgeInsets.zero,
                          onTap: () => setSheetState(
                            () => dayViewMode = _DayViewMode.byRoom,
                          ),
                          trailing: dayViewMode == _DayViewMode.byRoom
                              ? const Icon(Icons.check_rounded)
                              : null,
                        ),
                        ListTile(
                          title: const Text('День по педагогу'),
                          contentPadding: EdgeInsets.zero,
                          onTap: () => setSheetState(
                            () => dayViewMode = _DayViewMode.byTeacher,
                          ),
                          trailing: dayViewMode == _DayViewMode.byTeacher
                              ? const Icon(Icons.check_rounded)
                              : null,
                        ),
                      ],
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () => Navigator.of(
                          ctx,
                        ).pop((branchId: branchId, mode: dayViewMode)),
                        child: const Text('Применить'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );

    if (result == null) return;
    setState(() {
      _clearHighlight();
      _selectedBranchId = result.branchId;
      _dayViewMode = result.mode;
      if (_selectedTeacherId != null &&
          !_filteredLessons.any(
            (lesson) => lesson['teacher_id']?.toString() == _selectedTeacherId,
          )) {
        _selectedTeacherId = null;
      }
    });
    _fetchAll();
  }

  // ═══════════════════════════════════════════════════════════════════════════
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
        if (_currentView == _ScheduleView.day) {
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
            if (_currentView == _ScheduleView.day) _buildDayViewModeToggle(),
          ],
          _buildDateNavigation(),
          if (!firstLoad && _currentView == _ScheduleView.day) ...[
            _buildDayLegend(),
            _buildAvailabilitySummary(),
          ],
          Expanded(child: _buildScheduleContent()),
        ],
      ),
      floatingActionButton: firstLoad
          ? null
          : FloatingActionButton(
              onPressed: () => _showAddLessonDialog(
                _currentView == _ScheduleView.day
                    ? _selectedDate
                    : DateTime.now(),
                null,
              ),
              backgroundColor: AppColor.gold,
              child: Icon(Icons.add_rounded, color: Colors.white),
            ),
    );
  }

  Widget _buildScheduleContent() {
    // Skeleton only on the very first load. On re-fetches we keep the existing
    // calendar on screen (a thin progress bar in the header signals the refresh)
    // so changing branch/date/view never blanks the grid.
    if (_isLoading && !_hasLoadedOnce) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: ScheduleSkeleton(rows: 7, columns: 6),
      );
    }
    if (_loadError != null && !_hasLoadedOnce) {
      return _ScheduleError(error: _loadError, onRetry: _fetchAll);
    }
    return switch (_currentView) {
      _ScheduleView.year => _buildYearView(),
      _ScheduleView.month => _buildMonthView(),
      _ScheduleView.day => _buildDayView(),
    };
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final title = switch (_currentView) {
      _ScheduleView.year => 'Расписание / $_displayedYear',
      _ScheduleView.month =>
        '${_monthNamesNominative[_displayedMonth.month]} ${_displayedMonth.year}',
      _ScheduleView.day => 'Расписание / День',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.search_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 22,
            ),
            tooltip: 'Поиск',
            onPressed: _showScheduleSearch,
          ),
          IconButton(
            icon: Icon(
              Icons.tune_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 22,
            ),
            tooltip: 'Фильтры',
            onPressed: _showScheduleFilters,
          ),
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 22,
            ),
            onPressed: _fetchAll,
          ),
        ],
      ),
    );
  }

  // ── Год / Месяц / День segmented control (primary navigation) ──────────────
  Widget _buildViewSwitcher() {
    Widget seg(String label, _ScheduleView view) {
      final active = _currentView == view;
      return Expanded(
        child: GestureDetector(
          onTap: () => _switchView(view),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.ease,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColor.gold : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active
                    ? AppColor.onGold
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.control + 4),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(28),
          ),
        ),
        child: Row(
          children: [
            seg('Год', _ScheduleView.year),
            const SizedBox(width: 4),
            seg('Месяц', _ScheduleView.month),
            const SizedBox(width: 4),
            seg('День', _ScheduleView.day),
          ],
        ),
      ),
    );
  }

  void _switchView(_ScheduleView view) {
    if (_currentView == view) return;
    setState(() {
      _clearHighlight();
      _currentView = view;
    });
    if (view == _ScheduleView.year) {
      _fetchYearSummary();
    } else if (view == _ScheduleView.day) {
      _fetchAvailabilityForSelectedDay();
      _fetchDayLessons(_selectedDate);
    }
  }

  // ── Branch selector pills ─────────────────────────────────────────────────
  Widget _buildBranchSelector() {
    if (_branches.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          ..._branches.map((b) {
            final id = b['id'].toString();
            final isSelected = id == _selectedBranchId;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  b['name'].toString(),
                  style: TextStyle(
                    color: isSelected
                        ? AppColor.gold
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 14,
                  ),
                ),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _clearHighlight();
                    _selectedBranchId = id;
                  });
                  _fetchAll();
                },
                backgroundColor: Theme.of(context).colorScheme.surface,
                selectedColor: AppColor.gold.withAlpha(25),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected
                        ? AppColor.gold
                        : Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withAlpha(60),
                    width: 1,
                  ),
                ),
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
              ),
            );
          }),
          if (_selectedBranchId != null)
            TextButton.icon(
              onPressed: _editBranchTimezone,
              icon: const Icon(Icons.schedule_rounded, size: 16),
              label: Text(_offsetLabel(_selectedBranchOffset)),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  String _offsetLabel(int minutes) {
    final sign = minutes >= 0 ? '+' : '−';
    final h = (minutes.abs() ~/ 60).toString();
    final m = minutes.abs() % 60;
    return m == 0 ? 'UTC$sign$h' : 'UTC$sign$h:${m.toString().padLeft(2, '0')}';
  }

  Future<void> _editBranchTimezone() async {
    final branchId = _selectedBranchId;
    if (branchId == null) return;
    final branch = _branches.firstWhere(
      (b) => b['id'].toString() == branchId,
      orElse: () => <String, dynamic>{},
    );
    final branchName = branch['name']?.toString() ?? 'Филиал';
    // Russia spans UTC+2..UTC+12; offer those (minutes).
    const options = <int>[120, 180, 240, 300, 360, 420, 480, 540, 600, 660, 720];
    var selected = _selectedBranchOffset;
    if (!options.contains(selected)) selected = 180;

    final saved = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Часовой пояс — $branchName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Время занятий отображается в этом поясе.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Смещение'),
                items: options
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(_offsetLabel(m)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setLocal(() => selected = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (saved == null || saved == _selectedBranchOffset || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .updateBranch(branchId, utcOffsetMinutes: saved);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Часовой пояс обновлён: ${_offsetLabel(saved)}'),
          backgroundColor: AppColor.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _fetchAll();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось обновить пояс: $e'),
          backgroundColor: AppColor.danger,
        ),
      );
    }
  }

  // ── Day-view mode toggle (По аудиториям / По педагогу) ────────────────────
  Widget _buildDayViewModeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          _buildToggleButton(
            'По аудиториям',
            _dayViewMode == _DayViewMode.byRoom,
            () {
              if (_dayViewMode == _DayViewMode.byRoom) return;
              setState(() => _dayViewMode = _DayViewMode.byRoom);
              // The matrix is grouped server-side by mode, so re-fetch to avoid
              // showing the previous grouping's (stale) payload.
              _fetchAll();
            },
          ),
          SizedBox(width: 8),
          _buildToggleButton(
            'По педагогу',
            _dayViewMode == _DayViewMode.byTeacher,
            () {
              if (_dayViewMode == _DayViewMode.byTeacher) return;
              setState(() => _dayViewMode = _DayViewMode.byTeacher);
              _fetchAll();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.surface
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(80)
                : Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(40),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ── Date navigation ───────────────────────────────────────────────────────
  Widget _buildDateNavigation() {
    String dateLabel;
    VoidCallback onPrev, onNext;

    if (_currentView == _ScheduleView.year) {
      dateLabel = '$_displayedYear';
      onPrev = _prevYear;
      onNext = _nextYear;
    } else if (_currentView == _ScheduleView.month) {
      dateLabel =
          '${_monthNamesGenitive[_displayedMonth.month].toLowerCase()} ${_displayedMonth.year}';
      onPrev = _prevMonth;
      onNext = _nextMonth;
    } else {
      final weekDayNames = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
      final wd = weekDayNames[_selectedDate.weekday - 1];
      dateLabel =
          '$wd, ${_selectedDate.day} ${_monthNamesGenitive[_selectedDate.month]} ${_selectedDate.year}';
      onPrev = _prevDay;
      onNext = _nextDay;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          InkWell(
            onTap: onPrev,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.chevron_left_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 22,
              ),
            ),
          ),
          Expanded(
            child: Text(
              dateLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: _goToToday,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withAlpha(80),
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'сегодня',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          InkWell(
            onTap: onNext,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilitySummary() {
    final availability = _roomAvailability.where((item) {
      return _selectedBranchId == null ||
          item['branch_id']?.toString() == _selectedBranchId;
    }).toList();
    final availableCount = availability
        .where((item) => item['is_available'] == true)
        .length;
    final busyCount = availability
        .where((item) => item['is_available'] == false)
        .length;
    final conflicts = _conflictsForSelectedDay();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withAlpha(150),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(24),
          ),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ScheduleBadge(
              icon: _availabilityLoading
                  ? Icons.sync_rounded
                  : Icons.meeting_room_outlined,
              label: _availabilityLoading
                  ? 'Проверяем аудитории'
                  : 'Свободно: $availableCount',
              color: AppColor.success,
            ),
            _ScheduleBadge(
              icon: Icons.event_busy_rounded,
              label: 'Занято: $busyCount',
              color: busyCount > 0
                  ? AppTheme.warning
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            _ScheduleBadge(
              icon: Icons.warning_amber_rounded,
              label: 'Конфликты: ${conflicts.length}',
              color: conflicts.isEmpty
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : AppColor.danger,
            ),
            if (availability.isEmpty && !_availabilityLoading)
              Text(
                'Доступность аудиторий появится после расчета backend.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _conflictsForSelectedDay() {
    return _scheduleConflicts.where((conflict) {
      final dt = _parseServerTime(conflict['scheduled_at']);
      return dt != null &&
          dt.year == _selectedDate.year &&
          dt.month == _selectedDate.month &&
          dt.day == _selectedDate.day;
    }).toList();
  }

  Map<String, dynamic>? _availabilityForRoom(String roomId) {
    for (final item in _roomAvailability) {
      if (item['room_id']?.toString() == roomId) return item;
    }
    return null;
  }

  List<String> _conflictTypes(dynamic value) {
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList();
  }

  // Defensive: the backend may send duration as int, double, or string. A bare
  // `as int?` cast throws on a double and blanks the whole card (the lesson then
  // never renders), so parse leniently and fall back to a 60-minute slot.
  int _durationMinutes(Map<String, dynamic> lesson) {
    final raw = lesson['duration_minutes'];
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    final parsed = int.tryParse(raw?.toString() ?? '');
    return parsed ?? 60;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MONTH VIEW
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildMonthView() {
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDay.weekday; // 1=Mon..7=Sun
    final prevDays = startWeekday - 1;
    final prevMonthLastDay = DateTime(year, month, 0).day;
    final totalSlots = prevDays + daysInMonth;
    final rows = (totalSlots / 7).ceil();
    final now = DateTime.now();

    // Focal day for the side summary: the selected day if it's in this month,
    // else today (if today is this month), else the 1st.
    DateTime focal;
    if (_selectedDate.year == year && _selectedDate.month == month) {
      focal = _selectedDate;
    } else if (now.year == year && now.month == month) {
      focal = DateTime(year, month, now.day);
    } else {
      focal = DateTime(year, month, 1);
    }

    final calendar = Column(
      children: [
        // Weekday headers.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: _weekDays
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withAlpha(180),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              children: List.generate(rows, (row) {
                return Expanded(
                  child: Row(
                    children: List.generate(7, (col) {
                      final index = row * 7 + col;
                      if (index < prevDays) {
                        final day = prevMonthLastDay - prevDays + 1 + index;
                        return _buildMonthCellRich(
                          day,
                          isCurrentMonth: false,
                          date: null,
                        );
                      }
                      final dayNum = index - prevDays + 1;
                      if (dayNum > daysInMonth) {
                        return _buildMonthCellRich(
                          dayNum - daysInMonth,
                          isCurrentMonth: false,
                          date: null,
                        );
                      }
                      final date = DateTime(year, month, dayNum);
                      final isToday = date.year == now.year &&
                          date.month == now.month &&
                          date.day == now.day;
                      return _buildMonthCellRich(
                        dayNum,
                        isCurrentMonth: true,
                        date: date,
                        isToday: isToday,
                      );
                    }),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );

    return Column(
      children: [
        _buildMonthLegend(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 760 && c.maxHeight >= 420;
              if (!wide) return calendar;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: calendar),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 260,
                    child: _buildMonthSidePanel(focal),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMonthLegend() {
    Widget chip(Color c, String label) {
      return Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: c.withAlpha(22),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.withAlpha(70)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  chip(AppColor.actionBlue, 'Обычные'),
                  chip(AppColor.success, 'Пробные'),
                  chip(AppColor.warning, 'Пиковая'),
                  chip(AppColor.danger, 'Конфликт'),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: _goToToday,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColor.goldLine),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: const Text(
                'Сегодня',
                style: TextStyle(
                  color: AppColor.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthCellRich(
    int day, {
    required bool isCurrentMonth,
    DateTime? date,
    bool isToday = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final summary = date != null ? _monthDaySummary[_dateOnly(date)] : null;
    final lessons = date != null ? _lessonsForDate(date) : const [];
    final count = summary != null
        ? (summary['count'] as int? ?? 0)
        : lessons.length;
    final isSelected = date != null &&
        _selectedDate.year == date.year &&
        _selectedDate.month == date.month &&
        _selectedDate.day == date.day;

    // Up to two preview chips from the in-memory (capped) matrix; the count
    // badge stays authoritative for the full-day total.
    final sorted = [...lessons];
    sorted.sort((a, b) {
      final ta = _parseLessonTime(a);
      final tb = _parseLessonTime(b);
      if (ta == null || tb == null) return 0;
      return ta.compareTo(tb);
    });

    return Expanded(
      child: GestureDetector(
        onTap: date != null ? () => _onMonthDayTap(date) : null,
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.fromLTRB(5, 4, 5, 4),
          decoration: BoxDecoration(
            color: isCurrentMonth
                ? cs.surface.withAlpha(isSelected ? 220 : 120)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isToday
                  ? AppColor.gold
                  : isSelected
                  ? AppColor.goldLine
                  : cs.onSurfaceVariant.withAlpha(14),
              width: isToday ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? BoxDecoration(
                            color: AppColor.gold,
                            borderRadius: BorderRadius.circular(7),
                          )
                        : null,
                    child: Text(
                      '$day',
                      style: TextStyle(
                        color: isToday
                            ? Colors.white
                            : isCurrentMonth
                            ? AppColor.text
                            : cs.onSurfaceVariant.withAlpha(90),
                        fontSize: 13,
                        fontWeight:
                            isToday ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (isCurrentMonth && count > 0)
                    Text(
                      '$count',
                      style: TextStyle(
                        color: count >= 9 ? AppColor.warning : AppColor.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              if (isCurrentMonth) ...[
                const SizedBox(height: 3),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final l in sorted.take(2))
                          _monthChip(l),
                        if (count > sorted.take(2).length)
                          Padding(
                            padding: const EdgeInsets.only(top: 1, left: 2),
                            child: Text(
                              '+${count - sorted.take(2).length} ${_pluralRu(count - sorted.take(2).length, 'занятие', 'занятия', 'занятий')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurfaceVariant.withAlpha(170),
                                fontSize: 9,
                              ),
                            ),
                          )
                        else if (count == 0 && sorted.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 1, left: 2),
                            child: Text(
                              'нет занятий',
                              style: TextStyle(
                                color: cs.onSurfaceVariant.withAlpha(110),
                                fontSize: 9,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthChip(Map<String, dynamic> lesson) {
    final cs = Theme.of(context).colorScheme;
    final start = _parseLessonTime(lesson);
    final conflicts = _conflictTypes(lesson['conflict_types']);
    final color = conflicts.isNotEmpty
        ? AppColor.danger
        : lesson['is_trial'] == true
        ? AppColor.success
        : AppColor.actionBlue;
    final time = start == null
        ? ''
        : '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} ';
    final name =
        _studentNames[lesson['student_id']?.toString()] ??
        lesson['group_name']?.toString() ??
        'Занятие';
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: color, width: 2)),
      ),
      child: Text(
        '$time$name',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cs.onSurface, fontSize: 9.5),
      ),
    );
  }

  Widget _buildMonthSidePanel(DateTime focal) {
    final cs = Theme.of(context).colorScheme;
    final lessons = _lessonsForDate(focal);
    final summary = _monthDaySummary[_dateOnly(focal)];
    final count = summary != null
        ? (summary['count'] as int? ?? 0)
        : lessons.length;
    final trials = lessons.where((l) => l['is_trial'] == true).length;
    final conflicts = lessons
        .where((l) => _conflictTypes(l['conflict_types']).isNotEmpty)
        .length;

    Widget stat(String value, String label, Color color) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface.withAlpha(120),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: cs.onSurfaceVariant.withAlpha(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface.withAlpha(90),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: cs.onSurfaceVariant.withAlpha(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${focal.day} ${_monthNamesGenitive[focal.month]}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  stat('$count', 'занятий в выбранном дне', AppColor.gold),
                  stat(
                    '$conflicts',
                    'конфликтов комнаты/педагога',
                    conflicts > 0 ? AppColor.danger : AppColor.text,
                  ),
                  stat(
                    '$trials',
                    'пробных уроков',
                    trials > 0 ? AppColor.success : AppColor.text,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: Material(
              color: AppColor.gold,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: () => _onMonthDayTap(focal),
                child: const Center(
                  child: Text(
                    'Открыть день',
                    style: TextStyle(
                      color: AppColor.onGold,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  YEAR VIEW
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildYearView() {
    if (_yearLoading && _yearMonths.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: ScheduleSkeleton(rows: 4, columns: 3),
      );
    }
    final now = DateTime.now();
    final maxCount = _yearMonths.values.fold<int>(
      0,
      (m, v) => v.count > m ? v.count : m,
    );
    final totalLessons = _yearMonths.values.fold<int>(
      0,
      (s, v) => s + v.count,
    );
    final activeMonths = _yearMonths.values.where((v) => v.count > 0).length;

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 760 && c.maxHeight >= 360;
        final cols = c.maxWidth >= 1040
            ? 4
            : c.maxWidth >= 520
            ? 3
            : 2;
        final grid = GridView.count(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          crossAxisCount: cols,
          childAspectRatio: 1.18,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            for (int m = 1; m <= 12; m++)
              _buildYearCard(
                m,
                maxCount,
                selected: _displayedMonth.year == _displayedYear &&
                    _displayedMonth.month == m,
                isCurrent: now.year == _displayedYear && now.month == m,
              ),
          ],
        );
        if (!wide) return grid;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: grid),
            SizedBox(
              width: 260,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 12, 16),
                child: _buildYearSummaryPanel(totalLessons, activeMonths),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildYearCard(
    int month,
    int maxCount, {
    required bool selected,
    required bool isCurrent,
  }) {
    final cs = Theme.of(context).colorScheme;
    final data = _yearMonths[month] ?? (count: 0, activeDays: 0);
    final intensity = maxCount == 0 ? 0.0 : data.count / maxCount;
    final loadColor = intensity > 0.85
        ? AppColor.warning
        : intensity > 0
        ? AppColor.success
        : cs.onSurfaceVariant;

    // 24-cell density heatmap (≈ working days), brightness ~ month load.
    final heat = List<Widget>.generate(24, (i) {
      final on = data.activeDays > 0 && i < (data.activeDays * 24 / 31).round();
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: on
                ? loadColor.withAlpha((40 + intensity * 150).round())
                : cs.onSurfaceVariant.withAlpha(18),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    });

    return GestureDetector(
      onTap: () => _onYearMonthTap(month),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface.withAlpha(selected ? 220 : 120),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected
                ? AppColor.gold
                : isCurrent
                ? AppColor.goldLine
                : cs.onSurfaceVariant.withAlpha(20),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _monthNamesNominative[month],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColor.goldSoft,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: AppColor.goldLine),
                  ),
                  child: Text(
                    '${data.count}',
                    style: const TextStyle(
                      color: AppColor.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Column(
                children: [
                  for (int r = 0; r < 3; r++)
                    Expanded(
                      child: Row(children: heat.sublist(r * 8, r * 8 + 8)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(
                  child: Text(
                    '${data.activeDays} ${_pluralRu(data.activeDays, 'активный день', 'активных дня', 'активных дней')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Spacer(),
                if (intensity > 0.85)
                  const Text(
                    'пик',
                    style: TextStyle(
                      color: AppColor.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (selected)
                  const Text(
                    'выбран',
                    style: TextStyle(
                      color: AppColor.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYearSummaryPanel(int totalLessons, int activeMonths) {
    final cs = Theme.of(context).colorScheme;
    Widget stat(String value, String label) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface.withAlpha(120),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: cs.onSurfaceVariant.withAlpha(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: AppColor.text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface.withAlpha(90),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: cs.onSurfaceVariant.withAlpha(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Сводка $_displayedYear',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          stat('$totalLessons', 'занятий за год'),
          stat('$activeMonths', 'месяцев с занятиями'),
          if (_yearLoading)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(AppColor.gold),
              ),
            ),
        ],
      ),
    );
  }

  String _pluralRu(int n, String one, String few, String many) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
    return many;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  DAY VIEW
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildDayView() {
    if (_dayViewMode == _DayViewMode.byTeacher) {
      return _buildDayViewByTeacher();
    }
    return _buildDayViewByRoom();
  }

  // ── Day view by Rooms (2-axis canvas — KVA-195) ────────────────────────────
  Widget _buildDayViewByRoom() {
    final rooms = _filteredRooms;
    final dayLessons = _lessonsForDate(_selectedDate);

    // Lessons whose room is NOT among the rendered room columns (no room_id, a
    // room missing from the loaded list, or a different branch) get a synthetic
    // «Без аудитории» column so every lesson stays visible (KVA-166).
    final renderedRoomIds = rooms.map((r) => r['id'].toString()).toSet();
    final unassignedLessons = dayLessons.where((l) {
      final rid = l['room_id']?.toString();
      return rid == null || rid.isEmpty || !renderedRoomIds.contains(rid);
    }).toList();

    if (rooms.isEmpty && unassignedLessons.isEmpty) {
      return Center(
        child: Text(
          'Нет аудиторий для выбранного филиала',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;

    // Columns: one per room (+ the unassigned bucket when needed). A room turns
    // red only on a real backend-derived conflict, never just because it's busy.
    final columns = <ScheduleColumn>[
      for (final r in rooms)
        ScheduleColumn(
          id: r['id'].toString(),
          name: r['name']?.toString() ?? 'Аудитория',
          color: _roomColorMap[r['id'].toString()] ?? cs.onSurfaceVariant,
          hasConflict: _conflictTypes(
            _availabilityForRoom(r['id'].toString())?['conflict_types'],
          ).isNotEmpty,
        ),
      if (unassignedLessons.isNotEmpty)
        ScheduleColumn(
          id: kUnassignedColumnId,
          name: 'Без аудитории',
          color: cs.onSurfaceVariant,
          isUnassigned: true,
        ),
    ];

    // Entries: branch-local positioned lesson blocks for the canvas.
    final entries = <ScheduleEntry>[];
    for (final l in dayLessons) {
      final start = _parseLessonTime(l);
      if (start == null) continue;
      final rid = l['room_id']?.toString();
      final columnId =
          (rid == null || rid.isEmpty || !renderedRoomIds.contains(rid))
          ? kUnassignedColumnId
          : rid;
      final status = l['status']?.toString();
      final teacher = _teacherNames[l['teacher_id']?.toString()] ?? '';
      final group = l['group_name']?.toString();
      final student = _studentNames[l['student_id']?.toString()] ?? '';
      final title = (group != null && group.isNotEmpty)
          ? group
          : (student.isNotEmpty ? student : 'Занятие');
      entries.add(
        ScheduleEntry(
          lesson: l,
          id: l['id']?.toString() ?? '',
          columnId: columnId,
          startLocal: start,
          durationMinutes: _durationMinutes(l),
          title: title,
          subtitle: teacher,
          isTrial: l['is_trial'] == true,
          conflicts: _conflictTypes(l['conflict_types']),
          movable: l['id'] != null &&
              status != 'cancelled' &&
              status != 'completed' &&
              status != 'done',
          highlighted: _highlightLessonId != null &&
              l['id']?.toString() == _highlightLessonId,
        ),
      );
    }

    return ScheduleDayCanvas(
      key: ValueKey(
        'day-${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}'
        '-${_selectedBranchId ?? ''}-${columns.length}',
      ),
      date: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ),
      columns: columns,
      entries: entries,
      onCreateSlot: _openQuickCreate,
      onMove: _moveLessonOptimistic,
      onResize: _resizeLesson,
      onOpenLesson: _showLessonDetails,
    );
  }

  // Interaction legend above the day grid: all the rules live here, not on every
  // cell (owner rule «инструкции в легенду, не поверх ячеек»).
  Widget _buildDayLegend() {
    Widget chip(Color c, String label) {
      return Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: c.withAlpha(22),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.withAlpha(70)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(AppColor.transferCyan, 'Тянуть вниз — выбрать часы'),
            chip(AppColor.actionBlue, 'Перетащить — время / комната'),
            chip(AppColor.gold, 'Край (наведи) — растянуть'),
            chip(AppColor.danger, 'Конфликт'),
          ],
        ),
      ),
    );
  }

  // ── Focus-on-lesson (Phase 5) ───────────────────────────────────────────────
  // Applies a [ScheduleFocusState] from the client card: switch to the lesson's
  // day-view, remember the highlight id (matched by `id` in the day's data) and
  // backfill the day. The canvas renders the gold pulse; we arm a timer to clear
  // it. We then consume the navigation request so re-tapping re-fires focus.
  void _applyScheduleFocus(ScheduleFocusState focus) {
    final date = focus.focusDate;
    final day = DateTime(date.year, date.month, date.day);
    _highlightClearTimer?.cancel();
    setState(() {
      _selectedDate = day;
      _displayedMonth = DateTime(day.year, day.month);
      _currentView = _ScheduleView.day;
      _highlightLessonId = focus.highlightLessonId;
    });
    _fetchAvailabilityForSelectedDay();
    _fetchDayLessons(day);
    _armHighlightClear();
    ref.read(scheduleNavigationProvider.notifier).clear();
  }

  void _armHighlightClear() {
    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _highlightLessonId == null) return;
      setState(() => _highlightLessonId = null);
    });
  }

  // Drop the focus highlight on the next day / view / branch change so it never
  // lingers on an unrelated day. Safe to call when nothing is highlighted.
  void _clearHighlight() {
    if (_highlightLessonId == null) return;
    _highlightClearTimer?.cancel();
    _highlightLessonId = null;
  }

  // ── Create from the grid (tap = 1h, vertical-select = span) ────────────────
  // Consolidated to the ONE create window — the full [CreateLessonDialog],
  // pre-filled with the picked room/time/duration. (Previously a separate compact
  // "quick" sheet existed too; having three near-identical lesson windows was
  // confusing, so the grid now opens the same dialog the «+» button uses.)
  Future<void> _openQuickCreate(
    String columnId,
    DateTime startLocal,
    int durationMinutes,
  ) async {
    final roomId =
        (columnId == kUnassignedColumnId || columnId.isEmpty) ? null : columnId;
    final created = await CreateLessonDialog.show(
      context,
      initialDate: startLocal,
      initialRoomId: roomId,
      initialBranchId: _selectedBranchId,
      initialDurationMinutes: durationMinutes,
    );
    if (created == true && mounted) {
      _fetchDayLessons(_selectedDate);
    }
  }

  // ── Optimistic move + rollback + undo (KVA-195) ────────────────────────────
  // Vertical drop → new time; horizontal drop → new room. The block jumps to the
  // new slot immediately (the rest of the grid stays put), then the move commits
  // via the SAME `updateLesson` PATCH the app already used. On error we roll the
  // block back; on success a short «Отменить» snackbar reverts it.
  Future<void> _moveLessonOptimistic(
    Map<String, dynamic> lesson,
    DateTime newStartLocal,
    String newColumnId,
  ) async {
    final lessonId = lesson['id']?.toString();
    if (lessonId == null || _movingLesson) return;

    final targetRoomId =
        (newColumnId == kUnassignedColumnId || newColumnId.isEmpty)
        ? null
        : newColumnId;
    final currentRoomId = lesson['room_id']?.toString();
    final currentStart = _parseLessonTime(lesson);

    // No-op drop (same room + same minute) → skip the round-trip.
    if (currentStart != null &&
        currentStart.hour == newStartLocal.hour &&
        currentStart.minute == newStartLocal.minute &&
        (targetRoomId ?? '') == (currentRoomId ?? '')) {
      return;
    }

    final offset = _offsetForLesson(lesson);
    final utc = DateTime.utc(
      newStartLocal.year,
      newStartLocal.month,
      newStartLocal.day,
      newStartLocal.hour,
      newStartLocal.minute,
    ).subtract(Duration(minutes: offset));
    final newScheduledAtIso = utc.toIso8601String();

    // Snapshot for rollback / undo BEFORE the in-place patch.
    final prevScheduledAt = lesson['scheduled_at'];
    final prevRoomId = lesson['room_id'];
    final prevConflicts = lesson['conflict_types'];
    final roomChanged = targetRoomId != null && targetRoomId != currentRoomId;

    setState(() {
      _movingLesson = true;
      lesson['scheduled_at'] = newScheduledAtIso;
      // Drop the stale conflict flag immediately — the slot changed, so the old
      // verdict no longer applies. The refetch below re-derives it server-side
      // and re-flags only if the new slot genuinely conflicts.
      lesson['conflict_types'] = const <String>[];
      if (roomChanged) {
        lesson['room_id'] = targetRoomId;
        lesson['room_name'] = _roomNames[targetRoomId];
      }
    });

    try {
      await ref.read(magicCrmServiceProvider).updateLesson(
            lessonId,
            scheduledAt: newScheduledAtIso,
            roomId: roomChanged ? targetRoomId : null,
          );
      if (!mounted) return;
      await _fetchDayLessons(_selectedDate); // server re-derives conflicts
      if (!mounted) return;
      final moved = _lessons.firstWhere(
        (l) => l['id']?.toString() == lessonId,
        orElse: () => const <String, dynamic>{},
      );
      final conflicts = _conflictTypes(moved['conflict_types']);
      if (conflicts.isNotEmpty) {
        MagicToast.show(
          context,
          'Перенесено, но есть конфликт',
          detail: conflicts.map(_conflictLabel).join(', '),
          type: MagicToastType.danger,
        );
      } else if (prevRoomId != null || !roomChanged) {
        // Undo restores time + room. Clearing a room back to «Без аудитории»
        // isn't expressible via the PATCH contract, so only offer undo when the
        // previous room is reversible (a real room, or the room didn't change).
        _showUndoableMove(lessonId, prevScheduledAt, prevRoomId);
      } else {
        MagicToast.show(
          context,
          'Занятие перенесено',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          lesson['scheduled_at'] = prevScheduledAt;
          lesson['room_id'] = prevRoomId;
          lesson['room_name'] =
              prevRoomId == null ? null : _roomNames[prevRoomId.toString()];
          lesson['conflict_types'] = prevConflicts;
        });
        MagicToast.show(
          context,
          'Не удалось перенести занятие',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _movingLesson = false);
    }
  }

  void _showUndoableMove(
    String lessonId,
    dynamic prevScheduledAt,
    dynamic prevRoomId,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Занятие перенесено'),
        backgroundColor: AppColor.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Отменить',
          textColor: Colors.white,
          onPressed: () => _undoMove(lessonId, prevScheduledAt, prevRoomId),
        ),
      ),
    );
  }

  Future<void> _undoMove(
    String lessonId,
    dynamic prevScheduledAt,
    dynamic prevRoomId,
  ) async {
    if (prevScheduledAt == null) return;
    try {
      await ref.read(magicCrmServiceProvider).updateLesson(
            lessonId,
            scheduledAt: prevScheduledAt.toString(),
            roomId: prevRoomId?.toString(),
          );
      if (mounted) await _fetchDayLessons(_selectedDate);
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось отменить перенос',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  // ── Resize via hover/focus edge handles (KVA-195) ──────────────────────────
  // Top handle moves the start, bottom handle moves the end. Committed on release
  // through the existing `updateLesson` PATCH — never opens the editor.
  Future<void> _resizeLesson(
    Map<String, dynamic> lesson,
    DateTime newStartLocal,
    int newDurationMinutes,
  ) async {
    final lessonId = lesson['id']?.toString();
    if (lessonId == null || _movingLesson) return;

    final offset = _offsetForLesson(lesson);
    final utc = DateTime.utc(
      newStartLocal.year,
      newStartLocal.month,
      newStartLocal.day,
      newStartLocal.hour,
      newStartLocal.minute,
    ).subtract(Duration(minutes: offset));
    final newScheduledAtIso = utc.toIso8601String();

    final prevScheduledAt = lesson['scheduled_at'];
    final prevDuration = lesson['duration_minutes'];
    final prevConflicts = lesson['conflict_types'];

    setState(() {
      _movingLesson = true;
      lesson['scheduled_at'] = newScheduledAtIso;
      lesson['duration_minutes'] = newDurationMinutes;
      lesson['conflict_types'] = const <String>[];
    });

    try {
      await ref.read(magicCrmServiceProvider).updateLesson(
            lessonId,
            scheduledAt: newScheduledAtIso,
            durationMinutes: newDurationMinutes,
          );
      if (!mounted) return;
      await _fetchDayLessons(_selectedDate);
      if (!mounted) return;
      MagicToast.show(
        context,
        'Длительность обновлена',
        type: MagicToastType.success,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          lesson['scheduled_at'] = prevScheduledAt;
          lesson['duration_minutes'] = prevDuration;
          lesson['conflict_types'] = prevConflicts;
        });
        MagicToast.show(
          context,
          'Не удалось изменить длительность',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _movingLesson = false);
    }
  }

  // ── Day view by Teacher ───────────────────────────────────────────────────
  Widget _buildDayViewByTeacher() {
    final dayLessons = _lessonsForDate(_selectedDate);

    // Get unique teacher IDs for this day
    final teacherIds = dayLessons
        .map((l) => l['teacher_id']?.toString())
        .where((id) => id != null)
        .toSet()
        .toList();
    teacherIds.sort(
      (a, b) => (_teacherNames[a] ?? '').compareTo(_teacherNames[b] ?? ''),
    );

    if (_selectedTeacherId == null && teacherIds.isNotEmpty) {
      _selectedTeacherId = teacherIds.first;
    }

    // Filter lessons for selected teacher
    final teacherLessons = dayLessons
        .where((l) => l['teacher_id']?.toString() == _selectedTeacherId)
        .toList();
    teacherLessons.sort((a, b) {
      final aTime = _parseLessonTime(a);
      final bTime = _parseLessonTime(b);
      if (aTime == null || bTime == null) return 0;
      return aTime.compareTo(bTime);
    });

    // All teachers from the data (not just today)
    final allTeachers = _teachers.where((t) {
      // Only show teachers that have lessons in this branch
      return true;
    }).toList();

    return Column(
      children: [
        // Teacher selector
        if (allTeachers.isNotEmpty)
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: allTeachers.length,
              itemBuilder: (context, i) {
                final t = allTeachers[i];
                final tid = t['id'].toString();
                final isSelected = _selectedTeacherId == tid;
                final name = _teacherNames[tid] ?? 'Без имени';
                final initials = name
                    .split(' ')
                    .map((w) => w.isNotEmpty ? w[0] : '')
                    .take(2)
                    .join('')
                    .toUpperCase();
                final lessonsCount = dayLessons
                    .where((l) => l['teacher_id']?.toString() == tid)
                    .length;

                return GestureDetector(
                  onTap: () => setState(() => _selectedTeacherId = tid),
                  child: Container(
                    width: 160,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColor.gold.withAlpha(30)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColor.gold
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColor.gold.withAlpha(50),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: AppColor.gold,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '$lessonsCount зан.',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant.withAlpha(150),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        SizedBox(height: 8),
        // Teacher lessons list
        Expanded(
          child: teacherLessons.isEmpty
              ? Center(
                  child: Text(
                    _selectedTeacherId == null
                        ? 'Выберите педагога'
                        : 'Нет занятий на этот день',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: teacherLessons.length,
                  itemBuilder: (context, i) =>
                      _buildTeacherLessonCard(teacherLessons[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildTeacherLessonCard(Map<String, dynamic> lesson) {
    final start = _parseLessonTime(lesson);
    if (start == null) return const SizedBox.shrink();

    final duration = _durationMinutes(lesson);
    final end = start.add(Duration(minutes: duration));

    final timeStr =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} – '
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';

    final studentName =
        _studentNames[lesson['student_id']?.toString()] ?? 'Ученик';
    final roomId = lesson['room_id']?.toString();
    final roomName = roomId != null
        ? (_roomNames[roomId] ?? 'Аудитория')
        : 'Без аудитории';
    final roomColor = roomId != null
        ? (_roomColorMap[roomId] ??
              Theme.of(context).colorScheme.onSurfaceVariant)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final conflicts = _conflictTypes(lesson['conflict_types']);

    return GestureDetector(
      onTap: () => _showLessonDetails(lesson),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: conflicts.isEmpty
              ? Theme.of(context).colorScheme.surface
              : AppColor.danger.withAlpha(24),
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: conflicts.isEmpty ? roomColor : AppColor.danger,
              width: 4,
            ),
          ),
        ),
        child: Row(
          children: [
            // Time
            Column(
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    color: roomColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(width: 12),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    studentName,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    roomName,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withAlpha(180),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Status indicator
            if (conflicts.isNotEmpty)
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColor.danger,
                size: 18,
              )
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _statusColor(lesson['status']),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(dynamic status) {
    switch (status?.toString()) {
      case 'completed':
        return AppColor.success;
      case 'cancelled':
        return AppColor.danger;
      default:
        return AppColor.gold;
    }
  }

  // ── Lesson details dialog ─────────────────────────────────────────────────
  void _showLessonDetails(Map<String, dynamic> lesson) {
    final start = _parseLessonTime(lesson);
    if (start == null) return;

    final duration = _durationMinutes(lesson);
    final end = start.add(Duration(minutes: duration));

    final teacherName =
        _teacherNames[lesson['teacher_id']?.toString()] ?? 'Не назначен';
    final studentName =
        _studentNames[lesson['student_id']?.toString()] ?? 'Не назначен';
    final roomId = lesson['room_id']?.toString();
    final roomName = roomId != null
        ? (_roomNames[roomId] ?? 'Аудитория')
        : 'Без аудитории';
    final conflicts = _conflictTypes(lesson['conflict_types']);
    final lessonId = lesson['id']?.toString();
    final currentStatus = lesson['status']?.toString() ?? 'scheduled';

    final timeRange =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} – '
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    final completable =
        lessonId != null &&
        currentStatus != 'completed' &&
        currentStatus != 'done';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColor.scrim,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.sheet),
                ),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 2),
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColor.goldSoft,
                            borderRadius: BorderRadius.circular(AppRadius.icon),
                            border: Border.all(color: AppColor.goldLine),
                          ),
                          child: const Icon(
                            Icons.event_note_rounded,
                            size: 20,
                            color: AppColor.gold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                studentName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  timeRange,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          iconSize: 20,
                          color: cs.onSurfaceVariant,
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow(Icons.person_rounded, 'Ученик', studentName),
                          const SizedBox(height: 10),
                          _detailRow(
                            Icons.school_rounded,
                            'Педагог',
                            teacherName,
                          ),
                          const SizedBox(height: 10),
                          _detailRow(Icons.room_rounded, 'Аудитория', roomName),
                          const SizedBox(height: 10),
                          _detailRow(
                            Icons.access_time_rounded,
                            'Время',
                            timeRange,
                          ),
                          const SizedBox(height: 10),
                          _detailRow(
                            Icons.info_outline_rounded,
                            'Статус',
                            _lessonStatusLabel(currentStatus),
                          ),
                          if (conflicts.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _detailRow(
                              Icons.warning_amber_rounded,
                              'Конфликты',
                              conflicts.map(_conflictLabel).join(', '),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                    child: Column(
                      children: [
                        if (completable) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: Material(
                              color: AppColor.gold,
                              borderRadius: BorderRadius.circular(
                                AppRadius.control,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.control,
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _updateLessonStatus(
                                    lessonId,
                                    'completed',
                                    'Занятие отмечено проведённым',
                                  );
                                },
                                child: const Center(
                                  child: Text(
                                    'Завершить',
                                    style: TextStyle(
                                      color: AppColor.onGold,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          children: [
                            if (lessonId != null)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _editLesson(lesson);
                                  },
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Изменить'),
                                ),
                              ),
                            if (lessonId != null &&
                                currentStatus != 'cancelled') ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColor.danger,
                                    side: const BorderSide(
                                      color: AppColor.danger,
                                    ),
                                  ),
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Отменить занятие?'),
                                        content: const Text(
                                          'Занятие будет помечено как отменённое.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text('Нет'),
                                          ),
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: AppColor.danger,
                                            ),
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text('Отменить занятие'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed == true) {
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      await _updateLessonStatus(
                                        lessonId,
                                        'cancelled',
                                        'Занятие отменено',
                                      );
                                    }
                                  },
                                  child: const Text('Отменить'),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (lessonId != null) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColor.danger,
                            ),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Удалить занятие?'),
                                  content: const Text(
                                    'Занятие будет удалено из расписания безвозвратно.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Нет'),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColor.danger,
                                      ),
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Удалить'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                if (ctx.mounted) Navigator.pop(ctx);
                                await _deleteLesson(lessonId);
                              }
                            },
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                            label: const Text('Удалить занятие'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _lessonStatusLabel(String? status) {
    switch (status) {
      case 'completed':
      case 'done':
        return 'Проведено';
      case 'cancelled':
        return 'Отменено';
      case 'scheduled':
      case 'planned':
        return 'Запланировано';
      default:
        return status ?? 'Запланировано';
    }
  }

  Future<void> _editLesson(Map<String, dynamic> lesson) async {
    final changed = await CreateLessonDialog.show(context, lesson: lesson);
    if (changed == true) _fetchAll();
  }

  Future<void> _deleteLesson(String lessonId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(magicCrmServiceProvider).deleteLesson(lessonId);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Занятие удалено'),
          backgroundColor: AppColor.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _fetchAll();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось удалить занятие: $e'),
          backgroundColor: AppColor.danger,
        ),
      );
    }
  }

  Future<void> _updateLessonStatus(
    String lessonId,
    String status,
    String successMsg,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .updateLesson(lessonId, status: status);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(successMsg),
          backgroundColor: AppColor.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _fetchAll();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось обновить занятие: $e'),
          backgroundColor: AppColor.danger,
        ),
      );
    }
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColor.gold),
        SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  String _conflictLabel(String type) {
    return switch (type) {
      'room_overlap' => 'пересечение аудитории',
      'teacher_overlap' => 'пересечение педагога',
      'missing_teacher' => 'не назначен педагог',
      'branch_mismatch' => 'филиал не совпадает',
      _ => type,
    };
  }
}

// Error state with retry, mirroring the per-feature `_TasksError`/`_FinanceError`
// pattern so the schedule never fails silently into an anonymous skeleton.
class _ScheduleError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _ScheduleError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColor.danger,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              'Не удалось загрузить расписание',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

class _ScheduleBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ScheduleBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(54)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
