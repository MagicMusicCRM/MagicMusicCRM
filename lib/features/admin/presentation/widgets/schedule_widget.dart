import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

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
  '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

const _monthNamesNominative = [
  '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
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
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;

  // Data
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _lessons = [];
  List<Map<String, dynamic>> _teachers = [];
  Map<String, String> _teacherNames = {};
  Map<String, String> _studentNames = {};
  Map<String, Color> _roomColorMap = {};
  Map<String, String> _roomNames = {};


  // UI state
  String? _selectedBranchId;
  _ScheduleView _currentView = _ScheduleView.month;
  _DayViewMode _dayViewMode = _DayViewMode.byRoom;
  DateTime _selectedDate = DateTime.now();
  DateTime _displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String? _selectedTeacherId;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  // ── Data fetching ─────────────────────────────────────────────────────────
  Future<void> _fetchAll() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _supabase.from('branches').select('id, name'),
        _supabase.from('rooms').select('id, name, branch_id'),
        _supabase.from('lessons').select('id, scheduled_at, duration_minutes, status, teacher_id, student_id, room_id, branch_id'),
        _supabase.from('teachers').select('id, first_name, last_name, profiles(first_name, last_name)'),
        _supabase.from('students').select('id, first_name, last_name, profiles(first_name, last_name)'),
      ]);

      final branches = List<Map<String, dynamic>>.from(results[0]);
      final rooms = List<Map<String, dynamic>>.from(results[1]);
      final lessons = List<Map<String, dynamic>>.from(results[2]);
      final teachers = List<Map<String, dynamic>>.from(results[3]);
      final students = List<Map<String, dynamic>>.from(results[4]);

      // Default branch
      final defaultBranch = _selectedBranchId ?? (branches.isNotEmpty ? branches.first['id'].toString() : null);

      // Room color map
      final colorMap = <String, Color>{};
      final nameMap = <String, String>{};

      for (int i = 0; i < rooms.length; i++) {
        final rid = rooms[i]['id'].toString();
        colorMap[rid] = _roomColors[i % _roomColors.length];
        nameMap[rid] = rooms[i]['name']?.toString() ?? 'Аудитория';

      }

      // Teacher names
      final tNames = <String, String>{};
      for (final t in teachers) {
        final tid = t['id'].toString();
        tNames[tid] = _formatTeacherName(t);
      }

      // Student names
      final sNames = <String, String>{};
      for (final s in students) {
        final sid = s['id'].toString();
        sNames[sid] = _formatStudentName(s);
      }

      setState(() {
        _branches = branches;
        _rooms = rooms;
        _lessons = lessons;
        _teachers = teachers;
        _selectedBranchId = defaultBranch;
        _roomColorMap = colorMap;
        _roomNames = nameMap;

        _teacherNames = tNames;
        _studentNames = sNames;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching schedule: $e');
      setState(() => _isLoading = false);
    }
  }

  // ── Filtered helpers ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredRooms {
    if (_selectedBranchId == null) return _rooms;
    return _rooms.where((r) => r['branch_id']?.toString() == _selectedBranchId).toList();
  }

  List<Map<String, dynamic>> get _filteredLessons {
    return _lessons.where((l) {
      if (l['scheduled_at'] == null) return false;
      if (_selectedBranchId != null && l['branch_id'] != null && l['branch_id'].toString() != _selectedBranchId) return false;
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> _lessonsForDate(DateTime date) {
    return _filteredLessons.where((l) {
      final dt = _parseLessonTime(l);
      return dt != null && dt.year == date.year && dt.month == date.month && dt.day == date.day;
    }).toList();
  }

  DateTime? _parseLessonTime(Map<String, dynamic> lesson) {
    if (lesson['scheduled_at'] == null) return null;
    final dbTime = DateTime.parse(lesson['scheduled_at']).toUtc();
    return dbTime.add(const Duration(hours: 3));
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _goToToday() {
    setState(() {
      _selectedDate = DateTime.now();
      _displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
    });
  }

  void _prevMonth() => setState(() => _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1));
  void _nextMonth() => setState(() => _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1));
  void _prevDay() => setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
  void _nextDay() => setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));

  void _onMonthDayTap(DateTime date) {
    setState(() {
      _selectedDate = date;
      _currentView = _ScheduleView.day;
    });
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

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildHeader(),
          _buildBranchSelector(),
          if (_currentView == _ScheduleView.day) _buildDayViewModeToggle(),
          _buildDateNavigation(),
          Expanded(
            child: _currentView == _ScheduleView.month ? _buildMonthView() : _buildDayView(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddLessonDialog(
          _currentView == _ScheduleView.day ? _selectedDate : DateTime.now(),
          null,
        ),
        backgroundColor: AppTheme.primaryPurple,
        child: Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
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
              icon: Icon(Icons.arrow_back_rounded, color: Theme.of(context!).colorScheme.onSurface),
              onPressed: () => setState(() => _currentView = _ScheduleView.month),
              tooltip: 'Назад к месяцу',
            ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Theme.of(context!).colorScheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.search_rounded, color: Theme.of(context!).colorScheme.onSurfaceVariant, size: 22),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.tune_rounded, color: Theme.of(context!).colorScheme.onSurfaceVariant, size: 22),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: Theme.of(context!).colorScheme.onSurfaceVariant, size: 22),
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
                  color: isSelected ? AppTheme.primaryPurple : Theme.of(context!).colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 14,
                ),
              ),
              selected: isSelected,
              onSelected: (_) {
                setState(() => _selectedBranchId = id);
              },
              backgroundColor: Theme.of(context!).colorScheme.surface,
              selectedColor: AppTheme.primaryPurple.withAlpha(25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? AppTheme.primaryPurple : Theme.of(context!).colorScheme.onSurfaceVariant.withAlpha(60),
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
          _buildToggleButton('По аудиториям', _dayViewMode == _DayViewMode.byRoom, () {
            setState(() => _dayViewMode = _DayViewMode.byRoom);
          }),
          SizedBox(width: 8),
          _buildToggleButton('По педагогу', _dayViewMode == _DayViewMode.byTeacher, () {
            setState(() => _dayViewMode = _DayViewMode.byTeacher);
          }),
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
          color: isActive ? Theme.of(context!).colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Theme.of(context!).colorScheme.onSurfaceVariant.withAlpha(80) : Theme.of(context!).colorScheme.onSurfaceVariant.withAlpha(40),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Theme.of(context!).colorScheme.onSurface : Theme.of(context!).colorScheme.onSurfaceVariant,
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
      dateLabel = '${_monthNamesGenitive[_displayedMonth.month].toLowerCase()} ${_displayedMonth.year}';
      onPrev = _prevMonth;
      onNext = _nextMonth;
    } else {
      final weekDayNames = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
      final wd = weekDayNames[_selectedDate.weekday - 1];
      dateLabel = '$wd, ${_selectedDate.day} ${_monthNamesGenitive[_selectedDate.month]} ${_selectedDate.year}';
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
              child: Icon(Icons.chevron_left_rounded, color: Theme.of(context!).colorScheme.onSurfaceVariant, size: 22),
            ),
          ),
          Expanded(
            child: Text(
              dateLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context!).colorScheme.onSurface,
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
                border: Border.all(color: Theme.of(context!).colorScheme.onSurfaceVariant.withAlpha(80)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'сегодня',
                style: TextStyle(color: Theme.of(context!).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          InkWell(
            onTap: onNext,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.chevron_right_rounded, color: Theme.of(context!).colorScheme.onSurfaceVariant, size: 22),
            ),
          ),
        ],
      ),
    );
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
        // Weekday headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: _weekDays.map((d) => Expanded(
              child: Center(
                child: Text(
                  d,
                  style: TextStyle(
                    color: Theme.of(context!).colorScheme.onSurfaceVariant.withAlpha(180),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )).toList(),
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
                        return _buildMonthCell(day, isCurrentMonth: false, date: null);
                      }
                      final dayNum = index - prevDays + 1;
                      if (dayNum > daysInMonth) {
                        // Next month
                        final nextDay = dayNum - daysInMonth;
                        return _buildMonthCell(nextDay, isCurrentMonth: false, date: null);
                      }
                      final date = DateTime(year, month, dayNum);
                      final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
                      return _buildMonthCell(dayNum, isCurrentMonth: true, date: date, isToday: isToday);
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

  Widget _buildMonthCell(int day, {required bool isCurrentMonth, DateTime? date, bool isToday = false}) {
    final lessons = date != null ? _lessonsForDate(date) : <Map<String, dynamic>>[];
    final count = lessons.length;

    // Gather unique room colors for dots
    final dotColors = <Color>[];
    for (final l in lessons) {
      final rid = l['room_id']?.toString();
      final c = rid != null ? (_roomColorMap[rid] ?? Theme.of(context!).colorScheme.onSurfaceVariant) : Theme.of(context!).colorScheme.onSurfaceVariant;
      if (!dotColors.contains(c)) dotColors.add(c);
      if (dotColors.length >= 6) break; // max 6 dots
    }

    return Expanded(
      child: GestureDetector(
        onTap: date != null ? () => _onMonthDayTap(date) : null,
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isCurrentMonth ? Theme.of(context!).colorScheme.surface.withAlpha(120) : Colors.transparent,
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
                            ? Theme.of(context!).colorScheme.onSurface
                            : Theme.of(context!).colorScheme.onSurfaceVariant.withAlpha(80),
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
                  children: dotColors.take(6).map((c) => Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                    ),
                  )).toList(),
                ),
                SizedBox(height: 2),
                Text(
                  '$count зан.',
                  style: TextStyle(
                    color: Theme.of(context!).colorScheme.onSurfaceVariant.withAlpha(180),
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
          final color = _roomColorMap[rid] ?? Theme.of(context!).colorScheme.onSurfaceVariant;
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
                style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant, fontSize: 11),
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
        child: Text('Нет аудиторий для выбранного филиала', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant)),
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
                final color = _roomColorMap[rid] ?? Theme.of(context!).colorScheme.onSurfaceVariant;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
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
                                  color: Theme.of(context!).colorScheme.onSurfaceVariant.withAlpha(150),
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
                    final color = _roomColorMap[rid] ?? Theme.of(context!).colorScheme.onSurfaceVariant;
                    final roomLessons = dayLessons.where((l) => l['room_id']?.toString() == rid).toList();

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
                                    top: BorderSide(color: Theme.of(context!).colorScheme.onSurfaceVariant.withAlpha(20), width: 0.5),
                                  ),
                                ),
                              ),
                            );
                          }),
                          // Lesson cards
                          ...roomLessons.map((l) => _buildDayLessonCard(l, startHour, hourHeight, color)),
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

  Widget _buildDayLessonCard(Map<String, dynamic> lesson, int startHour, double hourHeight, Color roomColor) {
    final start = _parseLessonTime(lesson);
    if (start == null) return const SizedBox.shrink();

    final duration = lesson['duration_minutes'] as int? ?? 60;
    final end = start.add(Duration(minutes: duration));

    final topOffset = ((start.hour - startHour) + start.minute / 60.0) * hourHeight;
    final height = (duration / 60.0) * hourHeight;

    final teacherName = _teacherNames[lesson['teacher_id']?.toString()] ?? '';
    final studentName = _studentNames[lesson['student_id']?.toString()] ?? '';

    final timeStr = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} – '
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
            color: roomColor.withAlpha(40),
            borderRadius: BorderRadius.circular(6),
            border: Border(
              left: BorderSide(color: roomColor, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timeStr,
                style: TextStyle(color: roomColor, fontSize: 9, fontWeight: FontWeight.w600),
                maxLines: 1,
              ),
              if (height > 30)
                Text(
                  studentName,
                  style: TextStyle(color: Theme.of(context!).colorScheme.onSurface, fontSize: 10, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (height > 44)
                Text(
                  teacherName,
                  style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant.withAlpha(180), fontSize: 9),
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
    final teacherIds = dayLessons.map((l) => l['teacher_id']?.toString()).where((id) => id != null).toSet().toList();
    teacherIds.sort((a, b) => (_teacherNames[a] ?? '').compareTo(_teacherNames[b] ?? ''));

    if (_selectedTeacherId == null && teacherIds.isNotEmpty) {
      _selectedTeacherId = teacherIds.first;
    }

    // Filter lessons for selected teacher
    final teacherLessons = dayLessons.where((l) => l['teacher_id']?.toString() == _selectedTeacherId).toList();
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
                final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join('').toUpperCase();
                final lessonsCount = dayLessons.where((l) => l['teacher_id']?.toString() == tid).length;

                return GestureDetector(
                  onTap: () => setState(() => _selectedTeacherId = tid),
                  child: Container(
                    width: 160,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryPurple.withAlpha(30) : Theme.of(context!).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryPurple : Colors.transparent,
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
                                  color: isSelected ? Theme.of(context!).colorScheme.onSurface : Theme.of(context!).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '$lessonsCount зан.',
                                style: TextStyle(
                                  color: Theme.of(context!).colorScheme.onSurfaceVariant.withAlpha(150),
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
                    _selectedTeacherId == null ? 'Выберите педагога' : 'Нет занятий на этот день',
                    style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: teacherLessons.length,
                  itemBuilder: (context, i) => _buildTeacherLessonCard(teacherLessons[i]),
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

    final timeStr = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} – '
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';

    final studentName = _studentNames[lesson['student_id']?.toString()] ?? 'Ученик';
    final roomId = lesson['room_id']?.toString();
    final roomName = roomId != null ? (_roomNames[roomId] ?? 'Аудитория') : 'Без аудитории';
    final roomColor = roomId != null ? (_roomColorMap[roomId] ?? Theme.of(context!).colorScheme.onSurfaceVariant) : Theme.of(context!).colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: () => _showLessonDetails(lesson),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context!).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: roomColor, width: 4),
          ),
        ),
        child: Row(
          children: [
            // Time
            Column(
              children: [
                Text(
                  timeStr,
                  style: TextStyle(color: roomColor, fontSize: 12, fontWeight: FontWeight.w600),
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
                    style: TextStyle(color: Theme.of(context!).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 2),
                  Text(
                    roomName,
                    style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant.withAlpha(180), fontSize: 12),
                  ),
                ],
              ),
            ),
            // Status indicator
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
      case 'completed': return AppTheme.success;
      case 'cancelled': return AppTheme.danger;
      default: return AppTheme.primaryPurple;
    }
  }

  // ── Lesson details dialog ─────────────────────────────────────────────────
  void _showLessonDetails(Map<String, dynamic> lesson) {
    final start = _parseLessonTime(lesson);
    if (start == null) return;

    final duration = lesson['duration_minutes'] as int? ?? 60;
    final end = start.add(Duration(minutes: duration));

    final teacherName = _teacherNames[lesson['teacher_id']?.toString()] ?? 'Не назначен';
    final studentName = _studentNames[lesson['student_id']?.toString()] ?? 'Не назначен';
    final roomId = lesson['room_id']?.toString();
    final roomName = roomId != null ? (_roomNames[roomId] ?? 'Аудитория') : 'Без аудитории';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context!).colorScheme.surface,
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
            _detailRow(Icons.access_time_rounded, 'Время',
                '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} – '
                '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}'),
            SizedBox(height: 8),
            _detailRow(Icons.info_outline_rounded, 'Статус', lesson['status']?.toString() ?? 'planned'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Закрыть')),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryPurple),
        SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant, fontSize: 13)),
        Expanded(
          child: Text(value, style: TextStyle(color: Theme.of(context!).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  String _formatStudentName(Map<String, dynamic> s) {
    final fn = s['first_name']?.toString() ?? '';
    final ln = s['last_name']?.toString() ?? '';
    final p = s['profiles'] as Map<String, dynamic>?;
    
    var name = '$fn $ln'.trim();
    if (name.isEmpty && p != null) {
      name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    }
    return name.isEmpty ? 'Без имени' : name;
  }

  String _formatTeacherName(Map<String, dynamic> t) {
    final fn = t['first_name']?.toString() ?? '';
    final ln = t['last_name']?.toString() ?? '';
    final p = t['profiles'] as Map<String, dynamic>?;
    
    var name = '$fn $ln'.trim();
    if (name.isEmpty && p != null) {
      name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    }
    return name.isEmpty ? 'Без имени' : name;
  }
}
