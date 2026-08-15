import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';

class TeacherEmploymentInitial {
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> disciplines;
  final Set<String> levels;
  final Set<String> categories;
  final DateTime? birthday;
  final DateTime? workStartDate;
  final bool isPartTime;
  final bool isBlacklisted;
  final num? salary;
  final num? rate;

  const TeacherEmploymentInitial({
    this.branches = const [],
    this.disciplines = const [],
    this.levels = const {},
    this.categories = const {},
    this.birthday,
    this.workStartDate,
    this.isPartTime = false,
    this.isBlacklisted = false,
    this.salary,
    this.rate,
  });
}

class TeacherEmploymentValue {
  final List<String> branchIds;
  final List<String> disciplineIds;
  final List<String> levels;
  final List<String> categories;
  final DateTime? birthday;
  final DateTime? workStartDate;
  final bool isPartTime;
  final bool isBlacklisted;
  final num? salary;
  final bool salaryChanged;
  final num? rate;
  final bool rateChanged;
  final DateTime? rateEffectiveFrom;

  const TeacherEmploymentValue({
    required this.branchIds,
    required this.disciplineIds,
    required this.levels,
    required this.categories,
    required this.birthday,
    required this.workStartDate,
    required this.isPartTime,
    required this.isBlacklisted,
    required this.salary,
    required this.salaryChanged,
    required this.rate,
    required this.rateChanged,
    required this.rateEffectiveFrom,
  });

  Map<String, dynamic> get customDataPatch => {
    'birthday': _dateOnly(birthday) ?? '',
    'workStartDate': _dateOnly(workStartDate) ?? '',
    'levels': levels,
    'categories': categories,
    // Legacy singular keys are still part of list filtering and imports.
    'level': levels.join(', '),
    'category': categories.join(', '),
    'isPartTime': isPartTime,
    'isBlacklisted': isBlacklisted,
  };
}

class TeacherEmploymentFields extends ConsumerStatefulWidget {
  final TeacherEmploymentInitial initial;
  final bool requireRate;
  final bool enabled;

  const TeacherEmploymentFields({
    super.key,
    this.initial = const TeacherEmploymentInitial(),
    this.requireRate = false,
    this.enabled = true,
  });

  @override
  ConsumerState<TeacherEmploymentFields> createState() =>
      TeacherEmploymentFieldsState();
}

