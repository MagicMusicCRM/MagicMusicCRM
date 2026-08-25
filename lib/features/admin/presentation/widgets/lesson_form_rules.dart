import 'package:intl/intl.dart';

String formatCompensationMinorInput(String? valueMinor) {
  final value = BigInt.tryParse(valueMinor ?? '') ?? BigInt.zero;
  final whole = value ~/ BigInt.from(100);
  final fraction = (value % BigInt.from(100)).toString().padLeft(2, '0');
  return fraction == '00' ? '$whole' : '$whole,$fraction';
}

String formatLessonSnapshotNumber(num value) =>
    NumberFormat('#,##0.##', 'ru').format(value);

String formatClientChargeSnapshotLabel({
  required String clientChargeType,
  required num compatibilityValue,
}) => switch (clientChargeType) {
  'subscription' => '${formatLessonSnapshotNumber(compatibilityValue)} ч',
  'personal_account' => '${formatLessonSnapshotNumber(compatibilityValue)} ₽',
  _ => '0 ₽',
};

String formatTeacherCompensationSnapshotLabel({
  required String? mode,
  required String compensationInput,
  required String compatibilityRateType,
  required num compatibilityRate,
}) {
  if (mode == null) return 'Не выбрано';
  if (mode == 'none') return '0 ₽';
  if (mode == 'standard') {
    return compatibilityRateType == 'none'
        ? 'Стандартная ставка преподавателя · 0 ₽'
        : 'Стандартная ставка преподавателя · '
              '${formatLessonSnapshotNumber(compatibilityRate)} ₽/ч';
  }
  if (mode == 'percent') return '$compensationInput% от стандартной ставки';
  if (mode == 'hourly') return '$compensationInput ₽/ч';
  return '$compensationInput ₽ за занятие';
}

String? parseCompensationValueMinor({
  required String? mode,
  required String rawValue,
}) {
  if (mode == null || mode == 'none' || mode == 'standard') return null;
  final raw = rawValue.trim().replaceAll(' ', '').replaceAll(',', '.');
  final value = double.tryParse(raw);
  if (value == null || value < 0) return null;
  if (mode == 'percent') {
    if (value > 200) return null;
    return (value * 100).round().toString();
  }
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(raw)) return null;
  final parts = raw.split('.');
  return (BigInt.parse(parts.first) * BigInt.from(100) +
          BigInt.parse(parts.length == 1 ? '0' : parts.last.padRight(2, '0')))
      .toString();
}

bool hasLessonScheduleChanges({
  required Map<String, dynamic> lesson,
  required Map<String, dynamic> successor,
}) {
  String? value(String snake, String camel) {
    final raw = lesson[snake] ?? lesson[camel];
    final text = raw?.toString();
    return text == null || text.isEmpty ? null : text;
  }

  final currentStartsAt = DateTime.tryParse(
    value('scheduled_at', 'scheduledAt') ?? '',
  )?.toUtc();
  final nextStartsAt = DateTime.tryParse(
    successor['scheduledAt']?.toString() ?? '',
  )?.toUtc();
  final currentDuration =
      (lesson['duration_minutes'] ?? lesson['durationMinutes']) as num?;
  final teacherChanged =
      successor['teacherId']?.toString() != value('teacher_id', 'teacherId');
  final branchChanged =
      successor['branchId']?.toString() != value('branch_id', 'branchId');
  final roomChanged =
      successor['roomId']?.toString() != value('room_id', 'roomId');
  final scheduledChanged =
      currentStartsAt == null ||
      nextStartsAt == null ||
      !currentStartsAt.isAtSameMomentAs(nextStartsAt);
  final durationChanged =
      (successor['durationMinutes'] as num?)?.toInt() !=
      currentDuration?.toInt();
  return teacherChanged ||
      branchChanged ||
      roomChanged ||
      scheduledChanged ||
      durationChanged;
}
