import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

Future<bool?> showPersonLifecycleDialog(
  BuildContext context, {
  required String personType,
  required String personId,
  required String personName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _PersonLifecycleDialog(
      personType: personType,
      personId: personId,
      personName: personName,
    ),
  );
}

class _PersonLifecycleDialog extends ConsumerStatefulWidget {
  const _PersonLifecycleDialog({
    required this.personType,
    required this.personId,
    required this.personName,
  });

  final String personType;
  final String personId;
  final String personName;

  @override
  ConsumerState<_PersonLifecycleDialog> createState() =>
      _PersonLifecycleDialogState();
}

class _PersonLifecycleDialogState
    extends ConsumerState<_PersonLifecycleDialog> {
  final _reason = TextEditingController();
  Map<String, dynamic>? _preview;
  bool _loading = true;
  bool _saving = false;
  String? _error;

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

  Future<void> _load() async {
    try {
      final preview = await ref
          .read(magicCrmServiceProvider)
          .previewPersonLifecycle(
            personType: widget.personType,
            personId: widget.personId,
          );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _submit() async {
    final preview = _preview;
    final person = preview?['person'];
    if (preview == null || person is! Map) return;
    final reason = _reason.text.trim();
    if (reason.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите причину не короче 5 символов.')),
      );
      return;
    }
    final version = (person['version'] as num?)?.toInt();
    if (version == null) return;
    final restore = person['lifecycleState'] == 'archived';
    setState(() => _saving = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .changePersonLifecycle(
            personType: widget.personType,
            personId: widget.personId,
            restore: restore,
            expectedVersion: version,
            reasonText: reason,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось выполнить действие: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final person = preview?['person'];
    final personMap = person is Map ? person : const <dynamic, dynamic>{};
    final restore = personMap['lifecycleState'] == 'archived';
    final blockers = preview?['blockers'] is List
        ? preview!['blockers'] as List
        : const [];
    final impact = preview?['impact'] is Map
        ? preview!['impact'] as Map
        : const <dynamic, dynamic>{};
    final account = preview?['account'] is Map
        ? preview!['account'] as Map
        : const <dynamic, dynamic>{};

    return AlertDialog(
      title: Text(
        restore ? 'Восстановить карточку' : 'Отключить и архивировать',
      ),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Не удалось загрузить последствия: $_error'),
                  const SizedBox(height: AppSpace.md),
                  TextButton(onPressed: _load, child: const Text('Повторить')),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.personName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpace.md),
                    if (!restore) ...[
                      const Text(
                        'Будут одновременно закрыты назначения по филиалам, отключён вход, отозваны активные сессии и персональные разрешения. История сохраняется.',
                      ),
                      const SizedBox(height: AppSpace.md),
                    ],
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        _ImpactChip(
                          label: 'Сессии',
                          value: account['activeSessions'],
                        ),
                        _ImpactChip(
                          label: 'Разрешения',
                          value: account['activeOverrides'],
                        ),
                        _ImpactChip(
                          label: 'Занятия',
                          value: impact['futureLessons'],
                        ),
                        _ImpactChip(
                          label: 'Серии',
                          value: impact['activeSeries'],
                        ),
                        _ImpactChip(
                          label: 'Группы',
                          value: impact['activeGroups'],
                        ),
                        _ImpactChip(
                          label: 'Задачи',
                          value: impact['openTasks'],
                        ),
                        _ImpactChip(
                          label: 'Лиды',
                          value: impact['activeLeads'],
                        ),
                      ],
                    ),
                    if (blockers.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.md),
                      Container(
                        padding: const EdgeInsets.all(AppSpace.md),
                        decoration: BoxDecoration(
                          color: AppColor.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          border: Border.all(
                            color: AppColor.danger.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Сначала устраните блокирующие связи:'),
                            for (final blocker in blockers)
                              if (blocker is Map)
                                Text(
                                  '• ${blocker['message']} (${blocker['count']})',
                                ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpace.lg),
                    TextField(
                      controller: _reason,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: restore
                            ? 'Причина восстановления *'
                            : 'Причина отключения *',
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed:
              _saving ||
                  _loading ||
                  _error != null ||
                  (!restore && blockers.isNotEmpty)
              ? null
              : _submit,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(restore ? 'Восстановить' : 'Отключить и архивировать'),
        ),
      ],
    );
  }
}

class _ImpactChip extends StatelessWidget {
  const _ImpactChip({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final number = value is num
        ? (value as num).toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    return Chip(label: Text('$label: $number'));
  }
}
