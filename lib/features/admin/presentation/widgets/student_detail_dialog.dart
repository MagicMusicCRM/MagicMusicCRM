import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/top_up_dialog.dart';

final studentCommentsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, studentId) {
      return ref
          .watch(magicCrmServiceProvider)
          .listComments(entityType: 'student', entityId: studentId);
    });

class StudentDetailDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> student;

  const StudentDetailDialog({super.key, required this.student});

  static Future<bool?> show(
    BuildContext context,
    Map<String, dynamic> student,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (_) => StudentDetailDialog(student: student),
    );
  }

  @override
  ConsumerState<StudentDetailDialog> createState() =>
      _StudentDetailDialogState();
}

class _StudentDetailDialogState extends ConsumerState<StudentDetailDialog> {
  late Map<String, dynamic> _studentData;
  Map<String, dynamic>? _studentCard;
  late TextEditingController _notesCtrl;
  late TextEditingController _commentCtrl;
  bool _saving = false;
  bool _inviting = false;

  bool _loadingMetadata = true;
  List<CrmCustomFieldDefinition> _customFieldSchema = const [];

  @override
  void initState() {
    super.initState();
    _studentData = Map<String, dynamic>.from(widget.student);
    final customData =
        _studentData['custom_data'] as Map<String, dynamic>? ?? {};
    _notesCtrl = TextEditingController(
      text: customData['notes']?.toString() ?? '',
    );
    _commentCtrl = TextEditingController();
    _loadStudent();
  }

