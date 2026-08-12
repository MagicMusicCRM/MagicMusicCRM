import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

class GroupScheduleMemberOption {
  const GroupScheduleMemberOption({
    required this.studentId,
    required this.label,
    required this.subscriptions,
  });

  final String studentId;
  final String label;
  final List<Map<String, dynamic>> subscriptions;

  bool get hasSubscription => subscriptions.any(
    (subscription) => subscription['id']?.toString().isNotEmpty == true,
  );
}

class GroupScheduleParticipantsDraft {
  const GroupScheduleParticipantsDraft({
    required this.participants,
    required this.effectiveFrom,
  });

  final List<Map<String, dynamic>> participants;
  final DateTime? effectiveFrom;
}

class GroupScheduleParticipantsEditor extends StatefulWidget {
  const GroupScheduleParticipantsEditor({
    super.key,
    required this.members,
    this.initialParticipants = const [],
    this.requireEffectiveFrom = false,
    this.initialEffectiveFrom,
  });

  final List<GroupScheduleMemberOption> members;
  final List<SchedulePlanParticipant> initialParticipants;
  final bool requireEffectiveFrom;
  final DateTime? initialEffectiveFrom;

  @override
  State<GroupScheduleParticipantsEditor> createState() =>
      _GroupScheduleParticipantsEditorState();
}

class _GroupScheduleParticipantsEditorState
    extends State<GroupScheduleParticipantsEditor> {
  final Map<String, String> _selected = {};
  late DateTime _effectiveFrom;
  String? _error;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _effectiveFrom = DateUtils.dateOnly(widget.initialEffectiveFrom ?? today);
    if (widget.initialParticipants.isEmpty) {
      for (final member in widget.members) {
        final subscriptionId = _firstSubscriptionId(member);
        if (subscriptionId != null) {
          _selected[member.studentId] = subscriptionId;
        }
      }
    } else {
      for (final participant in widget.initialParticipants) {
        _selected[participant.studentId] = participant.subscriptionId;
      }
    }
  }

  String? _firstSubscriptionId(GroupScheduleMemberOption member) {
    for (final subscription in member.subscriptions) {
      final id = subscription['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  Future<void> _pickEffectiveFrom() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveFrom.isBefore(today) ? today : _effectiveFrom,
      firstDate: today,
      lastDate: DateTime(today.year + 5, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() {
        _effectiveFrom = DateUtils.dateOnly(picked);
        _error = null;
      });
    }
  }

  void _submit() {
    if (_selected.isEmpty) {
      setState(
        () => _error = 'Выберите хотя бы одного участника с абонементом.',
      );
      return;
    }
    Navigator.of(context).pop(
      GroupScheduleParticipantsDraft(
        participants: [
          for (final entry in _selected.entries)
            {'studentId': entry.key, 'subscriptionId': entry.value},
        ],
        effectiveFrom: widget.requireEffectiveFrom ? _effectiveFrom : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final eligible = widget.members.where((member) => member.hasSubscription);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Каждому участнику нужен собственный активный абонемент. '
          'Резерв занятия будет создан отдельно по каждому абонементу.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
        if (widget.requireEffectiveFrom) ...[
          const SizedBox(height: AppSpace.md),
          OutlinedButton.icon(
            key: const ValueKey('group-plan-effective-from'),
            onPressed: _pickEffectiveFrom,
            icon: const Icon(Icons.event_available_outlined),
            label: Text(
              'Применить с ${DateFormat('d MMMM yyyy', 'ru').format(_effectiveFrom)}',
            ),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        if (widget.members.isEmpty)
          const MagicPageState(
            kind: MagicPageStateKind.empty,
            title: 'В группе нет учеников',
            message: 'Сначала добавьте учеников в состав группы.',
          )
        else if (eligible.isEmpty)
          const MagicPageState(
            kind: MagicPageStateKind.empty,
            title: 'Нет участников с активным абонементом',
            message: 'Выдайте абонемент хотя бы одному ученику группы.',
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.members.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
              itemBuilder: (context, index) =>
                  _memberCard(widget.members[index]),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            _error!,
            key: const ValueKey('group-plan-participants-error'),
            style: TextStyle(color: scheme.error, fontSize: 12),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        FilledButton.icon(
          key: const ValueKey('group-plan-participants-submit'),
          onPressed: eligible.isEmpty ? null : _submit,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(widget.requireEffectiveFrom ? 'Применить' : 'Продолжить'),
        ),
      ],
    );
  }

  Widget _memberCard(GroupScheduleMemberOption member) {
    final scheme = Theme.of(context).colorScheme;
    final selectedSubscription = _selected[member.studentId];
    final selected = selectedSubscription != null;
    final subscriptions = [...member.subscriptions];
    if (selected &&
        !subscriptions.any(
          (subscription) =>
              subscription['id']?.toString() == selectedSubscription,
        )) {
      subscriptions.insert(0, {
        'id': selectedSubscription,
        'package_name': 'Текущий абонемент',
      });
    }
    return Container(
      key: ValueKey('group-plan-member-${member.studentId}'),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: selected ? AppColor.goldLine : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: selected,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(member.label),
            subtitle: member.hasSubscription
                ? null
                : const Text('Нет активного абонемента'),
            onChanged: member.hasSubscription
                ? (value) {
                    setState(() {
                      _error = null;
                      if (value == true) {
                        _selected[member.studentId] = _firstSubscriptionId(
                          member,
                        )!;
                      } else {
                        _selected.remove(member.studentId);
                      }
                    });
                  }
                : null,
          ),
          if (selected) ...[
            const SizedBox(height: AppSpace.xs),
            DropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: ValueKey('group-plan-subscription-${member.studentId}'),
              initialValue: selectedSubscription,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Абонемент'),
              items: [
                for (final subscription in subscriptions)
                  DropdownMenuItem<String>(
                    value: subscription['id']?.toString(),
                    child: Text(
                      _subscriptionLabel(subscription),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selected[member.studentId] = value;
                  _error = null;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  String _subscriptionLabel(Map<String, dynamic> subscription) {
    final name =
        (subscription['package_name'] ??
                subscription['packageName'] ??
                subscription['type'] ??
                'Абонемент')
            .toString();
    final total = _asInt(
      subscription['lessons_total'] ?? subscription['lessonsTotal'],
    );
    final used = _asInt(
      subscription['lessons_used'] ?? subscription['lessonsUsed'],
    );
    if (total == null) return name;
    final remaining = (total - (used ?? 0)).clamp(0, total);
    return '$name · осталось $remaining из $total';
  }

  int? _asInt(Object? value) {
    if (value == null) return null;
    return value is num ? value.toInt() : int.tryParse(value.toString());
  }
}
