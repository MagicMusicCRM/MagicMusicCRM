import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class StudentDetailScreen extends StatefulWidget {
  final String studentId;
  const StudentDetailScreen({super.key, required this.studentId});

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _student;
  Map<String, dynamic>? _balance;
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _lessons = [];
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _expectedPayments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    try {
      // Load student with profile
      final studentRes = await _supabase
          .from('students')
          .select('*, profiles(*)')
          .eq('id', widget.studentId)
          .single();
      
      // Load payments
      final paymentsRes = await _supabase
          .from('payments')
          .select('*')
          .eq('student_id', widget.studentId)
          .order('payment_date', ascending: false);

      // Load lessons
      final lessonsRes = await _supabase
          .from('lessons')
          .select('*, teachers(profiles(first_name, last_name)), groups(name), rooms(name)')
          .eq('student_id', widget.studentId)
          .order('scheduled_at', ascending: false);

      // Load tasks (fixed to look for tasks about this student)
      final tasksRes = await _supabase
          .from('tasks')
          .select('*, profiles:assigned_to(first_name, last_name)')
          .or('student_id.eq.${widget.studentId},assigned_to.eq.${widget.studentId}')
          .order('created_at', ascending: false);

      // Load groups student belongs to
      final groupsRes = await _supabase
          .from('group_students')
          .select('groups(id, name, teachers(profiles(first_name, last_name)))')
          .eq('student_id', widget.studentId);

      // Load balance from view
      final balanceRes = await _supabase
          .from('student_balances')
          .select('*')
          .eq('student_id', widget.studentId)
          .single();

      // Load comments
      final commentsRes = await _supabase
          .from('entity_comments')
          .select('*')
          .eq('entity_id', widget.studentId)
          .eq('entity_type', 'student')
          .order('created_at', ascending: false);

      // Load expected payments
      final expectedPaymentsRes = await _supabase
          .from('expected_payments')
          .select('*')
          .eq('student_id', widget.studentId)
          .order('due_date', ascending: false);

      if (mounted) {
        setState(() {
          _student = studentRes;
          _balance = balanceRes;
          _payments = List<Map<String, dynamic>>.from(paymentsRes);
          _lessons = List<Map<String, dynamic>>.from(lessonsRes);
          _tasks = List<Map<String, dynamic>>.from(tasksRes);
          _comments = List<Map<String, dynamic>>.from(commentsRes);
          _groups = List<Map<String, dynamic>>.from(groupsRes).map((g) => g['groups'] as Map<String, dynamic>).toList();
          _expectedPayments = List<Map<String, dynamic>>.from(expectedPaymentsRes);
          _tasks.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
          _comments.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading student data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)));
    }

    if (_student == null) {
      return const Scaffold(body: Center(child: Text('Ученик не найден')));
    }

    final profile = _student!['profiles'] as Map<String, dynamic>?;
    final name = '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}'.trim();
    final phone = profile?['phone'] ?? '—';
    final email = _student!['email'] ?? '—';
    final customData = _student!['custom_data'] as Map<String, dynamic>? ?? {};

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name.isEmpty ? 'Без имени' : name, style: const TextStyle(fontSize: 18)),
              if (_balance != null)
                Text(
                  'Баланс: ${_balance!['balance']} ₽',
                  style: TextStyle(
                    fontSize: 12,
                    color: (_balance!['balance'] as num) < 0 ? AppTheme.danger : AppTheme.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: AppTheme.primaryPurple,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primaryPurple,
            tabs: [
              Tab(text: 'Инфо'),
              Tab(text: 'Оплаты'),
              Tab(text: 'Инвойсы'),
              Tab(text: 'Документы'),
              Tab(text: 'Занятия'),
              Tab(text: 'История'),
              Tab(text: 'Прогресс'),
            ],
          ),
        ),
        floatingActionButton: _buildFAB(),
        body: TabBarView(
          children: [
            _buildInfoTab(phone, email, customData),
            _buildPaymentsTab(),
            _buildInvoicesTab(),
            _buildDocumentsTab(),
            _buildLessonsTab(),
            _buildHistoryTab(),
            _buildProgressTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTab(String phone, String email, Map<String, dynamic> customData) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard('Контактные данные', [
          _InfoRow(icon: Icons.phone_rounded, label: 'Телефон', value: phone),
          _InfoRow(icon: Icons.email_rounded, label: 'Email', value: email),
        ]),
        const SizedBox(height: 16),
        _buildInfoCard('Дополнительная информация', [
          _InfoRow(icon: Icons.cake_rounded, label: 'День рождения', value: _student!['birthday'] ?? '—'),
          _InfoRow(icon: Icons.person_outline_rounded, label: 'Пол', value: _student!['gender'] == 'male' ? 'Мужской' : (_student!['gender'] == 'female' ? 'Женский' : '—')),
          _InfoRow(icon: Icons.fingerprint_rounded, label: 'Holli Hop ID', value: _student!['hollihop_id']?.toString() ?? '—'),
          ...customData.entries.map((e) => _InfoRow(icon: Icons.info_outline_rounded, label: e.key, value: e.value?.toString() ?? '—')),
        ]),
        const SizedBox(height: 16),
        _buildInfoCard('Финансовые настройки', [
          _InfoRow(
            icon: Icons.payments_outlined, 
            label: 'Цена инд. занятия', 
            value: '${_student!['individual_price'] ?? 1500} ₽',
            onEdit: () => _editPrice(),
          ),
          if (_balance != null) ...[
            _InfoRow(icon: Icons.summarize_outlined, label: 'Всего оплачено', value: '${_balance!['total_paid']} ₽'),
            _InfoRow(icon: Icons.history_edu_outlined, label: 'Списано за уроки', value: '${_balance!['total_cost']} ₽'),
          ],
        ]),
        const SizedBox(height: 16),
        _buildInfoCard('Группы', [
          if (_groups.isEmpty)
            const _InfoRow(icon: Icons.group_off_rounded, label: 'Группы', value: 'Нет активных групп')
          else
            ..._groups.map((g) {
              final teacher = g['teachers'];
              String tName = '—';
              if (teacher != null) {
                final p = teacher['profiles'];
                tName = '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();
              }
              return _InfoRow(
                icon: Icons.group_rounded, 
                label: g['name'] ?? 'Группа', 
                value: 'Преп.: $tName',
              );
            }),
        ]),
      ],
    );
  }

  Widget? _buildFAB() {
    return Builder(
      builder: (context) {
        final tabIndex = DefaultTabController.of(context).index;
        if (tabIndex == 3) {
          return FloatingActionButton.extended(
            onPressed: _showAddHistoryDialog,
            label: const Text('Добавить'),
            icon: const Icon(Icons.add_rounded),
            backgroundColor: AppTheme.primaryPurple,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Future<void> _showAddHistoryDialog() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.comment_rounded, color: AppTheme.primaryPurple),
            title: const Text('Добавить комментарий'),
            onTap: () => Navigator.pop(ctx, 'comment'),
          ),
          ListTile(
            leading: const Icon(Icons.auto_graph_rounded, color: AppTheme.success),
            title: const Text('Заметка о прогрессе'),
            onTap: () => Navigator.pop(ctx, 'progress'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );

    if (type == 'comment') {
      _addComment();
    } else if (type == 'task') {
      _addTask();
    } else if (type == 'progress') {
      _addComment(isProgress: true);
    }
  }

  Future<void> _addComment({bool isProgress = false}) async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isProgress ? 'Заметка о прогрессе' : 'Новый комментарий'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(hintText: isProgress ? 'Опишите успехи ученика...' : 'Введите текст...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Сохранить')),
        ],
      ),
    );

    if (content != null && content.trim().isNotEmpty) {
      final finalContent = isProgress ? '[PROGRESS] ${content.trim()}' : content.trim();
      await _supabase.from('entity_comments').insert({
        'entity_id': widget.studentId,
        'entity_type': 'student',
        'content': finalContent,
        'author_id': _supabase.auth.currentUser?.id,
      });
      _loadAllData();
    }
  }

  Future<void> _addTask() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая задача'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Что нужно сделать?')),
            const SizedBox(height: 12),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Детали'), maxLines: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
        ],
      ),
    );

    if (result == true && titleCtrl.text.isNotEmpty) {
      await _supabase.from('tasks').insert({
        'title': titleCtrl.text.trim(),
        'description': descCtrl.text.trim(),
        'student_id': widget.studentId,
        'status': 'todo',
        'created_by': _supabase.auth.currentUser?.id,
      });
      _loadAllData();
    }
  }

  Future<void> _editPrice() async {
    final controller = TextEditingController(text: _student!['individual_price']?.toString());
    final newPrice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Цена занятия'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Сумма (₽)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Сохранить')),
        ],
      ),
    );

    if (newPrice != null && double.tryParse(newPrice) != null) {
      try {
        await _supabase.from('students').update({'individual_price': double.parse(newPrice)}).eq('id', widget.studentId);
        _loadAllData();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.primaryPurple)),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentsTab() {
    if (_payments.isEmpty) {
      return const Center(child: Text('Оплат не найдено', style: TextStyle(color: AppTheme.textSecondary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _payments.length,
      itemBuilder: (context, i) {
        final p = _payments[i];
        final dt = DateTime.tryParse(p['payment_date'] ?? '');
        final dateStr = dt != null ? DateFormat('d MMM yyyy', 'ru').format(dt) : '—';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_rounded, color: AppTheme.success),
            title: Text('${p['amount']} ₽', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(dateStr),
            trailing: Text(p['description'] ?? '', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ),
        );
      },
    );
  }

  Widget _buildLessonsTab() {
    if (_lessons.isEmpty) {
      return const Center(child: Text('Занятий не найдено', style: TextStyle(color: AppTheme.textSecondary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _lessons.length,
      itemBuilder: (context, i) {
        final l = _lessons[i];
        final dt = DateTime.tryParse(l['scheduled_at'] ?? '');
        final dateStr = dt != null ? DateFormat('d MMM, HH:mm', 'ru').format(dt) : '—';
        final teacher = l['teachers']?['profiles'];
        final teacherName = teacher != null ? '${teacher['first_name'] ?? ''} ${teacher['last_name'] ?? ''}'.trim() : '—';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Преп.: $teacherName • ${l['groups']?['name'] ?? 'Инд.'}'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (l['status'] == 'completed' ? AppTheme.success : AppTheme.primaryPurple).withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l['status'] == 'completed' ? 'Завершено' : 'Запланировано',
                style: TextStyle(fontSize: 11, color: l['status'] == 'completed' ? AppTheme.success : AppTheme.primaryPurple, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInvoicesTab() {
    if (_expectedPayments.isEmpty) {
      return const Center(child: Text('Инвойсов не найдено', style: TextStyle(color: AppTheme.textSecondary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _expectedPayments.length,
      itemBuilder: (context, i) {
        final p = _expectedPayments[i];
        final dt = DateTime.tryParse(p['due_date'] ?? '');
        final dateStr = dt != null ? DateFormat('d MMM yyyy', 'ru').format(dt) : '—';
        final status = p['status'] ?? 'pending';
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              status == 'paid' ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
              color: status == 'paid' ? AppTheme.success : AppTheme.warning,
            ),
            title: Text('${p['amount']} ₽', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Срок: $dateStr • ${p['description'] ?? "Счёт"}'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (status == 'paid' ? AppTheme.success : AppTheme.warning).withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status == 'paid' ? 'Оплачено' : 'Ожидает',
                style: TextStyle(fontSize: 11, color: status == 'paid' ? AppTheme.success : AppTheme.warning, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDocumentsTab() {
    final contractUrl = _student!['contract_url'] as String?;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard('Договоры и документы', [
          ListTile(
            leading: const Icon(Icons.description_rounded, color: AppTheme.primaryPurple),
            title: const Text('Основной договор'),
            subtitle: Text(contractUrl ?? 'Не прикреплен'),
            trailing: IconButton(
              icon: Icon(contractUrl != null ? Icons.edit_rounded : Icons.add_link_rounded),
              onPressed: _editContractUrl,
            ),
            onTap: contractUrl != null ? () {
              // TODO: Launch URL
            } : null,
          ),
        ]),
      ],
    );
  }

  Future<void> _editContractUrl() async {
    final controller = TextEditingController(text: _student!['contract_url']);
    final newUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ссылка на договор'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'https://...', labelText: 'URL документа'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Сохранить')),
        ],
      ),
    );

    if (newUrl != null) {
      await _supabase.from('students').update({'contract_url': newUrl.trim()}).eq('id', widget.studentId);
      _loadAllData();
    }
  }

  Widget _buildHistoryTab() {
    if (_tasks.isEmpty && _comments.isEmpty) {
      return const Center(child: Text('История пуста', style: TextStyle(color: AppTheme.textSecondary)));
    }

    final items = [
      ..._tasks.map((t) => {'type': 'task', 'data': t, 'date': t['created_at']}),
      ..._comments.where((c) => !(c['content']?.toString().startsWith('[PROGRESS]') ?? false))
          .map((c) => {'type': 'comment', 'data': c, 'date': c['created_at']}),
    ];
    items.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        final isTask = item['type'] == 'task';
        final data = item['data'] as Map<String, dynamic>;
        final dt = DateTime.tryParse(item['date'] as String? ?? '');
        final dateStr = dt != null ? DateFormat('d MMM HH:mm', 'ru').format(dt.toLocal()) : '—';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(isTask ? Icons.task_alt_rounded : Icons.comment_rounded, size: 16, color: isTask ? AppTheme.warning : AppTheme.primaryPurple),
                        const SizedBox(width: 8),
                        Text(isTask ? 'Задача' : 'Комментарий', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isTask ? AppTheme.warning : AppTheme.primaryPurple)),
                      ],
                    ),
                    Text(dateStr, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(isTask ? (data['title'] ?? '') : (data['content'] ?? ''), style: const TextStyle(fontSize: 14)),
                if (isTask && data['description'] != null) ...[
                  const SizedBox(height: 4),
                  Text(data['description'], style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildProgressTab() {
    final progressNotes = _comments.where((c) => c['content']?.toString().startsWith('[PROGRESS]') ?? false).toList();
    
    if (progressNotes.isEmpty) {
      return const Center(child: Text('Заметок об успехах ещё нет', style: TextStyle(color: AppTheme.textSecondary)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: progressNotes.length,
      itemBuilder: (ctx, i) {
        final note = progressNotes[i];
        final content = (note['content'] as String).replaceFirst('[PROGRESS] ', '');
        final dt = DateTime.tryParse(note['created_at'] ?? '');
        final dateStr = dt != null ? DateFormat('d MMM yyyy, HH:mm', 'ru').format(dt.toLocal()) : '—';
        final author = note['profiles'];
        final authorName = author != null ? '${author['first_name'] ?? ''} ${author['last_name'] ?? ''}'.trim() : 'Система';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.stars_rounded, color: AppTheme.success, size: 20),
                    const SizedBox(width: 8),
                    Text(dateStr, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const Spacer(),
                    Text(authorName, style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textSecondary)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(content, style: const TextStyle(fontSize: 15, height: 1.4)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onEdit;
  const _InfoRow({required this.icon, required this.label, required this.value, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (onEdit != null)
              const Icon(Icons.edit_outlined, size: 14, color: AppTheme.primaryPurple),
          ],
        ),
      ),
    );
  }
}
