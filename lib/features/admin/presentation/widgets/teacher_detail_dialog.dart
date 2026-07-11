import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';

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
  late TextEditingController _specializationController;
  late TextEditingController _levelController;
  late TextEditingController _categoryController;
  late TextEditingController _salaryController;
  late String _canonicalPhone;
  bool _saving = false;

  // KVA-238: custom-поля карточки педагога.
  DateTime? _birthday;
  DateTime? _workStartDate;
  bool _isPartTime = false;
  bool _isBlacklisted = false;

  // KVA-238: дисциплины и филиалы (мультивыбор).
  List<Map<String, dynamic>> _allDisciplines = const [];
  List<Map<String, dynamic>> _allBranches = const [];
  final Set<String> _disciplineIds = {};
  final Set<String> _branchIds = {};

  // KVA-238: ставка (история на бекенде; здесь — актуальное значение).
  num? _currentRate;
  num? _pendingRate;
  bool _rateTouched = false;

  // KVA-238: блок «Оплаты преподавателю». null = ещё грузится или нет прав.
  Map<String, dynamic>? _payroll;
  bool _payrollVisible = true;

  final _dateFmt = DateFormat('dd.MM.yyyy');
  final _money = NumberFormat('#,##0', 'ru');

  String get _teacherId => _localData['id'].toString();

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
    _specializationController = TextEditingController(
      text: _localData['specialization']?.toString() ?? '',
    );

    final custom = _localData['custom_data'] is Map<String, dynamic>
        ? _localData['custom_data'] as Map<String, dynamic>
        : const <String, dynamic>{};
    _birthday = _parseDate(custom['birthday']);
    _workStartDate = _parseDate(custom['workStartDate']);
    _isPartTime = custom['isPartTime'] == true;
    _isBlacklisted = custom['isBlacklisted'] == true;
    _levelController = TextEditingController(
      text: custom['level']?.toString() ?? '',
    );
    _categoryController = TextEditingController(
      text: custom['category']?.toString() ?? '',
    );
    _salaryController = TextEditingController(
      text: _localData['salary']?.toString() ?? '',
    );
    _currentRate = _localData['current_rate'] is num
        ? _localData['current_rate'] as num
        : num.tryParse(_localData['current_rate']?.toString() ?? '');
    for (final discipline in _asMapList(_localData['disciplines'])) {
      final id = discipline['id']?.toString();
      if (id != null) _disciplineIds.add(id);
    }
    for (final branch in _asMapList(_localData['assigned_branches'])) {
      final id = branch['id']?.toString();
      if (id != null) _branchIds.add(id);
    }

    _loadReferences();
    _loadPayroll();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _specializationController.dispose();
    _levelController.dispose();
    _categoryController.dispose();
    _salaryController.dispose();
    super.dispose();
  }

  Future<void> _loadReferences() async {
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final results = await Future.wait([
        crm.listDisciplines(),
        crm.listBranches(limit: 100),
      ]);
      if (!mounted) return;
      setState(() {
        _allDisciplines = results[0];
        _allBranches = results[1];
      });
    } catch (_) {
      // Справочники не критичны — оставляем чипы пустыми.
    }
  }

  Future<void> _loadPayroll() async {
    try {
      final payroll = await ref
          .read(magicCrmServiceProvider)
          .getTeacherPayroll(_teacherId);
      if (!mounted) return;
      setState(() => _payroll = payroll);
    } catch (_) {
      // 403 для админа: payroll виден только manager/system_admin.
      if (!mounted) return;
      setState(() => _payrollVisible = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final names = _nameController.text.trim().split(RegExp(r'\s+'));
      final fn = names.isNotEmpty ? names.first : '';
      final ln = names.length > 1 ? names.sublist(1).join(' ') : '';
      final crm = ref.read(magicCrmServiceProvider);

      final salaryText = _salaryController.text.trim().replaceAll(',', '.');
      final salary = salaryText.isEmpty ? null : num.tryParse(salaryText);
      final originalSalary = num.tryParse(
        _localData['salary']?.toString() ?? '',
      );

      await crm.updateTeacher(
        _teacherId,
        firstName: fn,
        lastName: ln,
        phone: _canonicalPhone,
        email: _emailController.text,
        specialization: _specializationController.text,
        customDataPatch: {
          'birthday': _birthday == null
              ? ''
              : DateFormat('yyyy-MM-dd').format(_birthday!),
          'workStartDate': _workStartDate == null
              ? ''
              : DateFormat('yyyy-MM-dd').format(_workStartDate!),
          'level': _levelController.text.trim(),
          'category': _categoryController.text.trim(),
          'isPartTime': _isPartTime,
          'isBlacklisted': _isBlacklisted,
        },
        // Оклад отправляем только при изменении: у админа нет прав payroll.
        salary: salary != null && salary != originalSalary ? salary : null,
        disciplineIds: _disciplineIds.toList(),
        branchIds: _branchIds.toList(),
      );

      // KVA-238: смена ставки — отдельная запись истории teacher_rates.
      if (_rateTouched && _pendingRate != null && _pendingRate != _currentRate) {
        await crm.setTeacherHourRate(
          teacherId: _teacherId,
          rate: _pendingRate!,
        );
      }

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
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createTeacherPayout(
            teacherId: _teacherId,
            kind: 'payout',
            amount: debt,
            comment: 'Оплата всей задолженности',
          );
      await _loadPayroll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _addBonusOrDeduction() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _BonusDeductionDialog(teacherId: _teacherId),
    );
    if (saved == true) await _loadPayroll();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Карточка преподавателя'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSummary(context),
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
                decoration: const InputDecoration(
                  labelText: 'Электронная почта',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Дата рождения',
                      value: _birthday,
                      format: _dateFmt,
                      onChanged: (date) => setState(() => _birthday = date),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: 'Начало работы',
                      value: _workStartDate,
                      format: _dateFmt,
                      onChanged: (date) =>
                          setState(() => _workStartDate = date),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _specializationController,
                decoration: const InputDecoration(labelText: 'Специализация'),
              ),
              if (_allDisciplines.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildChipsSection(
                  'Дисциплины',
                  _allDisciplines,
                  _disciplineIds,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _levelController,
                      decoration: const InputDecoration(labelText: 'Уровень'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _categoryController,
                      decoration: const InputDecoration(
                        labelText: 'Категория',
                      ),
                    ),
                  ),
                ],
              ),
              if (_allBranches.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildChipsSection('Филиалы', _allBranches, _branchIds),
              ],
              const SizedBox(height: 12),
              TeacherRateSelector(
                initialRate: _currentRate,
                onChanged: (rate) {
                  _pendingRate = rate;
                  _rateTouched = true;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _salaryController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Оклад, ₽/мес'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('По совместительству'),
                value: _isPartTime,
                onChanged: (value) => setState(() => _isPartTime = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Чёрный список'),
                value: _isBlacklisted,
                onChanged: (value) => setState(() => _isBlacklisted = value),
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
          onPressed: _saving ? null : _save,
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
      child: payroll == null
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
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: debt > 0 ? _payAllDebt : null,
                      child: const Text('Оплатить всю задолженность'),
                    ),
                    OutlinedButton(
                      onPressed: _addBonusOrDeduction,
                      child: const Text('Доплата / Вычет'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildChipsSection(
    String title,
    List<Map<String, dynamic>> options,
    Set<String> selected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((option) {
            final id = option['id']?.toString() ?? '';
            final isSelected = selected.contains(id);
            return FilterChip(
              label: Text(option['name']?.toString() ?? '—'),
              selected: isSelected,
              onSelected: (value) => setState(() {
                if (value) {
                  selected.add(id);
                } else {
                  selected.remove(id);
                }
              }),
            );
          }).toList(),
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
}

/// KVA-238: диалог «Доплата / Вычет».
class _BonusDeductionDialog extends ConsumerStatefulWidget {
  final String teacherId;

  const _BonusDeductionDialog({required this.teacherId});

  @override
  ConsumerState<_BonusDeductionDialog> createState() =>
      _BonusDeductionDialogState();
}

class _BonusDeductionDialogState extends ConsumerState<_BonusDeductionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _commentController = TextEditingController();
  String _kind = 'bonus';
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createTeacherPayout(
            teacherId: widget.teacherId,
            kind: _kind,
            amount: num.parse(
              _amountController.text.trim().replaceAll(',', '.'),
            ),
            comment: _commentController.text,
          );
      if (mounted) Navigator.pop(context, true);
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Доплата / Вычет'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'bonus', label: Text('Доплата')),
                  ButtonSegment(value: 'deduction', label: Text('Вычет')),
                ],
                selected: {_kind},
                onSelectionChanged: (selection) =>
                    setState(() => _kind = selection.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Сумма, ₽ *'),
                validator: (value) {
                  final text = value?.trim().replaceAll(',', '.') ?? '';
                  final parsed = num.tryParse(text);
                  if (parsed == null || parsed <= 0) {
                    return 'Введите сумму больше нуля';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _commentController,
                decoration: const InputDecoration(labelText: 'Комментарий'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
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
}

/// Поле даты: readOnly + системный date picker.
class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final DateFormat format;
  final ValueChanged<DateTime?> onChanged;

  const _DateField({
    required this.label,
    required this.value,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('$label-${value?.toIso8601String() ?? ''}'),
      readOnly: true,
      initialValue: value == null ? '' : format.format(value!),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: value == null
            ? const Icon(Icons.calendar_today_rounded, size: 16)
            : IconButton(
                icon: const Icon(Icons.clear_rounded, size: 16),
                onPressed: () => onChanged(null),
              ),
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime(2000),
          firstDate: DateTime(1940),
          lastDate: DateTime(2035),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _TeacherMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool wide;

  const _TeacherMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? 220 : 118,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(54)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
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

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map<String, dynamic>>().toList();
}

DateTime? _parseDate(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso;
  // Легаси-формат HolliHop: DD.MM.YYYY.
  final match = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(text);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(3)!),
    int.parse(match.group(2)!),
    int.parse(match.group(1)!),
  );
}

String _branchesText(dynamic value) {
  if (value is! List) return '';
  return value
      .map((branch) {
        if (branch is Map) {
          return (branch['name'] ?? branch['branch_name'] ?? '').toString();
        }
        return branch.toString();
      })
      .where((name) => name.trim().isNotEmpty)
      .join(', ');
}

String _roleLabel(String role) {
  return switch (role) {
    'admin' => 'Администратор',
    'manager' => 'Управляющий',
    'director' => 'Директор',
    'teacher' => 'Преподаватель',
    'system_admin' => 'Администратор системы',
    _ => role.isEmpty ? 'Нет' : role,
  };
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
