part of 'data_quality_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Section header with optional count badge.
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int? badge;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColor.goldSoft,
            borderRadius: BorderRadius.circular(AppRadius.icon),
          ),
          child: Icon(icon, color: AppColor.gold, size: 20),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badge! > 0
                  ? AppColor.goldSoft
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: badge! > 0 ? AppColor.goldLine : cs.outlineVariant,
              ),
            ),
            child: Text(
              '$badge',
              style: TextStyle(
                color: badge! > 0 ? AppColor.gold : cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phone review queue card.
// ─────────────────────────────────────────────────────────────────────────────
class _PhoneReviewCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool busy;
  final ValueChanged<Map<String, dynamic>> onResolve;

  const _PhoneReviewCard({
    required this.item,
    required this.busy,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rawPhone = _readString(item, [
      'rawPhone',
      'raw_phone',
      'phone',
      'normalizedPhone',
      'normalized',
    ]);
    final normalized = _readString(item, ['normalizedPhone', 'normalized']);
    final reason = _readString(item, ['reason']);
    final entityType = _readString(item, ['entityType', 'entity_type', 'lead']);
    final name = _readString(item, [
      'name',
      'entityName',
      'entity_name',
      'leadName',
    ]);

    final phoneLabel = rawPhone.isNotEmpty
        ? rawPhone
        : (normalized.isNotEmpty ? normalized : 'Без номера');

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColor.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.icon),
              ),
              child: const Icon(
                Icons.phone_forwarded_rounded,
                color: AppColor.gold,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    phoneLabel,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (normalized.isNotEmpty && normalized != rawPhone) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Нормализован: $normalized',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (name.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (reason.isNotEmpty)
                        _Chip(
                          icon: Icons.flag_outlined,
                          label: reason,
                          color: AppColor.gold,
                        ),
                      if (entityType.isNotEmpty)
                        _Chip(
                          icon: Icons.category_outlined,
                          label: entityType,
                          color: cs.onSurfaceVariant,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      key: ValueKey('resolve-phone-review-${item['id']}'),
                      onPressed: busy ? null : () => onResolve(item),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColor.gold,
                        side: const BorderSide(color: AppColor.goldLine),
                      ),
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.fact_check_outlined, size: 18),
                      label: Text(busy ? 'Сохраняем…' : 'Разобрать'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneReviewDecision {
  final String action;
  final String? phone;
  final String resolutionNote;

  const _PhoneReviewDecision({
    required this.action,
    required this.phone,
    required this.resolutionNote,
  });
}

class _PhoneReviewResolutionDialog extends StatefulWidget {
  final String rawPhone;

  const _PhoneReviewResolutionDialog({required this.rawPhone});

  @override
  State<_PhoneReviewResolutionDialog> createState() =>
      _PhoneReviewResolutionDialogState();
}

class _PhoneReviewResolutionDialogState
    extends State<_PhoneReviewResolutionDialog> {
  late final TextEditingController _phone;
  final TextEditingController _note = TextEditingController();
  String _action = 'corrected';

  @override
  void initState() {
    super.initState();
    _phone = TextEditingController(text: widget.rawPhone);
    _phone.addListener(_rebuild);
    _note.addListener(_rebuild);
  }

  @override
  void dispose() {
    _phone.removeListener(_rebuild);
    _note.removeListener(_rebuild);
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  bool get _canSubmit =>
      _note.text.trim().isNotEmpty &&
      (_action != 'corrected' || _phone.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Разобрать номер'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.rawPhone.isEmpty
                    ? 'В карточке номер не указан.'
                    : 'Текущее значение: ${widget.rawPhone}',
              ),
              const SizedBox(height: AppSpace.md),
              SegmentedButton<String>(
                key: const ValueKey('phone-review-action'),
                segments: const [
                  ButtonSegment(
                    value: 'corrected',
                    icon: Icon(Icons.edit_outlined),
                    label: Text('Исправить'),
                  ),
                  ButtonSegment(
                    value: 'accepted_as_is',
                    icon: Icon(Icons.check_rounded),
                    label: Text('Оставить как есть'),
                  ),
                ],
                selected: {_action},
                onSelectionChanged: (selected) {
                  setState(() => _action = selected.single);
                },
              ),
              if (_action == 'corrected') ...[
                const SizedBox(height: AppSpace.md),
                TextField(
                  key: const ValueKey('phone-review-phone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Исправленный номер',
                    hintText: '+7 999 123-45-67',
                    helperText: 'Будет сохранён в карточке в едином формате.',
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.md),
              TextField(
                key: const ValueKey('phone-review-note'),
                controller: _note,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Причина решения *',
                  hintText: 'Например: подтверждено по карточке клиента',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('submit-phone-review-resolution'),
          onPressed: !_canSubmit
              ? null
              : () => Navigator.pop(
                  context,
                  _PhoneReviewDecision(
                    action: _action,
                    phone: _action == 'corrected' ? _phone.text.trim() : null,
                    resolutionNote: _note.text.trim(),
                  ),
                ),
          child: const Text('Сохранить решение'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Merge candidate card.
// ─────────────────────────────────────────────────────────────────────────────
class _MergeCandidateCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String rowKey;
  final bool busy;
  final Future<void> Function(Map<String, dynamic> item, String rowKey) onMerge;

  const _MergeCandidateCard({
    required this.item,
    required this.rowKey,
    required this.busy,
    required this.onMerge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = _readString(item, ['name']);
    final phone = _readString(item, [
      'phone',
      'phoneNormalized',
      'phone_normalized',
    ]);
    final displayName = name.isEmpty ? 'Без имени' : name;
    final first = _readMap(item, 'first');
    final second = _readMap(item, 'second');
    final firstId = _readString(item, ['loserId', 'loser_id']);
    final secondId = _readString(item, ['winnerId', 'winner_id']);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColor.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.icon),
                  ),
                  child: const Icon(
                    Icons.people_alt_rounded,
                    color: AppColor.gold,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phone.isNotEmpty) ...[
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
              ],
            ),
            const SizedBox(height: AppSpace.md),
            _LeadRow(
              label: 'Запись A',
              detail: _candidateDetail(first, firstId),
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            _LeadRow(
              label: 'Запись B',
              detail: _candidateDetail(second, secondId),
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpace.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: busy ? null : () => onMerge(item, rowKey),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColor.gold,
                  foregroundColor: AppColor.onGold,
                  disabledBackgroundColor: AppColor.gold.withValues(alpha: 0.5),
                  disabledForegroundColor: AppColor.onGold,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
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
                    : const Icon(Icons.merge_type_rounded, size: 18),
                label: const Text('Объединить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadRow extends StatelessWidget {
  final String label;
  final String detail;
  final Color color;

  const _LeadRow({
    required this.label,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label — $detail',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Merge confirmation dialog with a winner picker.
// ─────────────────────────────────────────────────────────────────────────────
class _MergeConfirmDialog extends StatefulWidget {
  final String name;
  final String phone;
  final String firstId;
  final String secondId;
  final Map<String, dynamic> first;
  final Map<String, dynamic> second;

  const _MergeConfirmDialog({
    required this.name,
    required this.phone,
    required this.firstId,
    required this.secondId,
    required this.first,
    required this.second,
  });

  @override
  State<_MergeConfirmDialog> createState() => _MergeConfirmDialogState();
}

class _MergeConfirmDialogState extends State<_MergeConfirmDialog> {
  String? _winnerId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayName = widget.name.isEmpty ? 'этих лидов' : '«${widget.name}»';
    return AlertDialog(
      title: const Text('Объединить лиды?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Данные $displayName будут объединены. '
            'Выберите, какой лид останется основным.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: AppSpace.md),
          _WinnerOption(
            selected: _winnerId == widget.firstId,
            label: 'Запись A',
            detail: _candidateDetail(widget.first, widget.firstId),
            onTap: () => setState(() => _winnerId = widget.firstId),
          ),
          const SizedBox(height: 8),
          _WinnerOption(
            selected: _winnerId == widget.secondId,
            label: 'Запись B',
            detail: _candidateDetail(widget.second, widget.secondId),
            onTap: () => setState(() => _winnerId = widget.secondId),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: _winnerId == null
              ? null
              : () => Navigator.pop(context, _winnerId),
          child: const Text(
            'Объединить',
            style: TextStyle(color: AppColor.gold, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _WinnerOption extends StatelessWidget {
  final bool selected;
  final String label;
  final String detail;
  final VoidCallback onTap;

  const _WinnerOption({
    required this.selected,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColor.goldSoft : cs.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: selected ? AppColor.goldLine : cs.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: selected ? AppColor.gold : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _candidateDetail(Map<String, dynamic> candidate, String fallbackId) {
  final createdAt = _formatCandidateDate(_readString(candidate, ['createdAt']));
  final source = _readString(candidate, ['source']);
  final status = _readString(candidate, ['status']);
  final branch = _readString(candidate, ['branch']);
  final id = _readString(candidate, ['id']);
  final resolvedId = id.isEmpty ? fallbackId : id;
  final shortId = resolvedId.length > 8
      ? resolvedId.substring(resolvedId.length - 8)
      : resolvedId;
  final parts = <String>[
    if (createdAt.isNotEmpty) createdAt,
    if (source.isNotEmpty) source,
    if (status.isNotEmpty) status,
    if (branch.isNotEmpty) branch,
    if (shortId.isNotEmpty) 'ID …$shortId',
  ];
  return parts.isEmpty ? 'Нет данных для сравнения' : parts.join(' · ');
}

String _formatCandidateDate(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return value;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: chip, skeleton, error, empty.
// ─────────────────────────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardListSkeleton extends StatelessWidget {
  const _CardListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
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
                      SkeletonLine(width: 140),
                      SizedBox(height: 8),
                      SkeletonLine(width: 220),
                    ],
                  ),
                ),
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
            Icon(Icons.error_outline_rounded, color: AppColor.danger, size: 32),
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
              '$error',
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
            Icon(icon, color: AppColor.success, size: 34),
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
