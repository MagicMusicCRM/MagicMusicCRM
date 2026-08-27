import 'package:flutter/foundation.dart';

const _unchanged = Object();

@immutable
class SharedTaskEditorDraft {
  SharedTaskEditorDraft._({
    required this.taskId,
    required this.expectedVersion,
    required this.title,
    required this.body,
    required this.allDay,
    required this.start,
    required this.end,
    required this.priority,
    required this.audienceType,
    required this.targetId,
    required List<Map<String, dynamic>> audiences,
    required List<Map<String, dynamic>> existingReminders,
    required this.reminder,
    required this.reminderAt,
    required this.reminderCustomized,
    required Map<String, dynamic>? linkedEntity,
  }) : audiences = _freezeRows(audiences),
       existingReminders = _freezeRows(existingReminders),
       linkedEntity = linkedEntity == null
           ? null
           : Map<String, dynamic>.unmodifiable(linkedEntity);

  factory SharedTaskEditorDraft.initial({
    Map<String, dynamic>? task,
    Map<String, dynamic>? linkedEntity,
    DateTime? now,
  }) {
    final allDay = task?['allDay'] != false;
    final parsedStart = DateTime.tryParse(
      task?['startAt']?.toString() ?? '',
    )?.toLocal();
    final tomorrow = (now ?? DateTime.now()).add(const Duration(days: 1));
    final start = parsedStart == null
        ? dateOnly(tomorrow)
        : (allDay ? dateOnly(parsedStart) : parsedStart);
    final audiences = _rows(task?['audiences']);
    if (audiences.isEmpty) audiences.add({'type': 'allBranches'});
    final reminders = _rows(task?['reminders'])
        .map((item) => {'dueAt': item['dueAt'], 'channel': item['channel']})
        .toList();
    DateTime? reminderAt;
    var reminderCustomized = false;
    for (final item in reminders) {
      if (item['channel'] != 'in_app') continue;
      reminderAt = DateTime.tryParse(
        item['dueAt']?.toString() ?? '',
      )?.toLocal();
      if (reminderAt != null) {
        reminderCustomized = true;
        break;
      }
    }
    final reminder = reminders.any((item) => item['channel'] == 'in_app');
    reminderAt ??= reminder ? defaultReminderAt(allDay, start) : null;
    return SharedTaskEditorDraft._(
      taskId: task?['id']?.toString(),
      expectedVersion: task?['version'],
      title: task?['title']?.toString() ?? '',
      body: task?['body']?.toString() ?? '',
      allDay: allDay,
      start: start,
      end: DateTime.tryParse(task?['endAt']?.toString() ?? '')?.toLocal(),
      priority: task?['priority']?.toString() ?? 'medium',
      audienceType: 'allBranches',
      targetId: null,
      audiences: audiences,
      existingReminders: reminders,
      reminder: reminder,
      reminderAt: reminderAt,
      reminderCustomized: reminderCustomized,
      linkedEntity: linkedEntity ?? _map(task?['linkedEntity']),
    );
  }

  final String? taskId;
  final Object? expectedVersion;
  final String title;
  final String body;
  final bool allDay;
  final DateTime start;
  final DateTime? end;
  final String priority;
  final String audienceType;
  final String? targetId;
  final List<Map<String, dynamic>> audiences;
  final List<Map<String, dynamic>> existingReminders;
  final bool reminder;
  final DateTime? reminderAt;
  final bool reminderCustomized;
  final Map<String, dynamic>? linkedEntity;

  bool get created => taskId == null;
  bool get hasValidInterval => allDay || (end?.isAfter(start) ?? false);
  bool get canAddAudience => audienceType == 'allBranches' || targetId != null;

  SharedTaskEditorDraft copyWith({
    String? title,
    String? body,
    bool? allDay,
    DateTime? start,
    Object? end = _unchanged,
    String? priority,
    String? audienceType,
    Object? targetId = _unchanged,
    List<Map<String, dynamic>>? audiences,
    bool? reminder,
    Object? reminderAt = _unchanged,
    bool? reminderCustomized,
  }) => SharedTaskEditorDraft._(
    taskId: taskId,
    expectedVersion: expectedVersion,
    title: title ?? this.title,
    body: body ?? this.body,
    allDay: allDay ?? this.allDay,
    start: start ?? this.start,
    end: identical(end, _unchanged) ? this.end : end as DateTime?,
    priority: priority ?? this.priority,
    audienceType: audienceType ?? this.audienceType,
    targetId: identical(targetId, _unchanged)
        ? this.targetId
        : targetId as String?,
    audiences: audiences ?? this.audiences,
    existingReminders: existingReminders,
    reminder: reminder ?? this.reminder,
    reminderAt: identical(reminderAt, _unchanged)
        ? this.reminderAt
        : reminderAt as DateTime?,
    reminderCustomized: reminderCustomized ?? this.reminderCustomized,
    linkedEntity: linkedEntity,
  );

