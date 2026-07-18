import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cross-screen «open the schedule on this day, with this lesson highlighted»
/// request. Mirrors [messengerNavigationProvider]: a one-shot navigation target
/// the [ScheduleWidget] consumes (via `ref.listen`) and then clears so the same
/// lesson can be re-focused later.
///
/// The card sets the focus, closes itself and routes to the admin dashboard
/// schedule; the schedule reads [focusDate] (switches the calendar to that day,
/// day view) and [highlightLessonId] (the lesson to scroll to / pulse).
class ScheduleFocusState {
  /// Branch-local day to switch the calendar to. Only the date portion is used
  /// to pick the day; the lesson itself is matched by [highlightLessonId].
  final DateTime focusDate;

  /// Id of the lesson to highlight + scroll to within [focusDate]. Nullable so
  /// the schedule degrades to «just focus the day» when the lesson can't be
  /// resolved.
  final String? highlightLessonId;

  /// Optional lead preset. When present the schedule first becomes the active
  /// screen/day and only then opens its canonical create-lesson dialog.
  final String? leadId;
  final String? leadName;

  const ScheduleFocusState({
    required this.focusDate,
    this.highlightLessonId,
    this.leadId,
    this.leadName,
  });
}

class ScheduleFocusNotifier extends Notifier<ScheduleFocusState?> {
  @override
  ScheduleFocusState? build() => null;

  /// Focus the schedule on [date] with [lessonId] highlighted.
  void focus(DateTime date, String lessonId) =>
      state = ScheduleFocusState(focusDate: date, highlightLessonId: lessonId);

  /// Open the schedule on [date] and start a trial lesson for an existing lead
  /// from within that schedule. This replaces card/kanban-owned booking dialogs.
  void createForLead(
    DateTime date, {
    required String leadId,
    String? leadName,
  }) {
    state = ScheduleFocusState(
      focusDate: date,
      leadId: leadId,
      leadName: leadName,
    );
  }

  /// Clear the focus once the schedule has consumed it, so re-entering works.
  void clear() => state = null;
}

final scheduleNavigationProvider =
    NotifierProvider<ScheduleFocusNotifier, ScheduleFocusState?>(
      ScheduleFocusNotifier.new,
    );
