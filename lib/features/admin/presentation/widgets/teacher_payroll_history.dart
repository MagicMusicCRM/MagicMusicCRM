import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TeacherPayrollHistory extends StatelessWidget {
  const TeacherPayrollHistory({
    super.key,
    required this.payroll,
    required this.canManage,
    required this.mutating,
    required this.onEditRate,
    required this.onEditPayout,
    required this.onDelete,
  });

  final Map<String, dynamic> payroll;
  final bool canManage;
  final bool mutating;
  final ValueChanged<Map<String, dynamic>> onEditRate;
  final ValueChanged<Map<String, dynamic>> onEditPayout;
  final void Function(Map<String, dynamic> row, {required bool rate}) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RateHistory(
          rows: _mapList(payroll['rateHistory']).reversed.toList(),
          canManage: canManage,
          mutating: mutating,
          onEdit: onEditRate,
          onDelete: (row) => onDelete(row, rate: true),
        ),
        _PayoutHistory(
          rows: _mapList(payroll['payouts']),
          canManage: canManage,
          mutating: mutating,
          onEdit: onEditPayout,
          onDelete: (row) => onDelete(row, rate: false),
        ),
      ],
    );
  }
}

class _RateHistory extends StatelessWidget {
  const _RateHistory({
    required this.rows,
    required this.canManage,
    required this.mutating,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> rows;
  final bool canManage;
  final bool mutating;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0', 'ru');
    return ExpansionTile(
      key: const ValueKey('teacher-rate-history'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 6),
      title: Text('История ставок (${rows.length})'),
      children: rows.isEmpty
          ? const [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Нет записей'),
              ),
            ]
          : [
              for (final row in rows)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _number(row['rate']) == 0
                        ? 'Входит в оклад'
                        : '${money.format(_number(row['rate']))} ₽/астр.ч.',
                  ),
                  subtitle: Text(
                    'с ${_shortDay(row['effectiveFrom']?.toString() ?? '')}'
                    '${row['authorName'] == null ? '' : ' · ${row['authorName']}'}',
                  ),
                  trailing: canManage
                      ? _HistoryMenu(
                          enabled: !mutating,
                          onEdit: () => onEdit(row),
                          onDelete: () => onDelete(row),
                        )
                      : null,
                ),
            ],
    );
  }
}

class _PayoutHistory extends StatelessWidget {
  const _PayoutHistory({
    required this.rows,
    required this.canManage,
    required this.mutating,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> rows;
  final bool canManage;
  final bool mutating;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0', 'ru');
    return ExpansionTile(
      key: const ValueKey('teacher-payout-history'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 6),
      title: Text('История выплат (${rows.length})'),
      children: rows.isEmpty
          ? const [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Нет записей'),
              ),
            ]
          : [
              for (final row in rows)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${_kindLabel(row['kind']?.toString())}: '
                    '${money.format(_number(row['amount']))} ₽',
                  ),
                  subtitle: Text(
                    '${_shortDate(row['paidAt']?.toString() ?? '')}'
                    '${row['comment'] == null ? '' : ' · ${row['comment']}'}'
                    '${row['authorName'] == null ? '' : ' · ${row['authorName']}'}',
                  ),
                  trailing: canManage
                      ? _HistoryMenu(
                          enabled: !mutating,
                          onEdit: () => onEdit(row),
                          onDelete: () => onDelete(row),
                        )
                      : null,
                ),
            ],
    );
  }

  static String _kindLabel(String? kind) => switch (kind) {
    'bonus' => 'Доплата',
    'deduction' => 'Вычет',
    _ => 'Выплата',
  };
}

class _HistoryMenu extends StatelessWidget {
  const _HistoryMenu({
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });

  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: enabled,
      onSelected: (action) => action == 'edit' ? onEdit() : onDelete(),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Изменить')),
        PopupMenuItem(value: 'delete', child: Text('Удалить')),
      ],
    );
  }
}

num _number(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

String _shortDate(String value) {
  final parsed = DateTime.tryParse(value)?.toLocal();
  return parsed == null ? value : DateFormat('dd.MM.yyyy HH:mm').format(parsed);
}

String _shortDay(String value) {
  final parsed = DateTime.tryParse(value)?.toLocal();
  return parsed == null ? value : DateFormat('dd.MM.yyyy').format(parsed);
}
