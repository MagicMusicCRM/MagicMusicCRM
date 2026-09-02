class SchedulePlanRow {
  const SchedulePlanRow({
    required this.id,
    required this.teacherId,
    required this.teacherName,
    required this.roomId,
    required this.roomName,
    required this.branchId,
    required this.branchName,
    required this.weekday,
    required this.beginTime,
    required this.durationMinutes,
    required this.validFrom,
    required this.validUntil,
    required this.notes,
    required this.financialDecision,
    required this.active,
  });

  factory SchedulePlanRow.fromMap(Map<String, dynamic> map) => SchedulePlanRow(
    id: map['id']?.toString() ?? '',
    teacherId: map['teacherId']?.toString() ?? '',
    teacherName: map['teacherName']?.toString(),
    roomId: map['roomId']?.toString() ?? '',
    roomName: map['roomName']?.toString(),
    branchId: map['branchId']?.toString() ?? '',
    branchName: map['branchName']?.toString(),
    weekday: (map['weekday'] as num?)?.toInt() ?? 1,
    beginTime: map['beginTime']?.toString() ?? '',
    durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 60,
    validFrom: map['validFrom']?.toString() ?? '',
    validUntil: map['validUntil']?.toString(),
    notes: map['notes']?.toString(),
    financialDecision: Map<String, dynamic>.from(
      map['financialDecision'] as Map? ?? const {},
    ),
    active: map['active'] == true,
  );

  final String id;
  final String teacherId;
  final String? teacherName;
  final String roomId;
  final String? roomName;
  final String branchId;
  final String? branchName;
  final int weekday;
  final String beginTime;
  final int durationMinutes;
  final String validFrom;
  final String? validUntil;
  final String? notes;
  final Map<String, dynamic> financialDecision;
  final bool active;

  Map<String, dynamic> command({bool includeSeriesId = true}) => {
    if (includeSeriesId && id.isNotEmpty) 'seriesId': id,
    'teacherId': teacherId,
    'roomId': roomId,
    'branchId': branchId,
    'weekday': weekday,
    'beginTime': beginTime,
    'durationMinutes': durationMinutes,
    'financialDecision': financialDecision,
    if (notes?.trim().isNotEmpty == true) 'notes': notes!.trim(),
  };
}

class SchedulePlanParticipant {
  const SchedulePlanParticipant({
    required this.id,
    required this.studentId,
    required this.subscriptionId,
    required this.effectiveFrom,
    required this.effectiveUntil,
    required this.version,
  });

  factory SchedulePlanParticipant.fromMap(Map<String, dynamic> map) =>
      SchedulePlanParticipant(
        id: map['id']?.toString() ?? '',
        studentId: map['studentId']?.toString() ?? '',
        subscriptionId: map['subscriptionId']?.toString() ?? '',
        effectiveFrom: map['effectiveFrom']?.toString() ?? '',
        effectiveUntil: map['effectiveUntil']?.toString(),
        version: (map['version'] as num?)?.toInt() ?? 1,
      );

  final String id;
  final String studentId;
  final String subscriptionId;
  final String effectiveFrom;
  final String? effectiveUntil;
  final int version;

  Map<String, dynamic> get command => {
    'studentId': studentId,
    'subscriptionId': subscriptionId,
  };
}

class SchedulePlan {
  const SchedulePlan({
    this.scheduledLessonCount,
    this.coveredLessonCount,
    required this.id,
    required this.kind,
    required this.title,
    required this.studentId,
    required this.groupId,
    required this.subscriptionId,
    required this.activeFrom,
    required this.activeUntil,
    required this.status,
    required this.version,
    required this.endedAt,
    required this.endedBy,
    required this.endedByName,
    required this.endReason,
    required this.rows,
    required this.participants,
  });

