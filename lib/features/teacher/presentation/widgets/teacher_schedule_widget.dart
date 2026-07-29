import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/lesson_state_badges.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:intl/intl.dart';

/// Teacher schedule (P2-7 / KVA-195). v7 restyle + parity with the admin
/// schedule: shows the signed-in teacher's lessons from the same
/// `listLessons` payload the manager view consumes (student / room / branch
/// names, state and plan notes). The calendar and linked client/history/
/// homework drilldowns are actor-scoped and strictly read-only.
class TeacherScheduleWidget extends ConsumerStatefulWidget {
  const TeacherScheduleWidget({super.key});

  @override
  ConsumerState<TeacherScheduleWidget> createState() =>
      _TeacherScheduleWidgetState();
}

class _TeacherScheduleWidgetState extends ConsumerState<TeacherScheduleWidget> {
  bool _isLoading = true;
  Object? _loadError;

  List<Appointment> _appointments = [];
  final Map<String, Map<String, dynamic>> _lessonsById = {};
  final CalendarController _calendarController = CalendarController();
  CalendarView _view = CalendarView.day;
  String? _teacherId;
  bool _realtimeRefreshQueued = false;

  @override
  void initState() {
    super.initState();
    _calendarController.view = _view;
    _fetchScheduleData();
  }

