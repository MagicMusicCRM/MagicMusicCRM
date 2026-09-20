import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/form_feedback.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

class SchedulePlanArchiveForm extends StatefulWidget {
  const SchedulePlanArchiveForm({
    super.key,
    required this.service,
    required this.plan,
    this.restore = false,
  });
  final MagicCrmService service;
  final SchedulePlan plan;
  final bool restore;
  @override
  State<SchedulePlanArchiveForm> createState() =>
      _SchedulePlanArchiveFormState();
}

class _SchedulePlanArchiveFormState extends State<SchedulePlanArchiveForm> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  Map<String, dynamic>? _preview;
  MagicMutationIdentity? _identity;
  String? _error;
  bool _busy = false;
  String get _action => widget.restore ? 'restore' : 'archive';

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
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _identity = null;
      _preview = null;
    });
    try {
      final response = await (widget.restore
          ? widget.service.previewSchedulePlanRestore(widget.plan.id)
          : widget.service.previewSchedulePlanArchive(widget.plan.id));
      if (mounted) setState(() => _preview = response);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userErrorMessage(
            error,
            fallback: 'Не удалось проверить расписание.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy ||
        _preview?['canConfirm'] != true ||
        !validateAndRevealForm(_form)) {
      return;
    }
    _identity ??= MagicMutationIdentity.create('schedule-plan-$_action');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final command = widget.restore
          ? widget.service.restoreSchedulePlan
          : widget.service.archiveSchedulePlan;
      await command(
        widget.plan.id,
        identity: _identity!,
        expectedVersion: (_preview!['version'] as num).toInt(),
        impactFingerprint: _preview!['impactFingerprint'] as String,
        reasonText: _reason.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userErrorMessage(
          error,
          fallback: widget.restore
              ? 'Не удалось восстановить расписание. Повторите попытку.'
              : 'Не удалось архивировать расписание. Повторите попытку.',
        );
        if (error is MagicApiException &&
            (error.statusCode == 409 || error.statusCode == 422)) {
          _preview = null;
          _identity = null;
        }
      });
      revealFormFeedback(context, Key('schedule-$_action-error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blockers = (_preview?['blockers'] as List? ?? const [])
        .cast<String>();
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.plan.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            widget.restore
                ? 'Расписание вернётся в завершённые, а его отменённые занятия — в ленту. Занятия не возобновятся; оплаты и история останутся без изменений.'
                : 'Архивирование скроет отменённые занятия из ленты и уберёт серию из основного списка. История сохранится в разделе «Архив».',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_preview != null) ...[
            const SizedBox(height: AppSpace.md),
            Text('Занятий в серии: ${_preview!['lessonCount']}'),
            for (final blocker in blockers)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Text(
                  blocker,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_preview!['canConfirm'] == true) ...[
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: Key('schedule-$_action-reason'),
                controller: _reason,
                readOnly: _busy || _identity != null,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: widget.restore
                      ? 'Причина восстановления'
                      : 'Причина архивирования',
                ),
                validator: (value) => value?.trim().isNotEmpty == true
                    ? null
                    : widget.restore
                    ? 'Укажите причину восстановления'
                    : 'Укажите причину архивирования',
              ),
              const SizedBox(height: AppSpace.md),
              FilledButton.icon(
                key: Key('schedule-$_action-confirm'),
                onPressed: _busy ? null : _submit,
                icon: Icon(
                  widget.restore
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                label: Text(
                  widget.restore
                      ? 'Подтвердить восстановление'
                      : 'Подтвердить архивирование',
                ),
              ),
            ],
          ],
          if (_error != null)
            Padding(
              key: Key('schedule-$_action-error'),
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!_busy && _preview == null)
            TextButton(
              onPressed: _load,
              child: const Text('Повторить проверку'),
            ),
        ],
      ),
    );
  }
}