  SharedTaskEditorDraft setAllDay(bool value) {
    if (allDay == value) return this;
    final nextStart = value
        ? dateOnly(start)
        : DateTime(start.year, start.month, start.day, 9);
    return copyWith(
      allDay: value,
      start: nextStart,
      end: value ? null : nextStart.add(const Duration(hours: 1)),
      reminderAt: reminder && !reminderCustomized
          ? defaultReminderAt(value, nextStart)
          : reminderAt,
    );
  }

  SharedTaskEditorDraft setStart(DateTime value) {
    final nextStart = allDay ? dateOnly(value) : value;
    return copyWith(
      start: nextStart,
      reminderAt: reminder && !reminderCustomized
          ? defaultReminderAt(allDay, nextStart)
          : reminderAt,
    );
  }

  SharedTaskEditorDraft setReminder(bool value) => copyWith(
    reminder: value,
    reminderAt: value ? reminderAt ?? defaultReminderAt(allDay, start) : null,
    reminderCustomized: value ? reminderCustomized : false,
  );

  SharedTaskEditorDraft setReminderAt(DateTime value) =>
      copyWith(reminderAt: value, reminderCustomized: true);

  SharedTaskEditorDraft addAudience() {
    final audience = {
      'type': audienceType,
      if (audienceType != 'allBranches') 'targetId': targetId,
    };
    final key = '${audience['type']}:${audience['targetId'] ?? ''}';
    if (audiences.any(
      (item) => '${item['type']}:${item['targetId'] ?? ''}' == key,
    )) {
      return this;
    }
    final next = audienceType == 'allBranches'
        ? [audience]
        : [
            ...audiences.where((item) => item['type'] != 'allBranches'),
            audience,
          ];
    return copyWith(audiences: next);
  }

  SharedTaskEditorDraft removeAudience(Map<String, dynamic> audience) =>
      copyWith(audiences: audiences.where((item) => item != audience).toList());

  Map<String, dynamic> payload() {
    final payloadEnd = allDay
        ? null
        : (end ?? start.add(const Duration(hours: 1)));
    return {
      'title': title.trim(),
      if (body.trim().isNotEmpty) 'body': body.trim(),
      'allDay': allDay,
      'priority': priority,
      'startAt': start.toUtc().toIso8601String(),
      if (payloadEnd != null) 'endAt': payloadEnd.toUtc().toIso8601String(),
      'audiences': audiences,
      'linkedEntity': ?linkedEntity,
      if (!created || reminder || existingReminders.isNotEmpty)
        'reminders': reminderPayload(),
      if (!created) 'expectedVersion': expectedVersion,
    };
  }

  List<Map<String, dynamic>> reminderPayload() {
    final dueAt = (reminderAt ?? defaultReminderAt(allDay, start))
        .toUtc()
        .toIso8601String();
    var replacedInApp = false;
    final result = <Map<String, dynamic>>[];
    for (final item in existingReminders) {
      final channel = item['channel']?.toString();
      if (channel == null || channel.isEmpty) continue;
      if (channel == 'in_app') {
        if (reminder && !replacedInApp) {
          result.add({'dueAt': dueAt, 'channel': channel});
          replacedInApp = true;
        }
      } else {
        result.add({'dueAt': item['dueAt'], 'channel': channel});
      }
    }
    if (reminder && !replacedInApp) {
      result.add({'dueAt': dueAt, 'channel': 'in_app'});
    }
    return result;
  }

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime defaultReminderAt(bool allDay, DateTime start) => allDay
      ? DateTime(start.year, start.month, start.day, 9)
      : start.subtract(const Duration(hours: 1));
}

List<Map<String, dynamic>> _rows(Object? value) => value is List
    ? value
          .whereType<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList()
    : [];

Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? Map<String, dynamic>.from(value) : null;

List<Map<String, dynamic>> _freezeRows(List<Map<String, dynamic>> rows) =>
    List<Map<String, dynamic>>.unmodifiable(
      rows.map(Map<String, dynamic>.unmodifiable),
    );