  Future<void> _loadStudent() async {
    try {
      final id = _studentData['id']?.toString();
      final results = await Future.wait<dynamic>([
        if (id != null && id.isNotEmpty)
          ref.read(magicCrmServiceProvider).getStudentCard(id)
        else
          Future.value(_studentData),
        MagicSettingsService.getCrmCustomFields(),
      ]);
      if (!mounted) return;
      final payload = results[0] as Map<String, dynamic>;
      final card = payload['student'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(payload)
          : null;
      final student = card == null
          ? payload
          : card['student'] as Map<String, dynamic>;
      final customData = student['custom_data'] as Map<String, dynamic>? ?? {};
      _studentData = Map<String, dynamic>.from(student);
      _studentCard = card;
      _notesCtrl.text = customData['notes']?.toString() ?? '';
      if (mounted) {
        setState(() {
          _customFieldSchema = results[1] as List<CrmCustomFieldDefinition>;
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
      final customData = Map<String, dynamic>.from(
        _studentData['custom_data'] ?? {},
      );
      customData['notes'] = _notesCtrl.text;
      customData['middleName'] = _studentData['middle_name'];

      await ref
          .read(magicCrmServiceProvider)
          .updateStudent(
            id.toString(),
            firstName: _studentData['first_name']?.toString(),
            lastName: _studentData['last_name']?.toString(),
            phone: _studentData['phone']?.toString(),
            email: _studentData['email']?.toString(),
            customDataPatch: customData,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
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

  String? _linkSearchValue() {
    final profile = _studentData['profiles'] is Map<String, dynamic>
        ? _studentData['profiles'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final values = [
      _studentData['phone'],
      profile['phone'],
      _studentData['email'],
      profile['email'],
    ];
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  Future<void> _copyLinkSearchValue(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Контакт скопирован для связи')),
    );
  }

  void _openUserLinking(String value) {
    ref
        .read(crmNavigationRequestProvider.notifier)
        .navigateTo(CrmNavigationRequest.userRolesSearch(value));
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  String? _inviteEmail() {
    final profile = _studentData['profiles'] is Map<String, dynamic>
        ? _studentData['profiles'] as Map<String, dynamic>
        : const <String, dynamic>{};
    for (final value in [_studentData['email'], profile['email']]) {
      final email = value?.toString().trim().toLowerCase();
      if (email != null &&
          email.isNotEmpty &&
          !email.endsWith('@local.magicmusiccrm.invalid') &&
          !email.endsWith('@migration.invalid')) {
        return email;
      }
    }
    return null;
  }

  Future<void> _inviteStudent(String email) async {
    if (_inviting) return;
    final id = _studentData['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _inviting = true);
    try {
      await ref.read(magicCrmServiceProvider).inviteStudent(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Приглашение отправлено на $email')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить приглашение: $error')),
      );
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
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
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Ученик (ID: ${_studentData['hollihop_id'] ?? '—'})',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCrmCardSummary(),
                    const SizedBox(height: 16),
                    _sectionTitle('Общая информация'),
                    Row(
                      children: [
                        Expanded(child: _buildTextField('Имя', 'first_name')),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final res = await TopUpDialog.show(
                              context,
                              _studentData,
                            );
                            if (res == true && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Баланс пополнен',
                                    style: TextStyle(color: AppTheme.success),
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.add_card_rounded,
                            color: AppTheme.success,
                            size: 18,
                          ),
                          label: const Text(
                            'Пополнить баланс',
                            style: TextStyle(color: AppTheme.success),
                          ),
                        ),
                      ],
                    ),
                    _buildTextField('Фамилия', 'last_name'),
                    _buildTextField('Отчество', 'middle_name'),
                    _buildTextField(
                      'Телефон',
                      'phone',
                      keyboard: TextInputType.phone,
                    ),
                    _buildTextField(
                      'Электронная почта',
                      'email',
                      keyboard: TextInputType.emailAddress,
                    ),

                    const SizedBox(height: 16),
                    _sectionTitle('Дополнительно'),
                    if (_loadingMetadata)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: TableSkeleton(rows: 2, columns: 2),
                      )
                    else
                      ..._buildCustomFieldControls(
                        'students',
                        excludedKeys: const {
                          'hollihopId',
                          'middleName',
                          'notes',
                        },
                      ),

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
                    _CommentsList(studentId: _studentData['id'].toString()),
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
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Сохранить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCrmCardSummary() {
    final card = _studentCard;
    final groups = _cardList('groups');
    final lessons = _cardList('lessons');
    final payments = _cardList('payments');
    final tasks = _cardList('tasks');
    final expectedPayments = _cardList('expected_payments');
    final links = _cardList('links');
    final timeline = _cardList('timeline');
    final balance = card?['balance'] is Map
        ? Map<String, dynamic>.from(card!['balance'] as Map)
        : const <String, dynamic>{};
    final balanceValue = _asNum(balance['balance']);
    final totalPaid = _asNum(balance['total_paid']);
    final totalCost = _asNum(balance['total_cost']);
    final groupsCount = groups.isEmpty
        ? _asInt(_studentData['groups_count'])
        : groups.length;
    final lessonsCount = lessons.isEmpty
        ? _asInt(_studentData['lessons_count'])
        : lessons.length;
    final tasksCount = tasks.isEmpty
        ? _asInt(_studentData['open_tasks_count'])
        : tasks.length;
    final paymentsTotal = totalPaid > 0
        ? totalPaid
        : _asNum(_studentData['payments_total']);
    final hasAppAccount =
        links.isNotEmpty ||
        _studentData['linked_user_id'] != null ||
        _studentData['is_app_account'] == true;
    final linkedEmail = links.isNotEmpty
        ? links.first['email']?.toString() ?? ''
        : _studentData['linked_user_email']?.toString() ?? '';
    final linkSearchValue = hasAppAccount ? null : _linkSearchValue();
    final inviteEmail = hasAppAccount ? null : _inviteEmail();
    final balanceColor = balanceValue < 0
        ? AppTheme.danger
        : (balanceValue > 0 ? AppTheme.success : AppTheme.secondaryGold);

    if (card == null && _loadingMetadata) {
      return const TableSkeleton(rows: 2, columns: 3);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withAlpha(90),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CardMetric(
                icon: Icons.groups_rounded,
                label: 'Группы',
                value: groupsCount.toString(),
                color: AppTheme.primaryPurple,
              ),
              _CardMetric(
                icon: Icons.event_available_rounded,
                label: 'Занятия',
                value: lessonsCount.toString(),
                color: AppTheme.success,
              ),
              _CardMetric(
                icon: Icons.task_alt_rounded,
                label: 'Задачи',
                value: tasksCount.toString(),
                color: tasksCount == 0
                    ? AppTheme.secondaryGold
                    : AppTheme.warning,
              ),
              _CardMetric(
                icon: Icons.payments_rounded,
                label: 'Оплаты',
                value: '${_formatMoney(paymentsTotal)} ₽',
                color: AppTheme.secondaryGold,
              ),
              _CardMetric(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Баланс',
                value: '${_formatMoney(balanceValue)} ₽',
                color: balanceColor,
              ),
              _CardMetric(
                icon: hasAppAccount
                    ? Icons.verified_user_rounded
                    : Icons.person_off_rounded,
                label: 'Аккаунт',
                value: hasAppAccount ? 'Связан' : 'Нет',
                color: hasAppAccount ? AppTheme.success : AppTheme.warning,
              ),
            ],
          ),
          if (linkedEmail.trim().isNotEmpty ||
              linkSearchValue != null ||
              inviteEmail != null ||
              expectedPayments.isNotEmpty ||
              timeline.isNotEmpty ||
              totalCost > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                if (linkedEmail.trim().isNotEmpty)
                  _InlineFact(
                    icon: Icons.alternate_email_rounded,
                    text: linkedEmail.trim(),
                  ),
                if (linkSearchValue != null)
                  _InlineAction(
                    icon: Icons.content_copy_rounded,
                    text: 'Контакт для связи',
                    onTap: () => _copyLinkSearchValue(linkSearchValue),
                  ),
                if (linkSearchValue != null)
                  _InlineAction(
                    icon: Icons.manage_accounts_rounded,
                    text: 'Найти в пользователях',
                    onTap: () => _openUserLinking(linkSearchValue),
                  ),
                if (inviteEmail != null)
                  _InlineAction(
                    icon: Icons.mail_outline_rounded,
                    text: _inviting ? 'Отправка...' : 'Отправить приглашение',
                    onTap: () => _inviteStudent(inviteEmail),
                  ),
                if (expectedPayments.isNotEmpty)
                  _InlineFact(
                    icon: Icons.schedule_send_rounded,
                    text: 'Ожидаемых платежей: ${expectedPayments.length}',
                  ),
                if (timeline.isNotEmpty)
                  _InlineFact(
                    icon: Icons.history_rounded,
                    text: 'Событий: ${timeline.length}',
                  ),
                if (totalCost > 0)
                  _InlineFact(
                    icon: Icons.receipt_long_rounded,
                    text: 'Начислено: ${_formatMoney(totalCost)} ₽',
                  ),
              ],
            ),
          ],
          if (payments.isEmpty && lessons.isEmpty && tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'История ученика появится после импорта или первых операций.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _cardList(String key) {
    final raw = _studentCard?[key];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.primaryPurple,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    String key, {
    TextInputType? keyboard,
    bool isCustom = false,
  }) {
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

  List<Widget> _buildCustomFieldControls(
    String entity, {
    Set<String> excludedKeys = const {},
  }) {
    final fields = _customFieldSchema
        .where(
          (field) =>
              field.entity == entity && !excludedKeys.contains(field.key),
        )
        .toList();
    if (fields.isEmpty) {
      return [
        Text(
          'Дополнительные поля не настроены',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ];
    }
    return fields.map(_buildCustomFieldControl).toList();
  }

  Widget _buildCustomFieldControl(CrmCustomFieldDefinition field) {
    final customData = _studentData['custom_data'] as Map? ?? {};
    final rawValue = customData[field.key];
    final label = field.required ? '${field.label} *' : field.label;

    if (field.type == 'select') {
      final current = rawValue?.toString() ?? '';
      final initialValue = field.options.contains(current) ? current : '';
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: initialValue,
          decoration: InputDecoration(labelText: label, helperText: field.hint),
          items: [
            const DropdownMenuItem(value: '', child: Text('Не выбрано')),
            ...field.options.map(
              (option) => DropdownMenuItem(value: option, child: Text(option)),
            ),
          ],
          onChanged: (value) => _updateCustomData(
            field.key,
            value == null || value.isEmpty ? null : value,
          ),
        ),
      );
    }

    if (field.type == 'boolean') {
      return SwitchListTile(
        value: rawValue == true || rawValue?.toString() == 'true',
        onChanged: (value) => _updateCustomData(field.key, value),
        title: Text(label),
        subtitle: field.hint == null ? null : Text(field.hint!),
        contentPadding: EdgeInsets.zero,
      );
    }

    if (field.type == 'date') {
      return _buildDateCustomField(field, rawValue?.toString());
    }

    return _buildTextField(
      label,
      field.key,
      keyboard: _keyboardForCustomField(field.type),
      isCustom: true,
    );
  }

  Widget _buildDateCustomField(CrmCustomFieldDefinition field, String? value) {
    final dt = value == null ? null : DateTime.tryParse(value);
    final display = dt != null
        ? DateFormat('dd.MM.yyyy').format(dt)
        : 'Не выбрано';
    final label = field.required ? '${field.label} *' : field.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: dt ?? DateTime.now(),
            firstDate: DateTime(1950),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            _updateCustomData(field.key, picked.toIso8601String());
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, helperText: field.hint),
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

  TextInputType? _keyboardForCustomField(String type) {
    return switch (type) {
      'number' => TextInputType.number,
      'phone' => TextInputType.phone,
      'email' => TextInputType.emailAddress,
      'url' => TextInputType.url,
      _ => null,
    };
  }

  Widget _buildCommentInput() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _commentCtrl,
            decoration: const InputDecoration(
              hintText: 'Написать комментарий...',
              isDense: true,
            ),
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

    try {
      await ref
          .read(magicCrmServiceProvider)
          .createComment(
            entityType: 'student',
            entityId: _studentData['id'].toString(),
            body: text,
          );
      _commentCtrl.clear();
      ref.invalidate(studentCommentsProvider(_studentData['id'].toString()));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }
}

class _CardMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _CardMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 138,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(54)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineFact extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InlineFact({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineAction extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _InlineAction({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.primaryGold),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(
                color: AppTheme.primaryGold,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

num _asNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

String _formatMoney(num value) {
  return NumberFormat.decimalPattern('ru').format(value);
}

class _CommentsList extends ConsumerWidget {
  final String studentId;
  const _CommentsList({required this.studentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentCommentsProvider(studentId));
    return async.when(
      loading: () => const TimelineSkeleton(count: 2),
      error: (e, _) => Text(
        'Ошибка комментариев: $e',
        style: TextStyle(color: AppTheme.danger, fontSize: 12),
      ),
      data: (comments) {
        if (comments.isEmpty) {
          return Text(
            'Нет комментариев',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          );
        }

        return Column(
          children: comments.map((c) {
            final dt = DateTime.tryParse(c['created_at'] ?? '')?.toLocal();
            final dateStr = dt != null
                ? DateFormat('d MMM HH:mm').format(dt)
                : '';
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
                      Text(
                        c['author_name']?.toString() ?? 'Менеджер',
                        style: const TextStyle(
                          color: AppTheme.primaryPurple,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c['content']?.toString() ?? '',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
