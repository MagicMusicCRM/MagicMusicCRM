import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

class LeadBoardFilters {
  final String q;
  final String branchId;
  final String statusId;
  final String source;
  final String discipline;
  final String level;
  final String category;
  final String requestType;
  final String goal;
  final String gender;
  final String preferredSchedule;
  final String quick;
  final bool openTasks;

  /// Прятать лидов, которые уже стали учениками.
  ///
  /// Фильтр на бэке был написан ещё в июне, но фронт его НИ РАЗУ не передавал —
  /// мёртвый код. Теперь он к тому же осмыслен: до 17.07 связь students.lead_id
  /// стояла у 1 ученика из 1036, так что прятать было почти нечего.
  final bool hideConverted;

  const LeadBoardFilters({
    this.q = '',
    this.branchId = '',
    this.statusId = '',
    this.source = '',
    this.discipline = '',
    this.level = '',
    this.category = '',
    this.requestType = '',
    this.goal = '',
    this.gender = '',
    this.preferredSchedule = '',
    this.quick = 'all',
    this.openTasks = false,
    this.hideConverted = false,
  });

  LeadBoardFilters copyWith({
    String? q,
    String? branchId,
    String? statusId,
    String? source,
    String? discipline,
    String? level,
    String? category,
    String? requestType,
    String? goal,
    String? gender,
    String? preferredSchedule,
    String? quick,
    bool? openTasks,
    bool? hideConverted,
  }) {
    return LeadBoardFilters(
      q: q ?? this.q,
      branchId: branchId ?? this.branchId,
      statusId: statusId ?? this.statusId,
      source: source ?? this.source,
      discipline: discipline ?? this.discipline,
      level: level ?? this.level,
      category: category ?? this.category,
      requestType: requestType ?? this.requestType,
      goal: goal ?? this.goal,
      gender: gender ?? this.gender,
      preferredSchedule: preferredSchedule ?? this.preferredSchedule,
      quick: quick ?? this.quick,
      openTasks: openTasks ?? this.openTasks,
      hideConverted: hideConverted ?? this.hideConverted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeadBoardFilters &&
          q == other.q &&
          branchId == other.branchId &&
          statusId == other.statusId &&
          source == other.source &&
          discipline == other.discipline &&
          level == other.level &&
          category == other.category &&
          requestType == other.requestType &&
          goal == other.goal &&
          gender == other.gender &&
          preferredSchedule == other.preferredSchedule &&
          quick == other.quick &&
          openTasks == other.openTasks &&
          hideConverted == other.hideConverted;

  @override
  int get hashCode => Object.hash(
    q,
    branchId,
    statusId,
    source,
    discipline,
    level,
    category,
    requestType,
    goal,
    gender,
    preferredSchedule,
    quick,
    openTasks,
    hideConverted,
  );

  Map<String, dynamic> toJson() {
    return {
      'q': q,
      'branchId': branchId,
      'statusId': statusId,
      'source': source,
      'discipline': discipline,
      'level': level,
      'category': category,
      'requestType': requestType,
      'goal': goal,
      'gender': gender,
      'preferredSchedule': preferredSchedule,
      'quick': quick,
      'openTasks': openTasks,
      'hideConverted': hideConverted,
    };
  }

  factory LeadBoardFilters.fromJson(Map<String, dynamic> json) {
    return LeadBoardFilters(
      q: json['q']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      statusId: json['statusId']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      discipline: json['discipline']?.toString() ?? '',
      level: json['level']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      requestType: json['requestType']?.toString() ?? '',
      goal: json['goal']?.toString() ?? '',
      gender: json['gender']?.toString() ?? '',
      preferredSchedule: json['preferredSchedule']?.toString() ?? '',
      quick: json['quick']?.toString() ?? 'all',
      openTasks: json['openTasks'] == true,
      hideConverted: json['hideConverted'] == true,
    );
  }

  Future<Map<String, dynamic>> fetchBoard(
    MagicCrmService service, {
    String? cursor,
    String? columnId,
    int limit = 25,
  }) {
    final pageUnassigned = columnId == 'unassigned';
    final pageStatusId = columnId == null
        ? statusId
        : (pageUnassigned ? null : columnId);
    return service.listLeadBoard(
      q: q,
      branchId: branchId,
      statusId: pageStatusId,
      unassigned: pageUnassigned ? true : null,
      source: source,
      discipline: discipline,
      level: level,
      category: category,
      requestType: requestType,
      goal: goal,
      gender: gender,
      preferredSchedule: preferredSchedule,
      quick: quick,
      openTasks: openTasks ? true : null,
      hideConverted: hideConverted ? true : null,
      cursor: cursor,
      limit: limit,
    );
  }
}

final leadBoardProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, LeadBoardFilters>((ref, filters) {
      final service = ref.watch(magicCrmServiceProvider);
      return filters.fetchBoard(service);
    });

/// Kept as the legacy provider name while the data source is v3 REST.
final leadsStreamProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final board = await ref.watch(
    leadBoardProvider(const LeadBoardFilters()).future,
  );
  final columns = board['columns'] is List ? board['columns'] as List : [];
  return columns.whereType<Map<String, dynamic>>().expand((column) {
    final items = column['items'] is List ? column['items'] as List : [];
    return items.whereType<Map<String, dynamic>>();
  }).toList();
});

/// FutureProvider for lead statuses
final leadStatusesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.watch(magicCrmServiceProvider).listLeadStatuses(limit: 100);
});
