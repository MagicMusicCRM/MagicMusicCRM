import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/models/student_funnel.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/student_funnel_editor_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/student_funnel_editor_view.dart';

Future<bool?> showClientPipelineEditor(
  BuildContext context, {
  required List<Map<String, dynamic>> branches,
  String? initialBranchId,
  String initialClientType = 'student',
  VoidCallback? onPublished,
}) {
  return showMagicAdaptiveSurface<bool>(
    context,
    kind: AppSurfaceKind.selection,
    title: 'Воронки клиентов',
    subtitle: 'Единые правила лидов и учеников для школы и филиалов',
    icon: Icons.view_kanban_outlined,
    builder: (_) => _StudentFunnelEditor(
      branches: branches,
      initialBranchId: initialBranchId,
      initialClientType: initialClientType,
      onPublished: onPublished,
    ),
  );
}

class _StudentFunnelEditor extends ConsumerStatefulWidget {
  const _StudentFunnelEditor({
    required this.branches,
    required this.initialBranchId,
    required this.initialClientType,
    required this.onPublished,
  });

  final List<Map<String, dynamic>> branches;
  final String? initialBranchId;
  final String initialClientType;
  final VoidCallback? onPublished;

  @override
  ConsumerState<_StudentFunnelEditor> createState() =>
      _StudentFunnelEditorState();
}

class _StudentFunnelEditorState extends ConsumerState<_StudentFunnelEditor> {
  final _reason = TextEditingController();
  late final StudentFunnelEditorController _controller;

  @override
  void initState() {
    super.initState();
    _controller = StudentFunnelEditorController(
      gateway: _MagicCrmStudentFunnelGateway(ref.read(magicCrmServiceProvider)),
      initialClientType: widget.initialClientType,
      initialBranchId: widget.initialBranchId,
    );
    _controller.load();
    _controller.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_rebuild)
      ..dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final outcome = await _controller.previewPublish();
    if (!mounted || outcome is! StudentFunnelPublishPreview) return;
    final confirmed = await _confirmPreview(outcome.preview);
    if (!mounted) return;
    if (confirmed != true) {
      _controller.cancelPublishPreview(outcome);
      return;
    }
    final result = await _controller.confirmPublish(outcome);
    if (!mounted || result is! StudentFunnelMutationSuccess) return;
    _reason.clear();
    widget.onPublished?.call();
  }

  Future<void> _requestRollback(int targetVersion) async {
    final confirmed = await showMagicDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Вернуть версию $targetVersion?'),
        content: const Text(
          'Текущая воронка останется в истории, а выбранный вариант будет опубликован как новая версия.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Вернуть'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await _controller.rollback(targetVersion);
    if (!mounted || result is! StudentFunnelMutationSuccess) return;
    widget.onPublished?.call();
  }

  Future<void> _changeScope(String? value) async {
    final target = value == '__school__' ? null : value;
    if (target == _controller.snapshot.branchId) return;
    var discardConfirmed = true;
    if (_controller.snapshot.draftDirty) {
      discardConfirmed = await _confirmScopeDiscard();
    }
    final changed = await _controller.changeScope(
      target,
      discardConfirmed: discardConfirmed,
    );
    if (changed && mounted) _reason.clear();
  }

  Future<void> _changeClientType(String? value) async {
    if (value == null || value == _controller.snapshot.clientType) return;
    var discardConfirmed = true;
    if (_controller.snapshot.draftDirty) {
      discardConfirmed = await _confirmDiscard();
    }
    final changed = await _controller.changeClientType(
      value,
      discardConfirmed: discardConfirmed,
    );
    if (changed && mounted) _reason.clear();
  }

  Future<bool> _confirmScopeDiscard() async {
    final discard = await showMagicDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сменить область?'),
        content: const Text(
          'Неопубликованные изменения текущей воронки будут сброшены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Остаться'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сменить'),
          ),
        ],
      ),
    );
    return discard == true && mounted;
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showMagicDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сбросить изменения?'),
        content: const Text('Неопубликованные изменения будут потеряны.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Остаться'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    return discard == true && mounted;
  }

  Future<bool?> _confirmPreview(Map<String, dynamic> preview) {
    final changes = preview['changes'] as Map? ?? const {};
    return showMagicDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Опубликовать воронку?'),
        content: Text(
          'Новых этапов: ${changes['created'] ?? 0} · '
          'изменено: ${changes['updated'] ?? 0} · '
          'архивировано: ${changes['archived'] ?? 0}\n'
          'Затронуто клиентов: ${preview['affectedClients'] ?? 0}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Опубликовать'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBlockedClose(bool didPop, bool? result) async {
    if (didPop) return;
    final discard = await showMagicDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Закрыть без публикации?'),
        content: const Text('Неопубликованные изменения будут потеряны.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Остаться'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop(_controller.snapshot.changed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StudentFunnelEditorView(
      contract: _controller,
      branches: widget.branches,
      reasonController: _reason,
      onClientTypeChanged: _changeClientType,
      onScopeChanged: _changeScope,
      onPublish: _publish,
      onRollback: _requestRollback,
      onRetry: _controller.load,
      onClose: () => Navigator.of(context).pop(_controller.snapshot.changed),
      onBlockedClose: _handleBlockedClose,
    );
  }
}

class _MagicCrmStudentFunnelGateway implements StudentFunnelEditorGateway {
  const _MagicCrmStudentFunnelGateway(this._service);

  final MagicCrmService _service;

  @override
  Future<StudentFunnelConfiguration> getConfiguration({
    required String clientType,
    String? branchId,
  }) => _service.getClientPipeline(clientType: clientType, branchId: branchId);

  @override
  Future<List<Map<String, dynamic>>> listRevisions({
    required String clientType,
    String? branchId,
  }) => _service.listClientPipelineRevisions(
    clientType: clientType,
    branchId: branchId,
  );

  @override
  Future<Map<String, dynamic>> preview({
    required String clientType,
    String? branchId,
    required int expectedVersion,
    required List<StudentFunnelStage> stages,
  }) => _service.previewClientPipeline(
    clientType: clientType,
    branchId: branchId,
    expectedVersion: expectedVersion,
    stages: stages,
  );

  @override
  Future<Map<String, dynamic>> publish({
    required String clientType,
    String? branchId,
    required int expectedVersion,
    required String reason,
    required List<StudentFunnelStage> stages,
  }) => _service.publishClientPipeline(
    clientType: clientType,
    branchId: branchId,
    expectedVersion: expectedVersion,
    reason: reason,
    stages: stages,
  );

  @override
  Future<Map<String, dynamic>> rollback({
    required String clientType,
    String? branchId,
    required int expectedVersion,
    required int targetVersion,
    required String reason,
  }) => _service.rollbackClientPipeline(
    clientType: clientType,
    branchId: branchId,
    expectedVersion: expectedVersion,
    targetVersion: targetVersion,
    reason: reason,
  );
}
