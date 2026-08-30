import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/models/audit_presentation_event.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

class AuditEventCard extends StatefulWidget {
  const AuditEventCard({super.key, required this.event, this.onOpenTarget});

  final AuditPresentationEvent event;
  final VoidCallback? onOpenTarget;

  @override
  State<AuditEventCard> createState() => _AuditEventCardState();
}

class _AuditEventCardState extends State<AuditEventCard> {
  String? _expandedEventId;

  bool get _isExpanded => _expandedEventId == widget.event.id;

  void _toggleExpanded() {
    setState(() {
      _expandedEventId = _isExpanded ? null : widget.event.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final targetName = event.target.displayName ?? event.target.label;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColor.surface,
        border: Border.all(color: AppColor.borderSoft),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: const Key('audit-event-expand'),
              borderRadius: BorderRadius.circular(AppRadius.control),
              onTap: _toggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: AppColor.text,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            targetName,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColor.text2),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            event.actor.name,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColor.text3),
                          ),
                          if (event.occurredAt != null) ...[
                            const SizedBox(height: AppSpace.xs),
                            Text(
                              _formattedTime(event.occurredAt!),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColor.text3),
                            ),
                          ],
                          if (event.summary != null) ...[
                            const SizedBox(height: AppSpace.sm),
                            Text(
                              event.summary!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppColor.text2),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColor.text2,
                    ),
                  ],
                ),
              ),
            ),
            if (_isExpanded) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpace.md),
                child: Divider(height: 1, color: AppColor.divider),
              ),
              ...event.changes.map(_AuditChangeRow.new),
              if (event.reason != null) ...[
                if (event.changes.isNotEmpty)
                  const SizedBox(height: AppSpace.md),
                Text(
                  'Причина: ${event.reason}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColor.text2),
                ),
              ],
            ],
            if (widget.onOpenTarget != null) ...[
              const SizedBox(height: AppSpace.sm),
              TextButton(
                onPressed: widget.onOpenTarget,
                style: TextButton.styleFrom(
                  foregroundColor: AppColor.brandSolid,
                ),
                child: Text(
                  'Открыть ${_targetObjectLabel(event.target.type, event.target.label)}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formattedTime(DateTime occurredAt) =>
      DateFormat('dd.MM.yyyy HH:mm').format(occurredAt.toLocal());
}

class _AuditChangeRow extends StatelessWidget {
  const _AuditChangeRow(this.change);

  final AuditPresentationChange change;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            change.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColor.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Было: ${change.before ?? '—'}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColor.text2),
          ),
          Text(
            'Стало: ${change.after ?? '—'}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColor.text2),
          ),
        ],
      ),
    );
  }
}

String _targetObjectLabel(String type, String fallbackLabel) {
  return switch (type) {
    'student' => 'ученика',
    'client' => 'клиента',
    'lead' => 'лида',
    'teacher' => 'преподавателя',
    'lesson' => 'занятие',
    'group' => 'группу',
    'branch' => 'филиал',
    'payment' => 'платёж',
    'subscription' => 'абонемент',
    'task' => 'задачу',
    _ => fallbackLabel.toLowerCase(),
  };
}
