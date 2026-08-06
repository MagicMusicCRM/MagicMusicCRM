import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/student_funnel.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/v7/adaptive_surface.dart';

import 'client_forms_api.dart';

Future<Map<String, dynamic>?> showStudentCreateSurface(
  BuildContext context, {
  String? initialBranchId,
}) {
  return showMagicAdaptiveSurface<Map<String, dynamic>>(
    context,
    kind: AppSurfaceKind.selection,
    title: 'Новый ученик',
    subtitle: 'Карточка будет сразу добавлена в воронку',
    icon: Icons.person_add_alt_1_rounded,
    builder: (_) =>
        StudentCreateDialogV4(initialBranchId: initialBranchId, embedded: true),
  );
}

class LeadCreateDialog extends ConsumerStatefulWidget {
  const LeadCreateDialog({super.key});

  @override
  ConsumerState<LeadCreateDialog> createState() => _LeadCreateDialogState();
}

class _LeadCreateDialogState extends ConsumerState<LeadCreateDialog> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _customValues = <String, Object?>{};
  String _phone = '';
  String? _sourceId;
  String? _branchId;
  String? _status;
  List<Map<String, dynamic>> _sources = const [];
  List<Map<String, dynamic>> _branches = const [];
  List<StudentFunnelStage> _statuses = const [];
  List<Map<String, dynamic>> _fields = const [];
  Map<String, String> _fieldErrors = const {};
  String? _loadError;
  String? _submitError;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata({bool inactiveSourceRefresh = false}) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final api = ref.read(clientFormsApiProvider);
      final results = await Future.wait([
        api.listSources(),
        api.listFields(entityType: 'lead'),
        api.listBranches(),
      ]);
      if (!mounted) return;
      final sources = results[0];
      final branches = results[2];
      final branchIds = branches
          .map((branch) => branch['id']?.toString())
          .whereType<String>()
          .toSet();
      final selectedBranch = branchIds.contains(_branchId)
          ? _branchId
          : branches.length == 1
          ? branches.first['id']?.toString()
          : null;
      final funnel = await ref
          .read(magicCrmServiceProvider)
          .getClientPipeline(clientType: 'lead', branchId: selectedBranch);
      if (!mounted) return;
      final statuses = funnel.activeStages;
      setState(() {
        _sources = sources;
        _branches = branches;
        _branchId = selectedBranch;
        _statuses = statuses;
        if (!statuses.any((stage) => stage.key == _status)) {
          _status = statuses.firstOrNull?.key;
        }
        _fields = _createPlacementFields(results[1]);
        if (_sourceId != null &&
            !sources.any((source) => source['id']?.toString() == _sourceId)) {
          _sourceId = null;
          if (inactiveSourceRefresh) {
            _fieldErrors = {
              ..._fieldErrors,
              'sourceId': 'Источник был архивирован. Выберите другой.',
            };
          }
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Не удалось загрузить справочники: $error';
      });
    }
  }

  Map<String, String> _validate() {
    final errors = <String, String>{};
    if (_firstName.text.trim().isEmpty) {
      errors['firstName'] = 'Укажите имя.';
    }
    if (_lastName.text.trim().isEmpty) {
      errors['lastName'] = 'Укажите фамилию.';
    }
    if (_phone.isEmpty) errors['phone'] = 'Укажите корректный телефон.';
    if (_sourceId == null) errors['sourceId'] = 'Выберите источник.';
    if (_branchId == null) errors['branchId'] = 'Выберите филиал.';
    if (_status == null) errors['status'] = 'Выберите этап воронки.';
    for (final field in _fields.where((item) => item['required'] == true)) {
      final id = field['id']?.toString() ?? '';
      final value = _customValues[id];
      if (_isEmptyFieldValue(value)) {
        errors['customFields.${field['key']}'] = 'Обязательное поле.';
      }
    }
    return errors;
  }

  Future<void> _save() async {
    final errors = _validate();
    if (errors.isNotEmpty) {
      setState(() => _fieldErrors = errors);
      return;
    }
    setState(() {
      _saving = true;
      _submitError = null;
      _fieldErrors = const {};
    });
    try {
      final result = await ref
          .read(clientFormsApiProvider)
          .createLead(
            firstName: _firstName.text,
            lastName: _lastName.text,
            phone: _phone,
            sourceId: _sourceId!,
            branchId: _branchId!,
            status: _status!,
            customFields: _serializedCustomFields(_fields, _customValues),
          );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      final fieldError = _serverFieldError(error);
      setState(() {
        _saving = false;
        if (fieldError != null) {
          _fieldErrors = {fieldError.$1: fieldError.$2};
        } else {
          _submitError = error is MagicApiException && error.statusCode == 403
              ? 'Недостаточно прав для создания заявки.'
              : 'Не удалось создать заявку: $error';
        }
      });
      if (fieldError?.$1 == 'sourceId') {
        await _loadMetadata(inactiveSourceRefresh: true);
      }
    }
  }

  Future<void> _selectBranch(String? branchId) async {
    if (branchId == null || branchId == _branchId) return;
    setState(() {
      _branchId = branchId;
      _saving = true;
      _submitError = null;
    });
    try {
      final funnel = await ref
          .read(magicCrmServiceProvider)
          .getClientPipeline(clientType: 'lead', branchId: branchId);
      if (!mounted) return;
      final statuses = funnel.activeStages;
      setState(() {
        _statuses = statuses;
        if (!statuses.any((stage) => stage.key == _status)) {
          _status = statuses.firstOrNull?.key;
        }
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _submitError = 'Не удалось загрузить воронку филиала: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AdaptiveClientDialog(
      title: 'Новый лид',
      loading: _loading,
      loadError: _loadError,
      onRetry: _loadMetadata,
      submitError: _submitError,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('lead-submit'),
          onPressed:
              _saving ||
                  _loading ||
                  _sources.isEmpty ||
                  _branches.isEmpty ||
                  _statuses.isEmpty
              ? null
              : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Создать'),
        ),
      ],
      child: _loading || _loadError != null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _textField(
                  key: const ValueKey('lead-first-name'),
                  controller: _firstName,
                  label: 'Имя *',
                  error: _fieldErrors['firstName'],
                ),
                _textField(
                  key: const ValueKey('lead-last-name'),
                  controller: _lastName,
                  label: 'Фамилия *',
                  error: _fieldErrors['lastName'],
                ),
                RuPhoneField(
                  key: const ValueKey('lead-phone'),
                  onCanonicalChanged: (value) => _phone = value,
                  decoration: InputDecoration(
                    labelText: 'Телефон *',
                    errorText: _fieldErrors['phone'],
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                if (_branches.isEmpty)
                  const _EmptyMetadata(
                    message:
                        'Нет доступных филиалов. Создание лида недоступно.',
                  )
                else
                  DropdownButtonFormField<String>(
                    key: const ValueKey('lead-branch'),
                    initialValue: _branchId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Филиал *',
                      errorText: _fieldErrors['branchId'],
                    ),
                    items: _branches
                        .map(
                          (branch) => DropdownMenuItem(
                            value: branch['id']?.toString(),
                            child: Text(branch['name']?.toString() ?? '—'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _saving ? null : _selectBranch,
                  ),
                const SizedBox(height: AppSpace.sm),
                if (_statuses.isEmpty)
                  const _EmptyMetadata(
                    message:
                        'В воронке нет активных этапов. Директор должен обновить настройку.',
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'lead-status-${_branchId ?? 'school'}-${_statuses.map((stage) => stage.key).join('-')}',
                    ),
                    initialValue: _status,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Этап воронки *',
                      errorText: _fieldErrors['status'],
                    ),
                    items: _statuses
                        .map(
                          (stage) => DropdownMenuItem(
                            value: stage.key,
                            child: Text(stage.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _status = value),
                  ),
                const SizedBox(height: AppSpace.sm),
                if (_sources.isEmpty)
                  const _EmptyMetadata(
                    message:
                        'Нет активных источников. Директор должен добавить источник.',
                  )
                else
                  KeyedSubtree(
                    key: const ValueKey('lead-source'),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'lead-source-${_sources.map((item) => item['id']).join('-')}',
                      ),
                      initialValue: _sourceId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Рекламный источник *',
                        errorText: _fieldErrors['sourceId'],
                      ),
                      hint: const Text('Выберите источник'),
                      items: _sources
                          .map(
                            (source) => DropdownMenuItem(
                              value: source['id']?.toString(),
                              child: Text(
                                source['displayName']?.toString() ?? '—',
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _sourceId = value),
                    ),
                  ),
                _ClientFieldInputs(
                  fields: _fields,
                  values: _customValues,
                  errors: _fieldErrors,
                  enabled: !_saving,
                  onChanged: (id, value) => _customValues[id] = value,
                ),
              ],
            ),
    );
  }
}

