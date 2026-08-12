part of 'client_card.dart';

// Standalone presentation widgets for the client card. Kept in the same
// library (part) so they retain private access without widening the API.

class _CommentsList extends ConsumerStatefulWidget {
  /// One ref per half whose comments should be shown. A single-side card passes
  /// one ref; a converted client passes both ('lead', …) and ('student', …).
  final List<ClientHalfRef> refs;

  /// When true (converted), each comment gets a «Лид»/«Ученик» origin chip.
  final bool showOrigin;
  final int refreshKey;
  const _CommentsList({
    required this.refs,
    required this.showOrigin,
    required this.refreshKey,
  });

  @override
  ConsumerState<_CommentsList> createState() => _CommentsListState();
}

class _CommentsListState extends ConsumerState<_CommentsList> {
  // The comments future is held in a field (not recreated in build()) so the
  // list doesn't re-fetch on every parent rebuild — the card rebuilds often on
  // realtime events. Recomputed only when refs/refreshKey change or on retry.
  late Future<List<Comment>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadMerged();
  }

  @override
  void didUpdateWidget(covariant _CommentsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey ||
        _refsSig(oldWidget.refs) != _refsSig(widget.refs)) {
      _future = _loadMerged();
    }
  }

  String _refsSig(List<ClientHalfRef> refs) =>
      refs.map((r) => '${r.entityType}/${r.entityId}').join(',');

  // Maps a comment `kind` to a short Russian badge label. Unknown / generic
  // kinds (e.g. plain staff comments) get no badge.
  String? _kindLabel(Object? kind) {
    return switch (kind?.toString()) {
      'admin_comment' => 'Админ',
      'teacher_note' => 'Педагог',
      'progress' => 'Прогресс',
      _ => null,
    };
  }

  /// «К занятию 11 июл» — метка комментария, оставленного к конкретному уроку.
  ///
  /// Дата занятия, а не комментария: они совпадают у импортированных (HolliHop
  /// времени написания не хранит), но разойдутся у тех, что сотрудник напишет
  /// в приложении, — и тогда важна именно дата занятия, про которое речь.
  Widget _lessonBadge(String lessonAt, ColorScheme cs) {
    final dt = DateTime.tryParse(lessonAt)?.toLocal();
    final label = dt != null
        ? 'К занятию ${DateFormat('d MMM', 'ru').format(dt)}'
        : 'К занятию';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_note_rounded, size: 11, color: cs.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kindBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColor.goldSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColor.goldLine),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColor.gold,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }

  // Loads every ref's comments in PARALLEL, isolates per-ref failures (a failed
  // half contributes no rows but never fails the whole list), tags each comment
  // with its origin entityType (`_origin`), merges, de-dups by id and sorts by
  // created_at desc.
  Future<List<Comment>> _loadMerged() async {
    final crm = ref.read(magicCrmServiceProvider);
    final results = await Future.wait(
      widget.refs.map((r) async {
        try {
          final rows = await crm.listComments(
            entityType: r.entityType,
            entityId: r.entityId,
            // Заказчик просил видеть в этой же ленте и комментарии админов к
            // конкретным занятиям клиента. Они живут на занятии (у группового
            // — один на всех), поэтому бэк подмешивает их сюда сам, одним
            // запросом. У лида занятий нет — просить нечего.
            includeLessonComments: r.entityType == 'student',
          );
          return rows.map((c) => {...c, '_origin': r.entityType}).toList();
        } catch (_) {
          return <Map<String, dynamic>>[];
        }
      }),
    );
    var merged = mergeByIdSorted(results, dateKey: 'created_at');
    // Only a converted client aggregates more than one half, and that is the
    // only place the importer's lead+student copies can collide — so collapse
    // content-identical notes there. Single-side lists are left untouched.
    if (widget.refs.length > 1) {
      merged = dedupeCommentsByContent(merged);
    }
    return merged.map(Comment.fromMap).toList();
  }

  bool get _isStaff {
    final role = ref.read(releaseGateStatusProvider).asData?.value.role;
    return role == 'admin' ||
        role == 'manager' ||
        role == 'director' ||
        role == 'system_admin';
  }

  Widget _visibilityToggle(Map<String, dynamic> c) {
    final id = c['id']?.toString() ?? '';
    final rawVersion = c['version'];
    final version = rawVersion is num
        ? rawVersion.toInt()
        : int.tryParse('$rawVersion') ?? 1;
    return CommentShareButton(
      commentId: id,
      version: version,
      sharedWithTeacher: c['shared_with_teacher'] == true,
      allowed: _isStaff && id.isNotEmpty,
      onChanged: () {
        if (!mounted) return;
        final next = _loadMerged();
        setState(() {
          _future = next;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<Comment>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: LinearProgressIndicator(color: AppColor.gold),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Не удалось загрузить комментарии',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: AppSpace.xs),
                TextButton.icon(
                  onPressed: () => setState(() => _future = _loadMerged()),
                  style: TextButton.styleFrom(foregroundColor: AppColor.gold),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) return const SizedBox.shrink();
        final comments = snapshot.data!;
        if (comments.isEmpty) {
          return Text(
            'Нет комментариев',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          );
        }

        return Column(
          children: comments.map((c) {
            final dt = DateTime.tryParse(c.createdAt ?? '')?.toLocal();
            final dateStr = dt != null
                ? DateFormat('d MMM HH:mm', 'ru').format(dt)
                : '';
            final kindLabel = _kindLabel(c.kind);
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: AppSpace.sm),
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                c.authorName.trim().isNotEmpty
                                    ? c.authorName
                                    : 'Сотрудник',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColor.gold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (kindLabel != null) ...[
                              const SizedBox(width: 6),
                              _kindBadge(kindLabel),
                            ],
                            if (widget.showOrigin && c.origin != null) ...[
                              const SizedBox(width: 6),
                              ClientOriginChip(entityType: c.origin!),
                            ],
                            // Комментарий к конкретному занятию — не к клиенту
                            // вообще. Без этой пометки «миши не будет» в ленте
                            // непонятно к чему: заказчик и просил различать.
                            if (c.isAboutLesson) ...[
                              const SizedBox(width: 6),
                              _lessonBadge(c.lessonAt!, cs),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(c.content ?? '', style: const TextStyle(fontSize: 13)),
                  if (_isStaff &&
                      (c.kind == 'admin_comment' ||
                          c.kind == 'teacher_note')) ...[
                    const SizedBox(height: 2),
                    _visibilityToggle(c.raw),
                  ],
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// #12: строка задачи, раскрываемая тапом.
///
/// Свёрнутая повторяет прежний вид ([_entityTile]): иконка, название в одну
/// строку, статус. Развёрнутая показывает всё, что уже лежит в строке задачи
/// ([_legacyTask]): полное название, описание, «Поставил», «Исполнитель»,
/// «Срок» (красным, если просрочен и задача не закрыта), «Создана», приоритет.
class _TaskTile extends StatefulWidget {
  final Map<String, dynamic> task;
  const _TaskTile({required this.task});

  @override
  State<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<_TaskTile> {
  bool _expanded = false;

  String? _priorityLabel(Object? priority) {
    return switch (priority?.toString()) {
      'high' || 'urgent' => 'Высокий',
      'low' => 'Низкий',
      // «Средний» — дефолт, не подписываем: метка у каждой второй задачи —
      // это шум.
      _ => null,
    };
  }

  bool get _isOverdue {
    final due = DateTime.tryParse(widget.task['due_at']?.toString() ?? '');
    if (due == null) return false;
    final status = widget.task['status']?.toString();
    if (status == 'done' || status == 'cancelled') return false;
    return due.isBefore(DateTime.now());
  }

  Widget _metaRow(
    ColorScheme cs,
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: valueColor == null
                    ? FontWeight.w500
                    : FontWeight.w700,
                color: valueColor ?? cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final task = widget.task;
    final title = task['title']?.toString() ?? '';
    final description = task['description']?.toString().trim() ?? '';
    final creator = task['creator_name']?.toString().trim() ?? '';
    final assignee = task['assigned_name']?.toString().trim() ?? '';
    final due = _formatDate(task['due_at']);
    final created = _formatDate(task['created_at']);
    final priority = _priorityLabel(task['priority']);
    final statusLabel = _formatStatus(task['status']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.task_alt_rounded,
                        size: 18,
                        color: AppColor.gold,
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isEmpty ? 'Задача' : title,
                            maxLines: _expanded ? null : 1,
                            overflow: _expanded ? null : TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (statusLabel.isNotEmpty)
                            Text(
                              statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
                if (_expanded) ...[
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  if (creator.isNotEmpty)
                    _metaRow(
                      cs,
                      Icons.person_outline_rounded,
                      'Поставил',
                      creator,
                    ),
                  if (assignee.isNotEmpty)
                    _metaRow(
                      cs,
                      Icons.assignment_ind_outlined,
                      'Исполнитель',
                      assignee,
                    ),
                  if (due.isNotEmpty)
                    _metaRow(
                      cs,
                      Icons.schedule_rounded,
                      'Срок',
                      _isOverdue ? '$due · просрочена' : due,
                      valueColor: _isOverdue ? AppTheme.danger : null,
                    ),
                  if (created.isNotEmpty)
                    _metaRow(cs, Icons.event_outlined, 'Создана', created),
                  if (priority != null)
                    _metaRow(cs, Icons.flag_outlined, 'Приоритет', priority),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One labelled info row for compact read-only card sections.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final void Function(BuildContext context, EntityOpenTarget target)? onOpen;
  final bool highlighted;

  /// Мелкая приписка под значением — провенанс («из HolliHop») там, где важно
  /// отличать настоящие данные от подставленных приложением.
  final String? hint;

  /// Цвет приписки. Нужен там, где она несёт смысл, а не пояснение: «Долг»
  /// красным, «Переплата» зелёным — как на эталонной карточке.
  final Color? hintColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.hint,
    this.hintColor,
    this.trailing,
    this.onOpen,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      decoration: highlighted
          ? BoxDecoration(
              border: Border.all(color: AppColor.gold, width: 2),
              borderRadius: BorderRadius.circular(AppRadius.control),
            )
          : const BoxDecoration(),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xs,
          vertical: 6,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  if (onOpen == null)
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    EntityLinkText(
                      text: value,
                      onPressed: () =>
                          onOpen!(context, EntityOpenTarget.current),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (hint != null)
                    Text(
                      hint!,
                      style: TextStyle(
                        fontSize: 10,
                        color:
                            hintColor ??
                            Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: hintColor == null
                            ? FontWeight.normal
                            : FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpace.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
    return content;
  }
}

/// «Прогресс» tab body: homework assigned to the student by the teacher
/// (`app.lesson_homeworks`). Trial homework can still belong to a lead; after
/// subscription-triggered conversion the server moves it to the student.
/// Holds its own future so the aggregated card's frequent rebuilds don't
/// refetch; recomputed when its subject or [refreshKey] changes.
class _HomeworkProgressList extends ConsumerStatefulWidget {
  final String? studentId;
  final String? leadId;
  final int refreshKey;
  final bool embedded;
  const _HomeworkProgressList({
    this.studentId,
    this.leadId,
    required this.refreshKey,
    this.embedded = false,
  }) : assert(studentId != null || leadId != null);

  @override
  ConsumerState<_HomeworkProgressList> createState() =>
      _HomeworkProgressListState();
}

class _HomeworkProgressListState extends ConsumerState<_HomeworkProgressList> {
  late Future<List<Map<String, dynamic>>> _future;
  String? _attachingHomeworkId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _HomeworkProgressList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey ||
        oldWidget.studentId != widget.studentId ||
        oldWidget.leadId != widget.leadId) {
      _future = _load();
    }
  }

  Future<List<Map<String, dynamic>>> _load() {
    final studentId = widget.studentId?.trim();
    final leadId = widget.leadId?.trim();
    if ((studentId == null || studentId.isEmpty) &&
        (leadId == null || leadId.isEmpty)) {
      return Future.value(const <Map<String, dynamic>>[]);
    }
    return ref
        .read(magicCrmServiceProvider)
        .listHomeworks(studentId: studentId, leadId: leadId, limit: 50);
  }

  String _statusLabel(Object? s) => switch (s?.toString()) {
    'assigned' => 'Задано',
    'submitted' => 'Сдано',
    'done' || 'completed' || 'checked' => 'Проверено',
    _ => s?.toString() ?? '',
  };

  Future<void> _attachAssignment(Map<String, dynamic> homework) async {
    final homeworkId = homework['id']?.toString();
    if (homeworkId == null || homeworkId.isEmpty) return;
    final file = await pickHomeworkAttachment(context);
    if (file == null || !mounted) return;

    setState(() => _attachingHomeworkId = homeworkId);
    try {
      await ref
          .read(homeworkAttachmentServiceProvider)
          .uploadAndAttach(
            homeworkId: homeworkId,
            bytes: file.bytes,
            fileName: file.name,
            kind: 'assignment',
          );
      if (!mounted) return;
      setState(() => _future = _load());
      MagicToast.show(
        context,
        'Файл прикреплён',
        detail: file.name,
        type: MagicToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось прикрепить файл',
        detail: '$error',
        type: MagicToastType.danger,
      );
    } finally {
      if (mounted) setState(() => _attachingHomeworkId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColor.gold),
          );
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Не удалось загрузить домашние задания',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  TextButton.icon(
                    onPressed: () => setState(() => _future = _load()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          );
        }
        final items = snap.data ?? const <Map<String, dynamic>>[];
        if (items.isEmpty) {
          return Center(
            child: Text(
              'Домашних заданий пока нет',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpace.xl),
          shrinkWrap: widget.embedded,
          physics: widget.embedded
              ? const NeverScrollableScrollPhysics()
              : null,
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final h = items[i];
            final homeworkId = h['id']?.toString() ?? '';
            final title = (h['title'] ?? 'Домашнее задание').toString();
            final desc = (h['description'] ?? '').toString().trim();
            final due = DateTime.tryParse((h['dueAt'] ?? '').toString());
            final created = DateTime.tryParse(
              (h['createdAt'] ?? '').toString(),
            );
            final meta = [
              if (due != null)
                'Срок: ${DateFormat('d MMM yyyy', 'ru').format(due.toLocal())}',
              if (created != null)
                'Задано: ${DateFormat('d MMM', 'ru').format(created.toLocal())}',
            ].join('  •  ');
            final statusLabel = _statusLabel(h['status']);
            final attachments = homeworkAttachments(h['attachments']);
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.menu_book_rounded,
                          size: 18,
                          color: AppColor.gold,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (statusLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColor.goldSoft,
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              border: Border.all(color: AppColor.goldLine),
                            ),
                            child: Text(
                              statusLabel,
                              style: const TextStyle(
                                color: AppColor.gold,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        desc,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        meta,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (attachments.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.md),
                      HomeworkAttachmentList(attachments: attachments),
                    ],
                    const SizedBox(height: AppSpace.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: ValueKey('homework-attach-$homeworkId'),
                        onPressed: _attachingHomeworkId == null
                            ? () => _attachAssignment(h)
                            : null,
                        icon: _attachingHomeworkId == homeworkId
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.attach_file_rounded),
                        label: const Text('Добавить файл'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
