import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';

import 'group_schedule_participants_editor.dart';
import 'preferred_schedule_editor.dart';
import 'schedule_plan_end_form.dart';
import 'schedule_plan_rows_review.dart';

enum SchedulePlanMutationResult { committed, cancelled }

typedef _SchedulePlanReferences = ({
  List<Map<String, dynamic>> teachers,
  List<Map<String, dynamic>> rooms,
  Map<String, LessonDecisionCatalog> decisionCatalogs,
});

class SchedulePlanMutationFlow {
  const SchedulePlanMutationFlow({
    required this.service,
    required this.api,
    required this.branches,
    required this.subscriptions,
    required this.groupMembers,
    required this.studentId,
    required this.groupId,
    required this.subjectName,
    required this.defaultBranchId,
    required this.canManageTeacherCompensation,
  }) : assert((studentId == null) != (groupId == null));

  final MagicCrmService service;
  final MagicApiClient api;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> subscriptions;
  final List<GroupScheduleMemberOption> groupMembers;
  final String? studentId;
  final String? groupId;
  final String? subjectName;
  final String? defaultBranchId;
  final bool canManageTeacherCompensation;

  bool get _groupMode => groupId != null;

  Map<String, String> get _participantLabels => {
    if (_groupMode)
      for (final member in groupMembers) member.studentId: member.label,
  };

  Future<SchedulePlanMutationResult> create(BuildContext context) async {
    GroupScheduleParticipantsDraft? participantDraft;
    if (_groupMode) {
      participantDraft = await showMagicSheet<GroupScheduleParticipantsDraft>(
        context,
        title: 'Участники группового расписания',
        subtitle: 'Выберите учеников и их абонементы',
        icon: Icons.groups_rounded,
        builder: (_) => GroupScheduleParticipantsEditor(members: groupMembers),
      );
      if (participantDraft == null || !context.mounted) {
        return SchedulePlanMutationResult.cancelled;
      }
    }
    final references = await _references();
    if (!context.mounted) return SchedulePlanMutationResult.cancelled;
    final draft = await showMagicSheet<PreferredScheduleDraft>(
      context,
      title: 'Новое постоянное расписание',
      subtitle: 'Можно создать несколько дней и занятий одной командой',
      icon: Icons.event_repeat_rounded,
      builder: (_) => PreferredScheduleEditor(
        planMode: true,
        initialTitle: _groupMode
            ? (subjectName?.trim().isNotEmpty == true
                  ? subjectName!.trim()
                  : 'Групповые занятия')
            : 'Индивидуальные занятия',
        subscriptionOptions: _groupMode ? const [] : subscriptions,
        initialSubscriptionId: _groupMode
            ? null
            : subscriptions.first['id']?.toString(),
        requireSubscription: !_groupMode,
        allowOpenEnded: true,
        branches: branches,
        teachers: references.teachers,
        rooms: references.rooms,
        defaultBranchId: defaultBranchId,
        decisionCatalogs: references.decisionCatalogs,
        canManageTeacherCompensation: canManageTeacherCompensation,
        initialClientDecisions: _initialClientDecisions(participantDraft),
        participantLabels: _decisionParticipantLabels,
      ),
    );
    if (draft == null || !context.mounted) {
      return SchedulePlanMutationResult.cancelled;
    }
    final review = await showMagicSheet<SchedulePlanRowsReviewResult>(
      context,
      title: 'Проверка постоянного расписания',
      subtitle:
          'Добавьте отдельный набор дней для другого педагога или аудитории',
      icon: Icons.rule_rounded,
      builder: (_) => SchedulePlanRowsReview(
        initialRows: [draft],
        rowSummary: (row) => _draftSummary(row, references),
        onEditDraft: (editorContext, seed, adding) => _editReviewedDraft(
          editorContext,
          seed,
          adding: adding,
          references: references,
        ),
        participantLabels: _participantLabels,
        onValidate: (rows) => service.previewSchedulePlanConstraints(
          title: draft.title!,
          kind: _groupMode ? 'group' : 'individual',
          studentId: studentId,
          groupId: groupId,
          subscriptionId: draft.subscriptionId,
          participants: participantDraft?.participants ?? const [],
          activeFrom: _apiDate(draft.validFrom),
          activeUntil: draft.openEnded ? null : _apiDate(draft.validUntil),
          rows: [for (final row in rows) ..._draftRows(row)],
        ),
      ),
    );
    if (review == null || !context.mounted) {
      return SchedulePlanMutationResult.cancelled;
    }
    await service.createSchedulePlan(
      identity: MagicMutationIdentity.create('schedule-plan-create'),
      title: draft.title!,
      kind: _groupMode ? 'group' : 'individual',
      studentId: studentId,
      groupId: groupId,
      subscriptionId: draft.subscriptionId,
      participants: participantDraft?.participants ?? const [],
      activeFrom: _apiDate(draft.validFrom),
      activeUntil: draft.openEnded ? null : _apiDate(draft.validUntil),
      rows: [for (final row in review.rows) ..._draftRows(row)],
      historyPreviewToken: review.historyPreviewToken,
    );
    return SchedulePlanMutationResult.committed;
  }

