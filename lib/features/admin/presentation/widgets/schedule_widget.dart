import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

import 'create_lesson_dialog.dart';

// ── Color palette for rooms / teachers ──────────────────────────────────────
const List<Color> _roomColors = [
  Color(0xFFEF4444), // red
  Color(0xFFF59E0B), // amber
  Color(0xFF22C55E), // green
  Color(0xFF3B82F6), // blue
  Color(0xFFD4AF37), // gold
  Color(0xFFEC4899), // pink
  Color(0xFF14B8A6), // teal
  Color(0xFFF97316), // orange
];

// ── Enums ───────────────────────────────────────────────────────────────────
enum _ScheduleView { month, day }

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

const _weekDays = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];

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

  // Day (by-room) grid scroll: auto-scrolls to the earliest lesson once per
  // selected day so evening lessons aren't hidden below the 06:00 fold.
  final ScrollController _dayGridController = ScrollController();
  DateTime? _dayGridScrolledFor;

  // ── Drag-to-move (P2-2 / KVA-195) ──────────────────────────────────────────
  // Key on the scrollable grid body so a drop's global offset can be converted
  // to a grid-local offset (→ target hour/minute). Each room column carries an
  // index in its DragTarget data so the drop column → target room is known
  // without geometry math.
  final GlobalKey _dayGridBodyKey = GlobalKey();
  // True while a lesson block is being dragged, so the body suppresses the
  // one-shot auto-scroll (it would yank the grid out from under the finger).
  bool _isDraggingLesson = false;
  // Guards against overlapping move requests (double-drop / refetch in flight).
  bool _movingLesson = false;

  // Tap / long-press-drag booking selection on empty day-grid cells (KVA-195).
  String? _selRoomId;
  double? _selStartY;
  double? _selEndY;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  @override
  void dispose() {
    _dayGridController.dispose();
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
      _selectedDate = DateTime.now();
      _displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
    });
    _fetchAll();
  }

  void _prevMonth() {
    setState(
      () => _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
      ),
    );
    _fetchAll();
  }

  void _nextMonth() {
    setState(
      () => _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
      ),
    );
    _fetchAll();
  }

  void _prevDay() {
    setState(
      () => _selectedDate = _selectedDate.subtract(const Duration(days: 1)),
    );
    _fetchAvailabilityForSelectedDay();
    _fetchDayLessons(_selectedDate);
  }

  void _nextDay() {
    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
    _fetchAvailabilityForSelectedDay();
    _fetchDayLessons(_selectedDate);
  }

  void _onMonthDayTap(DateTime date) {
    setState(() {
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
      if (_isLoading) return;
      if (_currentView == _ScheduleView.day) {
        _fetchDayLessons(_selectedDate);
      } else {
        _fetchAll();
      }
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
          if (!firstLoad) ...[
            _buildBranchSelector(),
            if (_currentView == _ScheduleView.day) _buildDayViewModeToggle(),
          ],
          _buildDateNavigation(),
          if (!firstLoad && _currentView == _ScheduleView.day)
            _buildAvailabilitySummary(),
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
    return _currentView == _ScheduleView.month
        ? _buildMonthView()
        : _buildDayView();
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final title = _currentView == _ScheduleView.month
        ? '${_monthNamesNominative[_displayedMonth.month]} ${_displayedMonth.year}'
        : 'Расписание';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          if (_currentView == _ScheduleView.day)
            IconButton(
              icon: Icon(
                Icons.arrow_back_rounded,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () =>
                  setState(() => _currentView = _ScheduleView.month),
              tooltip: 'Назад к месяцу',
            ),
          Expanded(
            child: Text(
              title,
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
                  setState(() => _selectedBranchId = id);
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

    if (_currentView == _ScheduleView.month) {
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
    // Weekday: 1=Mon, 7=Sun. We start Monday.
    final startWeekday = firstDay.weekday; // 1-based, Mon=1
    final prevDays = startWeekday - 1;

    // Previous month fill
    final prevMonthLastDay = DateTime(year, month, 0).day;
    final totalSlots = prevDays + daysInMonth;
    final rows = (totalSlots / 7).ceil();

    final now = DateTime.now();

    return Column(
      children: [
        // Month calendar is always rendered (empty cells when there are no
        // lessons), matching the v7 prototype — no text hint over the grid.
        // Weekday headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        SizedBox(height: 4),
        // Calendar grid
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: List.generate(rows, (row) {
                return Expanded(
                  child: Row(
                    children: List.generate(7, (col) {
                      final index = row * 7 + col;
                      if (index < prevDays) {
                        // Previous month
                        final day = prevMonthLastDay - prevDays + 1 + index;
                        return _buildMonthCell(
                          day,
                          isCurrentMonth: false,
                          date: null,
                        );
                      }
                      final dayNum = index - prevDays + 1;
                      if (dayNum > daysInMonth) {
                        // Next month
                        final nextDay = dayNum - daysInMonth;
                        return _buildMonthCell(
                          nextDay,
                          isCurrentMonth: false,
                          date: null,
                        );
                      }
                      final date = DateTime(year, month, dayNum);
                      final isToday =
                          date.year == now.year &&
                          date.month == now.month &&
                          date.day == now.day;
                      return _buildMonthCell(
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
        // Room legend
        _buildRoomLegend(),
      ],
    );
  }

  Widget _buildMonthCell(
    int day, {
    required bool isCurrentMonth,
    DateTime? date,
    bool isToday = false,
  }) {
    // Prefer the lightweight whole-month aggregate; fall back to the detailed
    // (but limited) lesson list when no summary is available for the day.
    final summary = date != null
        ? _monthDaySummary[_dateOnly(date)]
        : null;
    final List<String> summaryRoomIds = summary != null
        ? (summary['room_ids'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[]
        : const <String>[];
    final lessons = date != null && summary == null
        ? _lessonsForDate(date)
        : <Map<String, dynamic>>[];
    final count = summary != null
        ? (summary['count'] as int? ?? 0)
        : lessons.length;

    // Gather unique room colors for dots
    final dotColors = <Color>[];
    final dotRoomIds = summary != null
        ? summaryRoomIds
        : lessons.map((l) => l['room_id']?.toString() ?? '').toList();
    for (final rid in dotRoomIds) {
      final c = rid.isNotEmpty
          ? (_roomColorMap[rid] ??
                Theme.of(context).colorScheme.onSurfaceVariant)
          : Theme.of(context).colorScheme.onSurfaceVariant;
      if (!dotColors.contains(c)) dotColors.add(c);
      if (dotColors.length >= 6) break; // max 6 dots
    }

    return Expanded(
      child: GestureDetector(
        onTap: date != null ? () => _onMonthDayTap(date) : null,
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isCurrentMonth
                ? Theme.of(context).colorScheme.surface.withAlpha(120)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isToday
                ? Border.all(color: AppColor.gold, width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Day number
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(
                        color: AppColor.gold,
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: Text(
                  '$day',
                  style: TextStyle(
                    color: isToday
                        ? Colors.white
                        : isCurrentMonth
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withAlpha(80),
                    fontSize: 14,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (isCurrentMonth && dotColors.isNotEmpty) ...[
                SizedBox(height: 3),
                // Colored dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: dotColors
                      .take(6)
                      .map(
                        (c) => Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                      .toList(),
                ),
                SizedBox(height: 2),
                Text(
                  '$count зан.',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withAlpha(180),
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomLegend() {
    final rooms = _filteredRooms;
    if (rooms.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: rooms.map((r) {
          final rid = r['id'].toString();
          final color =
              _roomColorMap[rid] ??
              Theme.of(context).colorScheme.onSurfaceVariant;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              SizedBox(width: 4),
              Text(
                r['name']?.toString() ?? '',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
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

  // ── Day view by Rooms ─────────────────────────────────────────────────────
  Widget _buildDayViewByRoom() {
    final rooms = _filteredRooms;
    final dayLessons = _lessonsForDate(_selectedDate);

    // Lessons whose room is NOT among the rendered room columns (no room_id, or
    // a room missing from the loaded list / a different branch). Without a home
    // column these would be silently dropped — the manager would see an empty
    // grid even though занятия exist. We surface them in a «Без аудитории»
    // column so every lesson for the day is visible (KVA-166).
    final renderedRoomIds = rooms.map((r) => r['id'].toString()).toSet();
    final unassignedLessons = dayLessons.where((l) {
      final rid = l['room_id']?.toString();
      return rid == null || rid.isEmpty || !renderedRoomIds.contains(rid);
    }).toList();

    // No rooms at all for the branch: still show any day lessons (e.g. trials
    // with no room) instead of a dead-end message that hides real занятия.
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

    const startHour = 6;
    const endHour = 23;
    const hourHeight = 60.0;
    const headerHeight = 50.0;

    _scheduleDayGridAutoScroll(dayLessons, startHour, hourHeight);

    // Like the v7 prototype, the calendar grid is ALWAYS rendered: rooms stay as
    // columns and the time rows render empty when the day has no lessons. We do
    // NOT swap the grid for a text hint — an empty day is an empty grid you can
    // still tap to book, not a dead-end message.

    final unassignedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ── Room headers (PINNED / sticky — P2-1) ──────────────────────────
        // This row lives OUTSIDE the scrollable grid body below, so the
        // room/availability columns stay fixed while the time grid scrolls
        // under them. The opaque surface + hairline divider make the pinned
        // header read as a sticky bar once rows scroll beneath it. Column
        // widths (52px gutter + Expanded rooms) mirror the body exactly so
        // headers stay aligned with their columns.
        Material(
          color: cs.surface,
          child: SizedBox(
            height: headerHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: cs.onSurfaceVariant.withAlpha(24),
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(width: 52), // time column (matches sticky gutter)
              ...rooms.map((r) {
                final rid = r['id'].toString();
                final color =
                    _roomColorMap[rid] ??
                    Theme.of(context).colorScheme.onSurfaceVariant;
                final availability = _availabilityForRoom(rid);
                // Only a real scheduling conflict (overlap / branch mismatch)
                // should red-flag a room. A room that is merely occupied by a
                // lesson (is_available == false) is normal — flagging that as
                // danger painted every working room red.
                final roomConflicts = _conflictTypes(
                  availability?['conflict_types'],
                );
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: roomConflicts.isEmpty
                            ? color.withAlpha(50)
                            : AppColor.danger,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (roomConflicts.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Tooltip(
                                  message: roomConflicts
                                      .map(_conflictLabel)
                                      .join(', '),
                                  child: const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 13,
                                    color: AppColor.danger,
                                  ),
                                ),
                              ),
                            Flexible(
                              child: Text(
                                r['name']?.toString() ?? '',
                                style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              if (unassignedLessons.isNotEmpty)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: unassignedColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: unassignedColor.withAlpha(50)),
                    ),
                    child: Center(
                      child: Text(
                        'Без аудитории',
                        style: TextStyle(
                          color: unassignedColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        ),

        // ── Time grid + lesson cards (SCROLLABLE body) ─────────────────────
        // The sticky gutter (left) and room columns share this single vertical
        // scroll controller, so hour labels stay glued to their rows as the
        // body scrolls under the pinned header above (P2-1).
        Expanded(
          child: SingleChildScrollView(
            controller: _dayGridController,
            child: SizedBox(
              key: _dayGridBodyKey,
              height: (endHour - startHour) * hourHeight,
              child: Row(
                children: [
                  // Time axis (sticky gutter — scrolls with rows, fixed width)
                  SizedBox(
                    width: 52,
                    child: Stack(
                      children: List.generate(endHour - startHour, (i) {
                        return Positioned(
                          top: i * hourHeight,
                          left: 0,
                          right: 0,
                          child: SizedBox(
                            height: hourHeight,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 0, right: 8),
                              child: Text(
                                '${(startHour + i).toString().padLeft(2, '0')}:00',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant.withAlpha(150),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  // Room columns (each a DragTarget so a lesson block can be
                  // dropped onto a new room/time slot — P2-2).
                  ...rooms.map((r) {
                    final rid = r['id'].toString();
                    final color =
                        _roomColorMap[rid] ??
                        Theme.of(context).colorScheme.onSurfaceVariant;
                    final roomLessons = dayLessons
                        .where((l) => l['room_id']?.toString() == rid)
                        .toList();

                    return Expanded(
                      child: DragTarget<Map<String, dynamic>>(
                        onWillAcceptWithDetails: (_) => !_movingLesson,
                        onAcceptWithDetails: (details) => _onLessonDropped(
                          lesson: details.data,
                          globalDropOffset: details.offset,
                          targetRoomId: rid,
                          startHour: startHour,
                          endHour: endHour,
                          hourHeight: hourHeight,
                        ),
                        builder: (context, candidate, rejected) {
                          final isHovering = candidate.isNotEmpty;
                          return GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTapUp: (d) => _onSlotTap(
                              rid,
                              d.localPosition.dy,
                              startHour,
                              endHour,
                              hourHeight,
                            ),
                            onLongPressStart: (d) =>
                                _onSlotSelectStart(rid, d.localPosition.dy),
                            onLongPressMoveUpdate: (d) =>
                                _onSlotSelectUpdate(d.localPosition.dy),
                            onLongPressEnd: (_) =>
                                _onSlotSelectEnd(startHour, endHour, hourHeight),
                            child: Stack(
                            children: [
                              // Booking selection overlay (tap / long-press-drag).
                              if (_selRoomId == rid &&
                                  _selStartY != null &&
                                  _selEndY != null)
                                Positioned(
                                  left: 2,
                                  right: 2,
                                  top: _selStartY! < _selEndY!
                                      ? _selStartY!
                                      : _selEndY!,
                                  height: (_selStartY! - _selEndY!)
                                      .abs()
                                      .clamp(10.0, 2000.0),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: AppColor.goldSoft,
                                      border:
                                          Border.all(color: AppColor.goldLine),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              // Drop highlight while a block hovers this column.
                              if (isHovering)
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: AppColor.goldSoft,
                                      border: Border.all(
                                        color: AppColor.goldLine,
                                      ),
                                    ),
                                  ),
                                ),
                              // Grid lines
                              ...List.generate(endHour - startHour, (i) {
                                return Positioned(
                                  top: i * hourHeight,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: hourHeight,
                                    decoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withAlpha(20),
                                          width: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              // Affordance: an empty room column invites booking
                              // (the tap/long-press gesture is otherwise invisible).
                              if (roomLessons.isEmpty)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Center(
                                      child: Text(
                                        'Нажмите,\nчтобы назначить',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 10,
                                          height: 1.3,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withAlpha(90),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              // Lesson cards
                              ...roomLessons.map(
                                (l) => _buildDayLessonCard(
                                  l,
                                  startHour,
                                  hourHeight,
                                  color,
                                ),
                              ),
                            ],
                          ),
                          );
                        },
                      ),
                    );
                  }),
                  // «Без аудитории» column — lessons with no/unknown room so they
                  // are never silently dropped from the day grid (KVA-166).
                  // Also a DragTarget: dropping here moves the lesson off any
                  // room (roomId cleared) while still re-timing it (P2-2).
                  if (unassignedLessons.isNotEmpty)
                    Expanded(
                      child: DragTarget<Map<String, dynamic>>(
                        onWillAcceptWithDetails: (_) => !_movingLesson,
                        onAcceptWithDetails: (details) => _onLessonDropped(
                          lesson: details.data,
                          globalDropOffset: details.offset,
                          targetRoomId: '',
                          startHour: startHour,
                          endHour: endHour,
                          hourHeight: hourHeight,
                        ),
                        builder: (context, candidate, rejected) {
                          final isHovering = candidate.isNotEmpty;
                          return Stack(
                            children: [
                              if (isHovering)
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: AppColor.goldSoft,
                                      border: Border.all(
                                        color: AppColor.goldLine,
                                      ),
                                    ),
                                  ),
                                ),
                              ...List.generate(endHour - startHour, (i) {
                                return Positioned(
                                  top: i * hourHeight,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: hourHeight,
                                    decoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withAlpha(20),
                                          width: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              ...unassignedLessons.map(
                                (l) => _buildDayLessonCard(
                                  l,
                                  startHour,
                                  hourHeight,
                                  unassignedColor,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Auto-scrolls the day grid to the earliest lesson once per selected day, so
  // afternoon/evening lessons aren't hidden below the 06:00 fold (the grid
  // starts at 06:00 but most lessons are later — the visible top looked empty).
  void _scheduleDayGridAutoScroll(
    List<Map<String, dynamic>> dayLessons,
    int startHour,
    double hourHeight,
  ) {
    if (dayLessons.isEmpty) return;
    if (_dayGridScrolledFor == _selectedDate) return;
    // Don't yank the grid while a block is mid-drag (P2-2).
    if (_isDraggingLesson) return;

    double? earliestTop;
    for (final l in dayLessons) {
      final s = _parseLessonTime(l);
      if (s == null) continue;
      final top = ((s.hour - startHour) + s.minute / 60.0) * hourHeight;
      earliestTop = earliestTop == null
          ? top
          : (top < earliestTop ? top : earliestTop);
    }
    if (earliestTop == null) return;
    final target = earliestTop - 16; // keep a little context above the lesson

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dayGridController.hasClients) return;
      _dayGridScrolledFor = _selectedDate;
      final max = _dayGridController.position.maxScrollExtent;
      _dayGridController.jumpTo(target.clamp(0.0, max));
    });
  }

  Widget _buildDayLessonCard(
    Map<String, dynamic> lesson,
    int startHour,
    double hourHeight,
    Color roomColor,
  ) {
    final start = _parseLessonTime(lesson);
    if (start == null) return const SizedBox.shrink();

    final duration = _durationMinutes(lesson);
    final end = start.add(Duration(minutes: duration));

    final topOffset =
        ((start.hour - startHour) + start.minute / 60.0) * hourHeight;
    final height = (duration / 60.0) * hourHeight;

    final teacherName = _teacherNames[lesson['teacher_id']?.toString()] ?? '';
    final studentName = _studentNames[lesson['student_id']?.toString()] ?? '';
    final conflicts = _conflictTypes(lesson['conflict_types']);

    final timeStr =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} – '
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';

    final clampedHeight = height.clamp(24.0, double.infinity);

    // The visual card body, reused for the in-grid block, the drag feedback,
    // and the dimmed placeholder left behind while dragging (P2-2).
    final cardBody = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: conflicts.isEmpty
            ? roomColor.withAlpha(40)
            : AppColor.danger.withAlpha(32),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: conflicts.isEmpty ? roomColor : AppColor.danger,
            width: 3,
          ),
          right: conflicts.isEmpty
              ? BorderSide.none
              : const BorderSide(color: AppColor.danger, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  timeStr,
                  style: TextStyle(
                    color: conflicts.isEmpty ? roomColor : AppColor.danger,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                ),
              ),
              if (conflicts.isNotEmpty)
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColor.danger,
                  size: 12,
                ),
            ],
          ),
          if (height > 30)
            Text(
              studentName,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (height > 44)
            Text(
              teacherName,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withAlpha(180),
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );

    final tappable = GestureDetector(
      onTap: () => _showLessonDetails(lesson),
      child: cardBody,
    );

    // Only re-schedulable lessons are draggable: a cancelled/completed block
    // must not be silently re-timed. Tap-to-open detail is unchanged for all.
    final status = lesson['status']?.toString();
    final movable =
        lesson['id'] != null &&
        status != 'cancelled' &&
        status != 'completed' &&
        status != 'done';

    if (!movable) {
      return Positioned(
        top: topOffset,
        left: 2,
        right: 2,
        height: clampedHeight,
        child: tappable,
      );
    }

    return Positioned(
      top: topOffset,
      left: 2,
      right: 2,
      height: clampedHeight,
      child: LongPressDraggable<Map<String, dynamic>>(
        data: lesson,
        onDragStarted: () {
          if (!_isDraggingLesson) {
            setState(() => _isDraggingLesson = true);
          }
        },
        onDragEnd: (_) {
          if (mounted && _isDraggingLesson) {
            setState(() => _isDraggingLesson = false);
          }
        },
        // The dragged proxy: a slightly opaque copy sized to the source block.
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.9,
            child: SizedBox(
              width: 120,
              height: clampedHeight,
              child: cardBody,
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: tappable),
        child: tappable,
      ),
    );
  }

  // ── Drag-to-move drop handler (P2-2 / KVA-195) ──────────────────────────────
  // Converts the drop's global offset into a grid-local Y → target hour/minute
  // (snapped to 5 min, clamped to the visible [startHour, endHour) window), then
  // routes the move through the SAME update path the widget already uses
  // (`magicCrmServiceProvider.updateLesson` with a new `scheduledAt` + `roomId`).
  // It does NOT invent any endpoint: after the update we re-run `_fetchAll`,
  // whose `getScheduleMatrix` call recomputes conflicts server-side (the existing
  // conflict check), and any returned `conflict_types` are surfaced to the user.
  // ── Tap / drag-to-book on empty grid cells (KVA-195) ───────────────────────
  // Convert a vertical offset inside a day-grid room column to a 15-min-snapped
  // DateTime on the selected day.
  DateTime _slotDateTime(
    double localY,
    int startHour,
    int endHour,
    double hourHeight,
  ) {
    final raw = startHour * 60 + (localY / hourHeight) * 60.0;
    var minutes = (raw / 15).round() * 15;
    minutes = minutes.clamp(startHour * 60, endHour * 60 - 15);
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      minutes ~/ 60,
      minutes % 60,
    );
  }

  void _onSlotTap(
    String roomId,
    double localY,
    int startHour,
    int endHour,
    double hourHeight,
  ) {
    _openCreateForSlot(
      roomId,
      _slotDateTime(localY, startHour, endHour, hourHeight),
      60,
    );
  }

  void _onSlotSelectStart(String roomId, double localY) {
    setState(() {
      _selRoomId = roomId;
      _selStartY = localY;
      _selEndY = localY;
    });
  }

  void _onSlotSelectUpdate(double localY) {
    if (_selRoomId == null) return;
    setState(() => _selEndY = localY);
  }

  void _onSlotSelectEnd(int startHour, int endHour, double hourHeight) {
    final roomId = _selRoomId;
    final a = _selStartY;
    final b = _selEndY;
    setState(() {
      _selRoomId = null;
      _selStartY = null;
      _selEndY = null;
    });
    if (roomId == null || a == null || b == null) return;
    final start = _slotDateTime(a < b ? a : b, startHour, endHour, hourHeight);
    final end = _slotDateTime(a < b ? b : a, startHour, endHour, hourHeight);
    var duration = end.difference(start).inMinutes;
    if (duration < 30) duration = 60; // a near-tap behaves like one slot
    _openCreateForSlot(roomId, start, duration);
  }

  Future<void> _openCreateForSlot(
    String roomId,
    DateTime start,
    int durationMinutes,
  ) async {
    final created = await CreateLessonDialog.show(
      context,
      initialDate: start,
      initialRoomId: roomId.isEmpty ? null : roomId,
      initialBranchId: _selectedBranchId,
      initialDurationMinutes: durationMinutes,
    );
    if (created == true && mounted) {
      if (_currentView == _ScheduleView.day) {
        _fetchDayLessons(_selectedDate);
      } else {
        _fetchAll();
      }
    }
  }

  void _onLessonDropped({
    required Map<String, dynamic> lesson,
    required Offset globalDropOffset,
    required String targetRoomId,
    required int startHour,
    required int endHour,
    required double hourHeight,
  }) {
    final bodyContext = _dayGridBodyKey.currentContext;
    final box = bodyContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    // Local Y inside the (scrolled) grid body → minutes from startHour.
    final localY = box.globalToLocal(globalDropOffset).dy;
    final rawMinutes = (localY / hourHeight) * 60.0;
    // Snap to 5-minute steps for a tidy slot.
    var snapped = (rawMinutes / 5).round() * 5;

    final duration = _durationMinutes(lesson);
    final maxStartMinutes = (endHour - startHour) * 60 - duration;
    if (snapped < 0) snapped = 0;
    if (maxStartMinutes >= 0 && snapped > maxStartMinutes) {
      snapped = maxStartMinutes;
    }

    final newHour = startHour + (snapped ~/ 60);
    final newMinute = snapped % 60;

    final currentStart = _parseLessonTime(lesson);
    final currentRoomId = lesson['room_id']?.toString() ?? '';
    if (currentStart != null &&
        currentStart.hour == newHour &&
        currentStart.minute == newMinute &&
        currentRoomId == targetRoomId) {
      return; // No-op drop (same slot) — skip the round-trip.
    }

    // Build the new instant directly in UTC space — the exact inverse of
    // `_parseLessonTime` (which does `dbTimeUtc.add(branchOffset)`), so we
    // subtract the branch offset from the chosen branch-local wall-clock. Using
    // `DateTime.utc` (not local `DateTime`) avoids double-applying the device's
    // own timezone.
    final branchLocalUtc = DateTime.utc(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      newHour,
      newMinute,
    );
    final utcStart =
        branchLocalUtc.subtract(Duration(minutes: _offsetForLesson(lesson)));

    _moveLesson(
      lesson: lesson,
      newScheduledAtUtcIso: utcStart.toIso8601String(),
      newRoomId: targetRoomId,
    );
  }

  Future<void> _moveLesson({
    required Map<String, dynamic> lesson,
    required String newScheduledAtUtcIso,
    required String newRoomId,
  }) async {
    final lessonId = lesson['id']?.toString();
    if (lessonId == null || _movingLesson) return;
    setState(() => _movingLesson = true);

    final currentRoomId = lesson['room_id']?.toString() ?? '';
    // Only send roomId when it actually changed AND we're targeting a real room
    // (empty target = «Без аудитории»; we leave room unchanged there rather than
    // guessing a clear-room payload the existing API may not model).
    final roomChanged = newRoomId.isNotEmpty && newRoomId != currentRoomId;

    try {
      await ref.read(magicCrmServiceProvider).updateLesson(
            lessonId,
            scheduledAt: newScheduledAtUtcIso,
            roomId: roomChanged ? newRoomId : null,
          );
      // Re-fetch so the matrix (existing server-side conflict check) reruns and
      // the grid reflects the new slot. Reset the per-day auto-scroll guard so
      // the moved block stays visible.
      _dayGridScrolledFor = null;
      if (mounted) await _fetchAll();
      if (!mounted) return;

      // Surface any conflict the matrix flagged on the moved lesson.
      final moved = _lessons.firstWhere(
        (l) => l['id']?.toString() == lessonId,
        orElse: () => const <String, dynamic>{},
      );
      final conflicts = _conflictTypes(moved['conflict_types']);
      if (conflicts.isNotEmpty) {
        MagicToast.show(
          context,
          'Занятие перенесено, но есть конфликт',
          detail: conflicts.map(_conflictLabel).join(', '),
          type: MagicToastType.danger,
        );
      } else {
        MagicToast.show(
          context,
          'Занятие перенесено',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось перенести занятие',
        detail: '$e',
        type: MagicToastType.danger,
      );
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
