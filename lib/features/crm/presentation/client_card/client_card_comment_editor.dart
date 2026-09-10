part of 'client_card.dart';

extension _ClientCardCommentEditor on _ClientCardState {
  /// Staff может выбрать поток комментария; педагог всегда пишет teacher_note.
  bool get _canPickCommentKind {
    final role = _currentActorRole();
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
    final target = _commentTarget();
    if (target == null) return;
    final kind = _commentKindFor(target.$1);
    try {
      final created = await ref
          .read(magicCrmServiceProvider)
          .createComment(
            entityType: target.$1,
            entityId: target.$2,
            body: text,
            kind: kind,
          );
      _commentCtrl.clear();
      _onCommentCreated(kind, target: target, created: created);
    } catch (e) {
      _showCommentFailure(e);
    }
  }

  (String, String)? _commentTarget() {
    // Converted clients write to the student half where primary activity lives.
    final type = _isConverted ? 'student' : widget.entityType;
    final id = _isConverted ? _studentId : _entityId;
    return id.isEmpty ? null : (type, id);
  }

  String? _commentKindFor(String targetType) {
    // kind exists only for student comments. Teachers are forced into the
    // teacher stream by RBAC; staff may choose explicitly.
    if (targetType != 'student') return null;
    if (_canPickCommentKind) return _commentKind;
    final role = _currentActorRole();
    return role == 'teacher' ? 'teacher_note' : null;
  }

  void _onCommentCreated(
    String? kind, {
    required (String, String) target,
    required Map<String, dynamic> created,
  }) {
    if (!mounted) return;
    MagicToast.show(
      context,
      kind == 'teacher_note'
          ? 'Комментарий добавлен (для педагога)'
          : 'Комментарий добавлен',
      type: MagicToastType.success,
    );
    _emitState(() {
      _readController.recordComment(target.$1,created);
      _commentsRefreshKey++;
      _commentKind = 'admin_comment';
    });
    unawaited(_reloadOperationalHistory());
  }

  void _showCommentFailure(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userErrorMessage(error, fallback: 'Не удалось сохранить изменение.'),
        ),
      ),
    );
  }
}
