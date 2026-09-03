import 'package:magic_music_crm/core/widgets/magic_picker.dart';
import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import 'lifecycle_dialog_content.dart';

class GroupLifecycleDialog extends ConsumerStatefulWidget {
  const GroupLifecycleDialog({super.key, required this.group});

  final Map<String, dynamic> group;

  @override
  ConsumerState<GroupLifecycleDialog> createState() =>
      _GroupLifecycleDialogState();
}

class _GroupLifecycleDialogState extends ConsumerState<GroupLifecycleDialog> {
  final _reason = TextEditingController();
  Map<String, dynamic>? _preview;
  List<Map<String, dynamic>> _history = const [];
  String? _error;
  bool _loading = true;
  bool _saving = false;
  DateTime _effectiveDate = DateTime.now();

  String get _id => widget.group['id']?.toString() ?? '';
  bool get _archived =>
      (_preview?['group']?['lifecycleState'] ??
          widget.group['lifecycle_state']) ==
      'archived';
  int get _version {
    final raw = _preview?['group']?['version'] ?? widget.group['version'];
    return raw is num ? raw.toInt() : int.tryParse('$raw') ?? 1;
  }

  List<Map<String, dynamic>> get _blockers {
    final raw = _preview?['blockers'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load({String? errorAfterLoad}) async {
    if (_id.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final values = await Future.wait([
        crm.previewGroupArchive(_id),
        crm.listGroupLifecycleHistory(_id),
      ]);
      if (!mounted) return;
      setState(() {
        _preview = values[0] as Map<String, dynamic>;
        _history = values[1] as List<Map<String, dynamic>>;
        _error = errorAfterLoad;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userErrorMessage(
          error,
          fallback: 'Не удалось проверить группу.',
        );
        _loading = false;
      });
    }
  }

  Future<void> _commit() async {
    final reason = _reason.text.trim();
    if (reason.length < 3) {
      setState(() => _error = 'Укажите понятную причину (минимум 3 символа).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      if (_archived) {
        await crm.restoreGroup(
          _id,
          expectedVersion: _version,
          reasonText: reason,
          effectiveDate: _dateKey(_effectiveDate),
        );
      } else {
        await crm.archiveGroup(
          _id,
          expectedVersion: _version,
          reasonText: reason,
          effectiveDate: _dateKey(_effectiveDate),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = userErrorMessage(
          error,
          fallback: 'Не удалось изменить группу.',
        );
      });
      await _load(
        errorAfterLoad: userErrorMessage(
          error,
          fallback: 'Не удалось изменить группу.',
        ),
      );
    }
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickEffectiveDate() async {
    final selected = await showMagicDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'Дата действия',
    );
    if (selected != null && mounted) {
      setState(() => _effectiveDate = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = widget.group['name']?.toString() ?? 'Группа';
    final canRestore = _preview?['canRestore'] == true;
    final canArchive = _preview?['canArchive'] == true;
    final canCommit = _archived ? canRestore : canArchive;
    final operational = _preview?['impact']?['operational'];
    final members = operational is Map
        ? ((operational['activeMembers'] as num?)?.toInt() ?? 0)
        : 0;
    final preserved = _preview?['impact']?['preservedHistory'];
    final preservedFacts = preserved is Map
        ? <MapEntry<String, dynamic>>[
            MapEntry('Записей состава', preserved['memberships']),
            MapEntry('Всего занятий', preserved['lessons']),
            MapEntry('Завершённых занятий', preserved['completedLessons']),
            MapEntry('Завершённых серий', preserved['endedSeries']),
            MapEntry('Завершённых планов', preserved['endedPlans']),
          ].where((item) {
            final value = item.value;
            return value is num && value.toInt() > 0;
          }).toList()
        : const <MapEntry<String, dynamic>>[];
    return LifecycleDialogContent(
      title: _archived ? 'Восстановить группу' : 'Завершить группу',
      width: 640,
      loading: _loading,
      saving: _saving,
      archived: _archived,
      canCommit: canCommit,
      commitLabel: _archived ? 'Восстановить' : 'Завершить',
      reasonLabel: _archived
          ? 'Причина восстановления *'
          : 'Причина завершения *',
      reasonController: _reason,
      effectiveDate: _dateKey(_effectiveDate),
      onPickEffectiveDate: _pickEffectiveDate,
      history: _history,
      archivedHistoryLabel: 'Группа завершена',
      restoredHistoryLabel: 'Группа восстановлена',
      preservedFacts: preservedFacts,
      error: _error,
      onCommit: _commit,
      details: [
        Text('«$name»', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          _archived
              ? 'Группа снова станет доступна для состава и нового расписания. История завершений сохранится.'
              : 'Группа уйдёт из рабочих списков. Состав ($members) и все финансовые факты останутся без изменений.',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        if (_blockers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Сначала завершите активные сценарии',
            style: TextStyle(color: colors.error, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final blocker in _blockers)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.error_outline_rounded, color: colors.error),
              title: Text('${blocker['label']}: ${blocker['count']}'),
              subtitle: Text(blocker['remediation']?.toString() ?? ''),
            ),
        ] else ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.verified_outlined, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _archived
                      ? 'Филиал, аудитория и преподаватель активны. Группу можно восстановить.'
                      : 'Будущих занятий и активных планов нет. Группу можно завершить.',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
