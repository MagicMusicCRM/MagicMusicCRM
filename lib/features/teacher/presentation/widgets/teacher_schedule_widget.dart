import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_sheets.dart';
import 'package:intl/intl.dart';

/// Teacher schedule (P2-7 / KVA-195). v7 restyle + parity with the admin
/// schedule: shows the signed-in teacher's lessons from the same
/// `listLessons` payload the manager view consumes (student / room / branch
/// names, status, plan notes). Read-only chrome is fine for the teacher — the
/// service calls (`listTeachers` / `listLessons` / `updateLesson`) are
/// unchanged; only the surfaces/accents are migrated to
/// the v7 tokens (AppColor / AppRadius / AppSpace) and the P0 components
/// (showMagicSheet / MagicToast / SkeletonBox). Surfaces follow the app theme
/// (light + dark) via [Theme.of]; accents use the v7 gold/success/danger.
class TeacherScheduleWidget extends ConsumerStatefulWidget {
  const TeacherScheduleWidget({super.key});

  @override
  ConsumerState<TeacherScheduleWidget> createState() =>
      _TeacherScheduleWidgetState();
}

class _TeacherScheduleWidgetState extends ConsumerState<TeacherScheduleWidget> {
  bool _isLoading = true;

  List<Appointment> _appointments = [];
  // Keeps the raw lesson payload keyed by lesson id so trial-only completion
  // can be distinguished from ordinary lessons (completed by admin attendance).
  final Map<String, Map<String, dynamic>> _lessonsById = {};
  final CalendarController _calendarController = CalendarController();
  bool _realtimeRefreshQueued = false;

  @override
  void initState() {
    super.initState();
    _fetchScheduleData();
  }