class StudentCreateDialogV4 extends ConsumerStatefulWidget {
  const StudentCreateDialogV4({
    super.key,
    this.initialBranchId,
    this.embedded = false,
  });

  final String? initialBranchId;
  final bool embedded;

  @override
  ConsumerState<StudentCreateDialogV4> createState() =>
      _StudentCreateDialogV4State();
}

class _StudentCreateDialogV4State extends ConsumerState<StudentCreateDialogV4> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _customValues = <String, Object?>{};
  String _phone = '';
  String? _branchId;
  String? _status;
  String? _sourceId;
  List<Map<String, dynamic>> _branches = const [];
  List<Map<String, dynamic>> _sources = const [];
  List<Map<String, dynamic>> _fields = const [];
  List<StudentFunnelStage> _statuses = const [];
  Map<String, String> _fieldErrors = const {};
  String? _loadError;
  String? _submitError;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final api = ref.read(clientFormsApiProvider);
      final results = await Future.wait([
        api.listBranches(),
        api.listFields(entityType: 'student'),
        api.listSources(),
      ]);
      if (!mounted) return;
      final branches = results[0];
      final availableIds = branches
          .map((branch) => branch['id']?.toString())
          .whereType<String>()
          .toSet();
      final selectedBranch = availableIds.contains(widget.initialBranchId)
          ? widget.initialBranchId
          : availableIds.contains(_branchId)
          ? _branchId
          : branches.length == 1
          ? branches.first['id']?.toString()
          : null;
      final funnel = await ref
          .read(magicCrmServiceProvider)
          .getClientPipeline(clientType: 'student', branchId: selectedBranch);
      if (!mounted) return;
      final statuses = funnel.activeStages;
      setState(() {
        _branches = branches;
        _fields = _createPlacementFields(results[1]);
        _sources = results[2];
        _branchId = selectedBranch;
        _statuses = statuses;
        if (!statuses.any((stage) => stage.key == _status)) {
          _status = statuses.firstOrNull?.key;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Не удалось загрузить справочники: $error';
      });
    }
  }

  Map<String, String> _validate() {
    final errors = <String, String>{};
    if (_firstName.text.trim().isEmpty) {
      errors['firstName'] = 'Укажите имя.';
    }
    if (_lastName.text.trim().isEmpty) {
      errors['lastName'] = 'Укажите фамилию.';
    }
    if (_phone.isEmpty) errors['phone'] = 'Укажите корректный телефон.';
    if (_branchId == null) errors['branchId'] = 'Выберите филиал.';
    if (_status == null) errors['status'] = 'Выберите этап воронки.';
    if (_sourceId == null) errors['sourceId'] = 'Выберите источник.';
    for (final field in _fields.where((item) => item['required'] == true)) {
      final id = field['id']?.toString() ?? '';
      final value = _customValues[id];
      if (_isEmptyFieldValue(value)) {
        errors['customFields.${field['key']}'] = 'Обязательное поле.';
      }
    }
    return errors;
  }

  Future<void> _save() async {
    final errors = _validate();
    if (errors.isNotEmpty) {
      setState(() => _fieldErrors = errors);
      return;
    }
    setState(() {
      _saving = true;
      _submitError = null;
      _fieldErrors = const {};
    });
    try {
      final result = await ref
          .read(clientFormsApiProvider)
          .createStudent(
            firstName: _firstName.text,
            lastName: _lastName.text,
            phone: _phone,
            branchId: _branchId!,
            status: _status!,
            sourceId: _sourceId!,
            customFields: _serializedCustomFields(_fields, _customValues),
          );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      final fieldError = _serverFieldError(error);
      setState(() {
        _saving = false;
        if (fieldError != null) {
          _fieldErrors = {fieldError.$1: fieldError.$2};
        } else {
          _submitError = error is MagicApiException && error.statusCode == 403
              ? 'Недостаточно прав для создания ученика.'
              : 'Не удалось создать ученика: $error';
        }
      });
    }
  }

  Future<void> _selectBranch(String? branchId) async {
    if (branchId == null || branchId == _branchId) return;
    setState(() {
      _branchId = branchId;
      _saving = true;
      _submitError = null;
    });
    try {
      final funnel = await ref
          .read(magicCrmServiceProvider)
          .getClientPipeline(clientType: 'student', branchId: branchId);
      if (!mounted) return;
      final statuses = funnel.activeStages;
      setState(() {
        _statuses = statuses;
        if (!statuses.any((stage) => stage.key == _status)) {
          _status = statuses.firstOrNull?.key;
        }
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _submitError = 'Не удалось загрузить воронку филиала: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AdaptiveClientDialog(
      title: 'Новый ученик',
      embedded: widget.embedded,
      loading: _loading,
      loadError: _loadError,
      onRetry: _loadMetadata,
      submitError: _submitError,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('student-submit'),
          onPressed:
              _saving || _loading || _branches.isEmpty || _sources.isEmpty
              ? null
              : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Создать'),
        ),
      ],
      child: _loading || _loadError != null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _textField(
                  key: const ValueKey('student-first-name'),
                  controller: _firstName,
                  label: 'Имя *',
                  error: _fieldErrors['firstName'],
                ),
                _textField(
                  key: const ValueKey('student-last-name'),
                  controller: _lastName,
                  label: 'Фамилия *',
                  error: _fieldErrors['lastName'],
                ),
                RuPhoneField(
                  key: const ValueKey('student-phone'),
                  onCanonicalChanged: (value) => _phone = value,
                  decoration: InputDecoration(
                    labelText: 'Телефон *',
                    errorText: _fieldErrors['phone'],
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                if (_branches.isEmpty)
                  const _EmptyMetadata(
                    message:
                        'Нет доступных филиалов. Создание ученика недоступно.',
                  )
                else
                  DropdownButtonFormField<String>(
                    key: const ValueKey('student-branch'),
                    initialValue: _branchId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Филиал *',
                      errorText: _fieldErrors['branchId'],
                    ),
                    items: _branches
                        .map(
                          (branch) => DropdownMenuItem(
                            value: branch['id']?.toString(),
                            child: Text(branch['name']?.toString() ?? '—'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _saving ? null : _selectBranch,
                  ),
                const SizedBox(height: AppSpace.sm),
                if (_sources.isEmpty)
                  const _EmptyMetadata(
                    message:
                        'Нет активных рекламных источников. Создание ученика недоступно.',
                  )
                else
                  DropdownButtonFormField<String>(
                    key: const ValueKey('student-source'),
                    initialValue: _sourceId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Рекламный источник *',
                      errorText: _fieldErrors['sourceId'],
                    ),
                    items: _sources
                        .map(
                          (source) => DropdownMenuItem(
                            value: source['id']?.toString(),
                            child: Text(
                              source['displayName']?.toString() ?? '—',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _sourceId = value),
                  ),
                const SizedBox(height: AppSpace.sm),
                if (_statuses.isEmpty)
                  const _EmptyMetadata(
                    message:
                        'В воронке нет активных этапов. Директор должен обновить настройку.',
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'student-status-${_branchId ?? 'school'}-${_statuses.map((stage) => stage.key).join('-')}',
                    ),
                    initialValue: _status,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Этап воронки *',
                      errorText: _fieldErrors['status'],
                    ),
                    items: _statuses
                        .map(
                          (stage) => DropdownMenuItem(
                            value: stage.key,
                            child: Text(stage.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _status = value),
                  ),
                _ClientFieldInputs(
                  fields: _fields,
                  values: _customValues,
                  errors: _fieldErrors,
                  enabled: !_saving,
                  onChanged: (id, value) => _customValues[id] = value,
                ),
              ],
            ),
    );
  }
}

class _AdaptiveClientDialog extends StatelessWidget {
  const _AdaptiveClientDialog({
    required this.title,
    required this.loading,
    required this.loadError,
    required this.onRetry,
    required this.submitError,
    required this.actions,
    required this.child,
    this.embedded = false,
  });

  final String title;
  final bool loading;
  final String? loadError;
  final VoidCallback onRetry;
  final String? submitError;
  final List<Widget> actions;
  final Widget? child;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.all(AppSpace.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (loadError != null)
          _LoadError(message: loadError!, onRetry: onRetry)
        else
          ?child,
        if (submitError != null) ...[
          const SizedBox(height: AppSpace.md),
          Text(
            submitError!,
            key: const ValueKey('client-form-submit-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
    if (embedded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          const SizedBox(height: AppSpace.lg),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: actions,
          ),
        ],
      );
    }
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: width < 480 ? AppSpace.sm : AppSpace.xl,
        vertical: AppSpace.lg,
      ),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(
          width: width < 480
              ? (width - (AppSpace.sm * 2) - 48).clamp(0, 520).toDouble()
              : 520,
          child: SingleChildScrollView(child: content),
        ),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: actions,
        ),
      ],
    );
  }
}

