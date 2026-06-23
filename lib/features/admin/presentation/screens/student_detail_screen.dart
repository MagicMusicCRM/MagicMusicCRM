import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/providers/chat_providers.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/client_app_user_panel.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class StudentDetailScreen extends ConsumerStatefulWidget {
  final String studentId;
  const StudentDetailScreen({super.key, required this.studentId});

  @override
  ConsumerState<StudentDetailScreen> createState() =>
      _StudentDetailScreenState();
}

class _StudentDetailScreenState extends ConsumerState<StudentDetailScreen> {
  Map<String, dynamic>? _student;
  Map<String, dynamic>? _balance;
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _lessons = [];
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _comments = [];
  // Two distinct, kind-discriminated comment streams shown on the Info card:
  // imported HolliHop admin comments and teacher-authored notes. The server
  // enforces RBAC and returns [] for users who may not see a given kind.
  List<Map<String, dynamic>> _adminComments = [];
  List<Map<String, dynamic>> _teacherNotes = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _expectedPayments = [];
  Map<String, dynamic>? _family;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      // Изолируем сбои отдельных секций: недоступность одной (напр. задач)
      // не должна ронять всю карточку. Списки → [], объекты → null.
      final results = await Future.wait<dynamic>([
        crm.getStudent(widget.studentId),
        crm
            .listPayments(studentId: widget.studentId, limit: 100)
            .catchError((_) => <Map<String, dynamic>>[]),
        crm
            .listLessons(studentId: widget.studentId, limit: 100)
            .catchError((_) => <Map<String, dynamic>>[]),
        crm
            .listTasks(studentId: widget.studentId, limit: 100)
            .catchError((_) => <Map<String, dynamic>>[]),
        crm
            .listStudentGroups(widget.studentId, limit: 100)
            .catchError((_) => <Map<String, dynamic>>[]),
        crm
            .listStudentBalances(studentId: widget.studentId, limit: 1)
            .catchError((_) => <Map<String, dynamic>>[]),
        crm
            .listComments(
              entityType: 'student',
              entityId: widget.studentId,
              limit: 100,
            )
            .catchError((_) => <Map<String, dynamic>>[]),
        crm
            .listExpectedPayments(studentId: widget.studentId, limit: 100)
            .catchError((_) => <Map<String, dynamic>>[]),
        (crm.getFamilyForEntity(
                  entityType: 'student',
                  entityId: widget.studentId,
                ) as Future<Map<String, dynamic>?>)
            .catchError((_) => null),
        crm
            .listComments(
              entityType: 'student',
              entityId: widget.studentId,
              kind: 'admin_comment',
              limit: 200,
            )
            .catchError((_) => <Map<String, dynamic>>[]),
        crm
            .listComments(
              entityType: 'student',
              entityId: widget.studentId,
              kind: 'teacher_note',
              limit: 200,
            )
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final studentRes = results[0] as Map<String, dynamic>;
      final paymentsRes = results[1] as List<Map<String, dynamic>>;
      final lessonsRes = results[2] as List<Map<String, dynamic>>;
      final tasksRes = results[3] as List<Map<String, dynamic>>;
      final groupsRes = results[4] as List<Map<String, dynamic>>;
      final balanceRows = results[5] as List<Map<String, dynamic>>;
      final commentsRes = results[6] as List<Map<String, dynamic>>;
      final expectedPaymentsRes = results[7] as List<Map<String, dynamic>>;
      final familyRes = results[8] as Map<String, dynamic>?;
      final adminCommentsRes = results[9] as List<Map<String, dynamic>>;
      final teacherNotesRes = results[10] as List<Map<String, dynamic>>;

      if (mounted) {
        setState(() {
          _student = studentRes;
          _balance = balanceRows.isEmpty ? null : balanceRows.first;
          _payments = paymentsRes;
          _lessons = lessonsRes;
          _tasks = tasksRes;
          _comments = commentsRes;
          _adminComments = adminCommentsRes;
          _teacherNotes = teacherNotesRes;
          _groups = groupsRes;
          _expectedPayments = expectedPaymentsRes;
          _family = familyRes;
          _tasks.sort(
            (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
          );
          _comments.sort(
            (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
          );
          // Newest-first, matching the existing _comments ordering.
          _adminComments.sort(
            (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
          );
          _teacherNotes.sort(
            (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
          );
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading student data: $e');
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const DetailPageSkeleton();
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColor.danger,
                ),
                const SizedBox(height: AppSpace.md),
                Text(
                  'Ошибка: $_error',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                TextButton(
                  onPressed: _loadAllData,
                  style: TextButton.styleFrom(foregroundColor: AppColor.gold),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_student == null) {
      return const Scaffold(body: Center(child: Text('Ученик не найден')));
    }

    final profile = _student!['profiles'] as Map<String, dynamic>?;
    final sfName = _student!['first_name']?.toString() ?? '';
    final slName = _student!['last_name']?.toString() ?? '';
    var name = '$sfName $slName'.trim();
    if (name.isEmpty && profile != null) {
      name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
          .trim();
    }
    final displayName = name.isEmpty ? 'Без имени' : name;
    // Contact fallback across both sources (student record + profile), matching
    // StudentDetailDialog so the same student shows the same contacts both ways.
    final phone =
        (_student!['phone']?.toString().trim().isNotEmpty == true
            ? _student!['phone']
            : profile?['phone']) ??
        '—';
    final email =
        (_student!['email']?.toString().trim().isNotEmpty == true
            ? _student!['email']
            : profile?['email']) ??
        '—';
    final customData = _student!['custom_data'] as Map<String, dynamic>? ?? {};
    // Parse balance defensively (it can arrive as a string) and color it
    // consistently: red < 0, green > 0, neutral at exactly 0.
    final balanceNum = _balance == null
        ? null
        : (_balance!['balance'] is num
              ? _balance!['balance'] as num
              : num.tryParse(_balance!['balance']?.toString() ?? ''));
    final balanceColor = balanceNum == null || balanceNum == 0
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : (balanceNum < 0 ? AppTheme.danger : AppTheme.success);

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(displayName, style: const TextStyle(fontSize: 18)),
              if (_balance != null)
                Text(
                  'Баланс: ${_balance!['balance']} ₽',
                  style: TextStyle(
                    fontSize: 12,
                    color: balanceColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(
                Icons.card_membership_rounded,
                color: AppTheme.primaryGold,
              ),
              tooltip: 'Выдать абонемент',
              onPressed: _showIssueSubscriptionSheet,
            ),
            IconButton(
              icon: const Icon(
                Icons.assignment_rounded,
                color: AppTheme.primaryGold,
              ),
              tooltip: 'Задать ДЗ',
              onPressed: _showAssignHomeworkSheet,
            ),
            if (_student != null &&
                (_student!['profile_user_id']?.toString().isNotEmpty == true ||
                    (_student!['profiles'] as Map<String, dynamic>?)?['user_id']
                            ?.toString()
                            .isNotEmpty ==
                        true))
              IconButton(
                icon: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppTheme.primaryGold,
                ),
                tooltip: 'Перейти в чат',
                onPressed: () {
                  final profileMap =
                      _student!['profiles'] as Map<String, dynamic>?;
                  final userId =
                      _student!['profile_user_id']?.toString() ??
                      profileMap?['user_id']?.toString();
                  if (userId == null || userId.isEmpty) return;
                  // Set the navigation target
                  ref
                      .read(messengerNavigationProvider.notifier)
                      .navigateTo(MessengerNavigationState(partnerId: userId));

                  // Navigate back to the dashboard where MessengerScreen is hosted
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    // Fallback to dashboard if we can't pop
                    context.go('/');
                  }
                },
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            labelColor: AppTheme.primaryGold,
            unselectedLabelColor: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant,
            indicatorColor: AppTheme.primaryGold,
            tabs: const [
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

  Widget _buildInfoTab(
    String phone,
    String email,
    Map<String, dynamic> customData,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard('Контактные данные', [
          _InfoRow(icon: Icons.phone_rounded, label: 'Телефон', value: phone),
          _InfoRow(
            icon: Icons.email_rounded,
            label: 'Электронная почта',
            value: email,
          ),
        ]),
        const SizedBox(height: 16),
        ClientAppUserPanel(
          entityType: 'student',
          entityId: widget.studentId,
        ),
        SizedBox(height: 16),
        _buildInfoCard('Дополнительная информация', [
          _InfoRow(
            icon: Icons.cake_rounded,
            label: 'День рождения',
            value: _student!['birthday'] ?? '—',
          ),
          _InfoRow(
            icon: Icons.person_outline_rounded,
            label: 'Пол',
            value: _student!['gender'] == 'male'
                ? 'Мужской'
                : (_student!['gender'] == 'female' ? 'Женский' : '—'),
          ),
          if ((_student!['hollihop_id']?.toString().trim().isNotEmpty ?? false))
            _InfoRow(
              icon: Icons.fingerprint_rounded,
              label: 'Идентификатор HolliHop',
              value: _student!['hollihop_id'].toString(),
            ),
          ...customData.entries
              .where(
                (e) =>
                    !_isHiddenCustomDataRow(e.key) &&
                    (e.value?.toString().trim().isNotEmpty ?? false),
              )
              .map(
                (e) => _InfoRow(
                  icon: Icons.info_outline_rounded,
                  label: e.key,
                  value: e.value.toString(),
                ),
              ),
        ]),
        SizedBox(height: 16),
        _buildInfoCard('Финансовые настройки', [
          _InfoRow(
            icon: Icons.payments_outlined,
            label: 'Цена инд. занятия',
            // Show an explicit unset state instead of a confident default a
            // manager might bill on.
            value: _student!['individual_price'] != null
                ? '${_student!['individual_price']} ₽'
                : 'Не задана',
            onEdit: () => _editPrice(),
          ),
          if (_balance != null) ...[
            _InfoRow(
              icon: Icons.summarize_outlined,
              label: 'Всего оплачено',
              value: '${_balance!['total_paid']} ₽',
            ),
            _InfoRow(
              icon: Icons.history_edu_outlined,
              label: 'Списано за уроки',
              value: '${_balance!['total_cost']} ₽',
            ),
          ],
        ]),
        SizedBox(height: 16),
        _buildInfoCard('Группы', [
          if (_groups.isEmpty)
            const _InfoRow(
              icon: Icons.group_off_rounded,
              label: 'Группы',
              value: 'Нет активных групп',
            )
          else
            ..._groups.map((g) {
              final teacher = g['teachers'];
              String tName = '—';
              if (teacher != null) {
                final tfName = teacher['first_name']?.toString() ?? '';
                final tlName = teacher['last_name']?.toString() ?? '';
                final p = teacher['profiles'] as Map<String, dynamic>?;
                tName = '$tfName $tlName'.trim();
                if (tName.isEmpty && p != null) {
                  tName = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'
                      .trim();
                }
              }
              return _InfoRow(
                icon: Icons.group_rounded,
                label: g['name'] ?? 'Группа',
                value: 'Преп.: $tName',
              );
            }),
        ]),
        const SizedBox(height: 16),
        _buildInfoCard('Семья', _buildFamilyRows()),
        const SizedBox(height: 16),
        _buildCommentsCard(
          title: 'Комментарии администратора',
          icon: Icons.admin_panel_settings_rounded,
          accent: AppColor.gold,
          comments: _adminComments,
          emptyLabel: 'Комментариев нет',
          addLabel: '+ Комментарий',
          onAdd: () => _addComment(kind: 'admin_comment'),
        ),
        const SizedBox(height: 16),
        _buildCommentsCard(
          title: 'Заметки преподавателя',
          icon: Icons.school_rounded,
          accent: AppColor.gold,
          comments: _teacherNotes,
          emptyLabel: 'Заметок преподавателя ещё нет',
          addLabel: '+ Заметка',
          onAdd: () => _addComment(kind: 'teacher_note'),
        ),
      ],
    );
  }

  /// Renders one of the two kind-discriminated comment sections (admin comments
  /// / teacher notes) using the file's existing card + section style. The list
  /// is capped and scrollable so imported HolliHop notes (which can run to the
  /// hundreds) never blow out the card height.
  Widget _buildCommentsCard({
    required String title,
    required IconData icon,
    required Color accent,
    required List<Map<String, dynamic>> comments,
    required String emptyLabel,
    required String addLabel,
    required VoidCallback onAdd,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: accent,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onAdd,
                  style: TextButton.styleFrom(
                    foregroundColor: accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(addLabel),
                ),
              ],
            ),
            const Divider(height: 24),
            if (comments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  emptyLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ConstrainedBox(
                // Cap the height so hundreds of imported notes stay scrollable
                // inside the card instead of pushing the page down endlessly.
                constraints: const BoxConstraints(maxHeight: 320),
                child: Scrollbar(
                  child: ListView.separated(
                    shrinkWrap: true,
                    primary: false,
                    padding: EdgeInsets.zero,
                    // Display at most 200 rows even if more were returned.
                    itemCount:
                        comments.length > 200 ? 200 : comments.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 16),
                    itemBuilder: (context, i) => _CommentRow(comment: comments[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFamilyRows() {
    final family = _family?['family'] as Map<String, dynamic>?;
    final members = (_family?['members'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const <Map<String, dynamic>>[];
    if (family == null || members.isEmpty) {
      return const [
        _InfoRow(
          icon: Icons.people_outline_rounded,
          label: 'Семья',
          value: 'Не указана',
        ),
      ];
    }
    final primaryId = family['primary_payer_member_id']?.toString();
    return members.map((m) {
      final role = switch (m['role']?.toString()) {
        'parent' => 'Родитель',
        'child' => 'Ребёнок',
        'guardian' => 'Опекун',
        'payer' => 'Плательщик',
        'sibling' => 'Брат/сестра',
        final v when v != null && v.isNotEmpty => v,
        _ => 'Член семьи',
      };
      final isPayer = primaryId != null && m['id']?.toString() == primaryId;
      final label = [
        role,
        if (m['is_primary_contact'] == true) 'осн. контакт',
        if (isPayer) 'плательщик',
      ].join(' · ');
      return _InfoRow(
        icon: Icons.people_alt_rounded,
        label: label,
        value: (m['name']?.toString().trim().isNotEmpty ?? false)
            ? m['name'].toString()
            : 'Без имени',
      );
    }).toList();
  }

  bool _isHiddenCustomDataRow(String key) {
    // Internal / system custom_data keys that must never be surfaced to users.
    // Matched case-insensitively so backend variants (camelCase / snake_case)
    // are all caught.
    const hidden = {
      'hollihopid',
      'hollihop_id',
      'hollihopstudentid',
      'hollihop_student_id',
      'externalid',
      'external_id',
      'demoaccount',
      'demo_account',
      'isdemo',
      'is_demo',
      'sourceleadid',
      'source_lead_id',
      'leadid',
      'lead_id',
      'branchid',
      'branch_id',
      'disciplineid',
      'discipline_id',
      'disciplineinternal',
      'discipline_internal',
    };
    return hidden.contains(key.trim().toLowerCase());
  }

  Widget? _buildFAB() {
    return Builder(
      builder: (context) {
        final tabIndex = DefaultTabController.of(context).index;
        if (tabIndex == 3) {
          return FloatingActionButton.extended(
            onPressed: _showAddHistoryDialog,
            label: Text('Добавить'),
            icon: Icon(Icons.add_rounded),
            backgroundColor: AppTheme.primaryGold,
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
            leading: Icon(Icons.comment_rounded, color: AppTheme.primaryGold),
            title: Text('Добавить комментарий'),
            onTap: () => Navigator.pop(ctx, 'comment'),
          ),
          ListTile(
            leading: Icon(Icons.auto_graph_rounded, color: AppTheme.success),
            title: Text('Заметка о прогрессе'),
            onTap: () => Navigator.pop(ctx, 'progress'),
          ),
          SizedBox(height: 20),
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

  /// Title shown in the add-comment dialog for the kind-discriminated sections.
  String _commentDialogTitle(String? kind) {
    switch (kind) {
      case 'admin_comment':
        return 'Новый комментарий администратора';
      case 'teacher_note':
        return 'Новая заметка преподавателя';
      default:
        return 'Новый комментарий';
    }
  }

  /// Adds a comment. When [kind] is `admin_comment` or `teacher_note` the
  /// comment is created via the kind discriminator and the matching section is
  /// refreshed. When [isProgress] is set the legacy `[PROGRESS]` note flow runs
  /// against `_comments`. Plain comments keep their original optimistic flow.
  Future<void> _addComment({bool isProgress = false, String? kind}) async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isProgress
              ? 'Заметка о прогрессе'
              : _commentDialogTitle(kind),
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: isProgress
                ? 'Опишите успехи ученика...'
                : 'Введите текст...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('Сохранить'),
          ),
        ],
      ),
    );

    if (content == null || content.trim().isEmpty) return;

    // Kind-discriminated sections (admin comments / teacher notes) use the
    // server's `kind` field. Create, then refresh the matching list.
    if (kind == 'admin_comment' || kind == 'teacher_note') {
      try {
        final saved = await ref
            .read(magicCrmServiceProvider)
            .createComment(
              entityType: 'student',
              entityId: widget.studentId,
              body: content.trim(),
              kind: kind,
            );
        if (!mounted) return;
        setState(() {
          final list = kind == 'admin_comment'
              ? _adminComments
              : _teacherNotes;
          list.insert(0, saved);
          list.sort(
            (a, b) =>
                (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
          );
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось добавить запись: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      return;
    }

    {
      final body = isProgress ? '[PROGRESS] ${content.trim()}' : content.trim();
      final tempId = 'local-${DateTime.now().microsecondsSinceEpoch}';
      final optimistic = {
        'id': tempId,
        'entity_type': 'student',
        'entity_id': widget.studentId,
        'content': body,
        'body': body,
        'created_at': DateTime.now().toIso8601String(),
        'profiles': {'first_name': 'Вы', 'last_name': ''},
        '_pending': true,
      };
      setState(() {
        _comments.insert(0, optimistic);
      });
      try {
        final saved = await ref
            .read(magicCrmServiceProvider)
            .createComment(
              entityType: 'student',
              entityId: widget.studentId,
              body: content.trim(),
              progress: isProgress,
            );
        if (!mounted) return;
        setState(() {
          final index = _comments.indexWhere((item) => item['id'] == tempId);
          if (index >= 0) _comments[index] = saved;
          _comments.sort(
            (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
          );
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _comments.removeWhere((item) => item['id'] == tempId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось добавить комментарий: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _addTask() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Новая задача'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Что нужно сделать?',
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Детали'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Создать'),
          ),
        ],
      ),
    );

    if (result == true && titleCtrl.text.isNotEmpty) {
      await ref
          .read(magicCrmServiceProvider)
          .createTask(
            entityType: 'student',
            entityId: widget.studentId,
            title: titleCtrl.text.trim(),
            description: descCtrl.text.trim(),
            status: 'open',
          );
      _loadAllData();
    }
  }

  Future<void> _editPrice() async {
    final controller = TextEditingController(
      text: _student!['individual_price']?.toString(),
    );
    final newPrice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Цена занятия'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Сумма (₽)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('Сохранить'),
          ),
        ],
      ),
    );

    if (newPrice != null && double.tryParse(newPrice) != null) {
      try {
        final price = double.parse(newPrice);
        await ref
            .read(magicCrmServiceProvider)
            .updateStudent(
              widget.studentId,
              customDataPatch: {
                'individualPrice': price,
                'individual_price': price,
              },
            );
        _loadAllData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
        }
      }
    }
  }

  // ── v7 helpers (P5b/P5c) ───────────────────────────────────────────────────
  /// Flat gold button — `AppColor.gold` fill, `AppColor.onGold` label, no
  /// shadow (per the Magic Music rule: shadows/glow forbidden on primary
  /// buttons).
  Widget _goldButton(String label, VoidCallback? onPressed) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColor.gold,
        foregroundColor: AppColor.onGold,
        disabledBackgroundColor: AppColor.goldSoft,
        disabledForegroundColor: AppColor.text2,
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }

  /// Ghost (outline) button used for «Отмена» in v7 sheets.
  Widget _ghostButton(String label, VoidCallback? onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColor.text,
        side: const BorderSide(color: AppColor.divider),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }

  // ── (1) «Выдать абонемент» ─────────────────────────────────────────────────
  Future<void> _showIssueSubscriptionSheet() async {
    final crm = ref.read(magicCrmServiceProvider);
    List<Map<String, dynamic>> packages;
    try {
      packages = await crm.listSubscriptionPackages(limit: 100);
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось загрузить абонементы',
        detail: '$e',
        type: MagicToastType.danger,
      );
      return;
    }
    if (!mounted) return;

    if (packages.isEmpty) {
      MagicToast.show(
        context,
        'Нет доступных абонементов',
        type: MagicToastType.info,
      );
      return;
    }

    final selected = await showMagicSheet<Map<String, dynamic>>(
      context,
      title: 'Выдать абонемент',
      subtitle: 'Выберите пакет занятий',
      icon: Icons.card_membership_rounded,
      builder: (sheetContext) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final pkg in packages) ...[
              _SubscriptionPackageTile(
                package: pkg,
                onTap: () => Navigator.pop(sheetContext, pkg),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          ],
        );
      },
    );

    if (selected == null || !mounted) return;

    final packageId = selected['id']?.toString();
    if (packageId == null || packageId.isEmpty) return;

    try {
      await crm.issueSubscription(widget.studentId, packageId);
      if (!mounted) return;
      MagicToast.show(
        context,
        'Абонемент выдан',
        detail: selected['name']?.toString(),
        type: MagicToastType.success,
      );
      _loadAllData();
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось выдать абонемент',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  // ── (2) «Задать ДЗ» ────────────────────────────────────────────────────────
  Future<void> _showAssignHomeworkSheet() async {
    final crm = ref.read(magicCrmServiceProvider);

    List<Map<String, dynamic>> homeworks = const [];
    try {
      homeworks = await crm.listHomeworks(studentId: widget.studentId, limit: 5);
    } catch (_) {
      // Listing is best-effort; the assign form still works without it.
    }
    if (!mounted) return;

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime? dueAt;

    final created = await showMagicSheet<bool>(
      context,
      title: 'Задать ДЗ',
      subtitle: 'Новое домашнее задание',
      icon: Icons.assignment_rounded,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final dueLabel = dueAt == null
                ? 'Срок не задан'
                : DateFormat('d MMM yyyy, HH:mm', 'ru').format(dueAt!);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Заголовок *',
                    hintText: 'Что нужно выучить?',
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Описание',
                    hintText: 'Подробности (необязательно)',
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: () async {
                    final now = DateTime.now();
                    final date = await showDatePicker(
                      context: sheetContext,
                      initialDate: dueAt ?? now,
                      firstDate: now.subtract(const Duration(days: 1)),
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (date == null || !sheetContext.mounted) return;
                    final time = await showTimePicker(
                      context: sheetContext,
                      initialTime: TimeOfDay.fromDateTime(dueAt ?? now),
                    );
                    setSheetState(() {
                      dueAt = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time?.hour ?? 0,
                        time?.minute ?? 0,
                      );
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                      vertical: AppSpace.md,
                    ),
                    decoration: BoxDecoration(
                      color: AppColor.input,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: AppColor.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.event_rounded,
                          size: 18,
                          color: AppColor.gold,
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Text(
                            dueLabel,
                            style: TextStyle(
                              fontSize: 14,
                              color: dueAt == null
                                  ? AppColor.text2
                                  : AppColor.text,
                            ),
                          ),
                        ),
                        if (dueAt != null)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            color: AppColor.text2,
                            tooltip: 'Сбросить срок',
                            onPressed: () => setSheetState(() => dueAt = null),
                          ),
                      ],
                    ),
                  ),
                ),
                if (homeworks.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.lg),
                  const Divider(height: 1, color: AppColor.divider),
                  const SizedBox(height: AppSpace.md),
                  const Text(
                    'Последние ДЗ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColor.gold,
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  for (final hw in homeworks)
                    _HomeworkTile(homework: hw),
                ],
              ],
            );
          },
        );
      },
      actions: [
        _ghostButton('Отмена', () => Navigator.pop(context, false)),
        _goldButton('Создать', () {
          if (titleCtrl.text.trim().isEmpty) {
            MagicToast.show(
              context,
              'Введите заголовок',
              type: MagicToastType.danger,
            );
            return;
          }
          Navigator.pop(context, true);
        }),
      ],
    );

    if (created != true || !mounted) return;

    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;

    try {
      await crm.createHomework(
        studentId: widget.studentId,
        title: title,
        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        dueAt: dueAt?.toIso8601String(),
      );
      if (!mounted) return;
      MagicToast.show(
        context,
        'ДЗ создано',
        detail: title,
        type: MagicToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось создать ДЗ',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppTheme.primaryGold,
              ),
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentsTab() {
    if (_payments.isEmpty) {
      return Center(
        child: Text(
          'Оплат не найдено',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _payments.length,
      itemBuilder: (context, i) {
        final p = _payments[i];
        final dt = DateTime.tryParse(p['payment_date'] ?? '');
        final dateStr = dt != null
            ? DateFormat('d MMM yyyy', 'ru').format(dt)
            : '—';
        final paymentNote = (p['notes'] ?? p['description'] ?? '')
            .toString()
            .trim();
        final method = (p['method'] ?? p['type'] ?? '').toString().trim();
        final subtitle = [
          dateStr,
          if (paymentNote.isNotEmpty) paymentNote,
        ].join(' • ');
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              Icons.account_balance_wallet_rounded,
              color: AppTheme.success,
            ),
            title: Text(
              '${p['amount']} ₽',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(subtitle),
            trailing: method.isEmpty
                ? null
                : Text(
                    method,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildLessonsTab() {
    if (_lessons.isEmpty) {
      return Center(
        child: Text(
          'Занятий не найдено',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _lessons.length,
      itemBuilder: (context, i) {
        final l = _lessons[i];
        final dt = DateTime.tryParse(l['scheduled_at'] ?? '');
        final dateStr = dt != null
            ? DateFormat('d MMM, HH:mm', 'ru').format(dt)
            : '—';
        final teacherData = l['teachers'] as Map<String, dynamic>?;
        String teacherName = '—';
        if (teacherData != null) {
          final tfName = teacherData['first_name']?.toString() ?? '';
          final tlName = teacherData['last_name']?.toString() ?? '';
          final p = teacherData['profiles'] as Map<String, dynamic>?;
          var tName = '$tfName $tlName'.trim();
          if (tName.isEmpty && p != null) {
            tName = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
          }
          teacherName = tName.isEmpty ? '—' : tName;
        }
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              dateStr,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Преп.: $teacherName • ${l['groups']?['name'] ?? 'Инд.'}',
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:
                    (l['status'] == 'completed'
                            ? AppTheme.success
                            : AppTheme.primaryGold)
                        .withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l['status'] == 'completed' ? 'Завершено' : 'Запланировано',
                style: TextStyle(
                  fontSize: 11,
                  color: l['status'] == 'completed'
                      ? AppTheme.success
                      : AppTheme.primaryGold,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInvoicesTab() {
    if (_expectedPayments.isEmpty) {
      return Center(
        child: Text(
          'Инвойсов не найдено',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _expectedPayments.length,
      itemBuilder: (context, i) {
        final p = _expectedPayments[i];
        final dt = DateTime.tryParse(p['due_date'] ?? '');
        final dateStr = dt != null
            ? DateFormat('d MMM yyyy', 'ru').format(dt)
            : '—';
        final status = p['status'] ?? 'pending';
        final description = (p['description'] ?? '').toString().trim();
        final subtitle = [
          'Срок: $dateStr',
          if (description.isNotEmpty) description,
        ].join(' • ');

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              status == 'paid'
                  ? Icons.check_circle_rounded
                  : Icons.pending_actions_rounded,
              color: status == 'paid' ? AppTheme.success : AppTheme.warning,
            ),
            title: Text(
              '${p['amount']} ₽',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(subtitle),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (status == 'paid' ? AppTheme.success : AppTheme.warning)
                    .withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status == 'paid' ? 'Оплачено' : 'Ожидает',
                style: TextStyle(
                  fontSize: 11,
                  color: status == 'paid' ? AppTheme.success : AppTheme.warning,
                  fontWeight: FontWeight.w600,
                ),
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
            leading: Icon(
              Icons.description_rounded,
              color: AppTheme.primaryGold,
            ),
            title: Text('Основной договор'),
            subtitle: Text(contractUrl ?? 'Не прикреплен'),
            trailing: IconButton(
              icon: Icon(
                contractUrl != null
                    ? Icons.edit_rounded
                    : Icons.add_link_rounded,
              ),
              onPressed: _editContractUrl,
            ),
            onTap: contractUrl != null
                ? () => _openContractUrl(contractUrl)
                : null,
          ),
        ]),
      ],
    );
  }

  Future<void> _openContractUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Некорректная ссылка на договор')),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть договор')),
      );
    }
  }

  Future<void> _editContractUrl() async {
    final controller = TextEditingController(text: _student!['contract_url']);
    final newUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ссылка на договор'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://...',
            labelText: 'Ссылка на документ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('Сохранить'),
          ),
        ],
      ),
    );

    if (newUrl != null) {
      await ref
          .read(magicCrmServiceProvider)
          .updateStudent(
            widget.studentId,
            customDataPatch: {
              'legacyContractUrl': newUrl.trim(),
              'contract_url': newUrl.trim(),
            },
          );
      _loadAllData();
    }
  }

  Widget _buildHistoryTab() {
    if (_tasks.isEmpty && _comments.isEmpty) {
      return Center(
        child: Text(
          'История пуста',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final items = [
      ..._tasks.map(
        (t) => {'type': 'task', 'data': t, 'date': t['created_at']},
      ),
      ..._comments
          .where(
            (c) =>
                !(c['content']?.toString().startsWith('[PROGRESS]') ?? false),
          )
          .map((c) => {'type': 'comment', 'data': c, 'date': c['created_at']}),
    ];
    items.sort(
      (a, b) => ((b['date'] as String?) ?? '').compareTo(
        (a['date'] as String?) ?? '',
      ),
    );

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        final isTask = item['type'] == 'task';
        final data = item['data'] as Map<String, dynamic>;
        final dt = DateTime.tryParse(item['date'] as String? ?? '');
        final dateStr = dt != null
            ? DateFormat('d MMM HH:mm', 'ru').format(dt.toLocal())
            : '—';

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
                        Icon(
                          isTask
                              ? Icons.task_alt_rounded
                              : Icons.comment_rounded,
                          size: 16,
                          color: isTask
                              ? AppTheme.warning
                              : AppTheme.primaryGold,
                        ),
                        SizedBox(width: 8),
                        Text(
                          isTask ? 'Задача' : 'Комментарий',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isTask
                                ? AppTheme.warning
                                : AppTheme.primaryGold,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  isTask ? (data['title'] ?? '') : (data['content'] ?? ''),
                  style: const TextStyle(fontSize: 14),
                ),
                if (isTask && data['description'] != null) ...[
                  SizedBox(height: 4),
                  Text(
                    data['description'],
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressTab() {
    final progressNotes = _comments
        .where(
          (c) => c['content']?.toString().startsWith('[PROGRESS]') ?? false,
        )
        .toList();

    if (progressNotes.isEmpty) {
      return Center(
        child: Text(
          'Заметок об успехах ещё нет',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: progressNotes.length,
      itemBuilder: (ctx, i) {
        final note = progressNotes[i];
        final content = (note['content'] as String).replaceFirst(
          '[PROGRESS] ',
          '',
        );
        final dt = DateTime.tryParse(note['created_at'] ?? '');
        final dateStr = dt != null
            ? DateFormat('d MMM yyyy, HH:mm', 'ru').format(dt.toLocal())
            : '—';
        final author = note['profiles'];
        final authorName = author != null
            ? '${author['first_name'] ?? ''} ${author['last_name'] ?? ''}'
                  .trim()
            : 'Система';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.stars_rounded,
                      color: AppTheme.success,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      authorName,
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  content,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
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
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (onEdit != null)
              Icon(
                Icons.edit_outlined,
                size: 14,
                color: AppTheme.primaryGold,
              ),
          ],
        ),
      ),
    );
  }
}

/// One comment row for the «Комментарии администратора» / «Заметки
/// преподавателя» sections: body, optional author, and date. Author/date sit on
/// a single trailing line so hundreds of imported HolliHop notes stay compact.
class _CommentRow extends StatelessWidget {
  final Map<String, dynamic> comment;
  const _CommentRow({required this.comment});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final body = (comment['body'] ?? comment['content'] ?? '')
        .toString()
        .trim();
    final author = (comment['author_name'] ?? '').toString().trim();
    final dt = DateTime.tryParse(comment['created_at']?.toString() ?? '');
    final dateStr = dt != null
        ? DateFormat('d MMM yyyy, HH:mm', 'ru').format(dt.toLocal())
        : '';
    final meta = [
      if (author.isNotEmpty) author,
      if (dateStr.isNotEmpty) dateStr,
    ].join(' • ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          body.isEmpty ? '—' : body,
          style: const TextStyle(fontSize: 14, height: 1.35),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            meta,
            style: TextStyle(
              fontSize: 11,
              color: muted,
            ),
          ),
        ],
      ],
    );
  }
}

/// Selectable subscription-package row inside the «Выдать абонемент» v7 sheet.
class _SubscriptionPackageTile extends StatelessWidget {
  final Map<String, dynamic> package;
  final VoidCallback onTap;
  const _SubscriptionPackageTile({required this.package, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = package['name']?.toString() ?? 'Абонемент';
    final lessons = package['lessons_total'] ?? package['lessonsTotal'];
    final price = package['price'];
    final validity = package['validity_days'] ?? package['validityDays'];
    final meta = [
      if (lessons != null) '$lessons зан.',
      if (price != null) '$price ₽',
      if (validity != null) '$validity дн.',
    ].join(' · ');

    return Material(
      color: AppColor.input,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: AppColor.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColor.goldSoft,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: AppColor.goldLine),
                ),
                child: const Icon(
                  Icons.card_membership_rounded,
                  size: 18,
                  color: AppColor.gold,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColor.text,
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          meta,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColor.text2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColor.text2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact read-only homework row for the «Последние ДЗ» section in the
/// «Задать ДЗ» v7 sheet.
class _HomeworkTile extends StatelessWidget {
  final Map<String, dynamic> homework;
  const _HomeworkTile({required this.homework});

  @override
  Widget build(BuildContext context) {
    final title = homework['title']?.toString() ?? '—';
    final status = homework['status']?.toString();
    final dueRaw = homework['due_at'] ?? homework['dueAt'];
    final due = DateTime.tryParse(dueRaw?.toString() ?? '');
    final subtitle = [
      if (status != null && status.isNotEmpty) _statusLabel(status),
      if (due != null) DateFormat('d MMM yyyy', 'ru').format(due.toLocal()),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.assignment_outlined,
              size: 16,
              color: AppColor.text2,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColor.text),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColor.text2,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'assigned':
        return 'Назначено';
      case 'submitted':
        return 'Сдано';
      case 'done':
      case 'completed':
        return 'Завершено';
      default:
        return status;
    }
  }
}
