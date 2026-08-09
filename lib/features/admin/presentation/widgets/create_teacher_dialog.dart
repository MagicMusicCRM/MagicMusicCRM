import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/v7/adaptive_surface.dart';

Future<bool?> showCreateTeacherSurface(BuildContext context) {
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.selection,
    title: 'Новый преподаватель',
    subtitle: 'Аккаунт, филиал и дисциплины',
    icon: Icons.school_outlined,
    builder: (_) => const CreateTeacherDialog(),
  );
}

class CreateTeacherDialog extends ConsumerStatefulWidget {
  const CreateTeacherDialog({super.key});

  @override
  ConsumerState<CreateTeacherDialog> createState() =>
      _CreateTeacherDialogState();
}

class _CreateTeacherDialogState extends ConsumerState<CreateTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordAgain = TextEditingController();
  String _phone = '';
  String? _branchId;
  final Set<String> _disciplineIds = {};
  List<Map<String, dynamic>> _branches = const [];
  List<Map<String, dynamic>> _disciplines = const [];
  bool _loading = true;
  bool _loadingDisciplines = false;
  bool _saving = false;
  bool _showPassword = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _passwordAgain.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final branches = await ref.read(magicCrmServiceProvider).listBranches();
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$error';
      });
    }
  }

  Future<void> _selectBranch(String? branchId) async {
    setState(() {
      _branchId = branchId;
      _disciplineIds.clear();
      _disciplines = const [];
      _loadingDisciplines = branchId != null;
    });
    if (branchId == null) return;
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .listBranchDisciplines(branchId);
      if (!mounted || _branchId != branchId) return;
      setState(() {
        _disciplines = items;
        _loadingDisciplines = false;
      });
    } catch (error) {
      if (!mounted || _branchId != branchId) return;
      setState(() => _loadingDisciplines = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить дисциплины: $error')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_disciplineIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы одну дисциплину.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createTeacher(
            firstName: _firstName.text,
            lastName: _lastName.text,
            phone: _phone,
            email: _email.text,
            password: _password.text,
            branchIds: [_branchId!],
            disciplineIds: _disciplineIds.toList(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Обязательное поле' : null;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Не удалось загрузить филиалы.'),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _loadBranches,
            child: const Text('Повторить'),
          ),
        ],
      );
    }
    if (_branches.isEmpty) {
      return const Text(
        'Сначала создайте доступный филиал. Без филиала преподавателя создать нельзя.',
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('create-teacher-form'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Преподаватель сразу появится в списке пользователей и сможет войти с указанными данными.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _firstName,
            decoration: const InputDecoration(labelText: 'Имя *'),
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _lastName,
            decoration: const InputDecoration(labelText: 'Фамилия'),
          ),
          const SizedBox(height: 12),
          RuPhoneField(onCanonicalChanged: (value) => _phone = value),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email для входа *'),
            validator: (value) {
              final error = _required(value);
              if (error != null) return error;
              return value!.trim().contains('@')
                  ? null
                  : 'Введите корректный email';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Пароль *',
              helperText: 'Не менее 10 символов',
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Скрыть пароль' : 'Показать пароль',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
            validator: (value) => (value?.length ?? 0) < 10
                ? 'Пароль должен содержать минимум 10 символов'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordAgain,
            obscureText: !_showPassword,
            decoration: const InputDecoration(labelText: 'Повторите пароль *'),
            validator: (value) =>
                value != _password.text ? 'Пароли не совпадают' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            menuMaxHeight: 256,
            initialValue: _branchId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Филиал *'),
            items: [
              for (final branch in _branches)
                DropdownMenuItem(
                  value: branch['id']?.toString(),
                  child: Text(branch['name']?.toString() ?? 'Филиал'),
                ),
            ],
            onChanged: _saving ? null : _selectBranch,
            validator: (value) => value == null ? 'Выберите филиал' : null,
          ),
          const SizedBox(height: 12),
          if (_loadingDisciplines)
            const Center(child: CircularProgressIndicator())
          else if (_branchId != null && _disciplines.isEmpty)
            const Text(
              'В филиале нет дисциплин. Сначала добавьте их в настройках филиала.',
            )
          else if (_disciplines.isNotEmpty) ...[
            const Text('Дисциплины *'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final discipline in _disciplines)
                  FilterChip(
                    label: Text(discipline['name']?.toString() ?? '—'),
                    selected: _disciplineIds.contains(
                      discipline['discipline_id']?.toString(),
                    ),
                    onSelected: (selected) {
                      final id = discipline['discipline_id']?.toString();
                      if (id == null) return;
                      setState(() {
                        if (selected) {
                          _disciplineIds.add(id);
                        } else {
                          _disciplineIds.remove(id);
                        }
                      });
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving || _loadingDisciplines ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Создать преподавателя'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
