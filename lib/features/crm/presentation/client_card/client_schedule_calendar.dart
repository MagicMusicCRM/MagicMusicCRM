import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_page_state.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/features/admin/presentation/providers/schedule_navigation_provider.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

typedef ClientCalendarViewport = ({DateTime start, DateTime endExclusive});

ClientCalendarViewport clientCalendarViewport(
  CalendarView view,
  DateTime displayDate,
) {
  final day = DateTime(displayDate.year, displayDate.month, displayDate.day);
  if (view == CalendarView.day) {
    return (start: day, endExclusive: day.add(const Duration(days: 1)));
  }
  if (view == CalendarView.week) {
    final monday = day.subtract(Duration(days: day.weekday - DateTime.monday));
    return (start: monday, endExclusive: monday.add(const Duration(days: 7)));
  }
  final first = DateTime(day.year, day.month);
  final start = first.subtract(Duration(days: first.weekday - DateTime.monday));
  final last = DateTime(day.year, day.month + 1, 0);
  final end = last.add(Duration(days: 8 - last.weekday));
  return (start: start, endExclusive: end);
}

bool lessonBelongsToClient(
  Map<String, dynamic> lesson, {
  required String clientType,
  required String clientId,
}) {
  final key = clientType == 'lead' ? 'lead_id' : 'student_id';
  return lesson[key]?.toString() == clientId;
}

class ClientScheduleCalendar extends ConsumerStatefulWidget {
  const ClientScheduleCalendar({
    required this.clientType,
    required this.clientId,
    required this.clientName,
    required this.branches,
    required this.defaultBranchId,
    required this.canRead,
    this.active = true,
    this.initialViewState,
    this.onViewStateChanged,
    super.key,
  });

  final String clientType;
  final String clientId;
  final String clientName;
  final List<Map<String, dynamic>> branches;
  final String? defaultBranchId;
  final bool canRead;
  final bool active;
  final ContextViewState? initialViewState;
  final ValueChanged<ContextViewState>? onViewStateChanged;

  @override
  ConsumerState<ClientScheduleCalendar> createState() =>
      _ClientScheduleCalendarState();
}

