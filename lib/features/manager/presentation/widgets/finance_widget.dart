import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class FinanceWidget extends StatefulWidget {
  const FinanceWidget({super.key});

  @override
  State<FinanceWidget> createState() => _FinanceWidgetState();
}

class _FinanceWidgetState extends State<FinanceWidget> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;
  double _total = 0;
  String _period = 'month';

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      late DateTime from;
      switch (_period) {
        case 'week':
          from = now.subtract(const Duration(days: 7));
          break;
        case 'year':
          from = DateTime(now.year, 1, 1);
          break;
        default:
          from = DateTime(now.year, now.month, 1);
      }

      final data = await _supabase
          .from('payments')
          .select('*, students(profiles(first_name, last_name))')
          .gte('created_at', from.toIso8601String())
          .order('created_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(data);
      final total = list.fold<double>(0, (s, p) => s + (double.tryParse(p['amount'].toString()) ?? 0));

      setState(() {
        _payments = list;
        _total = total;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _addPayment() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _PaymentDialog(),
    );
    if (result != null) {
      await _supabase.from('payments').insert(result);
      _loadPayments();
    }
  }

  String _typeLabel(String? t) {
    switch (t) {
      case 'extra_lesson': return 'Доп. занятие';
      case 'other': return 'Прочее';
      default: return 'Абонемент';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'ru');
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _addPayment,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF10B981)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Итого поступлений', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('${fmt.format(_total)} ₽', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'week', label: Text('Нед.')),
                    ButtonSegment(value: 'month', label: Text('Мес.')),
                    ButtonSegment(value: 'year', label: Text('Год')),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) {
                    setState(() => _period = s.first);
                    _loadPayments();
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected) ? Colors.white30 : Colors.transparent,
                    ),
                    foregroundColor: WidgetStateProperty.all(Colors.white),
                    side: WidgetStateProperty.all(const BorderSide(color: Colors.white38)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.success))
                : _payments.isEmpty
                    ? const Center(child: Text('Нет платежей за период', style: TextStyle(color: AppTheme.textSecondary)))
                    : RefreshIndicator(
                        color: AppTheme.success,
                        onRefresh: _loadPayments,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          itemCount: _payments.length,
                          itemBuilder: (ctx, i) {
                            final p = _payments[i];
                            final amount = double.tryParse(p['amount'].toString()) ?? 0;
                            final type = _typeLabel(p['type'] as String?);
                            final student = p['students']?['profiles'];
                            final name = student != null
                                ? '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'.trim()
                                : 'Неизвестный ученик';
                            final dt = p['created_at'] != null ? DateTime.tryParse(p['created_at']) : null;
                            final dateStr = dt != null ? DateFormat('d MMM yyyy, HH:mm', 'ru').format(dt.toLocal()) : '';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Container(
                                  width: 42, height: 42,
                                  decoration: BoxDecoration(
                                    color: AppTheme.success.withAlpha(25),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.payments_rounded, color: AppTheme.success),
                                ),
                                title: Text(name.isEmpty ? 'Без имени' : name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('$type · $dateStr', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                trailing: Text('${fmt.format(amount)} ₽', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w700, fontSize: 15)),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog();

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _amountCtrl = TextEditingController();
  String _type = 'subscription';
  List<Map<String, dynamic>> _students = [];
  String? _selectedStudentId;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    final data = await Supabase.instance.client
        .from('students')
        .select('id, profiles(first_name, last_name)');
    setState(() => _students = List<Map<String, dynamic>>.from(data));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceDark,
      title: const Text('Новый платёж'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedStudentId,
            dropdownColor: AppTheme.cardDark,
            decoration: const InputDecoration(labelText: 'Ученик'),
            items: _students.map((s) {
              final p = s['profiles'] as Map<String, dynamic>?;
              final name = '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();
              return DropdownMenuItem(value: s['id'] as String, child: Text(name.isEmpty ? 'Без имени' : name));
            }).toList(),
            onChanged: (v) => setState(() => _selectedStudentId = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: _amountCtrl, decoration: const InputDecoration(labelText: 'Сумма (₽)'), keyboardType: TextInputType.number),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _type,
            dropdownColor: AppTheme.cardDark,
            decoration: const InputDecoration(labelText: 'Тип'),
            items: const [
              DropdownMenuItem(value: 'subscription', child: Text('Абонемент')),
              DropdownMenuItem(value: 'extra_lesson', child: Text('Доп. занятие')),
              DropdownMenuItem(value: 'other', child: Text('Прочее')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'subscription'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amountCtrl.text.trim());
            if (amount != null && amount > 0) {
              Navigator.pop(context, {
                'amount': amount,
                'type': _type,
                'student_id': _selectedStudentId,
              });
            }
          },
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}
