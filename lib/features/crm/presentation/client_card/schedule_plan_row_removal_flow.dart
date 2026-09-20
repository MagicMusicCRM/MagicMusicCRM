import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface_kind.dart';
import 'package:magic_music_crm/core/widgets/magic_picker.dart';

const schedulePlanRowRemovalMessages = <String, String>{
  'SCHEDULE_PLAN_VERSION_STALE':
      'Расписание уже изменилось. Я обновил данные — проверьте строку ещё раз.',
  'SCHEDULE_PLAN_ROW_PREVIEW_INVALID':
      'Состав занятий изменился. Повторите предварительную проверку.',
  'SCHEDULE_PLAN_ROW_HAS_NO_FUTURE_BOUNDARY':
      'Укажите дату, с которой строка перестаёт действовать.',
};

String? schedulePlanRowRemovalMessage(String? code) =>
    schedulePlanRowRemovalMessages[code];

class SchedulePlanRowRemovalFlow {
  const SchedulePlanRowRemovalFlow({
    required this.service,
    required this.onInvalidated,
  });

  final MagicCrmService service;
  final Future<void> Function() onInvalidated;

  Future<bool> remove(
    BuildContext context, {
    required SchedulePlan plan,
    required SchedulePlanRow row,
  }) async {
    final removed = await showMagicAdaptiveSurface<bool>(
      context,
      kind: AppSurfaceKind.confirmation,
      title: 'Удалить строку',
      subtitle: '${plan.title} · ${_weekday(row.weekday)} ${row.beginTime}',
      icon: Icons.delete_outline_rounded,
      builder: (_) => SchedulePlanRowRemovalForm(
        service: service,
        plan: plan,
        row: row,
        onInvalidated: onInvalidated,
      ),
    );
    return removed == true;
  }
}

class SchedulePlanRowRemovalForm extends StatefulWidget {
  const SchedulePlanRowRemovalForm({
    super.key,
    required this.service,
    required this.plan,
    required this.row,
    required this.onInvalidated,
  });

  final MagicCrmService service;
  final SchedulePlan plan;
  final SchedulePlanRow row;
  final Future<void> Function() onInvalidated;

  @override
  State<SchedulePlanRowRemovalForm> createState() =>
      _SchedulePlanRowRemovalFormState();
}

