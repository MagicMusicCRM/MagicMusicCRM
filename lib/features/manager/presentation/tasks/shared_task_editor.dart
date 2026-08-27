import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor_view.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

Future<bool?> showSharedTaskEditor(
  BuildContext context, {
  required SharedTasksDataSource dataSource,
  Map<String, dynamic>? task,
  EntityLink? linkedEntity,
  VoidCallback? onSaved,
}) async {
  List<SharedTaskAudienceOption> options = const [];
  try {
    options = await dataSource.audienceOptions();
  } catch (_) {
    // The all-branches audience remains usable without directory data.
  }
  if (!context.mounted) return null;
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.selection,
    title: task == null ? 'Новая задача' : 'Изменить задачу',
    subtitle: 'Срок, получатели и напоминание',
    icon: task == null ? Icons.add_task_rounded : Icons.edit_note_rounded,
    builder: (_) => SharedTaskEditor(
      dataSource: dataSource,
      audienceOptions: options,
      task: task,
      linkedEntity: linkedEntity,
      onSaved: onSaved,
      embedded: true,
    ),
  );
}

Future<void> showCreateSharedTask(
  BuildContext context,
  WidgetRef ref, {
  EntityLink? linkedEntity,
  VoidCallback? onSaved,
}) async {
  await showSharedTaskEditor(
    context,
    dataSource: MagicCrmSharedTasksDataSource.fromWidgetRef(ref),
    linkedEntity: linkedEntity,
    onSaved: onSaved,
  );
}

String _taskSavedMessage(Map<String, dynamic> result, {required bool created}) {
  final summary = result['recipientSummary'];
  final total = summary is Map<String, dynamic>
      ? summary['totalRecipients']
      : null;
  final action = created ? 'Задача создана.' : 'Задача сохранена.';
  return total is num
      ? '$action Получателей сейчас: ${total.toInt()}.'
      : action;
}

class SharedTaskEditor extends StatefulWidget {
  const SharedTaskEditor({
    super.key,
    required this.dataSource,
    this.audienceOptions = const [],
    this.task,
    this.linkedEntity,
    this.audiencePreview,
    this.onSaved,
    this.embedded = false,
  });

  final SharedTasksDataSource dataSource;
  final List<SharedTaskAudienceOption> audienceOptions;
  final Map<String, dynamic>? task;
  final EntityLink? linkedEntity;
  final SharedTaskAudiencePreviewLoader? audiencePreview;
  final VoidCallback? onSaved;
  final bool embedded;

  @override
  State<SharedTaskEditor> createState() => _SharedTaskEditorState();
}

class _SharedTaskEditorState extends State<SharedTaskEditor> {
  late final SharedTaskEditorController _controller;
  late final TextEditingController _title;
  late final TextEditingController _body;
  bool _savedCallbackAttempted = false;

  @override
  void initState() {
    super.initState();
    _controller = SharedTaskEditorController(
      dataSource: widget.dataSource,
      task: widget.task,
      linkedEntity: widget.linkedEntity == null
          ? null
          : {
              'type': widget.linkedEntity!.rawEntityType,
              'id': widget.linkedEntity!.entityId,
            },
      previewLoader: widget.audiencePreview,
    )..addListener(_onControllerChanged);
    _title = TextEditingController(text: _controller.draft.title);
    _body = TextEditingController(text: _controller.draft.body);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_controller.refreshAudiencePreview());
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SharedTaskEditorView(
    controller: _controller,
    titleController: _title,
    bodyController: _body,
    audienceOptions: widget.audienceOptions,
    embedded: widget.embedded,
    onCancel: _cancel,
    onSubmit: _submit,
  );

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _cancel() {
    if (_controller.draftFrozen || !mounted) return;
    Navigator.pop(context);
  }

  Future<void> _submit() async {
    if (_controller.draftFrozen) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final outcome = await _controller.submit();
    if (outcome is! SharedTaskSubmitSuccess || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!_savedCallbackAttempted) {
      _savedCallbackAttempted = true;
      try {
        widget.onSaved?.call();
      } catch (_) {
        // A consumer callback cannot turn a committed command into a retry.
      }
    }
    try {
      Navigator.pop(context, true);
    } catch (_) {
      // The server command has succeeded and must remain terminal.
    }
    try {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            _taskSavedMessage(outcome.result, created: outcome.created),
          ),
        ),
      );
    } catch (_) {
      // Presentation failure cannot make a committed command retryable.
    }
  }
}
