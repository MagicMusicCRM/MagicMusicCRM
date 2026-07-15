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

/// Family members list with per-row delete. [family] is the raw `_family`
/// payload (`{family: {...}, members: [...]}`); [onRemove] deletes a member.
Widget _familySection(
  ColorScheme cs, {
  required bool loading,
  required Map<String, dynamic>? family,
  required bool busy,
  required void Function(Map<String, dynamic> member) onRemove,
}) {
  if (loading) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: LinearProgressIndicator(color: AppColor.gold),
    );
  }
  final familyRecord = family?['family'] as Map<String, dynamic>?;
  final members = _list(family?['members']);
  if (familyRecord == null) {
    return Text('Семья не указана', style: TextStyle(color: cs.onSurfaceVariant));
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
          final isPayer = primaryId != null && m['id']?.toString() == primaryId;
          final subtitle = [
            _familyRoleLabel(m['role']),
            if (m['is_primary_contact'] == true) 'Осн. контакт',
            if (isPayer) 'Плательщик',
          ].where((value) => value.isNotEmpty).join(' · ');
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              leading: const Icon(
                Icons.people_alt_rounded,
                size: 18,
                color: AppColor.gold,
              ),
              title: Text(
                (m['name']?.toString().trim().isNotEmpty ?? false)
                    ? m['name'].toString()
                    : 'Без имени',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: subtitle.isEmpty ? null : Text(subtitle),
              trailing: IconButton(
                tooltip: 'Удалить участника',
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : () => onRemove(m),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AppTheme.danger,
                ),
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
          final subtitle =
              [student['phone'], student['email'], _duplicateMatchText(candidate)]
                  .where((value) => value != null && '$value'.isNotEmpty)
                  .join(' · ');
          final candidateId = candidate['id']?.toString();
          final pending = candidateId != null && candidateId == pendingId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              title: Text(
                title == null || title.isEmpty ? 'Существующий ученик' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: subtitle.isEmpty
                  ? null
                  : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
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

/// Lead «активность» aggregate: summary chips + linked-students/tasks/trials/
/// applications/timeline mini-sections. [onScheduleTrial] wires the «На пробный»
/// action (null hides it for a student-only card).
Widget _aggregateCard(
  ColorScheme cs, {
  required bool loadingCard,
  required Map<String, dynamic>? card,
  required List<Map<String, dynamic>> leadApplications,
  required int duplicateCount,
  required bool loadingDuplicates,
  required bool includeTasks,
  required VoidCallback? onScheduleTrial,
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

  final linkedStudents = _list(card['linked_students']);
  final tasks = _list(card['tasks']);
  final trials = _list(card['trials']);
  final otherLeads = _list(card['other_leads']);
  final timeline = _list(card['timeline']);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        children: [
          _summaryChip(Icons.school_outlined, 'Ученики', linkedStudents.length),
          _summaryChip(Icons.task_alt_rounded, 'Задачи', tasks.length),
          _summaryChip(Icons.event_available_rounded, 'Пробные', trials.length),
          _summaryChip(Icons.link_rounded, 'Похожие лиды', otherLeads.length),
          if (loadingDuplicates || duplicateCount > 0)
            _summaryChip(Icons.merge_type_rounded, 'Кандидаты', duplicateCount),
        ],
      ),
      const SizedBox(height: AppSpace.md),
      _miniSection(
        cs,
        title: 'Связанные ученики',
        empty: 'Связанных учеников нет',
        rows: linkedStudents,
        titleBuilder: (row) =>
            '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim(),
        subtitleBuilder: (row) => row['phone']?.toString(),
      ),
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
        action: onScheduleTrial != null
            ? TextButton.icon(
                onPressed: onScheduleTrial,
                style: TextButton.styleFrom(
                  foregroundColor: AppColor.gold,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 15),
                label: const Text('На пробный'),
              )
            : null,
      ),
      // KVA-234: заявки лида (HolliHop GetStudyRequests) — порядок секций по
      // HolliHop: Связанные ученики → Пробные занятия → Заявки → Лента.
      _miniSection(
        cs,
        title: 'Заявки',
        empty: 'Заявок нет',
        rows: leadApplications,
        titleBuilder: (row) => _formatDate(row['applied_at']),
        subtitleBuilder: (row) {
          final utm = row['utm'];
          final utmSource = utm is Map ? utm['Source']?.toString() : null;
          return [row['channel'], row['discipline'], utmSource]
              .where((value) => value != null && '$value'.isNotEmpty)
              .join(' · ');
        },
      ),
      _miniSection(
        cs,
        title: 'Лента',
        empty: 'История пока пустая',
        rows: timeline.take(8).toList(),
        titleBuilder: (row) => row['title']?.toString() ?? 'Событие',
        subtitleBuilder: (row) => _formatDate(row['occurred_at']),
      ),
    ],
  );
}