class _SchedulePlanRowRemovalFormState
    extends State<SchedulePlanRowRemovalForm> {
  late final TextEditingController _reason;
  _SchedulePlanRowRemovalPreview? _preview;
  DateTime? _effectiveFrom;
  MagicMutationIdentity? _identity;
  bool _confirmed = false;
  bool _dateRecoveryEnabled = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reason = TextEditingController();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _invalidatePreview() {
    if (_preview == null && !_confirmed && _error == null) return;
    setState(() {
      _preview = null;
      _confirmed = false;
      _identity = null;
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final current = _effectiveFrom ?? DateTime.tryParse(widget.row.validFrom);
    if (current == null || _loading) return;
    final picked = await showMagicDatePicker(
      context: context,
      initialDate: DateUtils.dateOnly(current),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null ||
        (_effectiveFrom != null && DateUtils.isSameDay(picked, current))) {
      return;
    }
    setState(() {
      _effectiveFrom = DateUtils.dateOnly(picked);
      _preview = null;
      _confirmed = false;
      _identity = null;
      _dateRecoveryEnabled = false;
      _error = null;
    });
  }

  Future<void> _previewRemoval() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Укажите причину удаления строки.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.service.previewSchedulePlanRowRemoval(
        widget.plan.id,
        widget.row.id,
        expectedVersion: widget.plan.version,
        effectiveFrom: _effectiveFrom == null
            ? null
            : _apiDate(_effectiveFrom!),
        reasonText: reason,
      );
      final preview = _SchedulePlanRowRemovalPreview.fromMap(response);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _effectiveFrom = preview.effectiveFrom;
        _confirmed = false;
        _dateRecoveryEnabled = false;
        _identity = MagicMutationIdentity.create('schedule-plan-row-remove');
      });
    } catch (error) {
      await _handleError(error, previewInvalidated: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _commit() async {
    final preview = _preview;
    final effectiveFrom = _effectiveFrom;
    if (preview == null || effectiveFrom == null || !_confirmed) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.service.removeSchedulePlanRow(
        widget.plan.id,
        widget.row.id,
        identity: _identity ??= MagicMutationIdentity.create(
          'schedule-plan-row-remove',
        ),
        expectedVersion: widget.plan.version,
        effectiveFrom: _apiDate(effectiveFrom),
        reasonText: _reason.text,
        previewToken: preview.previewToken,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      await _handleError(error, previewInvalidated: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleError(
    Object error, {
    required bool previewInvalidated,
  }) async {
    final code = _errorCode(error);
    final mapped = schedulePlanRowRemovalMessage(code);
    final stale = code == 'SCHEDULE_PLAN_VERSION_STALE';
    final refresh = stale || code == 'SCHEDULE_PLAN_ROW_PREVIEW_INVALID';
    if (refresh) await widget.onInvalidated();
    if (!mounted) return;
    if (stale) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _error =
          mapped ??
          userErrorMessage(
            error,
            fallback: 'Не удалось удалить строку расписания.',
          );
      if (previewInvalidated) {
        _preview = null;
        _confirmed = false;
        _identity = null;
      }
      _dateRecoveryEnabled = code == 'SCHEDULE_PLAN_ROW_HAS_NO_FUTURE_BOUNDARY';
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const Key('schedule-plan-row-removal-date'),
          onTap: preview != null || _dateRecoveryEnabled ? _pickDate : null,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Не действует с'),
            child: Text(
              _effectiveFrom == null
                  ? 'Определит сервер при проверке'
                  : 'С ${DateFormat('dd.MM.yyyy').format(_effectiveFrom!)}',
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          key: const Key('schedule-plan-row-removal-reason'),
          controller: _reason,
          enabled: !_loading,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Причина',
            hintText: 'Причина сохранится в истории изменений',
          ),
          onChanged: (_) => _invalidatePreview(),
        ),
        if (preview != null) ...[
          const SizedBox(height: AppSpace.sm),
          _ImpactCard(preview: preview),
          const SizedBox(height: AppSpace.sm),
          CheckboxListTile(
            key: const Key('schedule-plan-row-removal-confirm'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _confirmed,
            onChanged: _loading
                ? null
                : (value) => setState(() => _confirmed = value == true),
            title: const Text(
              'Подтверждаю удаление строки и отмену указанных занятий',
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            _error!,
            key: const Key('schedule-plan-row-removal-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_loading) ...[
          const SizedBox(height: AppSpace.sm),
          const LinearProgressIndicator(color: AppColor.gold),
        ],
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
                key: const Key('schedule-plan-row-removal-submit'),
                onPressed: _loading || (preview != null && !_confirmed)
                    ? null
                    : (preview == null ? _previewRemoval : _commit),
                style: preview == null
                    ? null
                    : FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                child: Text(preview == null ? 'Проверить' : 'Удалить строку'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ImpactCard extends StatelessWidget {
  const _ImpactCard({required this.preview});

  final _SchedulePlanRowRemovalPreview preview;

  @override
  Widget build(BuildContext context) {
    final impact = preview.impact;
    return Container(
      key: const Key('schedule-plan-row-removal-impact'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.warning.withValues(alpha: 0.12),
        border: Border.all(color: AppColor.warning),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Будет отменено будущих занятий: ${impact.futureUnfinishedLessons}',
          ),
          Text(
            'Освободится активных резервов: ${impact.activeReservationsToRelease}',
          ),
          Text(
            'Завершённых занятий сохранится: ${impact.terminalLessonsPreserved}',
          ),
          Text(
            'Изменённых занятий сохранится: ${impact.changedLessonsPreserved}',
          ),
          const SizedBox(height: AppSpace.xs),
          const Text(
            'История проведённых занятий сохранится',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          if (impact.endsPlan)
            const Text(
              'Это последняя действующая строка. Расписание будет завершено.',
            ),
        ],
      ),
    );
  }
}

class _SchedulePlanRowRemovalPreview {
  const _SchedulePlanRowRemovalPreview({
    required this.effectiveFrom,
    required this.impact,
    required this.previewToken,
  });

  factory _SchedulePlanRowRemovalPreview.fromMap(Map<String, dynamic> map) {
    final effectiveFrom = DateTime.tryParse(
      map['effectiveFrom']?.toString() ?? '',
    );
    final rawImpact = map['impact'];
    final previewToken = map['previewToken'];
    final canConfirm = map['canConfirm'];
    final confirmRequired = map['confirmRequired'];
    if (effectiveFrom == null ||
        rawImpact is! Map ||
        previewToken is! String ||
        previewToken.trim().isEmpty ||
        canConfirm is! bool ||
        confirmRequired is! bool ||
        !canConfirm ||
        !confirmRequired) {
      throw const FormatException('Invalid schedule plan row removal preview');
    }
    return _SchedulePlanRowRemovalPreview(
      effectiveFrom: DateUtils.dateOnly(effectiveFrom),
      impact: _SchedulePlanRowRemovalImpact.fromMap(
        Map<String, dynamic>.from(rawImpact),
      ),
      previewToken: previewToken,
    );
  }

  final DateTime effectiveFrom;
  final _SchedulePlanRowRemovalImpact impact;
  final String previewToken;
}

class _SchedulePlanRowRemovalImpact {
  const _SchedulePlanRowRemovalImpact({
    required this.futureUnfinishedLessons,
    required this.terminalLessonsPreserved,
    required this.changedLessonsPreserved,
    required this.activeReservationsToRelease,
    required this.endsPlan,
  });

  factory _SchedulePlanRowRemovalImpact.fromMap(Map<String, dynamic> map) {
    final endsPlan = map['endsPlan'];
    if (endsPlan is! bool) {
      throw const FormatException('Invalid schedule plan row removal impact');
    }
    return _SchedulePlanRowRemovalImpact(
      futureUnfinishedLessons: _requiredImpactCount(
        map,
        'futureUnfinishedLessons',
      ),
      terminalLessonsPreserved: _requiredImpactCount(
        map,
        'terminalLessonsPreserved',
      ),
      changedLessonsPreserved: _requiredImpactCount(
        map,
        'changedLessonsPreserved',
      ),
      activeReservationsToRelease: _requiredImpactCount(
        map,
        'activeReservationsToRelease',
      ),
      endsPlan: endsPlan,
    );
  }

  final int futureUnfinishedLessons;
  final int terminalLessonsPreserved;
  final int changedLessonsPreserved;
  final int activeReservationsToRelease;
  final bool endsPlan;
}

int _requiredImpactCount(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value is! int || value < 0) {
    throw const FormatException('Invalid schedule plan row removal impact');
  }
  return value;
}

String? _errorCode(Object error) {
  if (error is! MagicApiException || error.details is! Map) return null;
  return (error.details! as Map)['code']?.toString();
}

String _apiDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

String _weekday(int weekday) =>
    const {
      1: 'понедельник',
      2: 'вторник',
      3: 'среда',
      4: 'четверг',
      5: 'пятница',
      6: 'суббота',
      7: 'воскресенье',
    }[weekday] ??
    'день';
