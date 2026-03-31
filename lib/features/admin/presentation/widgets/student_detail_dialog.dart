import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/services/hollihop_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/top_up_dialog.dart';

class StudentDetailDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> student;

  const StudentDetailDialog({
    super.key,
    required this.student,
  });

  static Future<bool?> show(BuildContext context, Map<String, dynamic> student) {
    return showDialog<bool>(
      context: context,
      builder: (_) => StudentDetailDialog(student: student),
    );
  }

  @override
  ConsumerState<StudentDetailDialog> createState() => _StudentDetailDialogState();
}

class _StudentDetailDialogState extends ConsumerState<StudentDetailDialog> {
  late Map<String, dynamic> _studentData;
  late TextEditingController _notesCtrl;
  late TextEditingController _commentCtrl;
  final _supabase = Supabase.instance.client;
  bool _saving = false;

  List<Map<String, dynamic>> _branches = [];
  bool _loadingMetadata = true;

  @override
  void initState() {
    super.initState();
    _studentData = Map<String, dynamic>.from(widget.student);
    final customData = _studentData['custom_data'] as Map<String, dynamic>? ?? {};
    _notesCtrl = TextEditingController(text: customData['notes']?.toString() ?? '');
    _commentCtrl = TextEditingController();
    _fetchMetadata();
  }

  Future<void> _fetchMetadata() async {
    try {
      final results = await _supabase.from('branches').select('id, name');
      if (mounted) {
        setState(() {
          _branches = List<Map<String, dynamic>>.from(results);
          _loadingMetadata = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingMetadata = false);
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
      final id = _studentData['id'];
      final customData = Map<String, dynamic>.from(_studentData['custom_data'] ?? {});
      customData['notes'] = _notesCtrl.text;

      await _supabase.from('students').update({
        'first_name': _studentData['first_name'],
        'last_name': _studentData['last_name'],
        'middle_name': _studentData['middle_name'],
        'phone': _studentData['phone'],
        'email': _studentData['email'],
        'custom_data': customData,
      }).eq('id', id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _updateCustomData(String key, dynamic value) {
    setState(() {
      final cd = Map<String, dynamic>.from(_studentData['custom_data'] ?? {});
      cd[key] = value;
      _studentData['custom_data'] = cd;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _studentData['profiles'];
    final firstName = _studentData['first_name'] ?? p?['first_name'] ?? '';
    final lastName = _studentData['last_name'] ?? p?['last_name'] ?? '';
    final fullName = '$firstName $lastName'.trim();

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
                        fullName.isEmpty ? 'Без имени' : fullName,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text('Ученик (ID: ${_studentData['hollihop_id'] ?? 'N/A'})',
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
                    Row(
                      children: [
                        Expanded(child: _buildTextField('Имя', 'first_name')),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final res = await TopUpDialog.show(context, _studentData);
                            if (res == true) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Баланс пополнен', style: TextStyle(color: AppTheme.success))));
                            }
                          },
                          icon: const Icon(Icons.add_card_rounded, color: AppTheme.success, size: 18),
                          label: const Text('Пополнить баланс', style: TextStyle(color: AppTheme.success)),
                        ),
                      ],
                    ),
                    _buildTextField('Фамилия', 'last_name'),
                    _buildTextField('Отчество', 'middle_name'),
                    _buildTextField('Телефон', 'phone', keyboard: TextInputType.phone),
                    _buildTextField('Email', 'email', keyboard: TextInputType.emailAddress),
                    
                    const SizedBox(height: 16),
                    _sectionTitle('Дополнительно'),
                    if (_loadingMetadata)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      ))
                    else ...[
                      _buildInfoRow(Icons.trending_up, 'Уровень', _studentData['custom_data']?['level'] ?? 'Не указано'),
                      _buildInfoRow(Icons.school, 'Дисциплина', _studentData['custom_data']?['discipline'] ?? 'Не указана'),
                      _buildTextField('Тип обучения', 'study_type', isCustom: true),
                    ],

                    const SizedBox(height: 16),
                    _sectionTitle('Заметки'),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Общие примечания по ученику...',
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 16),
                    _sectionTitle('Комментарии'),
                    _CommentsList(studentId: _studentData['id']),
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
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryPurple),
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
          Icon(icon, size: 16, color: AppTheme.primaryPurple.withOpacity(0.7)),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, String key, {TextInputType? keyboard, bool isCustom = false}) {
    String? initialVal;
    if (isCustom) {
      initialVal = (_studentData['custom_data'] as Map?)?[key]?.toString();
    } else {
      initialVal = _studentData[key]?.toString();
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
            setState(() => _studentData[key] = v);
          }
        },
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
    
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('entity_comments').insert({
        'entity_type': 'student',
        'entity_id': _studentData['id'],
        'author_id': user.id,
        'content': text,
      });
      _commentCtrl.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }
}

class _CommentsList extends StatelessWidget {
  final String studentId;
  const _CommentsList({required this.studentId});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('entity_comments')
          .stream(primaryKey: ['id'])
          .map((list) => list.where((c) => 
            c['entity_id'] == studentId && 
            c['entity_type'] == 'student'
          ).toList())
          .map((list) {
            list.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
            return list;
          }),
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