class _ClientFieldInputs extends StatelessWidget {
  const _ClientFieldInputs({
    required this.fields,
    required this.values,
    required this.errors,
    required this.enabled,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> fields;
  final Map<String, Object?> values;
  final Map<String, String> errors;
  final bool enabled;
  final void Function(String id, Object? value) onChanged;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) return const SizedBox.shrink();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final field in fields) {
      groups
          .putIfAbsent(
            field['categoryLabel']?.toString() ?? 'Дополнительные поля',
            () => [],
          )
          .add(field);
    }
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in groups.entries) ...[
            const SizedBox(height: AppSpace.md),
            Text(group.key, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpace.xs),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final field in group.value)
                  SizedBox(
                    width: _fieldWidth(field, constraints.maxWidth),
                    child: _field(field),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(Map<String, dynamic> field) {
    final id = field['id']?.toString() ?? '';
    final key = field['key']?.toString() ?? id;
    final label =
        '${field['label'] ?? key}${field['required'] == true ? ' *' : ''}';
    final type = field['valueType']?.toString() ?? 'text';
    final error = errors['customFields.$key'];
    if (type == 'boolean') {
      return CheckboxListTile(
        key: ValueKey('custom-field-$key'),
        contentPadding: EdgeInsets.zero,
        value: values[id] == true,
        title: Text(label),
        subtitle: error == null
            ? null
            : Text(error, style: const TextStyle(color: AppColor.danger)),
        onChanged: enabled ? (value) => onChanged(id, value == true) : null,
      );
    }
    if (type == 'toggle') {
      return SwitchListTile(
        key: ValueKey('custom-field-$key'),
        contentPadding: EdgeInsets.zero,
        value: values[id] == true,
        title: Text(label),
        subtitle: error == null
            ? null
            : Text(error, style: const TextStyle(color: AppColor.danger)),
        onChanged: enabled ? (value) => onChanged(id, value) : null,
      );
    }
    if (type == 'select' || type == 'radio') {
      final options = (field['options'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false);
      if (type == 'radio') {
        return InputDecorator(
          decoration: InputDecoration(labelText: label, errorText: error),
          child: Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(option),
                  selected: values[id]?.toString() == option,
                  onSelected: enabled
                      ? (selected) {
                          if (selected) onChanged(id, option);
                        }
                      : null,
                ),
            ],
          ),
        );
      }
      return DropdownButtonFormField<String>(
        key: ValueKey('custom-field-$key'),
        initialValue: values[id]?.toString(),
        isExpanded: true,
        decoration: InputDecoration(labelText: label, errorText: error),
        items: options
            .map(
              (option) => DropdownMenuItem(value: option, child: Text(option)),
            )
            .toList(growable: false),
        onChanged: enabled ? (value) => onChanged(id, value) : null,
      );
    }
    if (type == 'multi_select' || type == 'checkbox_group') {
      final options = (field['options'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false);
      final selected = (values[id] as List? ?? const [])
          .map((value) => value.toString())
          .toSet();
      return InputDecorator(
        decoration: InputDecoration(labelText: label, errorText: error),
        child: Wrap(
          spacing: AppSpace.xs,
          children: [
            for (final option in options)
              FilterChip(
                label: Text(option),
                selected: selected.contains(option),
                onSelected: enabled
                    ? (checked) {
                        final next = {...selected};
                        checked ? next.add(option) : next.remove(option);
                        onChanged(id, next.toList(growable: false));
                      }
                    : null,
              ),
          ],
        ),
      );
    }
    final numeric = type == 'number' || type == 'money' || type == 'duration';
    return TextFormField(
      key: ValueKey('custom-field-$key'),
      initialValue: values[id]?.toString(),
      enabled: enabled,
      maxLines: type == 'textarea' ? 4 : 1,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : type == 'email'
          ? TextInputType.emailAddress
          : type == 'phone'
          ? TextInputType.phone
          : TextInputType.text,
      decoration: InputDecoration(labelText: label, errorText: error),
      onChanged: (value) {
        if (numeric) {
          onChanged(id, num.tryParse(value.replaceAll(',', '.')));
        } else {
          onChanged(id, value);
        }
      },
    );
  }
}

