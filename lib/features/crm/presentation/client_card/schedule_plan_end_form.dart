import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

class SchedulePlanEndForm extends StatefulWidget {
  const SchedulePlanEndForm({
    super.key,
    required this.service,
    required this.plan,
  });

  final MagicCrmService service;
  final SchedulePlan plan;

  @override
  State<SchedulePlanEndForm> createState() => _SchedulePlanEndFormState();
}

class _SchedulePlanEndFormState extends State<SchedulePlanEndForm> {
  late final TextEditingController _reason;
  late DateTime _lastDate;
  SchedulePlanEndPreview? _preview;
  MagicMutationIdentity? _identity;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reason = TextEditingController();
    final today = DateUtils.dateOnly(DateTime.now());
    final starts = DateTime.tryParse(widget.plan.activeFrom) ?? today;
    _lastDate = starts.isAfter(today) ? starts : today;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final starts = DateTime.tryParse(widget.plan.activeFrom) ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastDate,
      firstDate: starts.isAfter(today) ? starts : today,
      lastDate: DateUtils.dateOnly(
        DateTime.now().add(const Duration(days: 730)),
      ),
    );
    if (picked != null) _invalidate(() => _lastDate = picked);
  }

  void _invalidate(VoidCallback change) {
    setState(() {
      change();
      _preview = null;
      _identity = null;
      _error = null;
    });
  }

  Future<void> _calculate() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Укажите причину завершения.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await widget.service.previewSchedulePlanEnd(
        widget.plan.id,
        expectedVersion: widget.plan.version,
        lastDate: _apiDate(_lastDate),
        reasonText: reason,
      );
      if (mounted) setState(() => _preview = preview);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userErrorMessage(
            error,
            fallback: 'Не удалось рассчитать завершение расписания.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _commit() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.service.endSchedulePlan(
        widget.plan.id,
        identity: _identity ??= MagicMutationIdentity.create(
          'schedule-plan-end',
        ),
        expectedVersion: widget.plan.version,
        lastDate: _apiDate(_lastDate),
        reasonText: _reason.text,
        previewToken: preview.previewToken,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userErrorMessage(
            error,
            fallback: 'Не удалось завершить расписание.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final impact = _preview?.impact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const Key('schedule-plan-end-date'),
          onTap: _loading ? null : _pickDate,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Последняя дата'),
            child: Text(DateFormat('dd.MM.yyyy').format(_lastDate)),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          key: const Key('schedule-plan-end-reason'),
          controller: _reason,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Причина',
            hintText: 'Причина будет видна сотрудникам в истории',
          ),
          onChanged: (_) => _invalidate(() {}),
        ),
        if (impact != null) ...[
          Container(
            key: const Key('schedule-plan-end-impact'),
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: AppColor.warning.withValues(alpha: 0.12),
              border: Border.all(color: AppColor.warning),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Text(
              'Будут отменены: ${impact['futureUnsettledLessons'] ?? 0}\n'
              'Освободятся резервы: ${impact['activeReservations'] ?? 0} '
              '(${impact['reservedUnits'] ?? '0.00'} ч)\n'
              'Сохранятся завершённые: ${impact['preservedTerminalLessons'] ?? 0}',
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (_loading) const LinearProgressIndicator(color: AppColor.gold),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _loading
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: FilledButton(
                key: const Key('schedule-plan-end-submit'),
                onPressed: _loading
                    ? null
                    : (_preview == null ? _calculate : _commit),
                style: _preview == null
                    ? null
                    : FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                child: Text(_preview == null ? 'Рассчитать' : 'Завершить'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _apiDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