  Future<SchedulePlanMutationResult> edit(
    BuildContext context,
    SchedulePlan plan, {
    SchedulePlanRow? row,
  }) async {
    final references = await _references();
    if (!context.mounted) return SchedulePlanMutationResult.cancelled;
    final source = row == null
        ? null
        : <String, dynamic>{
            'id': row.id,
            'teacher_id': row.teacherId,
            'room_id': row.roomId,
            'branch_id': row.branchId,
            'weekday': row.weekday,
            'begin_time': row.beginTime,
            'duration_minutes': row.durationMinutes,
            'valid_from': row.validFrom,
            'valid_until': row.validUntil,
            'notes': row.notes,
            'financial_decision': row.financialDecision,
          };
    final draft = await showMagicSheet<PreferredScheduleDraft>(
      context,
      title: row == null ? 'Добавить строку' : 'Изменить строку',
      subtitle: 'Прошедшие занятия и снимки не изменятся',
      icon: Icons.edit_calendar_outlined,
      builder: (_) => PreferredScheduleEditor(
        planMode: true,
        initialTitle: plan.title,
        subscriptionOptions: plan.isGroup ? const [] : subscriptions,
        initialSubscriptionId: plan.subscriptionId,
        requireSubscription: !plan.isGroup,
        allowOpenEnded: true,
        branches: branches,
        teachers: references.teachers,
        rooms: references.rooms,
        defaultBranchId: defaultBranchId,
        series: source,
        decisionCatalogs: references.decisionCatalogs,
        canManageTeacherCompensation: canManageTeacherCompensation,
        participantLabels: _decisionParticipantLabels,
      ),
    );
    if (draft == null || !context.mounted) {
      return SchedulePlanMutationResult.cancelled;
    }
    final rows = plan.currentRows
        .map(
          (item) => _draftFromPlanRow(
            item,
            validFrom: draft.validFrom,
            validUntil: draft.validUntil,
            title: draft.title,
            subscriptionId: draft.subscriptionId,
            openEnded: draft.openEnded,
          ),
        )
        .toList();
    if (row == null) {
      rows.add(draft);
    } else {
      final index = rows.indexWhere((item) => item.seriesId == row.id);
      rows[index] = draft;
    }
    final review = await showMagicSheet<SchedulePlanRowsReviewResult>(
      context,
      title: 'Проверка изменений расписания',
      subtitle: 'Все строки проверяются до сохранения изменений',
      icon: Icons.rule_rounded,
      builder: (_) => SchedulePlanRowsReview(
        initialRows: rows,
        rowSummary: (row) => _draftSummary(row, references),
        onEditDraft: (editorContext, seed, adding) => _editReviewedDraft(
          editorContext,
          seed,
          adding: adding,
          references: references,
        ),
        participantLabels: _participantLabels,
        submitLabel: 'Проверить и сохранить',
        onValidate: (reviewRows) =>
            service.previewSchedulePlanUpdateConstraints(
              plan.id,
              expectedVersion: plan.version,
              effectiveFrom: _apiDate(draft.validFrom),
              title: draft.title!,
              subscriptionId: plan.isGroup ? null : draft.subscriptionId,
              activeUntil: draft.openEnded ? null : _apiDate(draft.validUntil),
              rows: [
                for (final reviewRow in reviewRows) ..._draftRows(reviewRow),
              ],
            ),
      ),
    );
    if (review == null || !context.mounted) {
      return SchedulePlanMutationResult.cancelled;
    }
    await service.updateSchedulePlan(
      plan.id,
      identity: MagicMutationIdentity.create('schedule-plan-update'),
      expectedVersion: plan.version,
      effectiveFrom: _apiDate(draft.validFrom),
      title: draft.title!,
      subscriptionId: plan.isGroup ? null : draft.subscriptionId,
      activeUntil: draft.openEnded ? null : _apiDate(draft.validUntil),
      rows: [for (final reviewedRow in review.rows) ..._draftRows(reviewedRow)],
      historyPreviewToken: review.historyPreviewToken,
    );
    return SchedulePlanMutationResult.committed;
  }

