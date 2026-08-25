part of 'client_card.dart';

extension _ClientCardCommentEditor on _ClientCardState {
  /// Staff может выбрать поток комментария; педагог всегда пишет teacher_note.
  bool get _canPickCommentKind {
    final role = ref.read(releaseGateStatusProvider).asData?.value.role;
    final isStaff =
        role == 'admin' ||
        role == 'manager' ||
        role == 'director' ||
        role == 'system_admin';
    final targetIsStudent = _isConverted || widget.entityType == 'student';
    return isStaff && targetIsStudent;
  }

  Widget _buildCommentInput(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_canPickCommentKind) ...[
          Wrap(
            spacing: AppSpace.sm,
            children: [
              for (final (kind, label) in const [
                ('admin_comment', 'Комментарий админа'),
                ('teacher_note', 'Для педагога'),
              ])
                ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: _commentKind == kind,
                  // #11: галочка + подпись ниже — чтобы выбор потока читался
                  // как выбор, а не как кнопка, которая «ничего не делает».
                  showCheckmark: true,
                  checkmarkColor: AppColor.gold,
                  selectedColor: AppColor.goldSoft,
                  onSelected: (_) => _emitState(() => _commentKind = kind),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            _commentKind == 'teacher_note'
                ? 'Комментарий увидит и педагог'
                : 'Комментарий виден только админам',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                decoration: _inputDecoration(
                  cs,
                  hint: 'Написать комментарий...',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Tooltip(
              message: 'Отправить комментарий',
              child: Material(
                color: AppColor.gold,
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: _addComment,
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpace.md),
                    child: Icon(
                      Icons.send_rounded,
                      color: AppColor.onGold,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAggregateCard(ColorScheme cs, {bool includeTasks = true}) {
    return _aggregateCard(
      cs,
      loadingCard: _loadingCard,
      card: _leadCard,
      duplicateCount: _duplicateCandidates
          .where(_isCurrentLeadDuplicateCandidate)
          .length,
      loadingDuplicates: _loadingDuplicates,
      includeTasks: includeTasks,
    );
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    // New comments target the card's primary half: the student side for a
    // converted client (where most activity lives), otherwise the open entity.
    final targetType = _isConverted ? 'student' : widget.entityType;
    final targetId = _isConverted ? _studentId : _entityId;
    if (targetId.isEmpty) return;
    // kind существует только у entity_comments (ученик): staff выбирает поток,
    // педагог всегда пишет teacher_note (admin_comment ему запрещён RBAC'ом).
    final role = ref.read(releaseGateStatusProvider).asData?.value.role;
    final kind = targetType != 'student'
        ? null
        : _canPickCommentKind
        ? _commentKind
        : role == 'teacher'
        ? 'teacher_note'
        : null;
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createComment(
            entityType: targetType,
            entityId: targetId,
            body: text,
            kind: kind,
          );
      _commentCtrl.clear();
      if (mounted) {
        // #11: видимая обратная связь — что комментарий создан и в какой
        // поток он ушёл; выбор потока возвращается к безопасному дефолту.
        MagicToast.show(
          context,
          kind == 'teacher_note'
              ? 'Комментарий добавлен (для педагога)'
              : 'Комментарий добавлен',
          type: MagicToastType.success,
        );
        _emitState(() {
          _commentsRefreshKey++;
          _commentKind = 'admin_comment';
        });
        if (_mode.hasStudentHalf) {
          _fetchStudentData();
        }
        if (_mode.hasLeadHalf) {
          _fetchCard();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось сохранить изменение.'),
            ),
          ),
        );
      }
    }
  }
}
