import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface_kind.dart';
import 'package:magic_music_crm/core/widgets/app_dropdown.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_controller.dart';

typedef SharedTaskCloseSubmit =
    Future<SharedTaskCloseResult> Function(SharedTaskCompletionInput input);

Future<bool?> showSharedTaskCloseDialog(
  BuildContext context, {
  required SharedTaskCloseSubmit onSubmit,
}) {
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.confirmation,
    title: 'Результат выполнения задачи',
    icon: Icons.task_alt_rounded,
    builder: (surfaceContext) => _SharedTaskCloseForm(onSubmit: onSubmit),
  );
}

class _SharedTaskCloseForm extends StatefulWidget {
  const _SharedTaskCloseForm({required this.onSubmit});

  final SharedTaskCloseSubmit onSubmit;

  @override
  State<_SharedTaskCloseForm> createState() => _SharedTaskCloseFormState();
}

class _SharedTaskCloseFormState extends State<_SharedTaskCloseForm> {
  final _formKey = GlobalKey<FormState>();
  final _comment = TextEditingController();
  String? _resultCode;
  Object? _error;
  bool _submitting = false;

  SharedTaskResultOption? get _selected {
    for (final option in sharedTaskResultOptions) {
      if (option.code == _resultCode) return option;
    }
    return null;
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final selected = _selected!;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await widget.onSubmit(
      SharedTaskCompletionInput(
        resultCode: selected.code,
        resultLabel: selected.label,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
      ),
    );
    if (!mounted) return;
    if (result.succeeded) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = result.error ?? StateError('close ignored');
    });
  }

  @override
  Widget build(BuildContext context) {
    final other = _resultCode == 'other';
    return SingleChildScrollView(
      padding: AppSpace.sheetBody,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: const Key('shared-task-result-select'),
              initialValue: _resultCode,
              decoration: const InputDecoration(labelText: 'Результат *'),
              items: [
                for (final option in sharedTaskResultOptions)
                  DropdownMenuItem(
                    value: option.code,
                    child: Text(option.label),
                  ),
              ],
              validator: (value) => value == null
                  ? 'Выберите результат выполнения задачи.'
                  : null,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() {
                      _resultCode = value;
                      _error = null;
                    }),
            ),
            const SizedBox(height: AppSpace.md),
            TextFormField(
              key: const Key('shared-task-result-comment'),
              controller: _comment,
              enabled: !_submitting,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: other
                    ? 'Пояснение *'
                    : 'Комментарий (необязательно)',
                alignLabelWithHint: true,
              ),
              validator: (value) => other && (value?.trim().isEmpty ?? true)
                  ? 'Для результата «Другое» добавьте пояснение.'
                  : null,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                userErrorMessage(
                  _error,
                  fallback:
                      'Не удалось закрыть задачу. Данные формы сохранены.',
                ),
                key: const Key('shared-task-close-error'),
                style: const TextStyle(color: AppColor.danger),
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: AppSpace.sm),
                FilledButton.icon(
                  key: const Key('shared-task-close-submit'),
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.task_alt_rounded),
                  label: const Text('Закрыть'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
