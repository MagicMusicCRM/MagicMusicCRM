import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/utilization_data_source.dart';

class UtilizationPanel extends ConsumerStatefulWidget {
  const UtilizationPanel({
    super.key,
    required this.filter,
    required this.onOpenEntity,
    this.reloadToken = 0,
  });

  final DashboardFilter filter;
  final ValueChanged<EntityLink> onOpenEntity;
  final int reloadToken;

  @override
  ConsumerState<UtilizationPanel> createState() => _UtilizationPanelState();
}

class _UtilizationPanelState extends ConsumerState<UtilizationPanel> {
  Map<String, dynamic>? _report;
  Object? _error;
  bool _loading = true;
  bool _showRooms = false;
  int _operation = 0;

  UtilizationDataSource get _source => ref.read(utilizationDataSourceProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant UtilizationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter ||
        oldWidget.reloadToken != widget.reloadToken) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final operation = ++_operation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await _source.load(widget.filter);
      if (!mounted || operation != _operation) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || operation != _operation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows =
        ((_report?[_showRooms ? 'rooms' : 'teachers'] as List?) ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.lg,
            AppSpace.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.school_outlined),
                  label: Text('Преподаватели'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.meeting_room_outlined),
                  label: Text('Помещения'),
                ),
              ],
              selected: {_showRooms},
              onSelectionChanged: (selection) =>
                  setState(() => _showRooms = selection.first),
            ),
          ),
        ),
        Expanded(
          child: _loading && _report == null
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _report == null
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: rows.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text(
                                'Нет данных по выбранному периоду и филиалу',
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpace.lg,
                            AppSpace.sm,
                            AppSpace.lg,
                            AppSpace.xl,
                          ),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpace.sm),
                          itemBuilder: (context, index) => _UtilizationRow(
                            row: rows[index],
                            onOpenEntity: widget.onOpenEntity,
                          ),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _errorState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Не удалось загрузить загрузку преподавателей и помещений'),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton(onPressed: _load, child: const Text('Повторить')),
      ],
    ),
  );
}

class _UtilizationRow extends StatelessWidget {
  const _UtilizationRow({required this.row, required this.onOpenEntity});

  final Map<String, dynamic> row;
  final ValueChanged<EntityLink> onOpenEntity;

  @override
  Widget build(BuildContext context) {
    final id = row['id']?.toString() ?? '';
    final linkRaw = row['entityLink'];
    final link = linkRaw is Map
        ? EntityLink.fromJson(Map<String, dynamic>.from(linkRaw))
        : null;
    final available = _minutes(row['availableMinutes']);
    final kind = row['kind']?.toString() ?? 'teacher';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row['name']?.toString() ??
                        (kind == 'room' ? 'Помещение' : 'Преподаватель'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: Key('utilization-open-$id'),
                  onPressed: link?.isSupported == true
                      ? () => onOpenEntity(link!)
                      : null,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(kind == 'room' ? 'К расписанию' : 'Карточка'),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                _MetricChip(
                  label: 'План',
                  value: _percent(row['plannedUtilization']),
                ),
                _MetricChip(
                  label: 'Факт',
                  value: _percent(row['actualUtilization']),
                ),
                _MetricChip(label: 'Доступно', value: available),
                _MetricChip(
                  label: 'Запланировано',
                  value: _minutes(row['plannedMinutes']),
                ),
                _MetricChip(
                  label: 'Проведено',
                  value: _minutes(row['actualMinutes']),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Занятий: план ${_integer(row['plannedLessons'])}, '
              'факт ${_integer(row['actualLessons'])} · '
              'Посещений: ${_integer(row['attendances'])}',
              style: const TextStyle(color: AppColor.text2),
            ),
            if (row['plannedUtilization'] == null ||
                row['actualUtilization'] == null) ...[
              const SizedBox(height: AppSpace.xs),
              const Text(
                'Нет данных',
                style: TextStyle(
                  color: AppColor.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'Для расчёта нужно рабочее окно филиала.',
                style: TextStyle(color: AppColor.text2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Chip(label: Text('$label: $value'));
}

String _percent(Object? value) {
  if (value is! num) return 'Нет данных';
  return '${(value * 100).round()}%';
}

String _minutes(Object? value) {
  final minutes = _integer(value);
  if (minutes == 0 && value == null) return 'Нет данных';
  final hours = minutes ~/ 60;
  final rest = minutes.remainder(60);
  if (hours == 0) return '$minutes мин';
  if (rest == 0) return '$hours ч';
  return '$hours ч $rest мин';
}

int _integer(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;
