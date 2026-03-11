import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class LeadsWidget extends StatefulWidget {
  const LeadsWidget({super.key});

  @override
  State<LeadsWidget> createState() => _LeadsWidgetState();
}

class _LeadsWidgetState extends State<LeadsWidget> {
  final _supabase = Supabase.instance.client;
  Map<String, List<Map<String, dynamic>>> _leadsByStatus = {};
  bool _loading = true;

  static const _statuses = [
    ('new', 'Новый', AppTheme.danger),
    ('contacted', 'Контакт', AppTheme.warning),
    ('negotiation', 'Переговоры', AppTheme.primaryPurple),
    ('converted', 'Договор', AppTheme.success),
    ('lost', 'Отказ', AppTheme.textSecondary),
  ];

  @override
  void initState() {
    super.initState();
    _loadLeads();
  }

  Future<void> _loadLeads() async {
    setState(() => _loading = true);
    try {
      final data = await _supabase
          .from('leads')
          .select()
          .order('created_at', ascending: false);

      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final s in _statuses) {
        grouped[s.$1] = [];
      }
      for (final l in data) {
        final status = l['status'] as String? ?? 'new';
        grouped.putIfAbsent(status, () => []).add(l);
      }

      setState(() {
        _leadsByStatus = grouped;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _addLead() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _LeadDialog(),
    );
    if (result != null) {
      await _supabase.from('leads').insert({
        'name': result['name'],
        'phone': result['phone'],
        'source': result['source'],
        'status': 'new',
      });
      _loadLeads();
    }
  }

  Future<void> _moveStatus(String id, String newStatus) async {
    await _supabase.from('leads').update({'status': newStatus}).eq('id', id);
    _loadLeads();
  }

  Future<void> _deleteLead(String id) async {
    await _supabase.from('leads').delete().eq('id', id);
    _loadLeads();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _addLead,
        child: const Icon(Icons.person_add_rounded),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: _statuses.map((s) {
          final leads = _leadsByStatus[s.$1] ?? [];
          if (leads.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(s.$2, style: TextStyle(color: s.$3, fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(width: 8),
                    Text('(${leads.length})', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              ...leads.map((lead) => _LeadCard(
                    lead: lead,
                    statusColor: s.$3,
                    allStatuses: _statuses,
                    onMove: _moveStatus,
                    onDelete: _deleteLead,
                  )),
              const SizedBox(height: 8),
            ],
          );
        }).toList(),
      ),
    );
  }
}

typedef StatusRecord = (String, String, Color);

class _LeadCard extends StatelessWidget {
  final Map<String, dynamic> lead;
  final Color statusColor;
  final List<StatusRecord> allStatuses;
  final Function(String, String) onMove;
  final Function(String) onDelete;

  const _LeadCard({
    required this.lead,
    required this.statusColor,
    required this.allStatuses,
    required this.onMove,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final id = lead['id'] as String;
    final name = lead['name'] as String? ?? 'Без имени';
    final phone = lead['phone'] as String? ?? '';
    final source = lead['source'] as String? ?? '';
    final currentStatus = lead['status'] as String? ?? 'new';
    final dt = lead['created_at'] != null ? DateTime.tryParse(lead['created_at']) : null;
    final dateStr = dt != null ? DateFormat('d MMM', 'ru').format(dt) : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (phone.isNotEmpty)
                    Text(phone, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  if (source.isNotEmpty)
                    Text('Источник: $source', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            if (dateStr.isNotEmpty)
              Text(dateStr, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary, size: 20),
              color: AppTheme.cardDark,
              onSelected: (v) {
                if (v == 'delete') onDelete(id);
                else onMove(id, v);
              },
              itemBuilder: (_) => [
                ...allStatuses
                    .where((s) => s.$1 != currentStatus)
                    .map((s) => PopupMenuItem(value: s.$1, child: Text('→ ${s.$2}'))),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'delete', child: Text('Удалить', style: TextStyle(color: AppTheme.danger))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadDialog extends StatefulWidget {
  const _LeadDialog();

  @override
  State<_LeadDialog> createState() => _LeadDialogState();
}

class _LeadDialogState extends State<_LeadDialog> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceDark,
      title: const Text('Новый лид'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Имя')),
          const SizedBox(height: 10),
          TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Телефон'), keyboardType: TextInputType.phone),
          const SizedBox(height: 10),
          TextField(controller: _sourceCtrl, decoration: const InputDecoration(labelText: 'Источник (ВКонтакте, сайт...)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            if (_nameCtrl.text.trim().isNotEmpty) {
              Navigator.pop(context, {
                'name': _nameCtrl.text.trim(),
                'phone': _phoneCtrl.text.trim(),
                'source': _sourceCtrl.text.trim(),
              });
            }
          },
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}