class _ClientScheduleCalendarState
    extends ConsumerState<ClientScheduleCalendar> {
  final CalendarController _controller = CalendarController();
  CalendarView _view = CalendarView.month;
  DateTime _displayDate = DateTime.now();
  String? _branchId;
  List<Map<String, dynamic>> _lessons = const [];
  Set<String> _selectedLessonIds = const {};
  bool _loading = true;
  String? _error;
  String? _loadedRequestKey;
  String? _pendingRequestKey;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loading = widget.active;
    _restore(widget.initialViewState);
    _controller
      ..view = _view
      ..displayDate = _displayDate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) {
        unawaited(_load(clientCalendarViewport(_view, _displayDate)));
      }
    });
  }

  @override
  void didUpdateWidget(covariant ClientScheduleCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      _loadedRequestKey = null;
      _pendingRequestKey = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_load(clientCalendarViewport(_view, _displayDate)));
        }
      });
    }
    final validBranch = widget.branches.any(
      (branch) => branch['id']?.toString() == _branchId,
    );
    if (!validBranch && widget.branches.isNotEmpty) {
      _branchId = _resolvedBranch();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (widget.active) _publishState();
          unawaited(_load(clientCalendarViewport(_view, _displayDate)));
        }
      });
    }
  }

  void _restore(ContextViewState? state) {
    final filters = state?.filters ?? const <String, dynamic>{};
    _view = switch (filters['clientCalendarMode']?.toString()) {
      'day' => CalendarView.day,
      'week' => CalendarView.week,
      _ => CalendarView.month,
    };
    _displayDate = state?.date?.toLocal() ?? DateTime.now();
    final requestedBranch = filters['clientCalendarBranchId']?.toString();
    _branchId =
        widget.branches.any(
          (branch) => branch['id']?.toString() == requestedBranch,
        )
        ? requestedBranch
        : _resolvedBranch();
  }

  String? _resolvedBranch() {
    final preferred = widget.defaultBranchId;
    if (preferred != null &&
        widget.branches.any(
          (branch) => branch['id']?.toString() == preferred,
        )) {
      return preferred;
    }
    return widget.branches.firstOrNull?['id']?.toString();
  }

  int get _branchOffsetMinutes {
    final branch = widget.branches
        .where((item) => item['id']?.toString() == _branchId)
        .firstOrNull;
    final raw = branch?['utc_offset_minutes'] ?? branch?['utcOffsetMinutes'];
    return raw is num ? raw.toInt() : int.tryParse('$raw') ?? 180;
  }

  String get _modeKey => switch (_view) {
    CalendarView.day => 'day',
    CalendarView.week => 'week',
    _ => 'month',
  };

  ContextViewState _viewState() => ContextViewState(
    filters: {
      ...?widget.initialViewState?.filters,
      'section': 'lessons',
      'clientCalendarMode': _modeKey,
      if (_branchId != null) 'clientCalendarBranchId': _branchId,
    },
    date: _displayDate,
    scrollOffset: widget.initialViewState?.scrollOffset ?? 0,
    selectedColumn: widget.initialViewState?.selectedColumn,
  );

  void _publishState() => widget.onViewStateChanged?.call(_viewState());

  DateTime _branchMidnightUtc(DateTime day) => DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).subtract(Duration(minutes: _branchOffsetMinutes));

  Future<void> _load(ClientCalendarViewport viewport) async {
    if (!widget.active) return;
    if (!widget.canRead || _branchId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final requestKey =
        '$_branchId|${viewport.start.toIso8601String()}|'
        '${viewport.endExclusive.toIso8601String()}';
    if ((_loadedRequestKey == requestKey || _pendingRequestKey == requestKey) &&
        _error == null) {
      return;
    }
    _pendingRequestKey = requestKey;
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final from = _branchMidnightUtc(viewport.start).toIso8601String();
      final to = _branchMidnightUtc(viewport.endExclusive).toIso8601String();
      final results = await Future.wait([
        crm.getScheduleMatrix(
          from: from,
          to: to,
          branchId: _branchId,
          limit: 500,
        ),
        crm.getScheduleMatrix(
          from: from,
          to: to,
          branchId: _branchId,
          studentId: widget.clientType == 'student' ? widget.clientId : null,
          leadId: widget.clientType == 'lead' ? widget.clientId : null,
          limit: 500,
        ),
      ]);
      if (!mounted || generation != _requestGeneration) return;
      final items = results.first['items'];
      final selectedItems = results.last['items'];
      setState(() {
        _lessons = items is List
            ? items.whereType<Map<String, dynamic>>().toList(growable: false)
            : const [];
        _selectedLessonIds = selectedItems is List
            ? selectedItems
                  .whereType<Map<String, dynamic>>()
                  .map((item) => item['id']?.toString())
                  .whereType<String>()
                  .toSet()
            : const {};
        _loadedRequestKey = requestKey;
        _pendingRequestKey = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = '$error';
        _pendingRequestKey = null;
        _loading = false;
      });
    }
  }

  void _setView(CalendarView view) {
    if (_view == view) return;
    setState(() {
      _view = view;
      _controller.view = view;
      _loadedRequestKey = null;
      _pendingRequestKey = null;
    });
    _publishState();
    unawaited(_load(clientCalendarViewport(view, _displayDate)));
  }

  void _move(int direction) {
    final next = switch (_view) {
      CalendarView.day => _displayDate.add(Duration(days: direction)),
      CalendarView.week => _displayDate.add(Duration(days: 7 * direction)),
      _ => DateTime(
        _displayDate.year,
        _displayDate.month + direction,
        _displayDate.day.clamp(1, 28),
      ),
    };
    setState(() {
      _displayDate = next;
      _controller.displayDate = next;
      _loadedRequestKey = null;
      _pendingRequestKey = null;
    });
    _publishState();
    unawaited(_load(clientCalendarViewport(_view, next)));
  }

  void _onViewChanged(ViewChangedDetails details) {
    if (!widget.active || details.visibleDates.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dates = details.visibleDates;
      final viewport = (
        start: DateTime(dates.first.year, dates.first.month, dates.first.day),
        endExclusive: DateTime(
          dates.last.year,
          dates.last.month,
          dates.last.day + 1,
        ),
      );
      final center = dates[dates.length ~/ 2];
      final changedDay =
          _displayDate.year != center.year ||
          _displayDate.month != center.month ||
          _displayDate.day != center.day;
      if (changedDay) {
        setState(() => _displayDate = center);
        _publishState();
      }
      unawaited(_load(viewport));
    });
  }

  DateTime? _calendarTime(Map<String, dynamic> lesson) {
    final parsed = DateTime.tryParse(lesson['scheduled_at']?.toString() ?? '');
    if (parsed == null) return null;
    final branchTime = parsed.toUtc().add(
      Duration(minutes: _branchOffsetMinutes),
    );
    return DateTime(
      branchTime.year,
      branchTime.month,
      branchTime.day,
      branchTime.hour,
      branchTime.minute,
    );
  }

  bool _selected(Map<String, dynamic> lesson) {
    final id = lesson['id']?.toString();
    return (id != null && _selectedLessonIds.contains(id)) ||
        lessonBelongsToClient(
          lesson,
          clientType: widget.clientType,
          clientId: widget.clientId,
        );
  }

  String _lessonName(Map<String, dynamic> lesson) {
    if (_selected(lesson)) return widget.clientName;
    for (final key in const ['student_name', 'lead_name', 'group_name']) {
      final value = lesson[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return 'Занятие';
  }

  List<Appointment> get _appointments {
    return [
      for (final lesson in _lessons)
        if (_calendarTime(lesson) case final start?)
          Appointment(
            id: lesson['id']?.toString(),
            startTime: start,
            endTime: start.add(
              Duration(
                minutes: (lesson['duration_minutes'] as num?)?.toInt() ?? 60,
              ),
            ),
            subject: _lessonName(lesson),
            color: _selected(lesson) ? AppColor.success : AppColor.text2,
          ),
    ];
  }

  Future<void> _openLesson(Appointment appointment) async {
    final id = appointment.id?.toString();
    if (id == null || id.isEmpty) return;
    if (WorkspaceNavigationScope.maybeOf(context)?.isDesktop != true) {
      ref
          .read(scheduleNavigationProvider.notifier)
          .focus(appointment.startTime, id);
      ref
          .read(crmNavigationRequestProvider.notifier)
          .navigateTo(
            CrmNavigationRequest.schedule(
              date: appointment.startTime,
              lessonId: id,
              clientType: widget.clientType,
              clientId: widget.clientId,
            ),
          );
      final snapshot = await ref.read(capabilitySnapshotProvider.future);
      if (!mounted) return;
      final home = switch (snapshot.role) {
        'admin' || 'system_admin' => '/admin',
        'teacher' => '/teacher',
        _ => '/manager',
      };
      await context.push<void>(home);
      return;
    }
    await openEntityLink(
      context,
      ref,
      EntityLink.typed(entityType: EntityLinkType.lesson, entityId: id),
      sourceViewState: _viewState(),
    );
  }

  IconData _stateIcon(LessonStateProjection projection) =>
      switch (projection.state) {
        'successfully_completed' => Icons.check_circle_outline_rounded,
        'rescheduled' => Icons.sync_alt_rounded,
        'cancelled' => Icons.block_rounded,
        _ => Icons.schedule_rounded,
      };

  Widget _appointment(
    BuildContext context,
    CalendarAppointmentDetails details,
  ) {
    final appointment = details.appointments.first;
    final id = appointment.id?.toString();
    final lesson = _lessons
        .where((item) => item['id']?.toString() == id)
        .firstOrNull;
    if (lesson == null) return const SizedBox.shrink();
    final selected = _selected(lesson);
    final projection = LessonStateProjection.fromMap(lesson);
    final conflicts = lesson['conflict_types'] is List
        ? lesson['conflict_types'] as List
        : const [];
    final compact = details.bounds.height < 34 || details.bounds.width < 110;
    final relationColor = selected ? AppColor.success : AppColor.text2;
    return Container(
      key: ValueKey('client-calendar-lesson-$id'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: relationColor.withValues(alpha: selected ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: relationColor, width: selected ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.person_pin_circle_outlined
                : Icons.people_outline_rounded,
            size: compact ? 11 : 14,
            color: relationColor,
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              appointment.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: compact ? 9 : 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (lesson['is_trial'] == true)
            const Tooltip(
              message: 'Пробное занятие',
              child: Icon(
                Icons.star_outline_rounded,
                size: 13,
                color: AppColor.gold,
              ),
            ),
          if (conflicts.isNotEmpty)
            const Tooltip(
              message: 'Есть конфликт расписания',
              child: Icon(
                Icons.warning_amber_rounded,
                size: 13,
                color: AppColor.danger,
              ),
            ),
          Tooltip(
            message: projection.label,
            child: Icon(
              _stateIcon(projection),
              size: 13,
              color: projection.token.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeSelector(double width) {
    const views = <CalendarView, String>{
      CalendarView.month: 'Месяц',
      CalendarView.week: 'Неделя',
      CalendarView.day: 'День',
    };
    if (width >= 520) {
      return SegmentedButton<CalendarView>(
        key: const ValueKey('client-calendar-mode'),
        showSelectedIcon: false,
        segments: [
          for (final entry in views.entries)
            ButtonSegment(value: entry.key, label: Text(entry.value)),
        ],
        selected: {_view},
        onSelectionChanged: (selected) => _setView(selected.single),
      );
    }
    return DropdownButtonFormField<CalendarView>(
      key: const ValueKey('client-calendar-mode'),
      initialValue: _view,
      decoration: const InputDecoration(labelText: 'Режим'),
      items: [
        for (final entry in views.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (view) {
        if (view != null) _setView(view);
      },
    );
  }

  static const _months = [
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
  static const _monthTitles = [
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

  String get _periodLabel {
    final date = '${_displayDate.day} ${_months[_displayDate.month - 1]}';
    return switch (_view) {
      CalendarView.day => '$date ${_displayDate.year}',
      CalendarView.week => 'Неделя $date',
      _ => '${_monthTitles[_displayDate.month - 1]} ${_displayDate.year}',
    };
  }

  Widget _legendItem(IconData icon, Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );

  @override
  void dispose() {
    _requestGeneration++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canRead) {
      return const MagicPageState(
        kind: MagicPageStateKind.forbidden,
        title: 'Календарь недоступен',
        message: 'У вашей роли нет доступа к расписанию.',
      );
    }
    if (widget.branches.isEmpty || _branchId == null) {
      return const MagicPageState(
        kind: MagicPageStateKind.empty,
        title: 'Нет доступного филиала',
        message: 'Календарь открывается только в пределах выбранного филиала.',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('client-schedule-calendar'),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColor.divider),
      ),
      padding: const EdgeInsets.all(AppSpace.lg),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Календарь занятий',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Зелёным отмечены занятия клиента карточки; остальные доступны только в текущем филиале и периоде.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: AppSpace.md),
            if (constraints.maxWidth >= 700)
              Row(
                children: [
                  _modeSelector(constraints.maxWidth),
                  const SizedBox(width: AppSpace.md),
                  Expanded(child: _branchSelector()),
                ],
              )
            else ...[
              _modeSelector(constraints.maxWidth),
              const SizedBox(height: AppSpace.sm),
              _branchSelector(),
            ],
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                IconButton(
                  tooltip: 'Предыдущий период',
                  onPressed: () => _move(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    _periodLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final today = DateTime.now();
                    setState(() {
                      _displayDate = today;
                      _controller.displayDate = today;
                      _loadedRequestKey = null;
                      _pendingRequestKey = null;
                    });
                    _publishState();
                    unawaited(_load(clientCalendarViewport(_view, today)));
                  },
                  child: const Text('Сегодня'),
                ),
                IconButton(
                  tooltip: 'Следующий период',
                  onPressed: () => _move(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            Wrap(
              spacing: AppSpace.md,
              runSpacing: AppSpace.xs,
              children: [
                _legendItem(
                  Icons.person_pin_circle_outlined,
                  AppColor.success,
                  'Клиент карточки',
                ),
                _legendItem(
                  Icons.people_outline_rounded,
                  AppColor.text2,
                  'Другие клиенты',
                ),
                _legendItem(
                  Icons.star_outline_rounded,
                  AppColor.gold,
                  'Пробное',
                ),
                _legendItem(
                  Icons.warning_amber_rounded,
                  AppColor.danger,
                  'Конфликт',
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColor.danger,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    const Expanded(
                      child: Text('Не удалось загрузить календарь.'),
                    ),
                    TextButton(
                      onPressed: () {
                        _loadedRequestKey = null;
                        _pendingRequestKey = null;
                        unawaited(
                          _load(clientCalendarViewport(_view, _displayDate)),
                        );
                      },
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            if (_lessons.length >= 500)
              const Padding(
                padding: EdgeInsets.only(top: AppSpace.xs),
                child: Text(
                  'Показаны первые 500 занятий. Выберите меньший период.',
                  style: TextStyle(color: AppColor.danger, fontSize: 12),
                ),
              ),
            const SizedBox(height: AppSpace.sm),
            SizedBox(
              height: constraints.maxWidth < 520 ? 480 : 560,
              child: SfCalendar(
                key: const ValueKey('client-calendar-grid'),
                controller: _controller,
                view: _view,
                initialDisplayDate: _displayDate,
                headerHeight: 0,
                firstDayOfWeek: DateTime.monday,
                todayHighlightColor: AppColor.gold,
                cellBorderColor: AppColor.divider,
                backgroundColor: Colors.transparent,
                dataSource: _ClientLessonDataSource(_appointments),
                monthViewSettings: const MonthViewSettings(
                  appointmentDisplayMode:
                      MonthAppointmentDisplayMode.appointment,
                  showAgenda: false,
                ),
                timeSlotViewSettings: TimeSlotViewSettings(
                  startHour: 6,
                  endHour: 23,
                  timeFormat: 'HH:mm',
                  // The full 06:00–23:00 range fits the fixed viewport, so the
                  // calendar does not introduce another hidden inner scrollbar.
                  timeIntervalHeight: constraints.maxWidth < 520 ? 24 : 28,
                ),
                onViewChanged: _onViewChanged,
                onTap: (details) {
                  final appointments = details.appointments;
                  if (appointments != null && appointments.isNotEmpty) {
                    unawaited(_openLesson(appointments.first as Appointment));
                  }
                },
                appointmentBuilder: _appointment,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _branchSelector() => DropdownButtonFormField<String>(
    key: const ValueKey('client-calendar-branch'),
    initialValue: _branchId,
    decoration: const InputDecoration(labelText: 'Филиал'),
    items: [
      for (final branch in widget.branches)
        DropdownMenuItem(
          value: branch['id']?.toString(),
          child: Text(branch['name']?.toString() ?? 'Филиал'),
        ),
    ],
    onChanged: (branchId) {
      if (branchId == null || branchId == _branchId) return;
      setState(() {
        _branchId = branchId;
        _lessons = const [];
        _selectedLessonIds = const {};
        _loadedRequestKey = null;
        _pendingRequestKey = null;
      });
      _publishState();
      unawaited(_load(clientCalendarViewport(_view, _displayDate)));
    },
  );
}

class _ClientLessonDataSource extends CalendarDataSource {
  _ClientLessonDataSource(List<Appointment> source) {
    appointments = source;
  }
}
