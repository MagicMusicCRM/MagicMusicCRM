import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/services/hollihop_service.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';
import 'package:magic_music_crm/core/models/types.dart';

class LeadDetailDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> lead;
  final List<StatusRecord> allStatuses;

  const LeadDetailDialog({
    super.key,
    required this.lead,
    required this.allStatuses,
  });

  @override
  ConsumerState<LeadDetailDialog> createState() => _LeadDetailDialogState();
}

class _LeadDetailDialogState extends ConsumerState<LeadDetailDialog> {
  late Map<String, dynamic> _leadData;
  late TextEditingController _notesCtrl;
  late TextEditingController _commentCtrl;
  bool _saving = false;

  List<Map<String, dynamic>> _branches = [];
  bool _loadingMetadata = true;

  @override
  void initState() {
    super.initState();
    _leadData = Map<String, dynamic>.from(widget.lead);
    _notesCtrl = TextEditingController(text: _leadData['notes']?.toString() ?? '');
    _commentCtrl = TextEditingController();
    _fetchMetadata();
  }

  Future<void> _fetchMetadata() async {
    final hollihopService = ref.read(hollihopServiceProvider);
    final supaService = ref.read(supaLeadServiceProvider);
    
    final results = await Future.wait<dynamic>([
      hollihopService.getDisciplines() as Future<dynamic>,
      hollihopService.getLevels() as Future<dynamic>,
      supaService.getBranches() as Future<dynamic>,
    ]);
    
    if (mounted) {
      setState(() {
        _branches = List<Map<String, dynamic>>.from(results[2] as List);
        _loadingMetadata = false;
      });
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final id = _leadData['id'];
      await ref.read(supaLeadServiceProvider).updateLead(
        id: id,
        data: {
          'name': _leadData['name'],
          'last_name': _leadData['last_name'],
          'phone': _leadData['phone'],
          'email': _leadData['email'],
          'status': _leadData['status'],
          'notes': _notesCtrl.text,
          'custom_data': _leadData['custom_data'] ?? {},
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _updateCustomData(String key, dynamic value) {
    setState(() {
      final cd = Map<String, dynamic>.from(_leadData['custom_data'] ?? {});
      cd[key] = value;
      _leadData['custom_data'] = cd;
    });
  }

  @override
  Widget build(BuildContext context) {
    final curStatus = widget.allStatuses.firstWhere(
      (element) => element.$1 == _leadData['status'],
      orElse: () => widget.allStatuses.first,
    );

    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_leadData['name'] ?? ''} ${_leadData['last_name'] ?? ''}'.trim(),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text('Лид (ID: ${_leadData['hollihop_id'] ?? 'N/A'})',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Общая информация'),
                    _buildStatusPicker(curStatus),
                    _buildTextField('Имя', 'name'),
                    _buildTextField('Фамилия', 'last_name'),
                    _buildTextField('Телефон', 'phone', keyboard: TextInputType.phone),
                    _buildTextField('Email', 'email', keyboard: TextInputType.emailAddress),
                    
                    const SizedBox(height: 16),
                    _sectionTitle('Информация из HolliHop'),
                    if (_loadingMetadata)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      ))
                    else ...[
                      _buildInfoRow(Icons.category, 'Категория', _leadData['custom_data']?['category'] ?? 'Не указано'),
                      _buildInfoRow(Icons.source, 'Источник', _leadData['custom_data']?['source'] ?? 'Не указано'),
                      _buildInfoRow(Icons.school, 'Дисциплина', _leadData['custom_data']?['discipline'] ?? 'Не указана'),
                      _buildInfoRow(Icons.trending_up, 'Уровень', _leadData['custom_data']?['level'] ?? 'Без опыта'),
                      _buildTextField('Возраст', 'age', isCustom: true),
                      _buildTextField('Пробный урок', 'trial_lesson', isCustom: true),
                      _buildBranchDropdown('Основной филиал'),
                      _buildTextField('Тип обучения', 'study_type', isCustom: true),
                      _buildTextField('Категория', 'category', isCustom: true),
                      _buildDatePicker('Дата обращения', 'address_date', isCustom: true),
                      _buildTextField('Предпол. визит', 'expected_visit', isCustom: true),
                      _buildDatePicker('Дата визита', 'visit_date', isCustom: true),
                    ],

                    const SizedBox(height: 16),
                    _sectionTitle('Заметки'),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Общие примечания по лиду...',
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 16),
                    _sectionTitle('Комментарии'),
                    _CommentsList(leadId: _leadData['id']),
                    const SizedBox(height: 8),
                    _buildCommentInput(),
                  ],
                ),
              ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Сохранить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(title, style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryPurple.withAlpha(178)),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildStatusPicker(StatusRecord current) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _leadData['status'],
        decoration: const InputDecoration(labelText: 'Статус'),
        items: widget.allStatuses.map((s) {
          return DropdownMenuItem(
            value: s.$1,
            child: Row(
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(s.$2),
              ],
            ),
          );
        }).toList(),
        onChanged: (v) {
          if (v != null) setState(() => _leadData['status'] = v);
        },
      ),
    );
  }

  Widget _buildTextField(String label, String key, {TextInputType? keyboard, bool isCustom = false}) {
    String? initialVal;
    if (isCustom) {
      initialVal = (_leadData['custom_data'] as Map?)?[key]?.toString();
    } else {
      initialVal = _leadData[key]?.toString();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: initialVal ?? '',
        decoration: InputDecoration(labelText: label),
        keyboardType: keyboard,
        onChanged: (v) {
          if (isCustom) {
            _updateCustomData(key, v);
          } else {
            setState(() => _leadData[key] = v);
          }
        },
      ),
    );
  }

  Widget _buildBranchDropdown(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _leadData['branch_id'],
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface.withAlpha(127),
        ),
        items: _branches.map((b) => DropdownMenuItem(value: b['id'].toString(), child: Text(b['name']))).toList(),
        onChanged: (v) => setState(() => _leadData['branch_id'] = v),
      ),
    );
  }

  Widget _buildDatePicker(String label, String key, {bool isCustom = false}) {
    String? val;
    if (isCustom) {
      val = (_leadData['custom_data'] as Map?)?[key]?.toString();
    } else {
      val = _leadData[key]?.toString();
    }
    final dt = val != null ? DateTime.tryParse(val) : null;
    final display = dt != null ? DateFormat('dd.MM.yyyy').format(dt) : 'Не выбрано';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: dt ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            final iso = picked.toIso8601String();
            if (isCustom) {
              _updateCustomData(key, iso);
            } else {
              setState(() => _leadData[key] = iso);
            }
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface.withAlpha(127),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(display),
              const Icon(Icons.calendar_today_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommentInput() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _commentCtrl,
            decoration: const InputDecoration(hintText: 'Написать комментарий...', isDense: true),
          ),
        ),
        IconButton(
          onPressed: _addComment,
          icon: const Icon(Icons.send_rounded, color: AppTheme.primaryPurple),
        ),
      ],
    );
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await ref.read(supaLeadServiceProvider).addLeadComment(
        leadId: _leadData['id'],
        authorId: user.id,
        content: text,
      );
      _commentCtrl.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }
}

class _CommentsList extends ConsumerWidget {
  final String leadId;
  const _CommentsList({required this.leadId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ref.watch(supaLeadServiceProvider).getLeadCommentsStream(leadId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final comments = snapshot.data!;
        if (comments.isEmpty) return Text('Нет комментариев', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12));
        
        return Column(
          children: comments.map((c) {
            final dt = DateTime.tryParse(c['created_at'] ?? '')?.toLocal();
            final dateStr = dt != null ? DateFormat('d MMM HH:mm').format(dt) : '';
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Менеджер', style: TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.bold, fontSize: 11)),
                      Text(dateStr, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(c['content'] ?? '', style: const TextStyle(fontSize: 13)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
