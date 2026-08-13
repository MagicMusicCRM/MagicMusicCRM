import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/provision_access_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/person_lifecycle_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/person_access_role_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_employment_fields.dart';

part 'teacher_detail_widgets.dart';

class TeacherDetailDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> teacher;

  const TeacherDetailDialog({super.key, required this.teacher});

  static Future<bool?> show(
    BuildContext context,
    Map<String, dynamic> teacher,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => TeacherDetailDialog(teacher: teacher),
    );
  }

  @override
  ConsumerState<TeacherDetailDialog> createState() =>
      _TeacherDetailDialogState();
}

class _TeacherDetailDialogState extends ConsumerState<TeacherDetailDialog> {
  late Map<String, dynamic> _localData;
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late String _canonicalPhone;
  bool _saving = false;
  final _employmentKey = GlobalKey<TeacherEmploymentFieldsState>();
  late final TeacherEmploymentInitial _employmentInitial;

  // KVA-238: блок «Оплаты преподавателю». null = ещё грузится или нет прав.
  Map<String, dynamic>? _payroll;
  bool _payrollVisible = true;
  Object? _payrollError;
  bool _payrollMutating = false;

  final _money = NumberFormat('#,##0', 'ru');

  String get _teacherId => _localData['id'].toString();
  bool get _canManagePayrollHistory => const {
    'director',
    'system_admin',
  }.contains(ref.read(capabilitySnapshotProvider).asData?.value.role);
  String get _actorRole =>
      ref.read(capabilitySnapshotProvider).asData?.value.role ?? '';

