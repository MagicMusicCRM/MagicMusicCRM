import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';

class CreateStudentDialog extends ConsumerStatefulWidget {
  const CreateStudentDialog({super.key});

  @override
  ConsumerState<CreateStudentDialog> createState() =>
      _CreateStudentDialogState();
}

class _CreateStudentDialogState extends ConsumerState<CreateStudentDialog> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  String _canonicalPhone = '';
  // Branch and discipline are collected here, not left for a later edit: a
  // student saved without a branch drops out of every branch-scoped list.
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _disciplines = [];
  String? _branchId;
  String? _discipline; // discipline NAME (createStudent stores the name)
  bool _loadingBranches = true;
  bool _loadingDisciplines = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await ref
          .read(magicCrmServiceProvider)
          .listBranches(limit: 100);
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _loadingBranches = false;
        // Single-branch schools: no point making them pick the only option.
        if (_branches.length == 1) _branchId = _branches.first['id'].toString();
      });
      if (_branchId != null) await _loadDisciplines(_branchId!);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingBranches = false;
          _error = 'Не удалось загрузить филиалы: $e';
        });
      }
    }
  }

  Future<void> _loadDisciplines(String branchId) async {
    setState(() {
      _loadingDisciplines = true;
      _disciplines = [];
    });
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .listBranchDisciplines(branchId);
      if (!mounted) return;
      setState(() {
        _disciplines = items;
        _loadingDisciplines = false;
        // The previous branch's discipline may not exist in the new one.
        if (_discipline != null &&
            !_disciplines.any((d) => d['name']?.toString() == _discipline)) {
          _discipline = null;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDisciplines = false;
          _error = 'Не удалось загрузить направления: $e';
        });
      }
    }
  }

  Future<void> _save() async {
    final firstName = _firstNameController.text.trim();
    if (firstName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Введите имя ученика')));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final patch = <String, dynamic>{};
      if (_branchId != null && _branchId!.isNotEmpty) {
        patch['branchId'] = _branchId;
      }
      if (_discipline != null && _discipline!.isNotEmpty) {
        patch['discipline'] = _discipline;
      }
      final email = _emailController.text.trim();

      await ref
          .read(magicCrmServiceProvider)
          .createStudent(
            firstName: firstName,
            lastName: _lastNameController.text,
            phone: _canonicalPhone.isEmpty ? null : _canonicalPhone,
            email: email.isEmpty ? null : email,
            customDataPatch: patch.isEmpty ? null : patch,
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
      title: const Text('Новый ученик'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _firstNameController,
              decoration: const InputDecoration(labelText: 'Имя *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lastNameController,
              decoration: const InputDecoration(labelText: 'Фамилия'),
            ),
            const SizedBox(height: 12),
            RuPhoneField(onCanonicalChanged: (c) => _canonicalPhone = c),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            if (_loadingBranches)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _branchId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Филиал'),
                items: _branches
                    .map(
                      (b) => DropdownMenuItem(
                        value: b['id'].toString(),
                        child: Text(b['name']?.toString() ?? '—'),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        setState(() {
                          _branchId = value;
                          _discipline = null;
                          _disciplines = [];
                        });
                        if (value != null) _loadDisciplines(value);
                      },
              ),
            const SizedBox(height: 12),
            if (_loadingDisciplines)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else
              DropdownButtonFormField<String>(
                // initialValue is captured on first build: without a key tied
                // to the branch, switching branches swaps the items but leaves
                // the previous selection showing.
                key: ValueKey('disc:$_branchId'),
                initialValue: _discipline,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Направление',
                  helperText: _branchId == null
                      ? 'Сначала выберите филиал'
                      : null,
                ),
                items: _disciplines
                    .map(
                      (d) => DropdownMenuItem(
                        value: d['name']?.toString(),
                        child: Text(d['name']?.toString() ?? '—'),
                      ),
                    )
                    .toList(),
                onChanged: (_saving || _branchId == null)
                    ? null
                    : (value) => setState(() => _discipline = value),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
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