  Future<void> _fetchScheduleData() async {
    setState(() => _isLoading = true);
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final profile = await ref.read(magicAuthServiceProvider).currentProfile();
      // The teachers catalogue is ordered by name, so its first row is not the
      // signed-in teacher. Narrow by the current profile's email and still
      // require an exact user-id match before loading lessons.
      final teachers = await crm.listTeachers(q: profile.email, limit: 100);
      final teacher = teachers
          .where(
            (item) => item['profile_user_id']?.toString() == profile.userId,
          )
          .firstOrNull;

      if (teacher == null) {
        setState(() => _isLoading = false);
        return;
      }

      final lessonsRes = await crm.listLessons(
        teacherId: teacher['id']?.toString(),
        limit: 200,
      );

      final appointments = <Appointment>[];
      _lessonsById.clear();
      for (final lesson in lessonsRes) {
        if (lesson['scheduled_at'] == null) continue;
        final lessonId = lesson['id']?.toString();
        if (lessonId != null) _lessonsById[lessonId] = lesson;
        final dbTime = DateTime.parse(lesson['scheduled_at']).toUtc();
        final start = dbTime.add(const Duration(hours: 3));
        // Defensive: the backend may send duration as int, double, or string.
        // A bare `as int?` cast throws on a double and crashes the schedule
        // view, so parse leniently and fall back to a 60-minute slot (KVA-166).
        final durationRaw = lesson['duration_minutes'];
        final duration = durationRaw is int
            ? durationRaw
            : durationRaw is num
            ? durationRaw.round()
            : int.tryParse(durationRaw?.toString() ?? '') ?? 60;
        final end = start.add(Duration(minutes: duration));

        final status = lesson['status'] as String?;
        final subjectName =
            [lesson['student_name'], lesson['lead_name'], lesson['group_name']]
                .map((value) => value?.toString().trim() ?? '')
                .firstWhere(
                  (value) => value.isNotEmpty,
                  orElse: () => 'Ученик',
                );
        final studentName = lesson['is_trial'] == true
            ? 'Пробное · $subjectName'
            : subjectName;
        final roomName = lesson['room_name']?.toString() ?? 'Аудитория';
        final branchName = lesson['branch_name']?.toString() ?? '';
        final locationInfo = branchName.isNotEmpty
            ? '$roomName ($branchName)'
            : roomName;

        // v7 accents: gold for scheduled, success for completed, danger for
        // cancelled. Surfaces stay theme-driven; only the per-card accent uses
        // the locked tokens.
        Color bgColor = AppColor.gold;
        if (status == 'completed') bgColor = AppColor.success;
        if (status == 'cancelled') bgColor = AppColor.danger;

        appointments.add(
          Appointment(
            startTime: start,
            endTime: end,
            subject: studentName,
            location: locationInfo,
            color: bgColor,
            notes: lesson['notes']?.toString() ?? '',
            id: lesson['id'],
          ),
        );
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
      await ref
          .read(magicCrmServiceProvider)
          .updateLesson(lessonId, status: 'completed');
      if (mounted) {
        MagicToast.show(
          context,
          'Занятие завершено',
          type: MagicToastType.success,
        );
      }
      _fetchScheduleData();
    } catch (e) {
      debugPrint('Error completing lesson: $e');
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось завершить занятие',
          type: MagicToastType.danger,
        );
      }
    }
  }

  Future<void> _editLessonPlan(String lessonId, String currentPlan) async {
    final controller = TextEditingController(text: currentPlan);
    final cs = Theme.of(context).colorScheme;
    final result = await showMagicSheet<String>(
      context,
      title: 'План занятия',
      subtitle: 'Что планируете делать на уроке?',
      icon: Icons.edit_note_rounded,
      builder: (ctx) => TextField(
        controller: controller,
        maxLines: 5,
        autofocus: true,
        style: TextStyle(color: cs.onSurface),
        decoration: InputDecoration(
          hintText: 'Опишите план урока…',
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            borderSide: BorderSide(color: AppColor.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            borderSide: BorderSide(color: AppColor.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            borderSide: const BorderSide(color: AppColor.gold),
          ),
        ),
      ),
      actions: [
        _SheetButton.secondary(
          label: 'Отмена',
          onPressed: () => Navigator.pop(context),
        ),
        _SheetButton.gold(
          label: 'Сохранить',
          onPressed: () => Navigator.pop(context, controller.text),
        ),
      ],
    );
    controller.dispose();

    if (result != null) {
      await ref
          .read(magicCrmServiceProvider)
          .updateLesson(lessonId, notes: result.trim());
      _fetchScheduleData();
    }
  }

  Future<void> _assignHomework(String lessonId) async {
    final lesson = _lessonsById[lessonId];
    if (lesson == null) return;
    final studentId = lesson['student_id']?.toString();
    final leadId = lesson['lead_id']?.toString();
    if ((studentId == null || studentId.isEmpty) &&
        (leadId == null || leadId.isEmpty)) {
      if (mounted) {
        MagicToast.show(
          context,
          'У занятия нет ученика или лида',
          type: MagicToastType.danger,
        );
      }
      return;
    }

    final crm = ref.read(magicCrmServiceProvider);
    List<Map<String, dynamic>> recent = const [];
    try {
      recent = await crm.listHomeworks(lessonId: lessonId, limit: 20);
    } catch (_) {
      // The create form remains usable if the preview fetch is temporarily
      // unavailable; the mutation itself still has server-side lesson scope.
    }
    if (!mounted) return;

    final input = await showAssignHomeworkSheet(
      context,
      recentHomeworks: recent,
    );
    if (input == null || !mounted) return;

    try {
      await crm.createHomework(
        studentId: studentId?.isNotEmpty == true ? studentId : null,
        leadId: leadId?.isNotEmpty == true ? leadId : null,
        lessonId: lessonId,
        title: input.title,
        description: input.description,
        dueAt: input.dueAt?.toIso8601String(),
      );
      if (!mounted) return;
      MagicToast.show(
        context,
        'ДЗ назначено',
        detail: input.title,
        type: MagicToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось назначить ДЗ',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  void _scheduleRealtimeRefresh() {
    if (_realtimeRefreshQueued || !mounted) return;
    _realtimeRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _realtimeRefreshQueued = false;
      if (mounted) _fetchScheduleData();
    });
  }

  void _showLessonDetails(Appointment appointment) {
    if (appointment.id == null) return;
    final lessonId = appointment.id.toString();
    final cs = Theme.of(context).colorScheme;
    final accent = appointment.color;
    final hasPlan = appointment.notes?.isNotEmpty == true;
    final isTrial = _lessonsById[lessonId]?['is_trial'] == true;

    showMagicSheet<void>(
      context,
      title: appointment.subject,
      subtitle:
          '${DateFormat('dd.MM.yyyy HH:mm', 'ru').format(appointment.startTime)} – ${DateFormat('HH:mm', 'ru').format(appointment.endTime)}',
      icon: Icons.event_rounded,
      builder: (ctx) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(
              icon: Icons.place_outlined,
              text: appointment.location ?? 'Не указано',
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              'План занятия',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColor.gold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: AppColor.divider),
              ),
              child: Text(
                hasPlan ? appointment.notes! : 'План не заполнен',
                style: TextStyle(
                  color: hasPlan ? cs.onSurface : cs.onSurfaceVariant,
                  fontStyle: hasPlan ? FontStyle.normal : FontStyle.italic,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            // Teachers edit the plan/homework. Attendance and ordinary-lesson
            // completion are admin+ because they drive subscription charges.
            _ActionTile(
              icon: Icons.edit_note_rounded,
              label: 'Изменить план',
              accent: AppColor.gold,
              onTap: () {
                Navigator.pop(ctx);
                _editLessonPlan(lessonId, appointment.notes ?? '');
              },
            ),
            _ActionTile(
              icon: Icons.assignment_rounded,
              label: 'Домашнее задание',
              accent: AppColor.gold,
              onTap: () {
                Navigator.pop(ctx);
                _assignHomework(lessonId);
              },
            ),
            if (isTrial && accent == AppColor.gold)
              _ActionTile(
                icon: Icons.check_circle_outline_rounded,
                label: 'Завершить пробное',
                accent: AppColor.success,
                onTap: () {
                  Navigator.pop(ctx);
                  _markCompleted(lessonId);
                },
              ),
          ],
        );
      },
      actions: [
        _SheetButton.gold(
          label: 'Закрыть',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(crmRealtimeProvider, (previous, next) {
      final entity = next.value?.entity;
      if (entity == 'lesson' || entity == 'homework') {
        _scheduleRealtimeRefresh();
      }
    });
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Header controls
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.sm,
          ),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: AppColor.divider),
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<CalendarView>(
                    value: _calendarController.view,
                    dropdownColor: cs.surface,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    icon: Icon(
                      Icons.expand_more_rounded,
                      color: cs.onSurfaceVariant,
                      size: 20,
                    ),
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: CalendarView.day,
                        child: Text('День'),
                      ),
                      DropdownMenuItem(
                        value: CalendarView.week,
                        child: Text('Неделя'),
                      ),
                      DropdownMenuItem(
                        value: CalendarView.month,
                        child: Text('Месяц'),
                      ),
                      DropdownMenuItem(
                        value: CalendarView.schedule,
                        child: Text('Расписание'),
                      ),
                    ],
                    onChanged: (view) {
                      if (view != null) {
                        setState(() => _calendarController.view = view);
                      }
                    },
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: cs.onSurfaceVariant),
                tooltip: 'Обновить',
                onPressed: _fetchScheduleData,
              ),
            ],
          ),
        ),

        // Calendar Body
        Expanded(
          child: _isLoading
              ? const _ScheduleLoading()
              : SfCalendar(
                  controller: _calendarController,
                  view: CalendarView.day,
                  firstDayOfWeek: 1, // Monday
                  todayHighlightColor: AppColor.gold,
                  cellBorderColor: AppColor.divider,
                  backgroundColor: Colors.transparent,
                  timeSlotViewSettings: const TimeSlotViewSettings(
                    startHour: 6,
                    endHour: 23,
                    timeFormat: 'HH:mm',
                    timeIntervalHeight: 60,
                  ),
                  dataSource: _TeacherLessonDataSource(_appointments),
                  onTap: (CalendarTapDetails details) {
                    if (details.appointments != null &&
                        details.appointments!.isNotEmpty) {
                      final Appointment appItem = details.appointments![0];
                      _showLessonDetails(appItem);
                    }
                  },
                  appointmentBuilder:
                      (
                        BuildContext context,
                        CalendarAppointmentDetails details,
                      ) {
                        final Appointment app = details.appointments.first;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.xs,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: app.color.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                            border: Border.all(color: app.color, width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      app.subject,
                                      style: TextStyle(
                                        color: app.color,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
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

/// v7 loading state — token-driven skeleton rows in place of a bare spinner.
class _ScheduleLoading extends StatelessWidget {
  const _ScheduleLoading();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpace.md),
      itemBuilder: (_, _) => const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 44, height: 14, radius: AppRadius.sm),
          SizedBox(width: AppSpace.md),
          Expanded(child: SkeletonBox(height: 54, radius: AppRadius.chip)),
        ],
      ),
    );
  }
}

