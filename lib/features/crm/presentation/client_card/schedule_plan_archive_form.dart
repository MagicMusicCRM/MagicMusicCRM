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
  });
  final MagicCrmService service;
  final SchedulePlan plan;
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
      final response = await widget.service.previewSchedulePlanArchive(
        widget.plan.id,
      );
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

  Future<void> _archive() async {
    if (_busy ||
        _preview?['canConfirm'] != true ||
        !validateAndRevealForm(_form)) {
      return;
    }
    _identity ??= MagicMutationIdentity.create('schedule-plan-archive');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.archiveSchedulePlan(
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
          fallback: 'Не удалось архивировать расписание. Повторите попытку.',
        );
        if (error is MagicApiException &&
            (error.statusCode == 409 || error.statusCode == 422)) {
          _preview = null;
          _identity = null;
        }
      });
      revealFormFeedback(context, const Key('schedule-archive-error'));
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
          const Text(
            'Архивирование скроет отменённые занятия из ленты и уберёт серию из основного списка. История сохранится в разделе «Архив».',
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
                key: const Key('schedule-archive-reason'),
                controller: _reason,
                readOnly: _busy || _identity != null,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Причина архивирования',
                ),
                validator: (value) => value?.trim().isNotEmpty == true
                    ? null
                    : 'Укажите причину архивирования',
              ),
              const SizedBox(height: AppSpace.md),
              FilledButton.icon(
                key: const Key('schedule-archive-confirm'),
                onPressed: _busy ? null : _archive,
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Подтвердить архивирование'),
              ),
            ],
          ],
          if (_error != null)
            Padding(
              key: const Key('schedule-archive-error'),
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
