import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_toast.dart';

class ScheduleReferenceSettings extends ConsumerStatefulWidget {
  const ScheduleReferenceSettings({super.key, required this.canEdit});

  final bool canEdit;

  @override
  ConsumerState<ScheduleReferenceSettings> createState() =>
      _ScheduleReferenceSettingsState();
}

class _ScheduleReferenceSettingsState
    extends ConsumerState<ScheduleReferenceSettings> {
  static const _dayNames = <int, String>{
    1: 'Понедельник',
    2: 'Вторник',
    3: 'Среда',
    4: 'Четверг',
    5: 'Пятница',
    6: 'Суббота',
    7: 'Воскресенье',
  };

  List<Map<String, dynamic>> _branches = const [];
  List<Map<String, dynamic>> _teachers = const [];
  String? _branchId;
  String? _teacherId;
  int _branchVersion = 1;
  int _teacherVersion = 1;
  String _timezone = 'Europe/Moscow';
  final Map<int, Map<String, dynamic>> _weekly = {};
  final List<Map<String, dynamic>> _exceptions = [];
  final Map<String, Map<String, dynamic>> _assignments = {};
  final Map<int, Map<String, dynamic>> _recurring = {};
  final List<Map<String, dynamic>> _extraRecurring = [];
  final List<Map<String, dynamic>> _intervals = [];
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadCatalogs();
  }

  Future<void> _loadCatalogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final result = await Future.wait([
        crm.listBranches(limit: 100),
        crm.listTeachers(limit: 100),
      ]);
      if (!mounted) return;
      _branches = result[0];
      _teachers = result[1];
      _branchId = _validSelection(_branchId, _branches);
      _teacherId = _validSelection(_teacherId, _teachers);
      if (_branchId != null && _teacherId != null) {
        await _loadReference();
      } else {
        setState(() => _loading = false);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  String? _validSelection(String? selected, List<Map<String, dynamic>> items) {
    if (items.any((item) => item['id']?.toString() == selected)) {
      return selected;
    }
    return items.isEmpty ? null : items.first['id']?.toString();
  }

  Future<void> _loadReference() async {
    final branchId = _branchId;
    final teacherId = _teacherId;
    if (branchId == null || teacherId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(magicCrmServiceProvider)
          .getScheduleReference(branchId: branchId, teacherId: teacherId);
      if (!mounted || branchId != _branchId || teacherId != _teacherId) return;
      final branch = data['branch'] as Map<String, dynamic>? ?? const {};
      final teacher = data['teacher'] as Map<String, dynamic>? ?? const {};
      _weekly
        ..clear()
        ..addEntries(
          _maps(
            branch['weekly'],
          ).map((row) => MapEntry((row['weekday'] as num).toInt(), {...row})),
        );
      _exceptions
        ..clear()
        ..addAll(_maps(branch['exceptions']).map((row) => {...row}));
      _assignments.clear();
      for (final row in _maps(teacher['assignments'])) {
        final branchId = row['branchId']?.toString();
        if (branchId != null) _assignments[branchId] = {...row};
      }
      _recurring.clear();
      _extraRecurring.clear();
      _intervals.clear();
      for (final row in _maps(teacher['availability'])) {
        if (row['kind'] == 'recurring' && row['weekday'] is num) {
          final weekday = (row['weekday'] as num).toInt();
          if (_recurring.containsKey(weekday)) {
            _extraRecurring.add({...row});
          } else {
            _recurring[weekday] = {...row};
          }
        } else if (row['kind'] == 'interval') {
          _intervals.add({...row});
        }
      }
      setState(() {
        _branchVersion = (branch['version'] as num?)?.toInt() ?? 1;
        _teacherVersion = (teacher['version'] as num?)?.toInt() ?? 1;
        _timezone = branch['timezone']?.toString() ?? 'Europe/Moscow';
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map<String, dynamic>>().toList()
      : const [];

  String _teacherName(Map<String, dynamic> teacher) {
    final profile = teacher['profiles'] as Map<String, dynamic>?;
    final name = [
      profile?['last_name'] ?? teacher['last_name'],
      profile?['first_name'] ?? teacher['first_name'],
    ].where((part) => part?.toString().trim().isNotEmpty == true).join(' ');
    return name.isEmpty ? 'Преподаватель' : name;
  }

  Future<String?> _pickTime(String current) async {
    final parts = current.split(':').map(int.tryParse).toList();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: parts.firstOrNull ?? 9,
        minute: parts.elementAtOrNull(1) ?? 0,
      ),
    );
    return picked == null
        ? null
        : '${picked.hour.toString().padLeft(2, '0')}:'
              '${picked.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _saveBranchHours() => _save(() async {
    final result = await ref
        .read(magicCrmServiceProvider)
        .replaceBranchHours(
          branchId: _branchId!,
          expectedVersion: _branchVersion,
          timezone: _timezone,
          weekly: [
            for (final entry in _weekly.entries)
              {
                'weekday': entry.key,
                'open': entry.value['open'],
                'close': entry.value['close'],
              },
          ],
          exceptions: [for (final row in _exceptions) _clean(row)],
        );
    _branchVersion = (result['version'] as num?)?.toInt() ?? _branchVersion;
  }, 'Рабочие часы сохранены');

  Future<void> _saveAssignments() => _save(() async {
    final result = await ref
        .read(magicCrmServiceProvider)
        .replaceTeacherBranches(
          teacherId: _teacherId!,
          expectedVersion: _teacherVersion,
          assignments: [
            for (final row in _assignments.values)
              _clean({...row, 'activeFrom': row['activeFrom'] ?? '1970-01-01'}),
          ],
        );
    _teacherVersion = (result['version'] as num?)?.toInt() ?? _teacherVersion;
  }, 'Назначения сохранены');

  Future<void> _saveAvailability() => _save(() async {
    final result = await ref
        .read(magicCrmServiceProvider)
        .replaceTeacherAvailability(
          teacherId: _teacherId!,
          expectedVersion: _teacherVersion,
          rules: [
            for (final row in _recurring.values) _clean(row),
            for (final row in _extraRecurring) _clean(row),
            for (final row in _intervals) _clean(row),
          ],
        );
    _teacherVersion = (result['version'] as num?)?.toInt() ?? _teacherVersion;
  }, 'Доступность сохранена');

  Map<String, dynamic> _clean(Map<String, dynamic> source) => {
    for (final entry in source.entries)
      if (entry.value != null) entry.key: entry.value,
  };

  Future<void> _save(Future<void> Function() action, String success) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) MagicToast.show(context, success);
    } catch (error) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось сохранить',
          detail: '$error',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить настройки расписания.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadCatalogs,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Расписание', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              Text(
                widget.canEdit
                    ? 'Часы филиала, назначения и доступность преподавателей'
                    : 'Только просмотр. Редактирование выдаёт директор.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              _selectors(),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _branchId == null || _teacherId == null
              ? const Center(
                  child: Text('Нужны хотя бы один филиал и преподаватель.'),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    _hoursCard(),
                    const SizedBox(height: 12),
                    _assignmentsCard(),
                    const SizedBox(height: 12),
                    _availabilityCard(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _selectors() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        final width = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        final fields = [
          SearchablePickerField(
            key: ValueKey('settings-branch-$_branchId'),
            label: 'Филиал',
            selectedId: _branchId,
            isNullable: false,
            items: [
              for (final branch in _branches)
                SearchableSelectItem(
                  id: branch['id'].toString(),
                  label: branch['name']?.toString() ?? 'Филиал',
                ),
            ],
            onSelected: (item) {
              final value = item?.id;
              if (value == null || value == _branchId) return;
              _branchId = value;
              _loadReference();
            },
          ),
          SearchablePickerField(
            key: ValueKey('settings-teacher-$_teacherId'),
            label: 'Преподаватель',
            hintText: 'Введите имя или ФИО преподавателя',
            selectedId: _teacherId,
            isNullable: false,
            items: [
              for (final teacher in _teachers)
                SearchableSelectItem(
                  id: teacher['id'].toString(),
                  label: _teacherName(teacher),
                ),
            ],
            onSelected: (item) {
              final value = item?.id;
              if (value == null || value == _teacherId) return;
              _teacherId = value;
              _loadReference();
            },
          ),
        ];
        return compact
            ? Column(
                children: [fields[0], const SizedBox(height: 12), fields[1]],
              )
            : Row(
                children: [
                  SizedBox(width: width, child: fields[0]),
                  const SizedBox(width: 12),
                  SizedBox(width: width, child: fields[1]),
                ],
              );
      },
    );
  }

  Widget _hoursCard() {
    return _card(
      title: 'Рабочие часы филиала',
      action: widget.canEdit
          ? FilledButton(
              onPressed: _saving || _weekly.isEmpty ? null : _saveBranchHours,
              child: const Text('Сохранить'),
            )
          : null,
      children: [
        for (final day in _dayNames.entries)
          _timeRow(
            label: day.value,
            value: _weekly[day.key],
            onEnabled: (enabled) => setState(() {
              if (enabled) {
                _weekly[day.key] = {
                  'weekday': day.key,
                  'open': '09:00',
                  'close': '21:00',
                };
              } else {
                _weekly.remove(day.key);
              }
            }),
            onTime: (key, value) =>
                setState(() => _weekly[day.key]![key] = value),
          ),
        const Divider(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Исключения',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (widget.canEdit)
              TextButton.icon(
                onPressed: _addBranchException,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить'),
              ),
          ],
        ),
        for (final row in _exceptions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(row['date']?.toString() ?? ''),
            subtitle: Text(
              row['closed'] == true
                  ? 'Закрыто${_reason(row)}'
                  : '${row['open']}–${row['close']}${_reason(row)}',
            ),
            trailing: widget.canEdit
                ? IconButton(
                    tooltip: 'Удалить исключение',
                    onPressed: () => setState(() => _exceptions.remove(row)),
                    icon: const Icon(Icons.delete_outline_rounded),
                  )
                : null,
          ),
      ],
    );
  }

  String _reason(Map<String, dynamic> row) {
    final value = row['reason']?.toString().trim() ?? '';
    return value.isEmpty ? '' : ' · $value';
  }

  Widget _assignmentsCard() {
    return _card(
      title: 'Филиалы преподавателя',
      action: widget.canEdit
          ? FilledButton(
              onPressed: _saving || _assignments.isEmpty
                  ? null
                  : _saveAssignments,
              child: const Text('Сохранить'),
            )
          : null,
      children: [
        for (final branch in _branches)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _assignments.containsKey(branch['id']?.toString()),
            title: Text(branch['name']?.toString() ?? 'Филиал'),
            onChanged: !widget.canEdit
                ? null
                : (value) => setState(() {
                    final id = branch['id'].toString();
                    if (value == true) {
                      _assignments[id] = {
                        'branchId': id,
                        'activeFrom': '1970-01-01',
                      };
                    } else {
                      _assignments.remove(id);
                    }
                  }),
          ),
      ],
    );
  }

  Widget _availabilityCard() {
    final canEdit = widget.canEdit && _extraRecurring.isEmpty;
    return _card(
      title: 'Доступность преподавателя',
      action: canEdit
          ? FilledButton(
              onPressed: _saving ? null : _saveAvailability,
              child: const Text('Сохранить'),
            )
          : null,
      children: [
        if (_extraRecurring.isNotEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock_outline_rounded),
            title: Text('Сложная схема доступности'),
            subtitle: Text(
              'На один день задано несколько правил. '
              'Редактор не изменяет их, чтобы не потерять данные.',
            ),
          ),
        for (final day in _dayNames.entries)
          _timeRow(
            label: day.value,
            value: _recurring[day.key],
            editable: canEdit,
            onEnabled: (enabled) => setState(() {
              if (enabled) {
                _recurring[day.key] = {
                  'kind': 'recurring',
                  'available': true,
                  'timezone': _timezone,
                  'weekday': day.key,
                  'localStart': '09:00',
                  'localEnd': '21:00',
                  'validFrom': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                };
              } else {
                _recurring.remove(day.key);
              }
            }),
            startKey: 'localStart',
            endKey: 'localEnd',
            onTime: (key, value) =>
                setState(() => _recurring[day.key]![key] = value),
          ),
        const Divider(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Недоступность по датам',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (canEdit)
              TextButton.icon(
                onPressed: _addUnavailableInterval,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить'),
              ),
          ],
        ),
        for (final row in _intervals)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_intervalLabel(row)),
            subtitle: row['reason'] == null
                ? null
                : Text(row['reason'].toString()),
            trailing: canEdit
                ? IconButton(
                    tooltip: 'Удалить период',
                    onPressed: () => setState(() => _intervals.remove(row)),
                    icon: const Icon(Icons.delete_outline_rounded),
                  )
                : null,
          ),
      ],
    );
  }

  String _intervalLabel(Map<String, dynamic> row) {
    final start = DateTime.tryParse(
      row['startsAt']?.toString() ?? '',
    )?.toLocal();
    final end = DateTime.tryParse(row['endsAt']?.toString() ?? '')?.toLocal();
    if (start == null) return 'Период недоступности';
    final format = DateFormat('dd.MM.yyyy HH:mm');
    return end == null
        ? 'с ${format.format(start)}'
        : '${format.format(start)} — ${format.format(end)}';
  }

  Widget _timeRow({
    required String label,
    required Map<String, dynamic>? value,
    required ValueChanged<bool> onEnabled,
    required void Function(String key, String value) onTime,
    bool? editable,
    String startKey = 'open',
    String endKey = 'close',
  }) {
    final enabled = value != null;
    final canEdit = editable ?? widget.canEdit;
    return Row(
      children: [
        Semantics(
          label: '$label: ${enabled ? 'включено' : 'выключено'}',
          toggled: enabled,
          child: ExcludeSemantics(
            child: Switch(
              value: enabled,
              onChanged: canEdit ? onEnabled : null,
            ),
          ),
        ),
        Expanded(child: Text(label)),
        if (enabled) ...[
          TextButton(
            onPressed: !canEdit
                ? null
                : () async {
                    final next = await _pickTime(
                      value[startKey]?.toString() ?? '09:00',
                    );
                    if (next != null) onTime(startKey, next);
                  },
            child: Text(value[startKey]?.toString() ?? '09:00'),
          ),
          const Text('—'),
          TextButton(
            onPressed: !canEdit
                ? null
                : () async {
                    final next = await _pickTime(
                      value[endKey]?.toString() ?? '21:00',
                    );
                    if (next != null) onTime(endKey, next);
                  },
            child: Text(value[endKey]?.toString() ?? '21:00'),
          ),
        ],
      ],
    );
  }

  Widget _card({
    required String title,
    required List<Widget> children,
    Widget? action,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Future<void> _addBranchException() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final closed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Исключение'),
        content: const Text('Филиал закрыт весь день?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Особые часы'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Закрыт'),
          ),
        ],
      ),
    );
    if (closed == null || !mounted) return;
    String? open;
    String? close;
    if (!closed) {
      open = await _pickTime('09:00');
      if (open == null || !mounted) return;
      close = await _pickTime('21:00');
      if (close == null) return;
    }
    final row = <String, dynamic>{
      'date': DateFormat('yyyy-MM-dd').format(date),
      'closed': closed,
      'open': ?open,
      'close': ?close,
    };
    setState(() {
      _exceptions.removeWhere((item) => item['date'] == row['date']);
      _exceptions.add(row);
      _exceptions.sort(
        (a, b) => a['date'].toString().compareTo(b['date'].toString()),
      );
    });
  }

  Future<void> _addUnavailableInterval() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final startText = await _pickTime('09:00');
    if (startText == null || !mounted) return;
    final endText = await _pickTime('18:00');
    if (endText == null) return;
    DateTime combine(String time) {
      final parts = time.split(':').map(int.parse).toList();
      return DateTime(
        date.year,
        date.month,
        date.day,
        parts[0],
        parts[1],
      ).toUtc();
    }

    setState(() {
      _intervals.add({
        'kind': 'interval',
        'available': false,
        'startsAt': combine(startText).toIso8601String(),
        'endsAt': combine(endText).toIso8601String(),
      });
    });
  }
}
