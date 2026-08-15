part of 'deletion_requests_widget.dart';

/// The result of a confirm sheet: confirmed, with an optional resolution note.
class _ConfirmOutcome {
  const _ConfirmOutcome({this.note});
  final String? note;
}

// ─────────────────────────────────────────────────────────────────────────────
// Defensive readers (snake_case AND camelCase).
// ─────────────────────────────────────────────────────────────────────────────
String _readString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null) {
      final str = value.toString().trim();
      if (str.isNotEmpty) return str;
    }
  }
  return '';
}

/// A human-readable identity for a request row (name › email › phone › id).
String _identityLabel(Map<String, dynamic> item) {
  final name = _readString(item, [
    'profileName',
    'profile_name',
    'name',
    'fullName',
    'full_name',
    'userName',
    'user_name',
  ]);
  if (name.isNotEmpty) return name;
  final email = _readString(item, ['email', 'userEmail', 'user_email']);
  if (email.isNotEmpty) return email;
  final phone = _readString(item, ['phone', 'userPhone', 'user_phone']);
  if (phone.isNotEmpty) return phone;
  return '';
}

String _formatRequestedAt(Map<String, dynamic> item) {
  final raw = _readString(item, [
    'requestedAt',
    'requested_at',
    'createdAt',
    'created_at',
  ]);
  if (raw.isEmpty) return '';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  return DateFormat('d MMM yyyy, HH:mm', 'ru').format(dt.toLocal());
}