  @override
  void initState() {
    super.initState();
    _localData = Map<String, dynamic>.from(widget.teacher);
    final fn = _localData['first_name']?.toString() ?? '';
    final ln = _localData['last_name']?.toString() ?? '';
    final prof = _localData['profiles'] as Map<String, dynamic>?;
    final profileName =
        '${prof?['first_name'] ?? ''} ${prof?['last_name'] ?? ''}'.trim();
    final name = '$fn $ln'.trim();

    _nameController = TextEditingController(
      text: name.isEmpty ? profileName : name,
    );
    _canonicalPhone =
        _localData['phone']?.toString() ?? prof?['phone']?.toString() ?? '';
    _emailController = TextEditingController(
      text: _localData['email']?.toString() ?? '',
    );

    final custom = _localData['custom_data'] is Map<String, dynamic>
        ? _localData['custom_data'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final currentRate = _localData['current_rate'] is num
        ? _localData['current_rate'] as num
        : num.tryParse(_localData['current_rate']?.toString() ?? '');
    final salary = _localData['salary'] is num
        ? _localData['salary'] as num
        : num.tryParse(_localData['salary']?.toString() ?? '');
    _employmentInitial = TeacherEmploymentInitial(
      branches: _asMapList(_localData['assigned_branches']),
      disciplines: _asMapList(_localData['disciplines']),
      levels: _readMulti(custom, 'levels', 'level'),
      categories: _readMulti(custom, 'categories', 'category'),
      birthday: _parseDate(custom['birthday']),
      workStartDate: _parseDate(custom['workStartDate']),
      isPartTime: custom['isPartTime'] == true,
      isBlacklisted: custom['isBlacklisted'] == true,
      salary: salary,
      rate: currentRate,
    );

    _loadPayroll();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Existing rows are a mess: the plural key may hold a list, the legacy
  /// singular key a free-text string ("Начальный, Средний" from the HolliHop
  /// import). Read both so nothing already entered disappears from the card.
  static Set<String> _readMulti(
    Map<String, dynamic> custom,
    String pluralKey,
    String legacyKey,
  ) {
    final raw = custom[pluralKey] ?? custom[legacyKey];
    if (raw is List) {
      return {
        for (final value in raw)
          if (value?.toString().trim().isNotEmpty == true)
            value.toString().trim(),
      };
    }
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return {};
    return {
      for (final part in text.split(RegExp(r'[,;]')))
        if (part.trim().isNotEmpty) part.trim(),
    };
  }

  Future<void> _loadPayroll() async {
    if (mounted) {
      setState(() {
        _payrollError = null;
        _payrollVisible = true;
      });
    }
    try {
      final payroll = await ref
          .read(magicCrmServiceProvider)
          .getTeacherPayroll(_teacherId);
      if (!mounted) return;
      setState(() => _payroll = payroll);
    } catch (error) {
      if (!mounted) return;
      setState(() => _payrollError = error);
    }
  }

  Future<String?> _requestPayrollChangeReason(
    TeacherEmploymentValue employment,
  ) async {
    final controller = TextEditingController();
    String? errorText;
    final changes = <String>[
      if (employment.salaryChanged)
        'Оклад: ${_money.format(_employmentInitial.salary ?? 0)} → '
            '${_money.format(employment.salary ?? 0)} ₽',
      if (employment.rateChanged)
        'Ставка: ${_money.format(_employmentInitial.rate ?? 0)} → '
            '${_money.format(employment.rate ?? 0)} ₽/ч',
    ];
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Подтвердите финансовые условия'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(changes.join('\n')),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Причина изменения',
                    hintText: 'Например: новые условия с 1 сентября',
                    errorText: errorText,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(() => errorText = 'Укажите причину');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Подтвердить и сохранить'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите имя преподавателя.')),
      );
      return;
    }
    final employment = _employmentKey.currentState?.validateAndRead();
    if (employment == null) return;
    final payrollChanged = employment.salaryChanged || employment.rateChanged;
    int? payrollExpectedVersion;
    String? payrollReasonText;
    if (payrollChanged) {
      if (_payroll == null || _payrollError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось проверить версию расчётов. Обновите блок оплат и повторите.',
            ),
          ),
        );
        return;
      }
      payrollExpectedVersion = _num(_payroll!['version']).toInt();
      payrollReasonText = await _requestPayrollChangeReason(employment);
      if (payrollReasonText == null || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final names = _nameController.text.trim().split(RegExp(r'\s+'));
      final fn = names.isNotEmpty ? names.first : '';
      final ln = names.length > 1 ? names.sublist(1).join(' ') : '';
      final crm = ref.read(magicCrmServiceProvider);

      await crm.updateTeacher(
        _teacherId,
        firstName: fn,
        lastName: ln,
        phone: _canonicalPhone,
        email: _emailController.text,
        customDataPatch: employment.customDataPatch,
        salary: employment.salaryChanged ? employment.salary : null,
        disciplineIds: employment.disciplineIds,
        branchIds: employment.branchIds,
        rate: employment.rateChanged ? employment.rate : null,
        rateEffectiveFrom:
            employment.rateChanged && employment.rateEffectiveFrom != null
            ? DateFormat('yyyy-MM-dd').format(employment.rateEffectiveFrom!)
            : null,
        payrollExpectedVersion: payrollExpectedVersion,
        payrollReasonText: payrollReasonText,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Данные сохранены')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _provisionAccess() async {
    Map<String, dynamic>? updated;
    final saved = await showProvisionAccessDialog(
      context,
      personLabel: _nameController.text.trim(),
      initialEmail: _emailController.text,
      accessExists: _localData['is_app_account'] == true,
      onSubmit: (email, password) async {
        updated = await ref
            .read(magicCrmServiceProvider)
            .provisionTeacherAccess(
              teacherId: _teacherId,
              email: email,
              password: password,
            );
      },
    );
    if (saved == true && mounted && updated != null) {
      setState(() {
        _localData = updated!;
        _emailController.text = updated!['email']?.toString() ?? '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Доступ преподавателя создан')),
      );
    }
  }

  Future<void> _manageLifecycle() async {
    final saved = await showPersonLifecycleDialog(
      context,
      personType: 'teacher',
      personId: _teacherId,
      personName: _nameController.text.trim(),
    );
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _changeAccessRole() async {
    final userId = _localData['profile_user_id']?.toString() ?? '';
    if (userId.isEmpty) return;
    final selectedRole = await showPersonAccessRoleDialog(
      context,
      actorRole: _actorRole,
      userId: userId,
      personLabel: _nameController.text.trim(),
      teacher: true,
    );
    if (selectedRole == null || !mounted) return;
    setState(() => _localData = {..._localData, 'app_role': selectedRole});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Роль доступа обновлена')));
  }

  Future<void> _payAllDebt() async {
    final debt = _num(_payroll?['debt']);
    if (debt <= 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Оплатить всю задолженность'),
        content: Text('Выплатить ${_money.format(debt)} ₽?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выплатить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _payrollMutating = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createTeacherPayout(
            teacherId: _teacherId,
            kind: 'payout',
            amount: debt,
            expectedVersion: _num(_payroll?['version']).toInt(),
            reasonText: 'Оплата всей задолженности',
            comment: 'Оплата всей задолженности',
          );
      await _loadPayroll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _payrollMutating = false);
    }
  }

  Future<void> _addBonusOrDeduction() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _BonusDeductionDialog(
        teacherId: _teacherId,
        expectedVersion: _num(_payroll?['version']).toInt(),
      ),
    );
    if (saved == true) await _loadPayroll();
  }

  Future<void> _editRateEntry(Map<String, dynamic> row) async {
    final entryId = row['id']?.toString();
    if (!_canManagePayrollHistory || entryId == null) return;
    num? rate = _num(row['rate']);
    var effectiveFrom =
        DateTime.tryParse(row['effectiveFrom']?.toString() ?? '') ??
        DateTime.now();
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Исправить ставку'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeacherRateSelector(
                  initialRate: rate,
                  required: true,
                  onChanged: (value) => rate = value,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: effectiveFrom,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(() => effectiveFrom = picked);
                    }
                  },
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(
                    'Действует с ${DateFormat('dd.MM.yyyy').format(effectiveFrom)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Причина исправления *',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (rate == null || reasonController.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    final reasonText = reasonController.text.trim();
    if (confirmed != true || !mounted || rate == null) return;
    await _runPayrollHistoryMutation(
      () => ref
          .read(magicCrmServiceProvider)
          .updateTeacherRateEntry(
            teacherId: _teacherId,
            entryId: entryId,
            rate: rate!,
            effectiveFrom: DateFormat('yyyy-MM-dd').format(effectiveFrom),
            expectedVersion: _num(_payroll?['version']).toInt(),
            reasonText: reasonText,
          ),
    );
  }

  Future<void> _editPayoutEntry(Map<String, dynamic> row) async {
    final entryId = row['id']?.toString();
    if (!_canManagePayrollHistory || entryId == null) return;
    var kind = row['kind']?.toString() ?? 'payout';
    var paidAt =
        DateTime.tryParse(row['paidAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now();
    final amountController = TextEditingController(
      text: _num(row['amount']).toString(),
    );
    final commentController = TextEditingController(
      text: row['comment']?.toString() ?? '',
    );
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Исправить выплату'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  menuMaxHeight: 256,
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Тип'),
                  items: const [
                    DropdownMenuItem(value: 'payout', child: Text('Выплата')),
                    DropdownMenuItem(value: 'bonus', child: Text('Доплата')),
                    DropdownMenuItem(value: 'deduction', child: Text('Вычет')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => kind = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Сумма, ₽ *'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: paidAt,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setDialogState(() => paidAt = picked);
                  },
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(DateFormat('dd.MM.yyyy').format(paidAt)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commentController,
                  maxLength: 1000,
                  decoration: const InputDecoration(labelText: 'Комментарий'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Причина исправления *',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final amount = num.tryParse(
                  amountController.text.trim().replaceAll(',', '.'),
                );
                if (amount == null ||
                    amount <= 0 ||
                    reasonController.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    final amount = num.tryParse(
      amountController.text.trim().replaceAll(',', '.'),
    );
    final comment = commentController.text.trim();
    final reasonText = reasonController.text.trim();
    if (confirmed != true || !mounted || amount == null || amount <= 0) return;
    await _runPayrollHistoryMutation(
      () => ref
          .read(magicCrmServiceProvider)
          .updateTeacherPayoutEntry(
            teacherId: _teacherId,
            entryId: entryId,
            kind: kind,
            amount: amount,
            paidAt: DateFormat('yyyy-MM-dd').format(paidAt),
            expectedVersion: _num(_payroll?['version']).toInt(),
            reasonText: reasonText,
            comment: comment,
          ),
    );
  }

  Future<void> _deletePayrollEntry(
    Map<String, dynamic> row, {
    required bool rate,
  }) async {
    final entryId = row['id']?.toString();
    if (!_canManagePayrollHistory || entryId == null) return;
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(rate ? 'Удалить запись ставки?' : 'Удалить выплату?'),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Причина удаления *'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    final reasonText = reasonController.text.trim();
    if (confirmed != true || !mounted) return;
    final expectedVersion = _num(_payroll?['version']).toInt();
    await _runPayrollHistoryMutation(
      () => rate
          ? ref
                .read(magicCrmServiceProvider)
                .deleteTeacherRateEntry(
                  teacherId: _teacherId,
                  entryId: entryId,
                  expectedVersion: expectedVersion,
                  reasonText: reasonText,
                )
          : ref
                .read(magicCrmServiceProvider)
                .deleteTeacherPayoutEntry(
                  teacherId: _teacherId,
                  entryId: entryId,
                  expectedVersion: expectedVersion,
                  reasonText: reasonText,
                ),
    );
  }

  Future<void> _runPayrollHistoryMutation(
    Future<Map<String, dynamic>> Function() mutation,
  ) async {
    setState(() => _payrollMutating = true);
    try {
      await mutation();
      await _loadPayroll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _payrollMutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Карточка преподавателя'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSummary(context),
              if (const {'director', 'system_admin'}.contains(
                ref.watch(capabilitySnapshotProvider).asData?.value.role,
              )) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: _localData['lifecycle_state'] == 'archived'
                        ? null
                        : _provisionAccess,
                    icon: const Icon(Icons.key_rounded),
                    label: Text(
                      _localData['is_app_account'] == true
                          ? 'Данные для входа'
                          : 'Создать доступ',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _manageLifecycle,
                    icon: Icon(
                      _localData['lifecycle_state'] == 'archived'
                          ? Icons.restore_rounded
                          : Icons.person_off_outlined,
                    ),
                    label: Text(
                      _localData['lifecycle_state'] == 'archived'
                          ? 'Восстановить преподавателя'
                          : 'Отключить преподавателя',
                    ),
                  ),
                ),
              ],
              if (_payrollVisible) ...[
                const SizedBox(height: 12),
                _buildPayrollBlock(context),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Имя Фамилия'),
              ),
              const SizedBox(height: 12),
              RuPhoneField(
                initialCanonical: _canonicalPhone,
                onCanonicalChanged: (c) => _canonicalPhone = c,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Email для входа',
                  helperText: _credentialHelper(_localData),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Роль доступа',
                  helperText: 'Определяет права пользователя в приложении',
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _roleLabel(
                          _localData['app_role']?.toString() ?? 'teacher',
                        ),
                      ),
                    ),
                    if (const {
                          'director',
                          'system_admin',
                        }.contains(_actorRole) &&
                        (_localData['profile_user_id']?.toString().isNotEmpty ??
                            false))
                      TextButton(
                        key: const Key('teacher-change-access-role'),
                        onPressed: _saving ? null : _changeAccessRole,
                        child: const Text('Изменить'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              TeacherEmploymentFields(
                key: _employmentKey,
                initial: _employmentInitial,
                enabled: !_saving,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(
            'Отмена',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        FilledButton(
          onPressed: _saving || _localData['lifecycle_state'] == 'archived'
              ? null
              : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }

  /// KVA-238: блок «Оплаты преподавателю» — задолженность крупно + действия.
  Widget _buildPayrollBlock(BuildContext context) {
    final payroll = _payroll;
    final debt = _num(payroll?['debt']);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primaryGold.withAlpha(60)),
      ),
      child: _payrollError != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Не удалось загрузить расчёты преподавателя.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _payrollError.toString(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _loadPayroll,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Повторить'),
                  ),
                ),
              ],
            )
          : payroll == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Оплаты преподавателю',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Задолженность: ${_money.format(debt)} ₽',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: debt > 0 ? AppTheme.warning : AppTheme.success,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Начислено ${_money.format(_num(payroll['accruedTotal']))} ₽ '
                  '(${_num(payroll['hoursTotal'])} астр.ч.) · '
                  'выплачено ${_money.format(_num(payroll['paidTotal']))} ₽',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Завершено ${_num(payroll['completedLessons']).toInt()} · '
                  'оплачиваемых ${_num(payroll['payableLessons']).toInt()} · '
                  'без поурочного начисления '
                  '${_num(payroll['noAccrualLessons']).toInt()}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: debt > 0 && !_payrollMutating
                          ? _payAllDebt
                          : null,
                      child: const Text('Оплатить всю задолженность'),
                    ),
                    OutlinedButton(
                      onPressed: _payrollMutating ? null : _addBonusOrDeduction,
                      child: const Text('Доплата / Вычет'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildRateHistory(payroll),
                _buildPayoutHistory(payroll),
              ],
            ),
    );
  }

  Widget _buildRateHistory(Map<String, dynamic> payroll) {
    final rows = (payroll['rateHistory'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList()
        .reversed
        .toList();
    return ExpansionTile(
      key: const ValueKey('teacher-rate-history'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 6),
      title: Text('История ставок (${rows.length})'),
      children: rows.isEmpty
          ? const [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Нет записей'),
              ),
            ]
          : [
              for (final row in rows)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _num(row['rate']) == 0
                        ? 'Входит в оклад'
                        : '${_money.format(_num(row['rate']))} ₽/астр.ч.',
                  ),
                  subtitle: Text(
                    'с ${_shortDay(row['effectiveFrom']?.toString() ?? '')}'
                    '${row['authorName'] == null ? '' : ' · ${row['authorName']}'}',
                  ),
                  trailing: _canManagePayrollHistory
                      ? PopupMenuButton<String>(
                          enabled: !_payrollMutating,
                          onSelected: (action) => action == 'edit'
                              ? _editRateEntry(row)
                              : _deletePayrollEntry(row, rate: true),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Изменить'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Удалить'),
                            ),
                          ],
                        )
                      : null,
                ),
            ],
    );
  }

  Widget _buildPayoutHistory(Map<String, dynamic> payroll) {
    final rows = (payroll['payouts'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    String kindLabel(String? kind) => switch (kind) {
      'bonus' => 'Доплата',
      'deduction' => 'Вычет',
      _ => 'Выплата',
    };
    return ExpansionTile(
      key: const ValueKey('teacher-payout-history'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 6),
      title: Text('История выплат (${rows.length})'),
      children: rows.isEmpty
          ? const [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Нет записей'),
              ),
            ]
          : [
              for (final row in rows)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${kindLabel(row['kind']?.toString())}: '
                    '${_money.format(_num(row['amount']))} ₽',
                  ),
                  subtitle: Text(
                    '${_shortDate(row['paidAt']?.toString() ?? '')}'
                    '${row['comment'] == null ? '' : ' · ${row['comment']}'}'
                    '${row['authorName'] == null ? '' : ' · ${row['authorName']}'}',
                  ),
                  trailing: _canManagePayrollHistory
                      ? PopupMenuButton<String>(
                          enabled: !_payrollMutating,
                          onSelected: (action) => action == 'edit'
                              ? _editPayoutEntry(row)
                              : _deletePayrollEntry(row, rate: false),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Изменить'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Удалить'),
                            ),
                          ],
                        )
                      : null,
                ),
            ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    final branches = _branchesText(_localData['branches']);
    final students = _asInt(_localData['students_count']);
    final lessons = _asInt(_localData['lessons_count']);
    final rating = _asNum(_localData['rating']);
    final isAppAccount = _localData['is_app_account'] == true;
    final appRole = _localData['app_role']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withAlpha(90),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _TeacherMetric(
            icon: Icons.school_rounded,
            label: 'Ученики',
            value: students.toString(),
            color: AppTheme.primaryGold,
          ),
          _TeacherMetric(
            icon: _localData['password_configured'] == true
                ? Icons.password_rounded
                : Icons.no_encryption_gmailerrorred_rounded,
            label: 'Пароль',
            value: _localData['password_configured'] == true
                ? 'Настроен'
                : 'Не задан',
            color: _localData['password_configured'] == true
                ? AppTheme.success
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          _TeacherMetric(
            icon: Icons.event_available_rounded,
            label: 'Занятия',
            value: lessons.toString(),
            color: AppTheme.success,
          ),
          if (rating > 0)
            _TeacherMetric(
              icon: Icons.star_rounded,
              label: 'Рейтинг',
              value: rating.toStringAsFixed(1),
              color: AppTheme.secondaryGold,
            ),
          _TeacherMetric(
            icon: isAppAccount
                ? Icons.verified_user_rounded
                : Icons.person_off_rounded,
            label: 'Аккаунт',
            value: isAppAccount ? _roleLabel(appRole) : 'Нет',
            color: isAppAccount
                ? AppTheme.success
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          if (branches.isNotEmpty)
            _TeacherMetric(
              icon: Icons.location_on_outlined,
              label: 'Филиалы',
              value: branches,
              color: AppTheme.primaryGold,
              wide: true,
            ),
        ],
      ),
    );
  }

  num _num(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _credentialHelper(Map<String, dynamic> data) {
    final passwordChanged = data['password_changed_at']?.toString();
    final emailChanged = data['email_changed_at']?.toString();
    final parts = <String>[
      if (data['password_configured'] == true) 'Пароль настроен',
      if (emailChanged != null && emailChanged.isNotEmpty)
        'email обновлён ${_shortDate(emailChanged)}',
      if (passwordChanged != null && passwordChanged.isNotEmpty)
        'пароль обновлён ${_shortDate(passwordChanged)}',
    ];
    return parts.isEmpty ? 'Доступ ещё не создан' : parts.join(' · ');
  }

  String _shortDate(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    return parsed == null
        ? value
        : DateFormat('dd.MM.yyyy HH:mm').format(parsed);
  }

  String _shortDay(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    return parsed == null ? value : DateFormat('dd.MM.yyyy').format(parsed);
  }
}