  Future<SchedulePlanMutationResult> editParticipants(
    BuildContext context,
    SchedulePlan plan,
  ) async {
    if (!plan.isGroup || groupMembers.isEmpty) {
      return SchedulePlanMutationResult.cancelled;
    }
    final draft = await showMagicSheet<GroupScheduleParticipantsDraft>(
      context,
      title: 'Участники «${plan.title}»',
      subtitle: 'Изменение действует только для занятий с выбранной даты',
      icon: Icons.group_outlined,
      builder: (_) => GroupScheduleParticipantsEditor(
        members: groupMembers,
        initialParticipants: plan.currentParticipants,
        requireEffectiveFrom: true,
      ),
    );
    if (draft == null || !context.mounted || draft.effectiveFrom == null) {
      return SchedulePlanMutationResult.cancelled;
    }
    final references = await _references();
    if (!context.mounted) return SchedulePlanMutationResult.cancelled;
    final effectiveFrom = draft.effectiveFrom!;
    final validUntil =
        DateTime.tryParse(plan.activeUntil ?? '') ??
        effectiveFrom.add(const Duration(days: 90));
    final rows = plan.currentRows
        .map(
          (row) => _draftFromPlanRow(
            row,
            validFrom: effectiveFrom,
            validUntil: validUntil,
            title: plan.title,
            subscriptionId: plan.subscriptionId,
            openEnded: plan.activeUntil == null,
          ),
        )
        .toList();
    final review = await showMagicSheet<SchedulePlanRowsReviewResult>(
      context,
      title: 'Проверка расписания участников',
      subtitle: 'Проверяем каждого выбранного ученика по всем строкам',
      icon: Icons.rule_rounded,
      builder: (_) => SchedulePlanRowsReview(
        initialRows: rows,
        rowSummary: (row) => _draftSummary(row, references),
        onEditDraft: (editorContext, seed, adding) => _editReviewedDraft(
          editorContext,
          seed,
          adding: adding,
          references: references,
        ),
        participantLabels: _participantLabels,
        submitLabel: 'Проверить и сохранить',
        onValidate: (reviewRows) =>
            service.previewSchedulePlanUpdateConstraints(
              plan.id,
              expectedVersion: plan.version,
              effectiveFrom: _apiDate(effectiveFrom),
              title: plan.title,
              participants: draft.participants,
              activeUntil: plan.activeUntil,
              rows: [
                for (final reviewRow in reviewRows) ..._draftRows(reviewRow),
              ],
            ),
      ),
    );
    if (review == null || !context.mounted) {
      return SchedulePlanMutationResult.cancelled;
    }
    await service.updateSchedulePlan(
      plan.id,
      identity: MagicMutationIdentity.create(
        'schedule-plan-participants-update',
      ),
      expectedVersion: plan.version,
      effectiveFrom: _apiDate(draft.effectiveFrom!),
      title: plan.title,
      participants: draft.participants,
      activeUntil: plan.activeUntil,
      rows: [for (final reviewedRow in review.rows) ..._draftRows(reviewedRow)],
      historyPreviewToken: review.historyPreviewToken,
    );
    return SchedulePlanMutationResult.committed;
  }

