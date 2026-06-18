import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';

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
  Object? _loadError;

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

  @override
  void initState() {
    super.initState();
    _fetchAll();
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
      // has data (from month-summary which covers all branches).
      if (enrichedLessons.isEmpty &&
          _selectedBranchId == null &&
          branches.length > 1) {
        for (final b in branches) {
          final bid = b['id'].toString();
          if (bid != defaultBranch) {
            defaultBranch = bid;
            break;
          }
        }
      }

      setState(() {
        _branches = branches;
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
      });
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

  DateTime? _parseLessonTime(Map<String, dynamic> lesson) {
    if (lesson['scheduled_at'] == null) return null;
    final dbTime = DateTime.parse(lesson['scheduled_at']).toUtc();
    return dbTime.add(const Duration(hours: 3));
  }

  DateTime? _parseServerTime(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return parsed.toUtc().add(const Duration(hours: 3));
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
  }

  void _nextDay() {
    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
    _fetchAvailabilityForSelectedDay();
  }

  void _onMonthDayTap(DateTime date) {
    setState(() {
      _selectedDate = date;
      _currentView = _ScheduleView.day;
    });
    _fetchAvailabilityForSelectedDay();
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
    // Keep the header and date controls visible during loading/error so the
    // manager can always tell where they are and retry, instead of staring at
    // an anonymous skeleton grid.
    final isBusy = _isLoading || _loadError != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildHeader(),
          if (!isBusy) ...[
            _buildBranchSelector(),
            if (_currentView == _ScheduleView.day) _buildDayViewModeToggle(),
          ],
          _buildDateNavigation(),
          if (!isBusy && _currentView == _ScheduleView.day)
            _buildAvailabilitySummary(),
          Expanded(child: _buildScheduleContent()),
        ],
      ),
      floatingActionButton: isBusy
          ? null
          : FloatingActionButton(
              onPressed: () => _showAddLessonDialog(
                _currentView == _ScheduleView.day
                    ? _selectedDate
                    : DateTime.now(),
                null,
              ),
              backgroundColor: AppTheme.primaryPurple,
              child: Icon(Icons.add_rounded, color: Colors.white),
            ),
    );
  }

  Widget _buildScheduleContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: ScheduleSkeleton(rows: 7, columns: 6),
      );
    }
    if (_loadError != null) {
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
        children: _branches.map((b) {
          final id = b['id'].toString();
          final isSelected = id == _selectedBranchId;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                b['name'].toString(),
                style: TextStyle(
                  color: isSelected
                      ? AppTheme.primaryPurple
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
              selectedColor: AppTheme.primaryPurple.withAlpha(25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? AppTheme.primaryPurple
                      : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withAlpha(60),
                  width: 1,
                ),
              ),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
          );
        }).toList(),
      ),
    );
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
              setState(() => _dayViewMode = _DayViewMode.byRoom);
            },
          ),
          SizedBox(width: 8),
          _buildToggleButton(
            'По педагогу',
            _dayViewMode == _DayViewMode.byTeacher,
            () {
              setState(() => _dayViewMode = _DayViewMode.byTeacher);
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
              color: AppTheme.success,
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
                  : AppTheme.danger,
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

  // Empty-state hint shown when the loaded period has no lessons, so an empty
  // calendar does not read as a broken/loading screen.
  Widget _buildEmptyScheduleHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
        child: Row(
          children: [
            Icon(
              Icons.event_busy_rounded,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'На выбранный период занятий нет',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _showAddLessonDialog(
                _currentView == _ScheduleView.day
                    ? _selectedDate
                    : DateTime.now(),
                null,
              ),
              child: const Text('Создать занятие'),
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
        if (_monthDaySummary.isEmpty && _filteredLessons.isEmpty)
          _buildEmptyScheduleHint(),
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
                ? Border.all(color: AppTheme.primaryPurple, width: 1.5)
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
                        color: AppTheme.primaryPurple,
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

    if (rooms.isEmpty) {
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

    return Column(
      children: [
        // Room headers
        SizedBox(
          height: headerHeight,
          child: Row(
            children: [
              SizedBox(width: 52), // time column
              ...rooms.map((r) {
                final rid = r['id'].toString();
                final color =
                    _roomColorMap[rid] ??
                    Theme.of(context).colorScheme.onSurfaceVariant;
                final availability = _availabilityForRoom(rid);
                final roomConflicts = _conflictTypes(
                  availability?['conflict_types'],
                );
                final isAvailable = availability == null
                    ? true
                    : availability['is_available'] == true;
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
                        color: isAvailable && roomConflicts.isEmpty
                            ? color.withAlpha(50)
                            : AppTheme.danger,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!isAvailable || roomConflicts.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 13,
                                  color: AppTheme.danger,
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
            ],
          ),
        ),

        // Time grid + lesson cards
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: (endHour - startHour) * hourHeight,
              child: Row(
                children: [
                  // Time axis
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
                  // Room columns
                  ...rooms.map((r) {
                    final rid = r['id'].toString();
                    final color =
                        _roomColorMap[rid] ??
                        Theme.of(context).colorScheme.onSurfaceVariant;
                    final roomLessons = dayLessons
                        .where((l) => l['room_id']?.toString() == rid)
                        .toList();

                    return Expanded(
                      child: Stack(
                        children: [
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
                  }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayLessonCard(
    Map<String, dynamic> lesson,
    int startHour,
    double hourHeight,
    Color roomColor,
  ) {
    final start = _parseLessonTime(lesson);
    if (start == null) return const SizedBox.shrink();

    final duration = lesson['duration_minutes'] as int? ?? 60;
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

    return Positioned(
      top: topOffset,
      left: 2,
      right: 2,
      height: height.clamp(24.0, double.infinity),
      child: GestureDetector(
        onTap: () => _showLessonDetails(lesson),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: conflicts.isEmpty
                ? roomColor.withAlpha(40)
                : AppTheme.danger.withAlpha(32),
            borderRadius: BorderRadius.circular(6),
            border: Border(
              left: BorderSide(
                color: conflicts.isEmpty ? roomColor : AppTheme.danger,
                width: 3,
              ),
              right: conflicts.isEmpty
                  ? BorderSide.none
                  : const BorderSide(color: AppTheme.danger, width: 1),
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
                        color: conflicts.isEmpty ? roomColor : AppTheme.danger,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  if (conflicts.isNotEmpty)
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.danger,
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
        ),
      ),
    );
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
                          ? AppTheme.primaryPurple.withAlpha(30)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryPurple
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
                            color: AppTheme.primaryPurple.withAlpha(50),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: AppTheme.primaryPurple,
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

    final duration = lesson['duration_minutes'] as int? ?? 60;
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
              : AppTheme.danger.withAlpha(24),
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: conflicts.isEmpty ? roomColor : AppTheme.danger,
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
                color: AppTheme.danger,
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
        return AppTheme.success;
      case 'cancelled':
        return AppTheme.danger;
      default:
        return AppTheme.primaryPurple;
    }
  }

  // ── Lesson details dialog ─────────────────────────────────────────────────
  void _showLessonDetails(Map<String, dynamic> lesson) {
    final start = _parseLessonTime(lesson);
    if (start == null) return;

    final duration = lesson['duration_minutes'] as int? ?? 60;
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Информация о занятии'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow(Icons.person_rounded, 'Ученик', studentName),
            SizedBox(height: 8),
            _detailRow(Icons.school_rounded, 'Педагог', teacherName),
            SizedBox(height: 8),
            _detailRow(Icons.room_rounded, 'Аудитория', roomName),
            SizedBox(height: 8),
            _detailRow(
              Icons.access_time_rounded,
              'Время',
              '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} – '
                  '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
            ),
            SizedBox(height: 8),
            _detailRow(
              Icons.info_outline_rounded,
              'Статус',
              lesson['status']?.toString() ?? 'planned',
            ),
            if (conflicts.isNotEmpty) ...[
              SizedBox(height: 8),
              _detailRow(
                Icons.warning_amber_rounded,
                'Конфликты',
                conflicts.map(_conflictLabel).join(', '),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryPurple),
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
              color: AppTheme.danger,
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
