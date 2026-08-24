import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_conflicts_api.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/preferred_schedule_editor.dart';

class SchedulePlanConstraintIssue {
  SchedulePlanConstraintIssue({
    required this.rowIndex,
    required this.draftIndex,
    required this.label,
    this.participantLabel,
    this.analyzerGrouped = false,
    this.fingerprint = '',
    Iterable<String> dates = const [],
    Iterable<String> lessonIds = const [],
    Iterable<int> rowIndexes = const [],
    Iterable<int> affectedRowIndexes = const [],
    Iterable<int> affectedDraftIndexes = const [],
    Iterable<String> participantLabels = const [],
  }) : dates = Set.unmodifiable(dates),
       lessonIds = Set.unmodifiable(lessonIds),
       rowIndexes = Set.unmodifiable(rowIndexes),
       affectedRowIndexes = Set.unmodifiable(affectedRowIndexes),
       affectedDraftIndexes = Set.unmodifiable(affectedDraftIndexes),
       participantLabels = Set.unmodifiable([
         ...participantLabels,
         ?participantLabel,
       ]);

  final int rowIndex;
  final int draftIndex;
  final String label;
  final String? participantLabel;
  final bool analyzerGrouped;
  final String fingerprint;
  final Set<String> dates;
  final Set<String> lessonIds;
  final Set<int> rowIndexes;
  final Set<int> affectedRowIndexes;
  final Set<int> affectedDraftIndexes;
  final Set<String> participantLabels;

  String get rowLabel {
    final rows = affectedRowIndexes.isEmpty
        ? <int>{rowIndex}
        : affectedRowIndexes;
    final sorted = rows.toList()..sort();
    return '${sorted.length == 1 ? 'Строка' : 'Строки'} '
        '${sorted.map((index) => index + 1).join(', ')}';
  }
}

class SchedulePlanSuggestion {
  const SchedulePlanSuggestion({
    required this.previewRowIndex,
    required this.draftIndex,
    required this.suggestion,
  });

  final int previewRowIndex;
  final int draftIndex;
  final ScheduleSuggestion suggestion;
}

class SchedulePlanConstraintInterpreter {
  const SchedulePlanConstraintInterpreter({
    required this.rows,
    this.participantLabels = const {},
  });

  final List<PreferredScheduleDraft> rows;
  final Map<String, String> participantLabels;

  List<SchedulePlanConstraintIssue> issues(Map<String, dynamic>? preview) {
    if (preview == null) return const [];
    final analyzerConflicts = preview['conflicts'];
    if (analyzerConflicts is List && analyzerConflicts.isNotEmpty) {
      return _analyzerIssues(analyzerConflicts);
    }
    return _legacyIssues(preview);
  }

  List<SchedulePlanSuggestion> suggestions(Map<String, dynamic>? preview) {
    if (preview == null) return const [];
    final result = <SchedulePlanSuggestion>[];
    for (final rawRow in (preview['rows'] as List? ?? const [])) {
      if (rawRow is! Map) continue;
      final rowIndex = (rawRow['index'] as num?)?.toInt() ?? 0;
      for (final rawSuggestion
          in (rawRow['suggestions'] as List? ?? const [])) {
        if (rawSuggestion is! Map) continue;
        result.add(
          SchedulePlanSuggestion(
            previewRowIndex: rowIndex,
            draftIndex: draftIndexForPreviewRow(rowIndex),
            suggestion: ScheduleSuggestion.fromJson(
              Map<String, dynamic>.from(rawSuggestion),
            ),
          ),
        );
      }
    }
    result.sort((left, right) {
      final byScore = right.suggestion.score.compareTo(left.suggestion.score);
      if (byScore != 0) return byScore;
      return left.previewRowIndex.compareTo(right.previewRowIndex);
    });
    return result.take(8).toList(growable: false);
  }

  int draftIndexForPreviewRow(int previewRowIndex) {
    if (rows.isEmpty) return 0;
    var firstRowIndex = 0;
    for (var draftIndex = 0; draftIndex < rows.length; draftIndex++) {
      final draft = rows[draftIndex];
      final rowCount = draft.weekdays.length * draft.lessonsPerDay;
      if (previewRowIndex < firstRowIndex + rowCount) return draftIndex;
      firstRowIndex += rowCount;
    }
    return rows.length - 1;
  }

  List<SchedulePlanConstraintIssue> _legacyIssues(
    Map<String, dynamic> preview,
  ) {
    final accumulators = <String, _IssueAccumulator>{};
    for (final rawRow in (preview['rows'] as List? ?? const [])) {
      if (rawRow is! Map) continue;
      final rowIndex = (rawRow['index'] as num?)?.toInt() ?? 0;
      for (final rawFailure in (rawRow['failures'] as List? ?? const [])) {
        if (rawFailure is! Map) continue;
        final studentId = rawFailure['studentId']?.toString() ?? '';
        final occurrence = rawFailure['occurrence'];
        final date = occurrence is Map
            ? occurrence['localDate']?.toString() ?? ''
            : '';
        for (final rawViolation
            in (rawFailure['violations'] as List? ?? const [])) {
          if (rawViolation is! Map) continue;
          final code = rawViolation['code']?.toString() ?? 'UNKNOWN';
          final resource = rawViolation['resource'];
          final resourceId = resource is Map
              ? resource['id']?.toString() ?? ''
              : '';
          final key = '$rowIndex:$code:$resourceId';
          final accumulator = accumulators.putIfAbsent(
            key,
            () => _IssueAccumulator(
              rowIndex: rowIndex,
              draftIndex: draftIndexForPreviewRow(rowIndex),
              label: labelFor(code),
              participantLabel:
                  code == 'CLIENT_OVERLAP' && participantLabels.isNotEmpty
                  ? participantLabels[studentId] ?? 'Ученик'
                  : null,
            ),
          );
          if (date.isNotEmpty) accumulator.dates.add(date);
          accumulator.lessonIds.addAll(
            (rawViolation['conflictingLessonIds'] as List? ?? const []).map(
              (id) => id.toString(),
            ),
          );
          accumulator.rowIndexes.addAll(
            (rawViolation['conflictingRowIndexes'] as List? ?? const [])
                .whereType<num>()
                .map((index) => index.toInt()),
          );
        }
      }
    }
    return accumulators.values
        .map((accumulator) => accumulator.issue)
        .toList(growable: false);
  }