  Future<SchedulePlanMutationResult> end(
    BuildContext context,
    SchedulePlan plan,
  ) async {
    final changed = await showMagicSheet<bool>(
      context,
      title: 'Завершить «${plan.title}»',
      subtitle: 'Прошедшие и уже рассчитанные занятия сохранятся',
      icon: Icons.stop_circle_outlined,
      builder: (_) => SchedulePlanEndForm(service: service, plan: plan),
    );
    return changed == true
        ? SchedulePlanMutationResult.committed
        : SchedulePlanMutationResult.cancelled;
  }

  Future<PreferredScheduleDraft?> _editReviewedDraft(
    BuildContext context,
    PreferredScheduleDraft seed, {
    required bool adding,
    required _SchedulePlanReferences references,
  }) => showMagicSheet<PreferredScheduleDraft>(
    context,
    title: adding ? 'Добавить набор дней' : 'Изменить набор дней',
    subtitle: 'Для выбранных дней педагог и аудитория обязательны',
    icon: Icons.edit_calendar_outlined,
    builder: (_) => PreferredScheduleEditor(
      branches: branches,
      teachers: references.teachers,
      rooms: references.rooms,
      defaultBranchId: defaultBranchId,
      initialDraft: seed,
      showPeriod: false,
      requireFinancialDecision: true,
      decisionCatalogs: references.decisionCatalogs,
      canManageTeacherCompensation: canManageTeacherCompensation,
      participantLabels: _decisionParticipantLabels,
    ),
  );

