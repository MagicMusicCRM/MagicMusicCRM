import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class DebtorsWidget extends StatefulWidget {
  const DebtorsWidget({super.key});

  @override
  State<DebtorsWidget> createState() => _DebtorsWidgetState();
}

class _DebtorsWidgetState extends State<DebtorsWidget> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _debtors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDebtors();
  }

  Future<void> _loadDebtors() async {
    setState(() => _loading = true);
    try {
      final res = await _supabase
          .from('student_balances')
          .select('*, students(profiles(first_name, last_name, phone))')
          .lt('balance', 0)
          .order('balance', ascending: true);
      
      setState(() {
        _debtors = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading debtors: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: CircularProgressIndicator(color: AppTheme.danger));
    
    final fmt = NumberFormat('#,##0', 'ru');
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('Должники', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${_debtors.length}', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadDebtors,
              color: AppTheme.danger,
              child: _debtors.isEmpty
                  ? Center(child: Text('Должников не найдено', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _debtors.length,
                      itemBuilder: (ctx, i) {
                        final d = _debtors[i];
                        final balance = (d['balance'] as num?)?.toDouble() ?? 0;
                        final student = d['students']?['profiles'];
                        final name = student != null 
                            ? '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'.trim()
                            : 'Неизвестно';
                        final phone = student?['phone'] ?? 'Нет телефона';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            onTap: () => context.push('/admin/student/${d['student_id']}'),
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.danger.withAlpha(30),
                              child: Icon(Icons.person_remove_rounded, color: AppTheme.danger, size: 20),
                            ),
                            title: Text(name.isEmpty ? 'Без имени' : name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(phone, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${fmt.format(balance)} ₽', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w800, fontSize: 16)),
                                Text('задолженность', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              ],
                            ),
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