// ─────────────────────────────────────────────────────────────────────────────
// Status filter bar (chips: Все / Ожидает / В работе / Выполнен / Отклонён /
// Отменён).
// ─────────────────────────────────────────────────────────────────────────────
class _StatusFilterBar extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _StatusFilterBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const options = <(String?, String)>[
      (null, 'Все'),
      ('pending', 'Ожидает'),
      ('processing', 'В работе'),
      ('completed', 'Выполнен'),
      ('rejected', 'Отклонён'),
      ('cancelled', 'Отменён'),
    ];

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.sm,
        ),
        itemCount: options.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final (value, label) = options[i];
          final isSelected = selected == value;
          return _FilterChip(
            label: label,
            selected: isSelected,
            onTap: () => onSelect(value),
            cs: cs,
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColor.goldSoft : cs.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: selected ? AppColor.goldLine : cs.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColor.gold : cs.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Request card.
// ─────────────────────────────────────────────────────────────────────────────
class _DeletionRequestCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool busy;
  final bool canManage;
  final Future<void> Function(Map<String, dynamic> item, _DeletionAction action)
  onAction;

  const _DeletionRequestCard({
    required this.item,
    required this.busy,
    required this.canManage,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = _DeletionStatus.fromValue(_readString(item, ['status']));
    final identity = _identityLabel(item);
    final displayIdentity = identity.isEmpty ? 'Без имени' : identity;
    final email = _readString(item, ['email', 'userEmail', 'user_email']);
    final phone = _readString(item, ['phone', 'userPhone', 'user_phone']);
    final reason = _readString(item, ['reason']);
    final resolutionNote = _readString(item, [
      'resolutionNote',
      'resolution_note',
    ]);
    final requestedAt = _formatRequestedAt(item);
    final statusColor = status.color(cs);

    // Show secondary contact lines only when they aren't already the identity.
    final showEmail = email.isNotEmpty && email != identity;
    final showPhone = phone.isNotEmpty && phone != identity;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: avatar + identity + status pill.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColor.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.icon),
                  ),
                  child: const Icon(
                    Icons.person_remove_rounded,
                    color: AppColor.danger,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayIdentity,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (showEmail) ...[
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (showPhone) ...[
                        const SizedBox(height: 2),
                        Text(
                          phone,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                _StatusPill(status: status, color: statusColor),
              ],
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              _LabeledBlock(
                icon: Icons.notes_rounded,
                label: 'Причина',
                value: reason,
                color: cs.onSurfaceVariant,
              ),
            ],
            if (resolutionNote.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              _LabeledBlock(
                icon: Icons.assignment_turned_in_outlined,
                label: 'Резолюция',
                value: resolutionNote,
                color: statusColor,
              ),
            ],
            if (requestedAt.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    requestedAt,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ],
            // Actions — only for non-terminal rows.
            if (!status.isTerminal && canManage) ...[
              const SizedBox(height: AppSpace.md),
              const Divider(height: 1, color: AppColor.divider),
              const SizedBox(height: AppSpace.md),
              _ActionRow(
                status: status,
                busy: busy,
                onAction: (action) => onAction(item, action),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final _DeletionStatus status;
  final Color color;

  const _StatusPill({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _LabeledBlock({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(color: cs.onSurface, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final _DeletionStatus status;
  final bool busy;
  final ValueChanged<_DeletionAction> onAction;

  const _ActionRow({
    required this.status,
    required this.busy,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    // Match the authoritative backend state machine exactly.
    final actions = <_DeletionAction>[
      if (status == _DeletionStatus.pending) _DeletionAction.processing,
      if (status == _DeletionStatus.processing) ...[
        _DeletionAction.completed,
        _DeletionAction.rejected,
      ],
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final action in actions)
          _ActionButton(
            action: action,
            busy: busy,
            onTap: () => onAction(action),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final _DeletionAction action;
  final bool busy;
  final VoidCallback onTap;

  const _ActionButton({
    required this.action,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (action.danger) {
      return OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColor.danger,
          side: BorderSide(color: AppColor.danger.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        icon: Icon(action.icon, size: 16),
        label: Text(action.buttonLabel),
      );
    }

    final isPrimary = action == _DeletionAction.processing;
    if (isPrimary) {
      return ElevatedButton.icon(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColor.gold,
          foregroundColor: AppColor.onGold,
          disabledBackgroundColor: AppColor.gold.withValues(alpha: 0.5),
          disabledForegroundColor: AppColor.onGold,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColor.onGold,
                ),
              )
            : Icon(action.icon, size: 16),
        label: Text(action.buttonLabel),
      );
    }

    // «Выполнить» — neutral outlined affordance.
    return OutlinedButton.icon(
      onPressed: busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColor.gold,
        side: const BorderSide(color: AppColor.goldLine),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      icon: Icon(action.icon, size: 16),
      label: Text(action.buttonLabel),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Confirm sheet body. Terminal staff decisions require a resolution note;
// completion additionally requires an explicit anonymization acknowledgement.
// ─────────────────────────────────────────────────────────────────────────────
class _ConfirmSheetBody extends StatefulWidget {
  final _DeletionAction action;
  const _ConfirmSheetBody({required this.action});

  @override
  State<_ConfirmSheetBody> createState() => _ConfirmSheetBodyState();
}

class _ConfirmSheetBodyState extends State<_ConfirmSheetBody> {
  final TextEditingController _note = TextEditingController();
  bool _acknowledged = false;

  @override
  void initState() {
    super.initState();
    _note.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _note.removeListener(_onChanged);
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final action = widget.action;
    final isDanger = action.danger;
    final isCompletion = action == _DeletionAction.completed;
    final accent = isDanger ? AppColor.danger : AppColor.gold;
    final noteReady = !action.collectsNote || _note.text.trim().isNotEmpty;
    final canSubmit = noteReady && (!isCompletion || _acknowledged);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isCompletion
              ? 'Аккаунт будет обезличен, способы входа удалены, а активные '
                    'сеансы отозваны. Исторические записи, обязательные для '
                    'работы школы и закона, сохранятся.'
              : isDanger
              ? 'Запрос будет отклонён. Укажите причину решения.'
              : 'Статус запроса будет изменён на «${_DeletionStatus.fromValue(action.status).label}».',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
        if (action.collectsNote) ...[
          const SizedBox(height: AppSpace.lg),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: 'Резолюция',
              hintText: isDanger
                  ? 'Причина отклонения…'
                  : 'Комментарий к выполнению…',
              filled: true,
              fillColor: cs.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: BorderSide(color: accent.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ],
        if (isCompletion) ...[
          const SizedBox(height: AppSpace.md),
          CheckboxListTile(
            key: const ValueKey('confirm-deletion-anonymization'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _acknowledged,
            onChanged: (value) =>
                setState(() => _acknowledged = value ?? false),
            title: const Text(
              'Подтверждаю обезличивание аккаунта и отзыв способов входа',
            ),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
                child: const Text('Отмена'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: canSubmit
                    ? () {
                        final text = _note.text.trim();
                        Navigator.pop(
                          context,
                          _ConfirmOutcome(note: text.isEmpty ? null : text),
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: isDanger ? Colors.white : AppColor.onGold,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
                child: Text(action.buttonLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: skeleton, error, empty.
// ─────────────────────────────────────────────────────────────────────────────
class _CardListSkeleton extends StatelessWidget {
  const _CardListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        4,
        (_) => Card(
          margin: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(
              children: const [
                SkeletonBox(width: 40, height: 40, radius: AppRadius.icon),
                SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(width: 150),
                      SizedBox(height: 8),
                      SkeletonLine(width: 220),
                    ],
                  ),
                ),
                SizedBox(width: AppSpace.sm),
                SkeletonBox(width: 78, height: 22, radius: AppRadius.pill),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColor.danger,
              size: 32,
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Не удалось загрузить',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              userErrorMessage(
                error,
                fallback: 'Не удалось загрузить запросы.',
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: AppSpace.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColor.gold,
                side: const BorderSide(color: AppColor.goldLine),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          children: [
            Icon(icon, color: cs.onSurfaceVariant, size: 34),
            const SizedBox(height: AppSpace.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