class TeacherEmploymentFieldsState
    extends ConsumerState<TeacherEmploymentFields> {
  final _formKey = GlobalKey<FormState>();
  final _salaryController = TextEditingController();
  final Set<String> _branchIds = {};
  final Set<String> _disciplineIds = {};
  final Set<String> _levels = {};
  final Set<String> _categories = {};

  List<Map<String, dynamic>> _branches = const [];
  List<Map<String, dynamic>> _disciplines = const [];
  List<String> _levelOptions = const [];
  List<String> _categoryOptions = const [];
  DateTime? _birthday;
  DateTime? _workStartDate;
  DateTime? _rateEffectiveFrom;
  bool _isPartTime = false;
  bool _isBlacklisted = false;
  bool _loading = true;
  bool _loadingDisciplines = false;
  bool _rateTouched = false;
  num? _rate;
  String? _loadError;
  String? _selectionError;
  int _settingsSection = 0;
  int _disciplineLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _branches = [...initial.branches];
    _disciplines = [...initial.disciplines];
    _branchIds.addAll(_idsOf(initial.branches));
    _disciplineIds.addAll(_idsOf(initial.disciplines));
    _levels.addAll(initial.levels);
    _categories.addAll(initial.categories);
    _birthday = initial.birthday;
    _workStartDate = initial.workStartDate;
    _isPartTime = initial.isPartTime;
    _isBlacklisted = initial.isBlacklisted;
    _rate = initial.rate;
    _salaryController.text = initial.salary?.toString() ?? '';
    _loadReferences();
  }

  @override
  void dispose() {
    _salaryController.dispose();
    super.dispose();
  }

  static Set<String> _idsOf(List<Map<String, dynamic>> rows) => {
    for (final row in rows)
      if (row['id']?.toString().isNotEmpty == true) row['id'].toString(),
  };

  Future<void> _loadReferences() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final settings = ref.read(magicSettingsServiceProvider);
      final branches = await crm.listBranches(limit: 100);
      List<CrmCustomFieldDefinition> fields = const [];
      try {
        fields = await settings.getCrmCustomFields();
      } catch (_) {
        // Branch and discipline selection remain usable without custom fields.
      }
      if (!mounted) return;
      setState(() {
        _branches = _mergeOptions(branches, widget.initial.branches);
        _levelOptions = _customOptions(fields, 'levels', _levels);
        _categoryOptions = _customOptions(fields, 'categories', _categories);
        _loading = false;
      });
      await _loadDisciplines();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = userErrorMessage(
          error,
          fallback: 'Не удалось загрузить условия работы.',
        );
      });
    }
  }

  static List<Map<String, dynamic>> _mergeOptions(
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> initial,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final row in [...current, ...initial]) {
      final id = row['id']?.toString();
      if (id != null && id.isNotEmpty) byId[id] = row;
    }
    final result = byId.values.toList();
    result.sort(
      (a, b) =>
          (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''),
    );
    return result;
  }

  static List<String> _customOptions(
    List<CrmCustomFieldDefinition> fields,
    String key,
    Set<String> selected,
  ) {
    CrmCustomFieldDefinition? definition;
    for (final field in fields) {
      if (field.entity == 'teachers' && field.key == key) {
        definition = field;
        break;
      }
    }
    final values = <String>{...selected, ...?definition?.options}.toList();
    values.sort();
    return values;
  }

  Future<void> _loadDisciplines() async {
    final generation = ++_disciplineLoadGeneration;
    setState(() => _loadingDisciplines = true);
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final rows = await crm.listDisciplines();
      if (!mounted || generation != _disciplineLoadGeneration) return;
      setState(() {
        _disciplines = _mergeOptions(rows, widget.initial.disciplines);
        final available = _idsOf(_disciplines);
        _disciplineIds.removeWhere((id) => !available.contains(id));
        _loadingDisciplines = false;
      });
    } catch (_) {
      if (!mounted || generation != _disciplineLoadGeneration) return;
      setState(() => _loadingDisciplines = false);
    }
  }

  TeacherEmploymentValue? validateAndRead() {
    final formValid = _formKey.currentState?.validate() ?? false;
    String? error;
    if (_loading) {
      error = 'Дождитесь загрузки настроек преподавателя.';
    } else if (_loadError != null) {
      error = 'Не удалось загрузить филиалы.';
    } else if (_branchIds.isEmpty) {
      error = 'Выберите хотя бы один филиал.';
    } else if (widget.requireRate && _rate == null) {
      error = 'Выберите ставку преподавателя.';
    }
    setState(() => _selectionError = error);
    if (!formValid || error != null) return null;

    final salaryText = _salaryController.text.trim().replaceAll(',', '.');
    final enteredSalary = salaryText.isEmpty ? null : num.parse(salaryText);
    final initialSalary = widget.initial.salary;
    final salaryChanged = enteredSalary != initialSalary;
    return TeacherEmploymentValue(
      branchIds: _branchIds.toList()..sort(),
      disciplineIds: _disciplineIds.toList()..sort(),
      levels: _levels.toList()..sort(),
      categories: _categories.toList()..sort(),
      birthday: _birthday,
      workStartDate: _workStartDate,
      isPartTime: _isPartTime,
      isBlacklisted: _isBlacklisted,
      // Sending zero clears a previously configured fixed salary.
      salary: salaryChanged && enteredSalary == null ? 0 : enteredSalary,
      salaryChanged: salaryChanged,
      rate: _rate,
      rateChanged: _rateTouched && _rate != widget.initial.rate,
      rateEffectiveFrom: _rateEffectiveFrom,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Не удалось загрузить настройки преподавателя.'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _loadReferences,
            child: const Text('Повторить'),
          ),
        ],
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('teacher-employment-fields'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Условия работы и преподавания',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Ставка: оплата преподавателю за астрономический час. '
            'Она не списывается со счёта или абонемента ученика.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TeacherRateSelector(
            initialRate: widget.initial.rate,
            allowUnset: true,
            required: widget.requireRate,
            enabled: widget.enabled,
            label: 'Базовая ставка, ₽/астр.ч. *',
            onChanged: (value) {
              _rate = value;
              _rateTouched = true;
            },
          ),
          const SizedBox(height: 12),
          _TeacherDateField(
            label: 'Ставка действует с',
            value: _rateEffectiveFrom,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            enabled: widget.enabled,
            onChanged: (value) => setState(() => _rateEffectiveFrom = value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _salaryController,
            enabled: widget.enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Оклад, ₽/мес',
              helperText:
                  'Справочная фиксированная часть; автоматически к урокам не начисляется.',
              helperMaxLines: 2,
            ),
            validator: (value) {
              final text = value?.trim().replaceAll(',', '.') ?? '';
              if (text.isEmpty) return null;
              final parsed = num.tryParse(text);
              return parsed == null || parsed < 0
                  ? 'Введите сумму не меньше нуля'
                  : null;
            },
          ),
          const SizedBox(height: 16),
          _chips(title: 'Филиалы *', options: _branches, selected: _branchIds),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Дисциплины')),
                ButtonSegment(value: 1, label: Text('Уровни')),
                ButtonSegment(value: 2, label: Text('Категории')),
              ],
              selected: {_settingsSection},
              onSelectionChanged: !widget.enabled
                  ? null
                  : (selection) =>
                        setState(() => _settingsSection = selection.first),
            ),
          ),
          const SizedBox(height: 10),
          if (_settingsSection == 0)
            _loadingDisciplines
                ? const Center(child: CircularProgressIndicator())
                : _chips(
                    title: 'Дисциплины преподавателя (необязательно)',
                    options: _disciplines,
                    selected: _disciplineIds,
                    lockArchived: true,
                    emptyText: 'Добавьте дисциплины в общем справочнике.',
                  )
          else if (_settingsSection == 1)
            _stringChips(
              title: 'Уровни обучения',
              options: _levelOptions,
              selected: _levels,
              emptyText: 'Добавьте варианты уровней в настройках.',
            )
          else
            _stringChips(
              title: 'Категории учеников',
              options: _categoryOptions,
              selected: _categories,
              emptyText: 'Добавьте варианты категорий в настройках.',
            ),
          if (_selectionError != null) ...[
            const SizedBox(height: 8),
            Text(
              _selectionError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _TeacherDateField(
                  label: 'Дата рождения',
                  value: _birthday,
                  firstDate: DateTime(1940),
                  lastDate: DateTime.now(),
                  enabled: widget.enabled,
                  onChanged: (value) => setState(() => _birthday = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TeacherDateField(
                  label: 'Работает с',
                  value: _workStartDate,
                  firstDate: DateTime(1990),
                  lastDate: DateTime(2100),
                  enabled: widget.enabled,
                  onChanged: (value) => setState(() => _workStartDate = value),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('По совместительству'),
            value: _isPartTime,
            onChanged: !widget.enabled
                ? null
                : (value) => setState(() => _isPartTime = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Чёрный список'),
            value: _isBlacklisted,
            onChanged: !widget.enabled
                ? null
                : (value) => setState(() => _isBlacklisted = value),
          ),
        ],
      ),
    );
  }

  Widget _chips({
    required String title,
    required List<Map<String, dynamic>> options,
    required Set<String> selected,
    String? emptyText,
    VoidCallback? onChanged,
    bool lockArchived = false,
  }) {
    if (options.isEmpty) return Text(emptyText ?? 'Нет доступных вариантов.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in options)
              FilterChip(
                label: Text(
                  '${option['name']?.toString() ?? 'Не указано'}'
                  '${lockArchived && (option['lifecycleState'] == 'archived' || option['lifecycle_state'] == 'archived') ? ' (в архиве)' : ''}',
                ),
                selected: selected.contains(option['id']?.toString()),
                onSelected:
                    !widget.enabled ||
                        (lockArchived &&
                            (option['lifecycleState'] == 'archived' ||
                                option['lifecycle_state'] == 'archived') &&
                            !selected.contains(option['id']?.toString()))
                    ? null
                    : (value) {
                        final id = option['id']?.toString();
                        if (id == null) return;
                        setState(() {
                          value ? selected.add(id) : selected.remove(id);
                          _selectionError = null;
                        });
                        onChanged?.call();
                      },
              ),
          ],
        ),
      ],
    );
  }

  Widget _stringChips({
    required String title,
    required List<String> options,
    required Set<String> selected,
    required String emptyText,
  }) {
    return _chips(
      title: title,
      options: [
        for (final option in options) {'id': option, 'name': option},
      ],
      selected: selected,
      emptyText: emptyText,
    );
  }
}

