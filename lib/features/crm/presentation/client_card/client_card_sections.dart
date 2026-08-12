part of 'client_card.dart';

// Larger read-only card sections (lead activity aggregate, duplicate
// candidates) and their pure row helpers. Library-private via `part`; split
// from client_card_display.dart to keep each source under the ~800-line bar.

Map<String, dynamic> _candidateEntity(
  Map<String, dynamic> candidate,
  String entityType,
) {
  if (candidate['entity_type_a'] == entityType) {
    final value = candidate['entity_a'];
    return value is Map<String, dynamic> ? value : const <String, dynamic>{};
  }
  if (candidate['entity_type_b'] == entityType) {
    final value = candidate['entity_b'];
    return value is Map<String, dynamic> ? value : const <String, dynamic>{};
  }
  return const <String, dynamic>{};
}

String _duplicateMatchText(Map<String, dynamic> candidate) {
  final matchValue = candidate['match_value']?.toString().trim() ?? '';
  final confidence = _asNum(candidate['confidence']);
  final confidenceText = confidence > 0
      ? '${(confidence * 100).round()}% совпадение'
      : '';
  return [
    if (matchValue.isNotEmpty) matchValue,
    if (confidenceText.isNotEmpty) confidenceText,
  ].join(' · ');
}

/// Student «Группы» info card: active groups + their teachers (read-only).
Widget _studentGroupsInfoCard({required List<Map<String, dynamic>> groups}) {
  return _buildInfoCard('Группы', [
    if (groups.isEmpty)
      const _InfoRow(
        icon: Icons.group_off_rounded,
        label: 'Группы',
        value: 'Нет активных групп',
      )
    else
      ...groups.map((g) {
        final teacher = g['teachers'];
        var teacherName = '—';
        if (teacher is Map<String, dynamic>) {
          final firstName = teacher['first_name']?.toString() ?? '';
          final lastName = teacher['last_name']?.toString() ?? '';
          teacherName = '$firstName $lastName'.trim();
        }
        return _InfoRow(
          icon: Icons.groups_rounded,
          label: g['name']?.toString() ?? 'Группа',
          value: teacherName.isEmpty || teacherName == '—'
              ? 'Без преподавателя'
              : 'Преподаватель: $teacherName',
        );
      }),
  ]);
}

/// Family members list with per-row delete. [family] is the raw `_family`
/// payload (`{family: {...}, members: [...]}`); [onRemove] deletes a member.
Widget _familySection(
  ColorScheme cs, {
  required bool loading,
  required Map<String, dynamic>? family,
  required bool busy,
  required void Function(FamilyMember member) onRemove,
  required void Function(FamilyMember member) onSetPrimaryPayer,
  required void Function(BuildContext context, FamilyMember member) onOpen,
}) {
  if (loading) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: LinearProgressIndicator(color: AppColor.gold),
    );
  }
  final familyRecord = family?['family'] as Map<String, dynamic>?;
  final members = _list(family?['members']).map(FamilyMember.fromMap).toList();
  if (familyRecord == null) {
    return Text(
      'Семья не указана',
      style: TextStyle(color: cs.onSurfaceVariant),
    );
  }
  final primaryId = familyRecord['primary_payer_member_id']?.toString();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if ((familyRecord['name']?.toString().trim().isNotEmpty ?? false))
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            familyRecord['name'].toString(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      if (members.isEmpty)
        Text(
          'Участники не добавлены',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        )
      else
        ...members.map((m) {
          final isPayer = primaryId != null && m.id == primaryId;
          final subtitle = [
            _familyRoleLabel(m.role),
            if (m.isPrimaryContact) 'Осн. контакт',
            if (isPayer) 'Плательщик',
          ].where((value) => value.isNotEmpty).join(' · ');
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                side: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              leading: const Icon(
                Icons.people_alt_rounded,
                size: 18,
                color: AppColor.gold,
              ),
              title:
                  (m.entityType == 'lead' || m.entityType == 'student') &&
                      (m.entityId?.isNotEmpty ?? false)
                  ? Builder(
                      builder: (context) => EntityLinkText(
                        text: m.name.trim().isNotEmpty ? m.name : 'Без имени',
                        onPressed: () => onOpen(context, m),
                      ),
                    )
                  : Text(
                      m.name.trim().isNotEmpty ? m.name : 'Без имени',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              subtitle: subtitle.isEmpty ? null : Text(subtitle),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isPayer)
                    IconButton(
                      key: Key('family-primary-payer-${m.id}'),
                      tooltip: 'Назначить основным плательщиком',
                      visualDensity: VisualDensity.compact,
                      onPressed: busy ? null : () => onSetPrimaryPayer(m),
                      icon: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 18,
                        color: AppColor.gold,
                      ),
                    ),
                  IconButton(
                    tooltip: 'Удалить участника',
                    visualDensity: VisualDensity.compact,
                    onPressed: busy ? null : () => onRemove(m),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: AppTheme.danger,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
    ],
  );
}