  String _draftSummary(
    PreferredScheduleDraft row,
    _SchedulePlanReferences references,
  ) {
    final teacher = references.teachers
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (item) => item?['id']?.toString() == row.teacherId,
          orElse: () => null,
        );
    final room = references.rooms.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id']?.toString() == row.roomId,
      orElse: () => null,
    );
    final branch = branches.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id']?.toString() == row.branchId,
      orElse: () => null,
    );
    final teacherName =
        '${teacher?['first_name'] ?? ''} ${teacher?['last_name'] ?? ''}'.trim();
    return '${teacherName.isEmpty ? 'Педагог не выбран' : teacherName} · '
        '${room?['name'] ?? 'Аудитория не выбрана'} · '
        '${branch?['name'] ?? 'Филиал'} · ${row.durationMinutes} мин'
        '${row.lessonsPerDay > 1 ? ' × ${row.lessonsPerDay}' : ''}';
  }

  Future<_SchedulePlanReferences> _references() async {
    final teachersFuture = service.listTeachers(limit: 100);
    final roomsFuture = service.listRooms(limit: 100);
    final catalogsFuture = Future.wait<Map<String, dynamic>>([
      for (final branch in branches)
        api.get<Map<String, dynamic>>(
          '/crm/configuration/lesson-decisions',
          queryParameters: {'branchId': branch['id']?.toString()},
        ),
    ]);
    final teachers = await teachersFuture;
    final rooms = await roomsFuture;
    final rawCatalogs = await catalogsFuture;
    return (
      teachers: List<Map<String, dynamic>>.from(teachers),
      rooms: List<Map<String, dynamic>>.from(rooms),
      decisionCatalogs: {
        for (var index = 0; index < branches.length; index++)
          if (branches[index]['id']?.toString().isNotEmpty == true)
            branches[index]['id'].toString(): LessonDecisionCatalog.fromJson(
              rawCatalogs[index],
              LessonDecisionOperation.settle,
            ),
      },
    );
  }

  PreferredScheduleDraft _draftFromPlanRow(
    SchedulePlanRow row, {
    required DateTime validFrom,
    required DateTime validUntil,
    required String? title,
    required String? subscriptionId,
    required bool openEnded,
  }) => PreferredScheduleDraft(
    seriesId: row.id,
    branchId: row.branchId,
    weekdays: {row.weekday},
    beginTime: row.beginTime,
    durationMinutes: row.durationMinutes,
    lessonsPerDay: 1,
    validFrom: validFrom,
    validUntil: validUntil,
    teacherId: row.teacherId,
    roomId: row.roomId,
    notes: row.notes ?? '',
    title: title,
    subscriptionId: subscriptionId,
    settlementTypeKey:
        row.financialDecision['settlementTypeKey']?.toString() ?? '',
    teacherCompensationRuleKey:
        row.financialDecision['teacherCompensationRuleKey']?.toString() ?? '',
    teacherCreditedDurationMinutes:
        (row.financialDecision['teacherCreditedDurationMinutes'] as num?)
            ?.toInt(),
    teacherCompensationSource: row
        .financialDecision['teacherCompensationSource']
        ?.toString(),
    clientDecisions: [
      for (final item
          in row.financialDecision['clientDecisions'] as List? ?? const [])
        if (item is Map) Map<String, dynamic>.from(item),
    ],
    openEnded: openEnded,
  );

  List<Map<String, dynamic>> _draftRows(PreferredScheduleDraft draft) =>
      rowsFromDraft(
        draft,
        canManageTeacherCompensation: canManageTeacherCompensation,
      );

  static List<Map<String, dynamic>> rowsFromDraft(
    PreferredScheduleDraft draft, {
    required bool canManageTeacherCompensation,
  }) {
    final rows = <Map<String, dynamic>>[];
    final weekdays = draft.weekdays.toList()..sort();
    for (final weekday in weekdays) {
      for (var slot = 0; slot < draft.lessonsPerDay; slot++) {
        rows.add({
          if (draft.seriesId != null && rows.isEmpty)
            'seriesId': draft.seriesId,
          'teacherId': draft.teacherId,
          'roomId': draft.roomId,
          'branchId': draft.branchId,
          'weekday': weekday,
          'beginTime': slotTime(
            beginTime: draft.beginTime,
            durationMinutes: draft.durationMinutes,
            slot: slot,
          ),
          'durationMinutes': draft.durationMinutes,
          if (draft.notes.isNotEmpty) 'notes': draft.notes,
          'financialDecision': {
            'settlementTypeKey': draft.settlementTypeKey,
            'teacherCompensationRuleKey': draft.teacherCompensationRuleKey,
            if (draft.teacherCreditedDurationMinutes != null)
              'teacherCreditedDurationMinutes':
                  draft.teacherCreditedDurationMinutes,
            if (draft.teacherCompensationSource != null)
              'teacherCompensationSource': draft.teacherCompensationSource,
            'clientDecisions': lessonClientDecisionsPayload(
              draft.clientDecisions,
            ),
          },
        });
      }
    }
    return rows;
  }

  Map<String, String> get _decisionParticipantLabels => {
    ..._participantLabels,
    ?studentId: 'Ученик',
  };

  List<Map<String, dynamic>> _initialClientDecisions(
    GroupScheduleParticipantsDraft? participants,
  ) => _groupMode
      ? [
          for (final participant in participants?.participants ?? const [])
            {
              'clientId': participant['studentId'],
              'chargeType': 'subscription',
              'subscriptionId': participant['subscriptionId'],
            },
        ]
      : [
          if (studentId != null)
            {
              'clientId': studentId,
              'chargeType': 'subscription',
              if (subscriptions.firstOrNull?['id'] != null)
                'subscriptionId': subscriptions.first['id'],
            },
        ];

  static String slotTime({
    required String beginTime,
    required int durationMinutes,
    required int slot,
  }) {
    final parts = beginTime.split(':');
    final minutes =
        (int.tryParse(parts.first) ?? 0) * 60 +
        (int.tryParse(parts.last) ?? 0) +
        durationMinutes * slot;
    return '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
  }
}

String _apiDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