double _fieldWidth(Map<String, dynamic> field, double available) {
  if (available < 520) return available;
  return switch (field['width']?.toString()) {
    'third' => (available - AppSpace.sm * 2) / 3,
    'half' => (available - AppSpace.sm) / 2,
    _ => available,
  };
}

List<Map<String, dynamic>> _createPlacementFields(Object? raw) {
  if (raw is! List) return const [];
  final fields = raw
      .whereType<Map<String, dynamic>>()
      .where((field) {
        if (field['isSystem'] == true) return false;
        final placements = field['placements'];
        return placements is! List || placements.contains('create');
      })
      .toList(growable: false);
  fields.sort(
    (left, right) => ((left['order'] as num?)?.toInt() ?? 0).compareTo(
      (right['order'] as num?)?.toInt() ?? 0,
    ),
  );
  return fields;
}

bool _isEmptyFieldValue(Object? value) =>
    value == null ||
    (value is String && value.trim().isEmpty) ||
    (value is Iterable && value.isEmpty);

Widget _textField({
  required Key key,
  required TextEditingController controller,
  required String label,
  required String? error,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.sm),
    child: TextField(
      key: key,
      controller: controller,
      decoration: InputDecoration(labelText: label, errorText: error),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
      ],
    );
  }
}

class _EmptyMetadata extends StatelessWidget {
  const _EmptyMetadata({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('client-form-empty-metadata'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Text(message),
    );
  }
}

List<Map<String, dynamic>> _serializedCustomFields(
  List<Map<String, dynamic>> fields,
  Map<String, Object?> values,
) {
  return fields
      .where((field) {
        final value = values[field['id']?.toString()];
        return value != null && (value is! String || value.trim().isNotEmpty);
      })
      .map(
        (field) => {
          'definitionId': field['id'],
          'value': values[field['id']?.toString()],
        },
      )
      .toList(growable: false);
}

(String, String)? _serverFieldError(Object error) {
  if (error is! MagicApiException) return null;
  final details = error.details;
  if (details is! Map<String, dynamic>) return null;
  final field = details['field']?.toString();
  final message = details['message']?.toString();
  if (field == null || message == null) return null;
  return (field, message);
}
