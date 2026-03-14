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
  List<StatusRecord> _activeStatuses = [];
  bool _loading = true;

  static const _defaultStatuses = [
    ('new', 'Новый', AppTheme.danger),
    ('contacted', 'Контакт', AppTheme.warning),
    ('negotiation', 'Переговоры', AppTheme.primaryPurple),
    ('converted', 'Договор', AppTheme.success),
    ('lost', 'Отказ', AppTheme.textSecondary),
  ];

  @override
  void initState() {
    super.initState();
    _subscribeLeads();
  }

  void _subscribeLeads() {
    _supabase
        .from('leads')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen((data) {
      if (!mounted) return;
      final grouped = <String, List<Map<String, dynamic>>>{};
      final foundStatuses = <String>{};
      for (final s in _defaultStatuses) {
        grouped[s.$1] = [];
      }
      for (final l in data) {
        final status = l['status'] as String? ?? 'new';
        foundStatuses.add(status);
        grouped.putIfAbsent(status, () => []).add(l);
      }

      final active = List<StatusRecord>.from(_defaultStatuses);
      final knownKeys = _defaultStatuses.map((e) => e.$1).toSet();
      for (final s in foundStatuses) {
        if (!knownKeys.contains(s)) {
          active.add((s, s, AppTheme.primaryPurple));
        }
      }

      setState(() {
        _leadsByStatus = grouped;
        _activeStatuses = active;
        _loading = false;
      });
    }, onError: (err) {
      if (mounted) setState(() => _loading = false);
    });
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
    }
  }

  Future<void> _moveStatus(String id, String newStatus) async {
    await _supabase.from('leads').update({'status': newStatus}).eq('id', id);
  }

  Future<void> _deleteLead(String id) async {
    await _supabase.from('leads').delete().eq('id', id);
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
        children: _activeStatuses.map((s) {
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
                    allStatuses: _activeStatuses,
                    onMove: _moveStatus,
                    onDelete: _deleteLead,
                    onRefresh: () => setState(() {}),
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
  final VoidCallback? onRefresh;

  const _LeadCard({
    required this.lead,
    required this.statusColor,
    required this.allStatuses,
    required this.onMove,
    required this.onDelete,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final id = lead['id']?.toString() ?? '';
      final firstName = (lead['name']?.toString() ?? '').isNotEmpty ? lead['name']?.toString() : (lead['first_name']?.toString() ?? '');
      final lastName = lead['last_name']?.toString() ?? '';
      final name = '$firstName $lastName'.trim();
      final displayName = name.isEmpty ? 'Без имени' : name;
      final phone = lead['phone']?.toString() ?? '';
      final source = lead['source']?.toString() ?? '';
      final currentStatus = lead['status']?.toString() ?? 'new';
      final dtStr = lead['created_at']?.toString();
      final dt = dtStr != null ? DateTime.tryParse(dtStr) : null;
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
                  Text(displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
                if (v == 'delete') {
                  onDelete(id);
                } else if (v == 'comment') {
                  _addComment(context);
                } else if (v == 'task') {
                  _addTask(context);
                } else if (v == 'trial') {
                  _scheduleTrial(context);
                } else {
                  onMove(id, v);
                }
              },
              itemBuilder: (_) => [
                ...allStatuses
                    .where((s) => s.$1 != currentStatus)
                    .map((s) => PopupMenuItem(value: s.$1, child: Text('→ ${s.$2}'))),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'comment', child: Text('Добавить комментарий')),
                const PopupMenuItem(value: 'task', child: Text('Создать задачу')),
                const PopupMenuItem(value: 'trial', child: Text('Назначить пробный')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'delete', child: Text('Удалить', style: TextStyle(color: AppTheme.danger))),
              ],
            ),
          ],
        ),
      ),
    );
    } catch (e) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text('Ошибка: $e'),
        ),
      );
    }
  }

  Future<void> _addComment(BuildContext context) async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Комментарий к лиду'),
        content: TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(hintText: 'Текст...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Сохранить')),
        ],
      ),
    );
    if (content != null && content.trim().isNotEmpty) {
      await Supabase.instance.client.from('entity_comments').insert({
        'entity_id': lead['id'],
        'entity_type': 'lead',
        'content': content.trim(),
        'author_id': Supabase.instance.client.auth.currentUser?.id,
      });
      onRefresh?.call();
    }
  }

  Future<void> _addTask(BuildContext context) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Задача по лиду'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Что сделать?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Создать')),
        ],
      ),
    );
    if (title != null && title.trim().isNotEmpty) {
      await Supabase.instance.client.from('tasks').insert({
        'title': title.trim(),
        'lead_id': lead['id'],
        'status': 'todo',
        'created_by': Supabase.instance.client.auth.currentUser?.id,
      });
      onRefresh?.call();
    }
  }

  Future<void> _scheduleTrial(BuildContext context) async {
    final client = Supabase.instance.client;
    
    // Quick fetching of available teachers and rooms
    final [teachersRes, roomsRes] = await Future.wait([
      client.from('teachers').select('id, first_name, last_name'),
      client.from('rooms').select('id, name'),
    ]);
    
    final teachers = List<Map<String, dynamic>>.from(teachersRes);
    final rooms = List<Map<String, dynamic>>.from(roomsRes);

    if (!context.mounted) return;

    String? selectedTeacher = teachers.isNotEmpty ? teachers.first['id'] : null;
    String? selectedRoom = rooms.isNotEmpty ? rooms.first['id'] : null;
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Пробное занятие'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedTeacher,
                decoration: const InputDecoration(labelText: 'Учитель'),
                items: teachers.map((t) => DropdownMenuItem(
                  value: t['id'].toString(),
                  child: Text('${t['first_name']} ${t['last_name']}'),
                )).toList(),
                onChanged: (v) => setLocalState(() => selectedTeacher = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRoom,
                decoration: const InputDecoration(labelText: 'Кабинет'),
                items: rooms.map((r) => DropdownMenuItem(
                  value: r['id'].toString(),
                  child: Text(r['name']),
                )).toList(),
                onChanged: (v) => setLocalState(() => selectedRoom = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text('Дата: ${DateFormat('dd.MM.yyyy').format(selectedDate)}'),
                trailing: const Icon(Icons.calendar_today_rounded),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (picked != null) setLocalState(() => selectedDate = picked);
                },
              ),
              ListTile(
                title: Text('Время: ${selectedTime.format(ctx)}'),
                trailing: const Icon(Icons.access_time_rounded),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: selectedTime,
                  );
                  if (picked != null) setLocalState(() => selectedTime = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Назначить')),
          ],
        ),
      ),
    );

    if (confirmed == true && selectedTeacher != null && selectedRoom != null) {
      final scheduledAt = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );

      await client.from('lessons').insert({
        'lead_id': lead['id'],
        'teacher_id': selectedTeacher,
        'room_id': selectedRoom,
        'scheduled_at': scheduledAt.toIso8601String(),
        'is_trial': true,
        'status': 'planned',
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пробное занятие назначено')),
      );
      onRefresh?.call();
    }
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
