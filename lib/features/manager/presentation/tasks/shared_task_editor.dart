import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

Future<bool?> showSharedTaskEditor(
  BuildContext context, {
  required SharedTasksDataSource dataSource,
  Map<String, dynamic>? task,
  EntityLink? linkedEntity,
  VoidCallback? onSaved,
}) async {
  List<SharedTaskAudienceOption> options = const [];
  try {
    options = await dataSource.audienceOptions();
  } catch (_) {
    // The all-branches audience remains usable without directory data.
  }
  if (!context.mounted) return null;
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.selection,
    title: task == null ? 'Новая задача' : 'Изменить задачу',
    subtitle: 'Срок, получатели и напоминание',
    icon: task == null ? Icons.add_task_rounded : Icons.edit_note_rounded,
    builder: (_) => SharedTaskEditor(
      dataSource: dataSource,
      audienceOptions: options,
      task: task,
      linkedEntity: linkedEntity,
      onSaved: onSaved,
      embedded: true,
    ),
  );
}

Future<void> showCreateSharedTask(
  BuildContext context,
  WidgetRef ref, {
  EntityLink? linkedEntity,
  VoidCallback? onSaved,
}) async {
  await showSharedTaskEditor(
    context,
    dataSource: MagicCrmSharedTasksDataSource.fromWidgetRef(ref),
    linkedEntity: linkedEntity,
    onSaved: onSaved,
  );
}

String _taskSavedMessage(Map<String, dynamic> result, {required bool created}) {
  final summary = result['recipientSummary'];
  final total = summary is Map<String, dynamic>
      ? summary['totalRecipients']
      : null;
  final action = created ? 'Задача создана.' : 'Задача сохранена.';
  return total is num
      ? '$action Получателей сейчас: ${total.toInt()}.'
      : action;
}

class _MutationAttempt {
  const _MutationAttempt({
    required this.payloadFingerprint,
    required this.identity,
  });

  final String payloadFingerprint;
  final MagicMutationIdentity identity;
}

String _payloadFingerprint(Map<String, dynamic> payload) =>
    jsonEncode(_canonicalJson(payload));

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalJson(value[key])};
  }
  if (value is Iterable) {
    return value.map(_canonicalJson).toList(growable: false);
  }
  return value;
}

Map<String, dynamic> _immutablePayload(Map<String, dynamic> payload) =>
    Map<String, dynamic>.unmodifiable(
      payload.map((key, value) => MapEntry(key, _immutableJson(value))),
    );

Object? _immutableJson(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map(
        (key, nested) => MapEntry(key.toString(), _immutableJson(nested)),
      ),
    );
  }
  if (value is Iterable) {
    return List<Object?>.unmodifiable(value.map(_immutableJson));
  }
  return value;
}

class SharedTaskEditor extends StatefulWidget {
  const SharedTaskEditor({
    super.key,
    required this.dataSource,
    this.audienceOptions = const [],
    this.task,
    this.linkedEntity,
    this.audiencePreview,
    this.onSaved,
    this.embedded = false,
  });

  final SharedTasksDataSource dataSource;
  final List<SharedTaskAudienceOption> audienceOptions;
  final Map<String, dynamic>? task;
  final EntityLink? linkedEntity;
  final SharedTaskAudiencePreviewLoader? audiencePreview;
  final VoidCallback? onSaved;
  final bool embedded;

  @override
  State<SharedTaskEditor> createState() => _SharedTaskEditorState();
}