class _TeacherDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool enabled;
  final ValueChanged<DateTime?> onChanged;

  const _TeacherDateField({
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('$label-${value?.toIso8601String() ?? ''}'),
      initialValue: value == null
          ? ''
          : DateFormat('dd.MM.yyyy').format(value!),
      enabled: enabled,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: value == null
            ? const Icon(Icons.calendar_today_rounded, size: 16)
            : IconButton(
                tooltip: 'Очистить дату',
                onPressed: enabled ? () => onChanged(null) : null,
                icon: const Icon(Icons.clear_rounded, size: 16),
              ),
      ),
      onTap: !enabled
          ? null
          : () async {
              final initialDate = value ?? DateTime.now();
              final boundedInitial = initialDate.isBefore(firstDate)
                  ? firstDate
                  : initialDate.isAfter(lastDate)
                  ? lastDate
                  : initialDate;
              final picked = await showDatePicker(
                context: context,
                initialDate: boundedInitial,
                firstDate: firstDate,
                lastDate: lastDate,
                initialEntryMode: DatePickerEntryMode.input,
              );
              if (picked != null) onChanged(picked);
            },
    );
  }
}

String? _dateOnly(DateTime? value) {
  if (value == null) return null;
  return DateFormat('yyyy-MM-dd').format(value);
}
