import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

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
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _specializationController;
  bool _saving = false;

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
    _phoneController = TextEditingController(
      text: _localData['phone']?.toString() ?? prof?['phone']?.toString() ?? '',
    );
    _emailController = TextEditingController(
      text: _localData['email']?.toString() ?? '',
    );
    _specializationController = TextEditingController(
      text: _localData['specialization']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _specializationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final names = _nameController.text.trim().split(RegExp(r'\s+'));
      final fn = names.isNotEmpty ? names.first : '';
      final ln = names.length > 1 ? names.sublist(1).join(' ') : '';

      await ref
          .read(magicCrmServiceProvider)
          .updateTeacher(
            _localData['id'].toString(),
            firstName: fn,
            lastName: ln,
            phone: _phoneController.text,
            email: _emailController.text,
            specialization: _specializationController.text,
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Карточка преподавателя'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSummary(context),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Имя Фамилия'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Телефон'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Электронная почта'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _specializationController,
              decoration: const InputDecoration(labelText: 'Специализация'),
            ),
          ],
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