  factory SchedulePlan.fromMap(Map<String, dynamic> map) => SchedulePlan(
    scheduledLessonCount: (map['scheduledLessonCount'] as num?)?.toInt(),
    coveredLessonCount: (map['coveredLessonCount'] as num?)?.toInt(),
    id: map['id']?.toString() ?? '',
    kind: map['kind']?.toString() ?? 'individual',
    title: map['title']?.toString() ?? 'Расписание',
    studentId: map['studentId']?.toString(),
    groupId: map['groupId']?.toString(),
    subscriptionId: map['subscriptionId']?.toString(),
    activeFrom: map['activeFrom']?.toString() ?? '',
    activeUntil: map['activeUntil']?.toString(),
    status: map['status']?.toString() ?? 'active',
    version: (map['version'] as num?)?.toInt() ?? 1,
    endedAt: map['endedAt']?.toString(),
    endedBy: map['endedBy']?.toString(),
    endedByName: map['endedByName']?.toString(),
    endReason: map['endReason']?.toString(),
    rows: (map['rows'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => SchedulePlanRow.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false),
    participants: (map['participants'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (participant) => SchedulePlanParticipant.fromMap(
            Map<String, dynamic>.from(participant),
          ),
        )
        .toList(growable: false),
  );

  final String id;
  final String kind;
  final String title;
  final String? studentId;
  final String? groupId;
  final String? subscriptionId;
  final String activeFrom;
  final String? activeUntil;
  final String status;
  final int version;
  final String? endedAt;
  final String? endedBy;
  final String? endedByName;
  final String? endReason;
  final int? scheduledLessonCount;
  final int? coveredLessonCount;
  final List<SchedulePlanRow> rows;
  final List<SchedulePlanParticipant> participants;

  bool get isActive => status == 'active';
  bool get isGroup => kind == 'group';
  List<SchedulePlanRow> get currentRows =>
      rows.where((row) => row.active).toList();
  List<SchedulePlanParticipant> get currentParticipants {
    if (participants.isEmpty) return const [];
    final latestEffectiveFrom = participants
        .map((participant) => participant.effectiveFrom)
        .reduce((left, right) => left.compareTo(right) >= 0 ? left : right);
    return participants
        .where(
          (participant) => participant.effectiveFrom == latestEffectiveFrom,
        )
        .toList(growable: false);
  }
}

class SchedulePlanTrayItem {
  const SchedulePlanTrayItem({
    required this.id,
    required this.scheduledAt,
    required this.localDate,
    required this.localTime,
    required this.state,
    required this.settlementMarkers,
    required this.relationMarker,
    required this.predecessorId,
    required this.successorId,
    required this.teacherName,
    required this.roomName,
  });

  factory SchedulePlanTrayItem.fromMap(Map<String, dynamic> map) =>
      SchedulePlanTrayItem(
        id: map['id']?.toString() ?? '',
        scheduledAt: map['scheduledAt']?.toString() ?? '',
        localDate: map['localDate']?.toString() ?? '',
        localTime: map['localTime']?.toString() ?? '',
        state: map['state']?.toString() ?? 'scheduled',
        settlementMarkers: (map['settlementMarkers'] as List? ?? const [])
            .whereType<Map>()
            .map((marker) => Map<String, dynamic>.from(marker))
            .toList(growable: false),
        relationMarker: map['relationMarker']?.toString() ?? 'none',
        predecessorId: map['predecessorId']?.toString(),
        successorId: map['successorId']?.toString(),
        teacherName: (map['teacher'] as Map?)?['name']?.toString(),
        roomName: (map['room'] as Map?)?['name']?.toString(),
      );

  final String id;
  final String scheduledAt;
  final String localDate;
  final String localTime;
  final String state;
  final List<Map<String, dynamic>> settlementMarkers;
  final String relationMarker;
  final String? predecessorId;
  final String? successorId;
  final String? teacherName;
  final String? roomName;
}

class SchedulePlanTrayPage {
  const SchedulePlanTrayPage({
    required this.planId,
    required this.items,
    required this.hasPrevious,
    required this.hasNext,
    required this.previousCursor,
    required this.nextCursor,
  });

  factory SchedulePlanTrayPage.fromMap(Map<String, dynamic> map) =>
      SchedulePlanTrayPage(
        planId: map['planId']?.toString() ?? '',
        items: (map['items'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  SchedulePlanTrayItem.fromMap(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false),
        hasPrevious: map['hasPrevious'] == true,
        hasNext: map['hasNext'] == true,
        previousCursor: map['previousCursor']?.toString(),
        nextCursor: map['nextCursor']?.toString(),
      );

  final String planId;
  final List<SchedulePlanTrayItem> items;
  final bool hasPrevious;
  final bool hasNext;
  final String? previousCursor;
  final String? nextCursor;
}

class SchedulePlanEndPreview {
  const SchedulePlanEndPreview({
    required this.previewToken,
    required this.previewExpiresAt,
    required this.impact,
  });

  factory SchedulePlanEndPreview.fromMap(Map<String, dynamic> map) =>
      SchedulePlanEndPreview(
        previewToken: map['previewToken']?.toString() ?? '',
        previewExpiresAt: map['previewExpiresAt']?.toString() ?? '',
        impact: Map<String, dynamic>.from(map['impact'] as Map? ?? const {}),
      );

  final String previewToken;
  final String previewExpiresAt;
  final Map<String, dynamic> impact;
}