/// Duplicate-candidate «связать с учеником» list. [pendingId] disables+spins the
/// row currently being attached; [onAttach] performs the link.
Widget _duplicateCandidatesSection(
  ColorScheme cs, {
  required List<Map<String, dynamic>> candidates,
  required bool loading,
  required String? pendingId,
  required void Function(Map<String, dynamic> candidate) onAttach,
}) {
  if (loading) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: LinearProgressIndicator(color: AppColor.gold),
    );
  }
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Кандидаты на связь с учеником',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        ...candidates.take(4).map((candidate) {
          final student = _candidateEntity(candidate, 'student');
          final title = student['name']?.toString().trim();
          final subtitle = [
            student['phone'],
            student['email'],
            _duplicateMatchText(candidate),
          ].where((value) => value != null && '$value'.isNotEmpty).join(' · ');
          final candidateId = candidate['id']?.toString();
          final pending = candidateId != null && candidateId == pendingId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                side: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              title: Text(
                title == null || title.isEmpty ? 'Существующий ученик' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: subtitle.isEmpty
                  ? null
                  : Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.goldSoft,
                  foregroundColor: AppColor.gold,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
                onPressed: pending ? null : () => onAttach(candidate),
                icon: pending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded, size: 16),
                label: const Text('Связать'),
              ),
            ),
          );
        }),
      ],
    ),
  );
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value.whereType<Map<String, dynamic>>().toList();
}

num _asNum(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

/// Lead «активность» aggregate: summary chips + the «Пробные занятия»
/// mini-section. Блоки «Связанные ученики»/«Заявки»/«Лента» удалены (#10):
/// они дублировали другие вкладки и разделы карточки; запись на пробное из
/// карточки убрана (#6) — вместо неё в баре действий «Открыть в расписании».
Widget _aggregateCard(
  ColorScheme cs, {
  required bool loadingCard,
  required Map<String, dynamic>? card,
  required int duplicateCount,
  required bool loadingDuplicates,
  required bool includeTasks,
}) {
  if (loadingCard) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: LinearProgressIndicator(color: AppColor.gold),
    );
  }
  if (card == null) {
    return Text(
      'Карточка активности временно недоступна',
      style: TextStyle(color: cs.onSurfaceVariant),
    );
  }

  final tasks = _list(card['tasks']);
  final trials = _list(card['trials']);
  final otherLeads = _list(card['other_leads']);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        children: [
          _summaryChip(Icons.task_alt_rounded, 'Задачи', tasks.length),
          _summaryChip(Icons.event_available_rounded, 'Пробные', trials.length),
          _summaryChip(Icons.link_rounded, 'Похожие лиды', otherLeads.length),
          if (loadingDuplicates || duplicateCount > 0)
            _summaryChip(Icons.merge_type_rounded, 'Кандидаты', duplicateCount),
        ],
      ),
      const SizedBox(height: AppSpace.md),
      if (includeTasks)
        _miniSection(
          cs,
          title: 'Задачи',
          empty: 'Открытых задач нет',
          rows: tasks,
          titleBuilder: (row) => row['title']?.toString() ?? 'Задача',
          subtitleBuilder: (row) => _formatStatus(row['status']),
        ),
      _miniSection(
        cs,
        title: 'Пробные занятия',
        empty: 'Пробные занятия не назначены',
        rows: trials,
        titleBuilder: (row) => _formatDate(row['scheduled_at']),
        subtitleBuilder: (row) => [
          row['teacher_name'],
          row['room_name'],
        ].where((value) => value != null && '$value'.isNotEmpty).join(' · '),
      ),
    ],
  );
}
