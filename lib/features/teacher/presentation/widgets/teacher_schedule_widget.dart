import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:intl/intl.dart';

class TeacherScheduleWidget extends ConsumerStatefulWidget {
  const TeacherScheduleWidget({super.key});

  @override
  ConsumerState<TeacherScheduleWidget> createState() => _TeacherScheduleWidgetState();
}

class _TeacherScheduleWidgetState extends ConsumerState<TeacherScheduleWidget> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  
  List<Appointment> _appointments = [];
  final CalendarController _calendarController = CalendarController();

  @override
  void initState() {
    super.initState();
    _fetchScheduleData();
  }

  Future<void> _fetchScheduleData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Get teacher record
      final teacher = await _supabase
          .from('teachers')
          .select('id')
          .eq('profile_id', userId)
          .maybeSingle();

      if (teacher == null) {
        setState(() => _isLoading = false);
        return;
      }

      final lessonsRes = await _supabase.from('lessons').select('''
        id, scheduled_at, duration_minutes, status, lesson_plan,
        students(first_name, last_name, profiles(first_name, last_name)),
        rooms(name, branches(name))
      ''').eq('teacher_id', teacher['id']);

      final appointments = <Appointment>[];
      for (final lesson in lessonsRes) {
        if (lesson['scheduled_at'] == null) continue;
        final dbTime = DateTime.parse(lesson['scheduled_at']).toUtc();
        final start = dbTime.add(const Duration(hours: 3));
        final duration = lesson['duration_minutes'] as int? ?? 60;
        final end = start.add(Duration(minutes: duration));
        
        final status = lesson['status'] as String?;
        final studentEntry = lesson['students'] as Map<String, dynamic>?;
        String studentName = 'Ученик';
        if (studentEntry != null) {
          final fn = studentEntry['first_name']?.toString() ?? '';
          final ln = studentEntry['last_name']?.toString() ?? '';
          final p = studentEntry['profiles'] as Map<String, dynamic>?;
          var name = '$fn $ln'.trim();
          if (name.isEmpty && p != null) {
            name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
          }
          studentName = name.isEmpty ? 'Без имени' : name;
        }
        final roomName = lesson['rooms']?['name'] ?? 'Аудитория';
        final branchName = lesson['rooms']?['branches']?['name'] ?? '';
        final locationInfo = branchName.isNotEmpty ? '$roomName ($branchName)' : roomName;

        Color bgColor = AppTheme.primaryPurple;
        if (status == 'completed') bgColor = AppTheme.success;
        if (status == 'cancelled') bgColor = AppTheme.danger;

        appointments.add(Appointment(
          startTime: start,
          endTime: end,
          subject: studentName,
          location: locationInfo,
          color: bgColor,
          notes: lesson['lesson_plan']?.toString() ?? '',
          id: lesson['id'],
        ));
      }

      setState(() {
        _appointments = appointments;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching teacher schedule: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markCompleted(String lessonId) async {
    try {
      await _supabase.from('lessons').update({'status': 'completed'}).eq('id', lessonId);
      _fetchScheduleData();
    } catch (e) {
      debugPrint('Error completing lesson: $e');
    }
  }

  Future<void> _editLessonPlan(String lessonId, String currentPlan) async {
    final controller = TextEditingController(text: currentPlan);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('План занятия'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Что планируете делать на уроке?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Сохранить')),
        ],
      ),
    );

    if (result != null) {
      await _supabase.from('lessons').update({'lesson_plan': result.trim()}).eq('id', lessonId);
      _fetchScheduleData();
    }
  }

  void _showLessonDetails(Appointment appointment) {
    if (appointment.id == null) return;
    final lessonId = appointment.id.toString();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(appointment.subject),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${DateFormat('dd.MM.yyyy HH:mm').format(appointment.startTime)} - ${DateFormat('HH:mm').format(appointment.endTime)}'),
              const SizedBox(height: 8),
              Text('Где: ${appointment.location ?? "Не указано"}'),
              const SizedBox(height: 16),
              if (appointment.notes?.isNotEmpty == true) ...[
                const Text('План занятия:', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.primaryPurple)),
                const SizedBox(height: 4),
                Text(appointment.notes!),
              ] else
                Text('План не заполнен', style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _editLessonPlan(lessonId, appointment.notes ?? '');
              },
              child: const Text('Изменить план'),
            ),
            if (appointment.color == AppTheme.primaryPurple)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _markCompleted(lessonId);
                },
                child: const Text('Завершить занятие', style: TextStyle(color: AppTheme.success)),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              DropdownButton<CalendarView>(
                value: _calendarController.view,
                dropdownColor: Theme.of(context).colorScheme.surface,
                items: const [
                  DropdownMenuItem(value: CalendarView.day, child: Text('День')),
                  DropdownMenuItem(value: CalendarView.week, child: Text('Неделя')),
                  DropdownMenuItem(value: CalendarView.month, child: Text('Месяц')),
                  DropdownMenuItem(value: CalendarView.schedule, child: Text('Расписание')),
                ],
                onChanged: (view) {
                  if (view != null) {
                    setState(() => _calendarController.view = view);
                  }
                },
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _fetchScheduleData,
              ),
            ],
          ),
        ),
        
        // Calendar Body
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple))
              : SfCalendar(
                  controller: _calendarController,
                  view: CalendarView.day,
                  firstDayOfWeek: 1, // Monday
                  timeSlotViewSettings: const TimeSlotViewSettings(
                    startHour: 6,
                    endHour: 23,
                    timeFormat: 'HH:mm',
                    timeIntervalHeight: 60,
                  ),
                  dataSource: _TeacherLessonDataSource(_appointments),
                  onTap: (CalendarTapDetails details) {
                    if (details.appointments != null && details.appointments!.isNotEmpty) {
                      final Appointment appItem = details.appointments![0];
                      _showLessonDetails(appItem);
                    }
                  },
                  appointmentBuilder: (BuildContext context, CalendarAppointmentDetails details) {
                    final Appointment app = details.appointments.first;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: app.color.withAlpha(50),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: app.color, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.subject,
                            style: TextStyle(color: app.color, fontSize: 11, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            app.location ?? '',
                            style: TextStyle(color: app.color, fontSize: 9),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TeacherLessonDataSource extends CalendarDataSource {
  _TeacherLessonDataSource(List<Appointment> source) {
    appointments = source;
  }
}
