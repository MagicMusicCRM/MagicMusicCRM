import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

class CustomFieldConfigWidget extends ConsumerStatefulWidget {
  const CustomFieldConfigWidget({super.key});

  @override
  ConsumerState<CustomFieldConfigWidget> createState() =>
      _CustomFieldConfigWidgetState();
}

class _CustomFieldConfigWidgetState
    extends ConsumerState<CustomFieldConfigWidget> {
  final _formKey = GlobalKey<FormState>();
  final _keyCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _hintCtrl = TextEditingController();
  final _optionsCtrl = TextEditingController();

  List<CrmCustomFieldDefinition> _fields = const [];
  String _entity = 'students';
  String _type = 'text';
  bool _required = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int? _editingIndex;

  @override
  void initState() {
    super.initState();
    _loadFields();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _labelCtrl.dispose();
    _hintCtrl.dispose();
    _optionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFields() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fields = await ref
          .read(magicSettingsServiceProvider)
          .getCrmCustomFields();
      if (!mounted) return;
      setState(() {
        _fields = fields;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить шаблоны полей';
        _loading = false;
      });
    }
  }

  Future<void> _saveFields() async {
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(magicSettingsServiceProvider)
          .updateCrmCustomFields(_fields);
      if (!mounted) return;
      setState(() {
        _fields = saved;
        _saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Шаблоны полей сохранены')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить шаблоны полей')),
      );
    }
  }

  void _submitField() {
    if (_formKey.currentState?.validate() != true) return;
    final key = _keyCtrl.text.trim();
    final duplicateIndex = _fields.indexWhere(
      (field) => field.entity == _entity && field.key == key,
    );
    if (duplicateIndex != -1 && duplicateIndex != _editingIndex) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Такой ключ уже есть у этой сущности')),
      );
      return;
    }

    final definition = CrmCustomFieldDefinition(
      entity: _entity,
      key: key,
      label: _labelCtrl.text.trim(),
      type: _type,
      required: _required,
      hint: _hintCtrl.text.trim().isEmpty ? null : _hintCtrl.text.trim(),
      options: _type == 'select'
          ? _optionsCtrl.text
                .split(RegExp(r'[\n,;]'))
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toSet()
                .toList()
          : const [],
    );

    setState(() {
      final next = [..._fields];
      final editIndex = _editingIndex;
      if (editIndex == null) {
        next.add(definition);
      } else {
        next[editIndex] = definition;
      }
      _fields = next;
      _resetForm();
    });
  }

  void _editField(int index) {
    final field = _fields[index];
    setState(() {
      _editingIndex = index;
      _entity = field.entity;
      _type = field.type;
      _required = field.required;
      _keyCtrl.text = field.key;
      _labelCtrl.text = field.label;
      _hintCtrl.text = field.hint ?? '';
      _optionsCtrl.text = field.options.join(', ');
    });
  }

  void _deleteField(int index) {
    setState(() {
      final next = [..._fields]..removeAt(index);
      _fields = next;
      if (_editingIndex == index) _resetForm();
    });
  }

  void _resetForm() {
    _editingIndex = null;
    _entity = 'students';
    _type = 'text';
    _required = false;
    _keyCtrl.clear();
    _labelCtrl.clear();
    _hintCtrl.clear();
    _optionsCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.md),
            ElevatedButton.icon(
              onPressed: _loadFields,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Повторить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColor.gold,
                foregroundColor: AppColor.onGold,
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Настройки полей',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Шаблоны дополнительных полей для CRM и перенесённых данных HolliHop',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          _buildEditor(context),
          const SizedBox(height: 16),
          _buildFieldList(context),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEditing = _editingIndex != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.schema_rounded,
                    color: AppColor.gold2,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEditing ? 'Редактирование поля' : 'Новое поле',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isEditing)
                    IconButton(
                      onPressed: () => setState(_resetForm),
                      tooltip: 'Отменить редактирование',
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _entity,
                      decoration: const InputDecoration(labelText: 'Сущность'),
                      items: crmCustomFieldEntities.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _entity = value);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: 'Тип'),
                      items: crmCustomFieldTypes.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _type = value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _keyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ключ поля',
                  hintText: 'naprimer_pole',
                ),
                validator: (value) {
                  final key = value?.trim() ?? '';
                  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(key)) {
                    return 'Латинская буква в начале, затем латиница, цифры или подчёркивание';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _labelCtrl,
                decoration: const InputDecoration(labelText: 'Название'),
                validator: (value) {
                  if ((value?.trim() ?? '').isEmpty) {
                    return 'Укажите название поля';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hintCtrl,
                decoration: const InputDecoration(labelText: 'Подсказка'),
              ),
              if (_type == 'select') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _optionsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Варианты выбора',
                    hintText: 'Вокал, Гитара, Фортепиано',
                  ),
                  validator: (value) {
                    final options = (value ?? '')
                        .split(RegExp(r'[\n,;]'))
                        .where((item) => item.trim().isNotEmpty)
                        .toList();
                    if (options.isEmpty) return 'Добавьте хотя бы один вариант';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                value: _required,
                onChanged: (value) => setState(() => _required = value),
                title: const Text('Обязательное поле'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _submitField,
                    icon: Icon(
                      isEditing ? Icons.check_rounded : Icons.add_rounded,
                    ),
                    label: Text(isEditing ? 'Обновить поле' : 'Добавить поле'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColor.gold,
                      foregroundColor: AppColor.onGold,
                      disabledBackgroundColor: AppColor.gold.withValues(
                        alpha: 0.5,
                      ),
                      disabledForegroundColor: AppColor.onGold,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _fields.isEmpty || _saving ? null : _saveFields,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: const Text('Сохранить шаблоны'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: cs.outlineVariant),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_fields.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Text(
            'Шаблоны пока не настроены. Добавьте поля и сохраните схему.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final indexedFields = _fields.indexed.toList()
      ..sort((a, b) {
        final entityCompare = a.$2.entity.compareTo(b.$2.entity);
        if (entityCompare != 0) return entityCompare;
        return a.$2.label.compareTo(b.$2.label);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Активные шаблоны',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${_fields.length}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...indexedFields.map(
          (entry) => _buildFieldTile(context, entry.$1, entry.$2),
        ),
      ],
    );
  }

  Widget _buildFieldTile(
    BuildContext context,
    int index,
    CrmCustomFieldDefinition field,
  ) {
    final entityLabel = crmCustomFieldEntities[field.entity] ?? field.entity;
    final typeLabel = crmCustomFieldTypes[field.type] ?? field.type;
    final options = field.options.isEmpty
        ? ''
        : ' · ${field.options.join(', ')}';
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: ListTile(
          title: Text(field.label),
          subtitle: Text(
            '$entityLabel · ${field.key} · $typeLabel${field.required ? ' · обязательно' : ''}$options',
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                onPressed: () => _editField(index),
                tooltip: 'Редактировать',
                icon: const Icon(Icons.edit_rounded),
              ),
              IconButton(
                onPressed: () => _deleteField(index),
                tooltip: 'Удалить',
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
