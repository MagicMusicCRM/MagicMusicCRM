import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';

import 'client_forms_api.dart';

const _studentStatuses = <String, String>{
  'active': 'Занимается',
  'paused': 'Приостановил',
  'completed': 'Закончил обучение',
};

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
  List<Map<String, dynamic>> _sources = const [];
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
      ]);
      if (!mounted) return;
      final sources = results[0];
      setState(() {
        _sources = sources;
        _fields = results[1];
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
    for (final field in _fields.where((item) => item['required'] == true)) {
      final id = field['id']?.toString() ?? '';
      final value = _customValues[id];
      if (value == null || (value is String && value.trim().isEmpty)) {
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
          onPressed: _saving || _loading || _sources.isEmpty ? null : _save,
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
                        labelText: 'Источник *',
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
  const StudentCreateDialogV4({super.key});

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
  String _status = 'active';
  List<Map<String, dynamic>> _branches = const [];
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
      ]);
      if (!mounted) return;
      setState(() {
        _branches = results[0];
        _fields = results[1];
        if (_branches.length == 1) {
          _branchId = _branches.first['id']?.toString();
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
    for (final field in _fields.where((item) => item['required'] == true)) {
      final id = field['id']?.toString() ?? '';
      final value = _customValues[id];
      if (value == null || (value is String && value.trim().isEmpty)) {
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
            status: _status,
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

  @override
  Widget build(BuildContext context) {
    return _AdaptiveClientDialog(
      title: 'Новый ученик',
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
          onPressed: _saving || _loading || _branches.isEmpty ? null : _save,
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
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _branchId = value),
                  ),
                const SizedBox(height: AppSpace.sm),
                DropdownButtonFormField<String>(
                  key: const ValueKey('student-status'),
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Статус клиента *',
                  ),
                  items: _studentStatuses.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _status = value ?? 'active'),
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
  });

  final String title;
  final bool loading;
  final String? loadError;
  final VoidCallback onRetry;
  final String? submitError;
  final List<Widget> actions;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
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
          child: SingleChildScrollView(
            child: Column(
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
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
    return Column(
      children: [
        for (final field in fields) ...[
          const SizedBox(height: AppSpace.sm),
          _field(field),
        ],
      ],
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
    if (type == 'select') {
      final options = (field['options'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false);
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
    return TextFormField(
      key: ValueKey('custom-field-$key'),
      initialValue: values[id]?.toString(),
      enabled: enabled,
      keyboardType: type == 'number'
          ? const TextInputType.numberWithOptions(decimal: true)
          : type == 'email'
          ? TextInputType.emailAddress
          : type == 'phone'
          ? TextInputType.phone
          : TextInputType.text,
      decoration: InputDecoration(labelText: label, errorText: error),
      onChanged: (value) {
        if (type == 'number') {
          onChanged(id, num.tryParse(value.replaceAll(',', '.')));
        } else {
          onChanged(id, value);
        }
      },
    );
  }
}

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
