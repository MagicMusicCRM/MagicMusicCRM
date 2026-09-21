part of 'client_card.dart';

extension _ClientCardAtGlance on _ClientCardState {
  (String, String)? _nextClientLesson() {
    final candidates = <(DateTime, String)>[];
    for (final lesson in _lessons) {
      if ({'cancelled', 'canceled'}.contains(lesson.status) ||
          lesson.lifecycleState == 'archived') {
        continue;
      }
      final at = DateTime.tryParse(lesson.scheduledAt ?? '');
      if (at == null || at.isBefore(DateTime.now())) continue;
      final details = [
        lesson.teacherName ?? lesson.teachers?['first_name']?.toString(),
        lesson.branchName ?? lesson.branches?['name']?.toString(),
        lesson.roomName ?? lesson.rooms?['name']?.toString(),
      ].whereType<String>().where((item) => item.trim().isNotEmpty).join(' · ');
      candidates.add((at, details));
    }
    for (final raw in _list(_leadCard?['trials'])) {
      final at = DateTime.tryParse(
        (raw['scheduled_at'] ?? raw['scheduledAt'] ?? '').toString(),
      );
      if (at == null || at.isBefore(DateTime.now())) continue;
      final details = [
        raw['teacher_name'] ?? raw['teacherName'],
        raw['branch_name'] ?? raw['branchName'],
        raw['room_name'] ?? raw['roomName'],
      ].whereType<String>().where((item) => item.trim().isNotEmpty).join(' · ');
      candidates.add((at, details));
    }
    if (candidates.isEmpty) return null;
    candidates.sort((left, right) => left.$1.compareTo(right.$1));
    final next = candidates.first;
    return (
      DateFormat('EEE, d MMM · HH:mm', 'ru').format(next.$1.toLocal()),
      next.$2.isEmpty ? 'Детали занятия откроются в расписании.' : next.$2,
    );
  }

  String _compactNumber(num value) => value == value.truncate()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}