class _SharedTaskEditorState extends State<SharedTaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late bool _allDay;
  late DateTime _start;
  late String _priority;
  DateTime? _end;
  String _audienceType = 'allBranches';
  String? _targetId;
  final List<Map<String, dynamic>> _audiences = [];
  List<Map<String, dynamic>> _existingReminders = const [];
  bool _reminder = false;
  DateTime? _reminderAt;
  bool _reminderCustomized = false;
  Map<String, dynamic>? _preview;
  Object? _previewError;
  bool _previewLoading = false;
  int _previewGeneration = 0;
  bool _saving = false;
  bool _terminalSuccess = false;
  bool _savedCallbackAttempted = false;
  Object? _saveError;
  _MutationAttempt? _attempt;

  SharedTaskAudiencePreviewLoader get _audiencePreview =>
      widget.audiencePreview ?? widget.dataSource.previewAudience;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _title = TextEditingController(text: task?['title']?.toString() ?? '');
    _body = TextEditingController(text: task?['body']?.toString() ?? '');
    _allDay = task?['allDay'] != false;
    final parsedStart = DateTime.tryParse(
      task?['startAt']?.toString() ?? '',
    )?.toLocal();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _start = parsedStart == null
        ? DateTime(tomorrow.year, tomorrow.month, tomorrow.day)
        : (_allDay ? _dateOnly(parsedStart) : parsedStart);
    _priority = task?['priority']?.toString() ?? 'medium';
    _end = DateTime.tryParse(task?['endAt']?.toString() ?? '')?.toLocal();
    final existing = task?['audiences'];
    if (existing is List) {
      _audiences.addAll(existing.whereType<Map<String, dynamic>>());
    }
    if (_audiences.isEmpty) {
      _audiences.add({'type': 'allBranches'});
    }
    final existingReminders = task?['reminders'];
    if (existingReminders is List) {
      _existingReminders = existingReminders
          .whereType<Map<String, dynamic>>()
          .map((item) => {'dueAt': item['dueAt'], 'channel': item['channel']})
          .toList();
    }
    for (final reminder in _existingReminders) {
      if (reminder['channel'] != 'in_app') continue;
      _reminder = true;
      _reminderAt = DateTime.tryParse(
        reminder['dueAt']?.toString() ?? '',
      )?.toLocal();
      if (_reminderAt != null) {
        _reminderCustomized = true;
        break;
      }
    }
    if (_reminder && _reminderAt == null) {
      _reminderAt = _defaultReminderAt();
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refreshAudiencePreview(),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.audienceOptions
        .where((option) => option.type == _audienceType)
        .toList();
    final content = SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('shared-task-title'),
              controller: _title,
              decoration: const InputDecoration(labelText: 'Название'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: const Key('shared-task-priority'),
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Приоритет'),
              items: const [
                DropdownMenuItem(value: 'high', child: Text('Высокий')),
                DropdownMenuItem(value: 'medium', child: Text('Обычный')),
                DropdownMenuItem(value: 'low', child: Text('Низкий')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _priority = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Описание'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('На весь день'),
              value: _allDay,
              onChanged: _setAllDay,
            ),
            _DateTimeButton(
              label: 'Начало',
              value: _start,
              dateOnly: _allDay,
              onChanged: _setStart,
            ),
            if (!_allDay)
              _DateTimeButton(
                label: 'Окончание',
                value: _end ?? _start.add(const Duration(hours: 1)),
                onChanged: (value) => setState(() => _end = value),
              ),
            if (!_hasValidInterval) ...[
              const SizedBox(height: AppSpace.xs),
              Text(
                'Окончание должно быть позже начала.',
                key: const Key('shared-task-interval-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const Divider(height: 28),
            Text('Кому', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'user', label: Text('Сотрудники')),
                ButtonSegment(value: 'branch', label: Text('Один филиал')),
                ButtonSegment(value: 'allBranches', label: Text('Вся школа')),
              ],
              selected: {_audienceType},
              onSelectionChanged: (selection) => setState(() {
                _audienceType = selection.first;
                _targetId = null;
              }),
            ),
            if (_audienceType != 'allBranches') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                menuMaxHeight: 256,
                key: const Key('shared-task-audience-target'),
                initialValue: _targetId,
                decoration: InputDecoration(
                  labelText: _audienceType == 'user' ? 'Сотрудник' : 'Филиал',
                ),
                items: options
                    .map(
                      (option) => DropdownMenuItem(
                        value: option.id,
                        child: Text(option.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _targetId = value),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _canAddAudience ? _addAudience : null,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Добавить получателя'),
            ),
            Wrap(
              spacing: 6,
              children: _audiences
                  .map(
                    (audience) => InputChip(
                      label: Text(_audienceLabel(audience)),
                      onDeleted: _audiences.length == 1
                          ? null
                          : () => _removeAudience(audience),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpace.sm),
            _buildAudiencePreview(context),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Напомнить в приложении'),
              subtitle: const Text('Можно выбрать точные дату и время'),
              value: _reminder,
              onChanged: _setReminder,
            ),
            if (_reminder)
              _DateTimeButton(
                key: const Key('shared-task-reminder-at'),
                label: 'Напомнить',
                value: _reminderAt ?? _defaultReminderAt(),
                onChanged: (value) => setState(() {
                  _reminderAt = value;
                  _reminderCustomized = true;
                }),
              ),
            if (_saveError != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                'Не удалось сохранить задачу. Повторите.',
                key: const Key('shared-task-save-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
    final actions = <Widget>[
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _canSubmit ? _submit : null,
        child: Text(widget.task == null ? 'Создать' : 'Сохранить'),
      ),
    ];
    if (widget.embedded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.sm),
                Expanded(child: actions[i]),
              ],
            ],
          ),
        ],
      );
    }
    return AlertDialog(
      title: Text(widget.task == null ? 'Новая задача' : 'Изменить задачу'),
      content: content,
      actions: actions,
    );
  }

  bool get _canAddAudience =>
      _audienceType == 'allBranches' || _targetId != null;

  bool get _canSubmit =>
      !_saving &&
      _title.text.trim().isNotEmpty &&
      _hasValidInterval &&
      !_terminalSuccess &&
      !_previewLoading &&
      _previewError == null &&
      _preview != null;

  bool get _hasValidInterval => _allDay || (_end?.isAfter(_start) ?? false);

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime _defaultReminderAt() => _allDay
      ? DateTime(_start.year, _start.month, _start.day, 9)
      : _start.subtract(const Duration(hours: 1));

  void _setAllDay(bool value) {
    setState(() {
      if (_allDay == value) return;
      _allDay = value;
      if (value) {
        _start = _dateOnly(_start);
        _end = null;
      } else {
        _start = DateTime(_start.year, _start.month, _start.day, 9);
        _end = _start.add(const Duration(hours: 1));
      }
      if (_reminder && !_reminderCustomized) {
        _reminderAt = _defaultReminderAt();
      }
    });
  }

  void _setStart(DateTime value) {
    setState(() {
      _start = _allDay ? _dateOnly(value) : value;
      if (_reminder && !_reminderCustomized) {
        _reminderAt = _defaultReminderAt();
      }
    });
  }

  void _setReminder(bool value) {
    setState(() {
      _reminder = value;
      if (value) {
        _reminderAt ??= _defaultReminderAt();
      } else {
        _reminderAt = null;
        _reminderCustomized = false;
      }
    });
  }

  void _addAudience() {
    final audience = {
      'type': _audienceType,
      if (_audienceType != 'allBranches') 'targetId': _targetId,
    };
    final key = '${audience['type']}:${audience['targetId'] ?? ''}';
    if (_audiences.any(
      (item) => '${item['type']}:${item['targetId'] ?? ''}' == key,
    )) {
      return;
    }
    setState(() {
      if (_audienceType == 'allBranches') {
        _audiences
          ..clear()
          ..add(audience);
      } else {
        _audiences.removeWhere((item) => item['type'] == 'allBranches');
        _audiences.add(audience);
      }
    });
    _refreshAudiencePreview();
  }

  void _removeAudience(Map<String, dynamic> audience) {
    setState(() => _audiences.remove(audience));
    _refreshAudiencePreview();
  }

  String _audienceLabel(Map<String, dynamic> audience) {
    if (audience['type'] == 'allBranches') return 'Вся школа';
    final id = audience['targetId']?.toString();
    for (final option in widget.audienceOptions) {
      if (option.id == id) return option.label;
    }
    return audience['type'] == 'user' ? 'Сотрудник' : 'Филиал';
  }

  void _refreshAudiencePreview() {
    final loader = _audiencePreview;
    if (!mounted) return;
    final generation = ++_previewGeneration;
    setState(() {
      _previewLoading = true;
      _previewError = null;
      _preview = null;
    });
    loader(_audiences.map(Map<String, dynamic>.from).toList()).then(
      (preview) {
        if (!mounted || generation != _previewGeneration) return;
        setState(() {
          _preview = preview;
          _previewLoading = false;
        });
      },
      onError: (Object error) {
        if (!mounted || generation != _previewGeneration) return;
        setState(() {
          _previewError = error;
          _previewLoading = false;
        });
      },
    );
  }

  Widget _buildAudiencePreview(BuildContext context) {
    return Container(
      key: const Key('shared-task-audience-preview'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Кто получит задачу',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpace.xs),
          if (_previewLoading)
            const LinearProgressIndicator(
              key: Key('shared-task-audience-preview-loading'),
            )
          else if (_previewError != null) ...[
            const Text(
              'Не удалось проверить получателей. Задача не будет отправлена '
              'без точного расчёта.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _refreshAudiencePreview,
                child: const Text('Повторить расчёт'),
              ),
            ),
          ] else if (_preview case final preview?) ...[
            Text(
              'Сейчас получат: ${preview['totalRecipients'] ?? 0}',
              key: const Key('shared-task-recipient-total'),
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpace.xs),
            for (final selector in _previewSelectors(preview))
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      selector['mode'] == 'fixed'
                          ? Icons.person_outline_rounded
                          : Icons.account_tree_outlined,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        '${selector['label'] ?? 'Получатель'}: '
                        '${selector['mode'] == 'fixed' ? 'лично' : 'динамический состав'}; '
                        'сейчас ${selector['currentRecipientCount'] ?? 0}',
                      ),
                    ),
                  ],
                ),
              ),
            if (preview['hasDynamicMembership'] == true) ...[
              const SizedBox(height: AppSpace.sm),
              const Text(
                'Для филиала и всей школы состав обновляется автоматически: '
                'задачу увидят сотрудники, которые входят туда на момент работы.',
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _previewSelectors(Map<String, dynamic> preview) {
    final selectors = preview['selectors'];
    return selectors is List
        ? selectors.whereType<Map<String, dynamic>>().toList()
        : const [];
  }

  Future<void> _submit() async {
    if (_saving || _terminalSuccess) return;
    final payload = _immutablePayload(_payload());
    final fingerprint = _payloadFingerprint(payload);
    final created = widget.task == null;
    final previousAttempt = _attempt;
    final attempt = previousAttempt?.payloadFingerprint == fingerprint
        ? previousAttempt!
        : _MutationAttempt(
            payloadFingerprint: fingerprint,
            identity: MagicMutationIdentity.create(
              created ? 'shared-task-create' : 'shared-task-update',
            ),
          );
    _attempt = attempt;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    Map<String, dynamic> result;
    try {
      result = created
          ? await widget.dataSource.create(payload, attempt.identity)
          : await widget.dataSource.update(
              widget.task!['id'].toString(),
              payload,
              attempt.identity,
            );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error;
      });
      return;
    }

    _terminalSuccess = true;
    _saving = false;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!_savedCallbackAttempted) {
      _savedCallbackAttempted = true;
      try {
        widget.onSaved?.call();
      } catch (_) {
        // A consumer callback cannot turn a committed command into a retry.
      }
    }
    try {
      Navigator.pop(context, true);
    } catch (_) {
      // The server command has succeeded and must remain terminal.
    }
    try {
      messenger?.showSnackBar(
        SnackBar(content: Text(_taskSavedMessage(result, created: created))),
      );
    } catch (_) {
      // Presentation failure cannot make a committed command retryable.
    }
  }

  Map<String, dynamic> _payload() {
    final end = _allDay ? null : (_end ?? _start.add(const Duration(hours: 1)));
    final existingLink = widget.task?['linkedEntity'];
    final linkedEntity = widget.linkedEntity == null
        ? existingLink
        : {
            'type': widget.linkedEntity!.rawEntityType,
            'id': widget.linkedEntity!.entityId,
          };
    return {
      'title': _title.text.trim(),
      if (_body.text.trim().isNotEmpty) 'body': _body.text.trim(),
      'allDay': _allDay,
      'priority': _priority,
      'startAt': _start.toUtc().toIso8601String(),
      if (end != null) 'endAt': end.toUtc().toIso8601String(),
      'audiences': _audiences,
      'linkedEntity': ?linkedEntity,
      if (widget.task != null || _reminder || _existingReminders.isNotEmpty)
        'reminders': _reminderPayload(),
      if (widget.task != null) 'expectedVersion': widget.task!['version'],
    };
  }

  List<Map<String, dynamic>> _reminderPayload() {
    final dueAt = (_reminderAt ?? _defaultReminderAt())
        .toUtc()
        .toIso8601String();
    var replacedInApp = false;
    final result = <Map<String, dynamic>>[];
    for (final reminder in _existingReminders) {
      final channel = reminder['channel']?.toString();
      if (channel == null || channel.isEmpty) continue;
      if (channel == 'in_app') {
        if (_reminder && !replacedInApp) {
          result.add({'dueAt': dueAt, 'channel': channel});
          replacedInApp = true;
        }
        continue;
      }
      result.add({'dueAt': reminder['dueAt'], 'channel': channel});
    }
    if (_reminder && !replacedInApp) {
      result.add({'dueAt': dueAt, 'channel': 'in_app'});
    }
    return result;
  }
}

class _DateTimeButton extends StatelessWidget {
  const _DateTimeButton({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.dateOnly = false,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool dateOnly;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        DateFormat(dateOnly ? 'dd.MM.yyyy' : 'dd.MM.yyyy HH:mm').format(value),
      ),
      trailing: const Icon(Icons.calendar_month_outlined),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        if (date == null || !context.mounted) return;
        if (dateOnly) {
          onChanged(DateTime(date.year, date.month, date.day));
          return;
        }
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value),
        );
        if (time == null) return;
        onChanged(
          DateTime(date.year, date.month, date.day, time.hour, time.minute),
        );
      },
    );
  }
}
