import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/lead_detail_dialog.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'manage_statuses_dialog.dart';

class LeadsWidget extends ConsumerStatefulWidget {
  const LeadsWidget({super.key});

  @override
  ConsumerState<LeadsWidget> createState() => _LeadsWidgetState();
}

class _LeadsWidgetState extends ConsumerState<LeadsWidget> {
  List<StatusRecord> _activeStatuses = [];

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    final res = await ref.read(leadStatusesProvider.future);
    final statuses = <StatusRecord>[];
    for (final r in res) {
      final key = r['key'].toString();
      final label = r['label'].toString();
      final rawColor = r['color']?.toString() ?? '8B5CF6';
      final hexColor = rawColor.replaceAll('#', '');
      final color = Color(int.parse('FF$hexColor', radix: 16));
      statuses.add((key, label, color));
    }
    
    if (!mounted) return;
    setState(() => _activeStatuses = statuses);
  }

  Future<void> _addLead() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _LeadDialog(),
    );
    if (result != null) {
      await ref.read(supaLeadServiceProvider).addLead(
        name: result['name']!,
        phone: result['phone']!,
        source: result['source']!,
      );
    }
  }

  Future<void> _moveStatus(String id, String newStatus) async {
    await ref.read(supaLeadServiceProvider).updateLeadStatus(id, newStatus);
  }

  Future<void> _deleteLead(String id) async {
    await ref.read(supaLeadServiceProvider).deleteLead(id);
  }

  void _openDetail(Map<String, dynamic> lead) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => LeadDetailDialog(lead: lead, allStatuses: _activeStatuses),
    );
  }

  @override
  Widget build(BuildContext context) {
    final leadsAsync = ref.watch(leadsStreamProvider);

    return leadsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold)),
      error: (err, stack) => Center(child: Text('Ошибка: $err')),
      data: (data) {
        final grouped = <String, List<Map<String, dynamic>>>{};
        final foundStatuses = <String>{};
        
        for (final s in _activeStatuses) {
          grouped[s.$1] = [];
        }
        for (final l in data) {
          final status = l['status'] as String? ?? 'new';
          foundStatuses.add(status);
          grouped.putIfAbsent(status, () => []).add(l);
        }

        final active = List<StatusRecord>.from(_activeStatuses);
        final knownKeys = _activeStatuses.map((e) => e.$1).toSet();
        for (final s in foundStatuses) {
          if (!knownKeys.contains(s)) {
            active.add((s, s, AppTheme.primaryPurple));
          }
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton(
            onPressed: _addLead,
            tooltip: 'Новый контакт',
            child: const Icon(Icons.person_add_rounded),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Воронка продаж', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ManageStatusesDialog.show(context);
                        _loadStatuses();
                      },
                      icon: const Icon(Icons.settings_rounded, size: 16),
                      label: const Text('Управление колонками'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: active.map((s) {
                      final leads = grouped[s.$1] ?? [];
                      return _KanbanColumn(
                        status: s,
                        leads: leads,
                        onMove: _moveStatus,
                        onDelete: _deleteLead,
                        onTap: _openDetail,
                        allStatuses: active,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KanbanColumn extends StatefulWidget {
  final StatusRecord status;
  final List<Map<String, dynamic>> leads;
  final Function(String, String) onMove;
  final Function(String) onDelete;
  final Function(Map<String, dynamic>) onTap;
  final List<StatusRecord> allStatuses;

  const _KanbanColumn({
    required this.status,
    required this.leads,
    required this.onMove,
    required this.onDelete,
    required this.onTap,
    required this.allStatuses,
  });

  @override
  State<_KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends State<_KanbanColumn> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(127),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) => true,
        onAcceptWithDetails: (details) => widget.onMove(details.data, widget.status.$1),
        builder: (context, candidateData, rejectedData) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.status.$3, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(widget.status.$2, style: TextStyle(color: widget.status.$3, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(10)),
                      child: Text('${widget.leads.length}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
                    ),
                  ],
                ),
              ),
              if (candidateData.isNotEmpty)
                Container(
                  height: 100,
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: widget.status.$3),
                    borderRadius: BorderRadius.circular(10),
                    color: widget.status.$3.withAlpha(25),
                  ),
                  child: const Center(child: Icon(Icons.move_to_inbox_rounded)),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: widget.leads.length,
                  itemBuilder: (context, index) {
                    final lead = widget.leads[index];
                    return _LeadCard(
                      lead: lead,
                      statusColor: widget.status.$3,
                      allStatuses: widget.allStatuses,
                      onMove: widget.onMove,
                      onDelete: widget.onDelete,
                      onTap: () => widget.onTap(lead),
                      onRefresh: () => setState(() {}),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Finalizing kanban column structure

class _LeadCard extends ConsumerWidget {
  final Map<String, dynamic> lead;
  final Color statusColor;
  final List<StatusRecord> allStatuses;
  final Function(String, String) onMove;
  final Function(String) onDelete;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  const _LeadCard({
    required this.lead,
    required this.statusColor,
    required this.allStatuses,
    required this.onMove,
    required this.onDelete,
    required this.onTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = lead['id']?.toString() ?? '';
    final firstName = lead['name']?.toString() ?? '';
    final lName = lead['last_name']?.toString() ?? '';
    final name = '$firstName $lName'.trim();
    final displayName = name.isEmpty ? 'Без имени' : name;
    final phone = lead['phone']?.toString() ?? '';
    final source = lead['source']?.toString() ?? '';
    final currentStatus = lead['status']?.toString() ?? 'new';
    final dtStr = lead['created_at']?.toString();
    final dt = dtStr != null ? DateTime.tryParse(dtStr) : null;
    final dateStr = dt != null ? DateFormat('d MMM', 'ru').format(dt) : '';

    final customData = lead['custom_data'] as Map<String, dynamic>? ?? {};
    final discipline = customData['discipline']?.toString() ?? '';
    final level = customData['level']?.toString() ?? '';

    return LongPressDraggable<String>(
      data: id,
      feedback: Transform.rotate(
        angle: 0.05,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryGold, width: 2),
            ),
            child: Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_horiz_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 150),
                      onSelected: (v) {
                        if (v == 'delete') {
                          onDelete(id);
                        } else if (v == 'comment') {
                          _addComment(context, ref);
                        } else if (v == 'task') {
                          _addTask(context, ref);
                        } else if (v == 'trial') {
                          _scheduleTrial(context, ref);
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
                        const PopupMenuItem(
                            value: 'delete',
                            child: Text('Удалить', style: TextStyle(color: AppTheme.danger))),
                      ],
                    ),
                  ],
                ),
                if (phone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(phone, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (discipline.isNotEmpty)
                      _InfoBadge(text: discipline, color: AppTheme.primaryPurple.withAlpha(51), textColor: AppTheme.primaryPurple),
                    if (level.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _InfoBadge(text: level, color: AppTheme.warning.withAlpha(51), textColor: AppTheme.warning),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (source.isNotEmpty)
                      Text(source, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
                    Text(dateStr, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addComment(BuildContext context, WidgetRef ref) async {
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
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await ref.read(supaLeadServiceProvider).addComment(
          leadId: lead['id'],
          content: content.trim(),
          authorId: userId,
        );
        onRefresh();
      }
    }
  }

  Future<void> _addTask(BuildContext context, WidgetRef ref) async {
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
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await ref.read(supaLeadServiceProvider).addLeadTask(
          leadId: lead['id'],
          title: title.trim(),
          creatorId: userId,
        );
        onRefresh();
      }
    }
  }

  Future<void> _scheduleTrial(BuildContext context, WidgetRef ref) async {
    final client = Supabase.instance.client;
    
    // Quick fetching of available teachers and rooms
    // TODO: Move teacher/room fetching to a dedicated service/provider too
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
                initialValue: selectedTeacher,
                decoration: const InputDecoration(labelText: 'Учитель'),
                items: teachers.map((t) => DropdownMenuItem(
                  value: t['id'].toString(),
                  child: Text('${t['first_name']} ${t['last_name']}'),
                )).toList(),
                onChanged: (v) => setLocalState(() => selectedTeacher = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRoom,
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

      await ref.read(supaLeadServiceProvider).scheduleTrial(
        leadId: lead['id'],
        teacherId: selectedTeacher!,
        roomId: selectedRoom!,
        scheduledAt: scheduledAt,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пробное занятие назначено')),
        );
      }
      onRefresh();
    }
  }
}

class _InfoBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;

  const _InfoBadge({required this.text, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold)),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
