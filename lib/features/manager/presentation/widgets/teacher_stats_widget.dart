import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';

/// KVA-238: отчёт «Статистика преподавателей» — учебные единицы (группа /
/// индивидуально с учеником / пробные), дни с часами, часы всего, ставка за
/// астр. час, начислено и оплачено за период. Клик по группе — drill-down:
/// «Ставка по данной группе» (процесс заказчика: в конце месяца пробные без
/// покупки вручную переводят в 0 — «входит в оклад»).
class TeacherStatsWidget extends ConsumerStatefulWidget {
  const TeacherStatsWidget({super.key});

  @override
  ConsumerState<TeacherStatsWidget> createState() => _TeacherStatsWidgetState();
}

class _TeacherStatsWidgetState extends ConsumerState<TeacherStatsWidget> {
  bool _loading = true;
  Object? _error;
  Map<String, dynamic> _report = const {};
  List<Map<String, dynamic>> _branches = const [];
  List<Map<String, dynamic>> _teachers = const [];

  late DateTime _from;
  late DateTime _to;
  String? _branchId;
  String? _teacherId;
  String? _unitType;

  final _money = NumberFormat('#,##0', 'ru');
  final _dayFmt = DateFormat('dd.MM');

  @override
  void initState() {
    super.initState();
    // Период по умолчанию — текущий месяц (закрытие месяца у заказчика).
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 1);
    _loadReferences();
    _loadReport();
  }

  Future<void> _loadReferences() async {
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final results = await Future.wait([
        crm.listBranches(limit: 100),
        crm.listTeachers(limit: 100),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = results[0];
        _teachers = results[1];
      });
    } catch (_) {
      // Фильтры-справочники не критичны для отчёта — молча оставляем пустыми.
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await ref
          .read(magicCrmServiceProvider)
          .getTeacherStatsReport(
            from: _from.toUtc().toIso8601String(),
            to: _to.toUtc().toIso8601String(),
            branchId: _branchId,
            teacherId: _teacherId,
            unitType: _unitType,
          );
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _pickPeriod() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(
        start: _from,
        end: _to.subtract(const Duration(days: 1)),
      ),
    );
    if (picked == null) return;
    setState(() {
      _from = picked.start;
      // Конец диапазона включительно → верхняя граница = следующий день.
      _to = picked.end.add(const Duration(days: 1));
    });
    await _loadReport();
  }

  Future<void> _editGroupRate(Map<String, dynamic> unit) async {
    final groupId = unit['groupId']?.toString();
    if (groupId == null || groupId.isEmpty) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _GroupRateDialog(
        groupId: groupId,
        groupName: unit['unitName']?.toString() ?? 'Группа',
        currentRate: unit['rate'] as num?,
      ),
    );
    if (saved == true) await _loadReport();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.all(12), child: _buildFilters()),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _pickPeriod,
          icon: const Icon(Icons.date_range_rounded, size: 18),
          label: Text(
            '${_dayFmt.format(_from)} – '
            '${_dayFmt.format(_to.subtract(const Duration(days: 1)))}',
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String?>(
            key: ValueKey('branch-$_branchId'),
            initialValue: _branchId,
            decoration: const InputDecoration(
              labelText: 'Филиал',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Все филиалы'),
              ),
              ..._branches.map(
                (branch) => DropdownMenuItem<String?>(
                  value: branch['id']?.toString(),
                  child: Text(
                    branch['name']?.toString() ?? 'Филиал',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() => _branchId = value);
              _loadReport();
            },
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            key: ValueKey('teacher-$_teacherId'),
            initialValue: _teacherId,
            decoration: const InputDecoration(
              labelText: 'Педагог',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Все педагоги'),
              ),
              ..._teachers.map((teacher) {
                final name =
                    '${teacher['first_name'] ?? ''} ${teacher['last_name'] ?? ''}'
                        .trim();
                return DropdownMenuItem<String?>(
                  value: teacher['id']?.toString(),
                  child: Text(
                    name.isEmpty ? 'Без имени' : name,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ],
            onChanged: (value) {
              setState(() => _teacherId = value);
              _loadReport();
            },
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String?>(
            key: ValueKey('unit-$_unitType'),
            initialValue: _unitType,
            decoration: const InputDecoration(
              labelText: 'Уч. единицы',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Все')),
              DropdownMenuItem<String?>(
                value: 'individual',
                child: Text('Индивидуальные'),
              ),
              DropdownMenuItem<String?>(
                value: 'group',
                child: Text('Групповые'),
              ),
              DropdownMenuItem<String?>(value: 'trial', child: Text('Пробные')),
            ],
            onChanged: (value) {
              setState(() => _unitType = value);
              _loadReport();
            },
          ),
        ),
        IconButton(
          tooltip: 'Обновить',
          onPressed: _loadReport,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGold),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Не удалось загрузить отчёт: $_error'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loadReport,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    final items = (_report['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (items.isEmpty) {
      return const Center(child: Text('Нет проведённых занятий за период'));
    }
    final totals = _report['totals'] as Map<String, dynamic>? ?? const {};
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        ...items.map(_buildTeacherCard),
        const SizedBox(height: 8),
        _buildTotals(totals),
      ],
    );
  }

  Widget _buildTeacherCard(Map<String, dynamic> item) {
    final units = (item['units'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item['teacherName']?.toString() ?? 'Без имени',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${_hours(item['hoursTotal'])} · '
                  'начислено ${_rub(item['accruedTotal'])} · '
                  'оплачено ${_rub(item['paidTotal'])}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...units.map(_buildUnitRow),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitRow(Map<String, dynamic> unit) {
    final isGroup = unit['unitType'] == 'group';
    final days = (unit['days'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((day) {
          final date = DateTime.tryParse(day['date']?.toString() ?? '');
          final label = date == null
              ? day['date'].toString()
              : _dayFmt.format(date);
          return '$label (${_hours(day['hours'])})';
        })
        .join(', ');
    final typeLabel = switch (unit['unitType']) {
      'group' => 'Группа',
      'trial' => 'Пробное',
      _ => 'Индивид.',
    };
    return InkWell(
      // Drill-down: ставка по группе редактируется кликом по строке.
      onTap: isGroup ? () => _editGroupRate(unit) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryGold.withAlpha(24),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(typeLabel, style: const TextStyle(fontSize: 11)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unit['unitName']?.toString() ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (days.isNotEmpty)
                    Text(
                      days,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_hours(unit['hoursTotal'])} × ${_rateLabel(unit['rate'])}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                Text(
                  _rub(unit['accruedTotal']),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (isGroup) ...[
              const SizedBox(width: 4),
              const Icon(Icons.edit_rounded, size: 14),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTotals(Map<String, dynamic> totals) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryGold.withAlpha(60)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('Итого', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text(
            '${_hours(totals['hoursTotal'])} · '
            'начислено ${_rub(totals['accruedTotal'])} · '
            'оплачено ${_rub(totals['paidTotal'])}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _rub(dynamic value) => '${_money.format(_num(value))} ₽';

  String _hours(dynamic value) {
    final hours = _num(value);
    final text = hours == hours.roundToDouble()
        ? hours.toStringAsFixed(0)
        : hours.toStringAsFixed(2);
    return '$text астр.ч.';
  }

  String _rateLabel(dynamic value) {
    final rate = _num(value);
    return rate == 0 ? 'оклад' : '${_money.format(rate)} ₽';
  }

  num _num(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// KVA-238: drill-down диалог «Ставка по данной группе».
class _GroupRateDialog extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;
  final num? currentRate;

  const _GroupRateDialog({
    required this.groupId,
    required this.groupName,
    this.currentRate,
  });

  @override
  ConsumerState<_GroupRateDialog> createState() => _GroupRateDialogState();
}

class _GroupRateDialogState extends ConsumerState<_GroupRateDialog> {
  num? _rate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rate = widget.currentRate;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .updateGroup(
            widget.groupId,
            teacherRate: _rate,
            setTeacherRate: true,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.groupName),
      content: SizedBox(
        width: 360,
        child: TeacherRateSelector(
          initialRate: widget.currentRate,
          allowInherit: true,
          label: 'Ставка по данной группе',
          onChanged: (rate) => _rate = rate,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