/// Icon + label detail row inside the lesson sheet.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: cs.onSurface, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

/// Tappable action row inside the lesson detail sheet (gold-soft fill + tinted
/// icon badge), mirroring the v7 pop-menu item.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.md,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: accent.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: accent),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Footer button for the v7 sheets. Flat gold (no shadow) for the primary
/// action; outlined secondary for dismiss/cancel.
class _SheetButton extends StatelessWidget {
  const _SheetButton._({
    required this.label,
    required this.onPressed,
    required this.gold,
  });

  factory _SheetButton.gold({
    required String label,
    required VoidCallback onPressed,
  }) => _SheetButton._(label: label, onPressed: onPressed, gold: true);

  factory _SheetButton.secondary({
    required String label,
    required VoidCallback onPressed,
  }) => _SheetButton._(label: label, onPressed: onPressed, gold: false);

  final String label;
  final VoidCallback onPressed;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(46)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );

    if (gold) {
      return FilledButton(
        onPressed: onPressed,
        style: style.copyWith(
          backgroundColor: const WidgetStatePropertyAll(AppColor.gold),
          foregroundColor: const WidgetStatePropertyAll(AppColor.onGold),
        ),
        child: Text(label),
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: style.copyWith(
        foregroundColor: WidgetStatePropertyAll(cs.onSurface),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColor.divider)),
      ),
      child: Text(label),
    );
  }
}

class _TeacherLessonDataSource extends CalendarDataSource {
  _TeacherLessonDataSource(List<Appointment> source) {
    appointments = source;
  }
}