  List<SchedulePlanConstraintIssue> _analyzerIssues(List<dynamic> rawItems) {
    final issues = <SchedulePlanConstraintIssue>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final code = rawItem['code']?.toString() ?? 'UNKNOWN';
      final fingerprint = rawItem['fingerprint']?.toString() ?? code;
      final rowIndexes = <int>{};
      final dates = <String>{};
      final labels = <String>{};
      for (final rawScope in (rawItem['scopes'] as List? ?? const [])) {
        if (rawScope is! Map) continue;
        final rowIndex = (rawScope['rowIndex'] as num?)?.toInt();
        if (rowIndex != null) rowIndexes.add(rowIndex);
        final date = rawScope['localDate']?.toString() ?? '';
        if (date.isNotEmpty) dates.add(date);
        final studentId = rawScope['studentId']?.toString() ?? '';
        if (code == 'CLIENT_OVERLAP' && studentId.isNotEmpty) {
          labels.add(participantLabels[studentId] ?? 'Ученик');
        }
      }
      if (rowIndexes.isEmpty) rowIndexes.add(0);
      final firstRow = rowIndexes.reduce(
        (left, right) => left < right ? left : right,
      );
      issues.add(
        SchedulePlanConstraintIssue(
          rowIndex: firstRow,
          draftIndex: draftIndexForPreviewRow(firstRow),
          label: labelFor(code),
          participantLabel: labels.length == 1 ? labels.single : null,
          analyzerGrouped: true,
          fingerprint: fingerprint,
          affectedRowIndexes: rowIndexes,
          affectedDraftIndexes: rowIndexes.map(draftIndexForPreviewRow),
          participantLabels: labels,
          dates: dates,
          lessonIds: (rawItem['conflictingLessonIds'] as List? ?? const []).map(
            (id) => id.toString(),
          ),
        ),
      );
    }
    return issues;
  }

  static String offsetTime(String value, int offsetMinutes) {
    final parts = value.split(':');
    final minutes =
        (int.tryParse(parts.first) ?? 0) * 60 +
        (int.tryParse(parts.last) ?? 0) +
        offsetMinutes;
    final normalized = (minutes % (24 * 60) + 24 * 60) % (24 * 60);
    return '${(normalized ~/ 60).toString().padLeft(2, '0')}:'
        '${(normalized % 60).toString().padLeft(2, '0')}';
  }

  static String suggestionLabel(SchedulePlanSuggestion item) {
    final suggestion = item.suggestion;
    final details = <String>[
      if (suggestion.roomName != null) suggestion.roomName!,
      if (suggestion.teacherName != null) suggestion.teacherName!,
      if (suggestion.startOffsetMinutes case final offset?)
        '${offset > 0 ? '+' : ''}$offset мин',
    ];
    return 'Строка ${item.previewRowIndex + 1} · №${suggestion.rank} · '
        '${suggestion.title}${details.isEmpty ? '' : ' · ${details.join(' · ')}'}';
  }

  static String labelFor(String code) => switch (code) {
    'INVALID_INTERVAL' => 'некорректный интервал',
    'OUTSIDE_BRANCH_HOURS' => 'вне часов работы филиала',
    'TEACHER_UNAVAILABLE' => 'педагог недоступен',
    'TEACHER_BRANCH_MISMATCH' => 'педагог не назначен в этот филиал',
    'ROOM_BRANCH_MISMATCH' => 'аудитория относится к другому филиалу',
    'TEACHER_OVERLAP' => 'педагог уже занят',
    'CLIENT_OVERLAP' => 'у клиента уже есть занятие',
    'ROOM_OVERLAP' => 'аудитория уже занята',
    _ => 'нарушено ограничение расписания',
  };
}

class _IssueAccumulator {
  _IssueAccumulator({
    required this.rowIndex,
    required this.draftIndex,
    required this.label,
    required this.participantLabel,
  });

  final int rowIndex;
  final int draftIndex;
  final String label;
  final String? participantLabel;
  final Set<String> dates = {};
  final Set<String> lessonIds = {};
  final Set<int> rowIndexes = {};

  SchedulePlanConstraintIssue get issue => SchedulePlanConstraintIssue(
    rowIndex: rowIndex,
    draftIndex: draftIndex,
    label: label,
    participantLabel: participantLabel,
    dates: dates,
    lessonIds: lessonIds,
    rowIndexes: rowIndexes,
  );
}
