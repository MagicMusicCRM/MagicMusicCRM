import 'package:magic_music_crm/core/widgets/magic_picker.dart';
import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import 'lifecycle_dialog_content.dart';

class BranchLifecycleDialog extends ConsumerStatefulWidget {
  const BranchLifecycleDialog({super.key, required this.branch});

  final Map<String, dynamic> branch;

  @override
  ConsumerState<BranchLifecycleDialog> createState() =>
      _BranchLifecycleDialogState();
}

class _BranchLifecycleDialogState extends ConsumerState<BranchLifecycleDialog> {
  final _reason = TextEditingController();
  Map<String, dynamic>? _preview;
  List<Map<String, dynamic>> _history = const [];
  String? _error;
  bool _loading = true;
  bool _saving = false;
  DateTime _effectiveDate = DateTime.now();

  String get _id => widget.branch['id']?.toString() ?? '';
  bool get _archived =>
      (_preview?['branch']?['lifecycleState'] ??
          widget.branch['lifecycle_state']) ==
      'archived';
  int get _version {
    final raw = _preview?['branch']?['version'] ?? widget.branch['version'];
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
        crm.previewBranchClose(_id),
        crm.listBranchLifecycleHistory(_id),
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
          fallback: 'Не удалось проверить филиал.',
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
        await crm.restoreBranch(
          _id,
          expectedVersion: _version,
          reasonText: reason,
          effectiveDate: _dateKey(_effectiveDate),
        );
      } else {
        await crm.closeBranch(
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
          fallback: 'Не удалось изменить филиал.',
        );
      });
      await _load(
        errorAfterLoad: userErrorMessage(
          error,
          fallback: 'Не удалось изменить филиал.',
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
    final name = widget.branch['name']?.toString() ?? 'Филиал';
    final canClose = _preview?['canClose'] == true;
    final preserved = _preview?['impact']?['preservedHistory'];
    final preservedFacts = preserved is Map
        ? <MapEntry<String, dynamic>>[
            MapEntry('Платежи', preserved['payments']),
            MapEntry('Расходы', preserved['expenses']),
            MapEntry('Занятия', preserved['lessons']),
            MapEntry('Чаты', preserved['chats']),
            MapEntry('Ревизии настроек', preserved['configurationRevisions']),
          ].where((item) {
            final value = item.value;
            return value is num && value.toInt() > 0;
          }).toList()
        : const <MapEntry<String, dynamic>>[];
    return LifecycleDialogContent(
      title: _archived ? 'Восстановить филиал' : 'Закрыть филиал',
      loading: _loading,
      saving: _saving,
      archived: _archived,
      canCommit: _archived || canClose,
      commitLabel: _archived ? 'Восстановить' : 'Закрыть филиал',
      reasonLabel: _archived
          ? 'Причина восстановления *'
          : 'Причина закрытия *',
      reasonController: _reason,
      effectiveDate: _dateKey(_effectiveDate),
      onPickEffectiveDate: _pickEffectiveDate,
      history: _history,
      archivedHistoryLabel: 'Филиал закрыт',
      restoredHistoryLabel: 'Филиал восстановлен',
      preservedFacts: preservedFacts,
      error: _error,
      onCommit: _commit,
      details: [
        Text('«$name»', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          _archived
              ? 'Филиал снова появится в рабочих списках. История закрытия сохранится.'
              : 'Филиал будет перемещён в архив. Финансы, завершённые занятия, аудит и ревизии настроек не удаляются.',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        if (!_archived && _blockers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Сначала устраните блокеры',
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
        ],
        if (!_archived && _blockers.isEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.verified_outlined, color: colors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Активных связей нет. Филиал можно закрыть.'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