  Future<void> _fetchScheduleData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
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
        if (!mounted) return;
        setState(() {
          _appointments = const [];
          _lessonsById.clear();
          _loadError = StateError('Профиль преподавателя не найден');
          _isLoading = false;
        });
        return;
      }

      final teacherId = teacher['id']?.toString();
      _teacherId = teacherId;
      final lessonsRes = await crm.listLessons(
        teacherId: teacherId,
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

        final subjectName =
            [lesson['student_name'], lesson['lead_name'], lesson['group_name']]
                .map((value) => value?.toString().trim() ?? '')
                .firstWhere(
                  (value) => value.isNotEmpty,
                  orElse: () => 'Ученик',
                );
        final roomName = lesson['room_name']?.toString() ?? 'Аудитория';
        final branchName = lesson['branch_name']?.toString() ?? '';
        final locationInfo = branchName.isNotEmpty
            ? '$roomName ($branchName)'
            : roomName;

        final state = LessonStateProjection.fromMap(lesson);

        appointments.add(
          Appointment(
            startTime: start,
            endTime: end,
            subject: subjectName,
            location: locationInfo,
            color: state.token.accent,
            notes: lesson['notes']?.toString() ?? '',
            id: lesson['id'],
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _appointments = appointments;
        _loadError = null;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching teacher schedule: $e');
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _isLoading = false;
      });
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

  Future<void> _showLessonDetails(Appointment appointment) async {
    if (appointment.id == null) return;
    final lessonId = appointment.id.toString();
    final lesson = _lessonsById[lessonId];
    if (lesson == null) return;
    final cs = Theme.of(context).colorScheme;
    final hasPlan = appointment.notes?.isNotEmpty == true;
    final state = LessonStateProjection.fromMap(lesson);

    await showMagicSheet<void>(
      context,
      title: appointment.subject,
      subtitle:
          '${DateFormat('dd.MM.yyyy HH:mm', 'ru').format(appointment.startTime)} – ${DateFormat('HH:mm', 'ru').format(appointment.endTime)}',
      icon: Icons.event_rounded,
      builder: (ctx) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Карточка клиента',
              key: ValueKey('teacher-client-card-title'),
              style: TextStyle(
                color: AppColor.gold,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                LessonStateBadge(projection: state),
                if (lesson['is_trial'] == true)
                  const LessonTrialBadge(compact: true),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
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
            _ReadOnlyLinkTile(
              key: ValueKey('teacher-history-$lessonId'),
              icon: Icons.history_rounded,
              label: 'История занятий',
              accent: AppColor.gold,
              onTap: () async {
                Navigator.pop(ctx);
                await Future<void>.delayed(kThemeAnimationDuration);
                if (mounted) await _showLessonHistory(lesson);
              },
            ),
            _ReadOnlyLinkTile(
              key: ValueKey('teacher-homeworks-$lessonId'),
              icon: Icons.assignment_outlined,
              label: 'Домашние задания',
              accent: AppColor.gold,
              onTap: () async {
                Navigator.pop(ctx);
                await Future<void>.delayed(kThemeAnimationDuration);
                if (mounted) await _showHomeworkHistory(lesson);
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

  Future<List<Map<String, dynamic>>> _loadLessonHistory(
    Map<String, dynamic> lesson,
  ) async {
    final crm = ref.read(magicCrmServiceProvider);
    final studentId = lesson['student_id']?.toString();
    if (studentId != null && studentId.isNotEmpty) {
      return crm.listLessons(
        studentId: studentId,
        teacherId: _teacherId,
        order: 'desc',
        limit: 50,
      );
    }
    final leadId = lesson['lead_id']?.toString();
    if (leadId == null || leadId.isEmpty) return const [];
    final assignedTrials = await crm.listLessons(
      teacherId: _teacherId,
      isTrial: true,
      order: 'desc',
      limit: 200,
    );
    return assignedTrials
        .where((item) => item['lead_id']?.toString() == leadId)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadHomeworkHistory(
    Map<String, dynamic> lesson,
  ) {
    final studentId = lesson['student_id']?.toString();
    final leadId = lesson['lead_id']?.toString();
    if (studentId?.isNotEmpty != true && leadId?.isNotEmpty != true) {
      return Future.value(const []);
    }
    return ref
        .read(magicCrmServiceProvider)
        .listHomeworks(
          studentId: studentId?.isNotEmpty == true ? studentId : null,
          leadId: leadId?.isNotEmpty == true ? leadId : null,
          limit: 50,
        );
  }

  Future<void> _showLessonHistory(Map<String, dynamic> lesson) {
    final history = _loadLessonHistory(lesson);
    return showMagicSheet<void>(
      context,
      title: 'История занятий',
      subtitle: _clientName(lesson),
      icon: Icons.history_rounded,
      builder: (_) => _TeacherLessonHistory(future: history),
      actions: [
        _SheetButton.gold(
          label: 'Закрыть',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Future<void> _showHomeworkHistory(Map<String, dynamic> lesson) {
    final homeworks = _loadHomeworkHistory(lesson);
    return showMagicSheet<void>(
      context,
      title: 'Домашние задания',
      subtitle: _clientName(lesson),
      icon: Icons.assignment_outlined,
      builder: (_) => _TeacherHomeworkHistory(future: homeworks),
      actions: [
        _SheetButton.gold(
          label: 'Закрыть',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  String _clientName(Map<String, dynamic> lesson) {
    return [lesson['student_name'], lesson['lead_name'], lesson['group_name']]
        .map((value) => value?.toString().trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => 'Клиент');
  }

  void _setView(CalendarView view) {
    setState(() {
      _view = view;
      _calendarController.view = view;
    });
  }

  Widget _viewSelector(ColorScheme cs, double width) {
    if (width >= 420) {
      return SegmentedButton<CalendarView>(
        key: const ValueKey('teacher-calendar-view-segments'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: CalendarView.day, label: Text('День')),
          ButtonSegment(value: CalendarView.week, label: Text('Неделя')),
        ],
        selected: {_view},
        onSelectionChanged: (views) => _setView(views.single),
      );
    }
    return Container(
      key: const ValueKey('teacher-calendar-view-dropdown'),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<CalendarView>(
          value: _view,
          dropdownColor: cs.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          items: const [
            DropdownMenuItem(value: CalendarView.day, child: Text('День')),
            DropdownMenuItem(value: CalendarView.week, child: Text('Неделя')),
          ],
          onChanged: (view) {
            if (view != null) _setView(view);
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _calendarController.dispose();
    super.dispose();
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
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                _viewSelector(cs, constraints.maxWidth),
                const Spacer(),
                IconButton(
                  key: const ValueKey('teacher-calendar-refresh'),
                  icon: Icon(Icons.refresh_rounded, color: cs.onSurfaceVariant),
                  tooltip: 'Обновить',
                  onPressed: _fetchScheduleData,
                ),
              ],
            ),
          ),
        ),

        // Calendar Body
        Expanded(
          child: _isLoading
              ? const _ScheduleLoading()
              : _loadError != null
              ? _ScheduleError(onRetry: _fetchScheduleData)
              : Stack(
                  children: [
                    SfCalendar(
                      key: const ValueKey('teacher-calendar-grid'),
                      controller: _calendarController,
                      view: _view,
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
                            final lesson = _lessonsById[app.id?.toString()];
                            return Container(
                              key: ValueKey('teacher-lesson-${app.id}'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpace.xs,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: app.color.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.chip,
                                ),
                                border: Border.all(color: app.color, width: 1),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (lesson?['is_trial'] == true) ...[
                                        const LessonTrialBadge(compact: true),
                                        const SizedBox(width: 3),
                                      ],
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
                                    style: TextStyle(
                                      color: app.color,
                                      fontSize: 9,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          },
                    ),
                    if (_appointments.isEmpty)
                      const Positioned.fill(
                        child: IgnorePointer(child: _ScheduleEmpty()),
                      ),
                  ],
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

class _ScheduleError extends StatelessWidget {
  const _ScheduleError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColor.danger,
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              'Не удалось загрузить расписание',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Проверьте соединение и повторите попытку.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: AppSpace.lg),
            OutlinedButton.icon(
              key: const ValueKey('teacher-calendar-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleEmpty extends StatelessWidget {
  const _ScheduleEmpty();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        key: const ValueKey('teacher-calendar-empty'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xl,
          vertical: AppSpace.lg,
        ),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColor.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.event_available_outlined,
              size: 36,
              color: AppColor.text2,
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Занятий пока нет',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeacherLessonHistory extends StatelessWidget {
  const _TeacherLessonHistory({required this.future});

  final Future<List<Map<String, dynamic>>> future;

  @override
  Widget build(BuildContext context) {
    return _AsyncReadOnlyList(
      future: future,
      emptyLabel: 'История занятий пуста',
      itemBuilder: (lesson) {
        final scheduledAt = DateTime.tryParse(
          lesson['scheduled_at']?.toString() ?? '',
        );
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            scheduledAt == null
                ? 'Дата не указана'
                : DateFormat(
                    'dd.MM.yyyy · HH:mm',
                    'ru',
                  ).format(scheduledAt.toLocal()),
          ),
          subtitle: Text(
            lesson['room_name']?.toString() ?? 'Аудитория не указана',
          ),
          trailing: LessonStateBadge.fromMap(lesson),
        );
      },
    );
  }
}

class _TeacherHomeworkHistory extends StatelessWidget {
  const _TeacherHomeworkHistory({required this.future});

  final Future<List<Map<String, dynamic>>> future;

  @override
  Widget build(BuildContext context) {
    return _AsyncReadOnlyList(
      future: future,
      emptyLabel: 'Домашних заданий пока нет',
      itemBuilder: (homework) {
        final status = switch (homework['status']?.toString()) {
          'submitted' => 'Сдано',
          'done' || 'completed' || 'checked' => 'Проверено',
          _ => 'Задано',
        };
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.assignment_outlined, color: AppColor.gold),
          title: Text(homework['title']?.toString() ?? 'Домашнее задание'),
          subtitle: Text(status),
        );
      },
    );
  }
}

class _AsyncReadOnlyList extends StatelessWidget {
  const _AsyncReadOnlyList({
    required this.future,
    required this.emptyLabel,
    required this.itemBuilder,
  });

  final Future<List<Map<String, dynamic>>> future;
  final String emptyLabel;
  final Widget Function(Map<String, dynamic>) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Center(
                child: CircularProgressIndicator(color: AppColor.gold),
              ),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Text(
                'Не удалось загрузить данные',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Text(
                emptyLabel,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) => itemBuilder(items[index]),
          );
        },
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

/// Read-only navigation row from the limited Teacher client card.
class _ReadOnlyLinkTile extends StatelessWidget {
  const _ReadOnlyLinkTile({
    super.key,
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

/// Footer button for read-only sheets.
class _SheetButton extends StatelessWidget {
  const _SheetButton._({required this.label, required this.onPressed});

  factory _SheetButton.gold({
    required String label,
    required VoidCallback onPressed,
  }) => _SheetButton._(label: label, onPressed: onPressed);

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
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

    return FilledButton(
      onPressed: onPressed,
      style: style.copyWith(
        backgroundColor: const WidgetStatePropertyAll(AppColor.gold),
        foregroundColor: const WidgetStatePropertyAll(AppColor.onGold),
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
