import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

class RoomLifecycleDialog extends ConsumerStatefulWidget {
  const RoomLifecycleDialog({super.key, required this.room});

  final Map<String, dynamic> room;

  @override
  ConsumerState<RoomLifecycleDialog> createState() =>
      _RoomLifecycleDialogState();
}

class _RoomLifecycleDialogState extends ConsumerState<RoomLifecycleDialog> {
  final _reason = TextEditingController();
  Map<String, dynamic>? _preview;
  List<Map<String, dynamic>> _history = const [];
  String? _error;
  bool _loading = true;
  bool _saving = false;
  DateTime _effectiveDate = DateTime.now();

  String get _id => widget.room['id']?.toString() ?? '';
  bool get _archived =>
      (_preview?['room']?['lifecycleState'] ??
          widget.room['lifecycle_state']) ==
      'archived';
  int get _version {
    final raw = _preview?['room']?['version'] ?? widget.room['version'];
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
        crm.previewRoomArchive(_id),
        crm.listRoomLifecycleHistory(_id),
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
        _error = '$error';
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
        await crm.restoreRoom(
          _id,
          expectedVersion: _version,
          reasonText: reason,
          effectiveDate: _dateKey(_effectiveDate),
        );
      } else {
        await crm.archiveRoom(
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
        _error = '$error';
      });
      await _load(errorAfterLoad: '$error');
    }
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickEffectiveDate() async {
    final selected = await showDatePicker(
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
    final name = widget.room['name']?.toString() ?? 'Аудитория';
    final canRestore = _preview?['canRestore'] == true;
    final canArchive = _preview?['canArchive'] == true;
    final canCommit = _archived ? canRestore : canArchive;
    final preserved = _preview?['impact']?['preservedHistory'];
    final preservedFacts = preserved is Map
        ? <MapEntry<String, dynamic>>[
            MapEntry('Все занятия', preserved['lessons']),
            MapEntry('Завершённые занятия', preserved['completedLessons']),
            MapEntry('Завершённые серии', preserved['endedSeries']),
            MapEntry('Завершённые планы', preserved['endedPlans']),
          ].where((item) {
            final value = item.value;
            return value is num && value.toInt() > 0;
          }).toList()
        : const <MapEntry<String, dynamic>>[];
    return AlertDialog(
      title: Text(
        _archived ? 'Восстановить аудиторию' : 'Архивировать аудиторию',
      ),
      content: SizedBox(
        width: 620,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '«$name»',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _archived
                          ? 'Аудитория снова появится в рабочих списках. Журнал архивации сохранится.'
                          : 'Аудитория исчезнет из выбора для новых занятий. История расписания не удаляется.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    if (_blockers.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Сначала устраните блокеры',
                        style: TextStyle(
                          color: colors.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final blocker in _blockers)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.error_outline_rounded,
                            color: colors.error,
                          ),
                          title: Text(
                            '${blocker['label']}: ${blocker['count']}',
                          ),
                          subtitle: Text(
                            blocker['remediation']?.toString() ?? '',
                          ),
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
                                  ? 'Филиал активен — аудиторию можно восстановить.'
                                  : 'Активных связей нет — аудиторию можно безопасно архивировать.',
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (preservedFacts.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'История останется без изменений',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final fact in preservedFacts)
                            Chip(label: Text('${fact.key}: ${fact.value}')),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _pickEffectiveDate,
                      icon: const Icon(Icons.event_outlined),
                      label: Text('Дата действия: ${_dateKey(_effectiveDate)}'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _reason,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: InputDecoration(
                        labelText: _archived
                            ? 'Причина восстановления *'
                            : 'Причина архивации *',
                        hintText: 'Причина останется в журнале изменений',
                      ),
                    ),
                    if (_history.isNotEmpty)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text('История (${_history.length})'),
                        children: [
                          for (final item in _history.take(10))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                item['toState'] == 'archived'
                                    ? Icons.archive_outlined
                                    : Icons.restore_rounded,
                              ),
                              title: Text(
                                item['toState'] == 'archived'
                                    ? 'Аудитория архивирована'
                                    : 'Аудитория восстановлена',
                              ),
                              subtitle: Text(
                                '${item['reasonText']?.toString() ?? '—'}'
                                '${item['effectiveDate'] == null ? '' : ' • ${item['effectiveDate']}'}',
                              ),
                            ),
                        ],
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: colors.error)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _saving || _loading || !canCommit ? null : _commit,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _archived ? Icons.restore_rounded : Icons.archive_outlined,
                ),
          label: Text(_archived ? 'Восстановить' : 'В архив'),
        ),
      ],
    );
  }
}
