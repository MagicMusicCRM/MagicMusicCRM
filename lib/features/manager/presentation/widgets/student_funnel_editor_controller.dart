import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/student_funnel.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/student_funnel_editor_contract.dart';

export 'package:magic_music_crm/features/manager/presentation/widgets/student_funnel_editor_contract.dart';

class StudentFunnelEditorController extends ChangeNotifier
    implements StudentFunnelEditorViewContract {
  StudentFunnelEditorController({
    required StudentFunnelEditorGateway gateway,
    required String initialClientType,
    String? initialBranchId,
  }) : _gateway = gateway,
       _clientType = initialClientType,
       _branchId = initialBranchId;

  final StudentFunnelEditorGateway _gateway;
  String _clientType;
  String? _branchId;
  StudentFunnelConfiguration? _configuration;
  List<StudentFunnelStage> _stages = const [];
  List<Map<String, dynamic>> _revisions = const [];
  String _reason = '';
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  bool _draftDirty = false;
  bool _disposed = false;
  int _loadGeneration = 0;
  StudentFunnelPublishPreview? _pendingPreview;

  @override
  StudentFunnelEditorSnapshot get snapshot => StudentFunnelEditorSnapshot(
    clientType: _clientType,
    branchId: _branchId,
    configuration: _configuration,
    stages: _stages,
    revisions: _revisions,
    reason: _reason,
    error: _error,
    loading: _loading,
    saving: _saving,
    changed: _changed,
    draftDirty: _draftDirty,
  );

  Future<void> load() async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    final clientType = _clientType;
    final branchId = _branchId;
    _loading = true;
    _error = null;
    _notify();
    try {
      final result = await Future.wait<Object>([
        _gateway.getConfiguration(clientType: clientType, branchId: branchId),
        _gateway.listRevisions(clientType: clientType, branchId: branchId),
      ]);
      if (!_isCurrent(generation)) return;
      final configuration = immutableStudentFunnelConfiguration(
        result[0] as StudentFunnelConfiguration,
      );
      _configuration = configuration;
      _stages = immutableStudentFunnelStages(configuration.stages);
      _revisions = immutableStudentFunnelRecords(
        result[1] as List<Map<String, dynamic>>,
      );
      _loading = false;
      _saving = false;
      _draftDirty = false;
      _notify();
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _loading = false;
      _saving = false;
      _error = userErrorMessage(
        error,
        fallback: 'Не удалось загрузить воронку.',
      );
      _notify();
    }
  }

  @override
  void setReason(String value) {
    if (_disposed || _saving || _reason == value) return;
    _reason = value;
    _draftDirty = true;
    _notify();
  }

  @override
  void updateStage(int index, StudentFunnelStage stage) {
    if (_disposed || _saving || index < 0 || index >= _stages.length) return;
    _stages = immutableStudentFunnelStages([..._stages]..[index] = stage);
    _draftDirty = true;
    _notify();
  }

  @override
  void moveStage(int from, int delta) {
    if (_disposed) return;
    final to = from + delta;
    if (_saving || from < 0 || from >= _stages.length) return;
    if (to < 0 || to >= _stages.length) return;
    final stages = [..._stages];
    final item = stages.removeAt(from);
    stages.insert(to, item);
    _stages = immutableStudentFunnelStages(stages);
    _draftDirty = true;
    _notify();
  }

  @override
  void addStage() {
    if (_disposed || _saving) return;
    _stages = immutableStudentFunnelStages([
      ..._stages,
      StudentFunnelStage(
        key: 'custom_${DateTime.now().microsecondsSinceEpoch}',
        label: 'Новый этап',
        style: 'gray',
        active: true,
        terminal: false,
        requiresReason: false,
        allowedTransitions: const [],
      ),
    ]);
    _draftDirty = true;
    _notify();
  }

  Future<StudentFunnelPreviewOutcome> previewPublish() async {
    if (_disposed) return const StudentFunnelPreviewFailure('');
    final rejection = _validateDraft();
    if (rejection != null) return rejection;
    final configuration = _configuration!;
    final candidate = StudentFunnelPublishPreview(
      preview: const {},
      clientType: _clientType,
      branchId: _branchId,
      expectedVersion: configuration.scopeVersion,
      reason: _reason.trim(),
      stages: _stages,
    );
    _saving = true;
    _error = null;
    _pendingPreview = null;
    _notify();
    try {
      final preview = await _gateway.preview(
        clientType: candidate.clientType,
        branchId: candidate.branchId,
        expectedVersion: candidate.expectedVersion,
        stages: candidate.stages,
      );
      if (_disposed) return const StudentFunnelPreviewFailure('');
      return _acceptPreview(candidate, preview);
    } catch (error) {
      final message = userErrorMessage(
        error,
        fallback: 'Не удалось опубликовать воронку.',
      );
      if (_disposed) return StudentFunnelPreviewFailure(message);
      _saving = false;
      _error = message;
      _notify();
      return StudentFunnelPreviewFailure(message);
    }
  }

  StudentFunnelPreviewOutcome _acceptPreview(
    StudentFunnelPublishPreview candidate,
    Map<String, dynamic> preview,
  ) {
    final blockingIssues = preview['blockingIssues'];
    if (preview['valid'] != true ||
        (blockingIssues is List && blockingIssues.isNotEmpty)) {
      final message = _blockingMessage(preview);
      _saving = false;
      _error = message;
      _notify();
      return StudentFunnelPreviewBlocked(preview, message);
    }
    final accepted = StudentFunnelPublishPreview(
      preview: preview,
      clientType: candidate.clientType,
      branchId: candidate.branchId,
      expectedVersion: candidate.expectedVersion,
      reason: candidate.reason,
      stages: candidate.stages,
    );
    _pendingPreview = accepted;
    return accepted;
  }

  void cancelPublishPreview(StudentFunnelPublishPreview preview) {
    if (_disposed || !identical(_pendingPreview, preview)) return;
    _pendingPreview = null;
    _saving = false;
    _notify();
  }

  Future<StudentFunnelMutationOutcome> confirmPublish(
    StudentFunnelPublishPreview preview,
  ) async {
    if (_disposed || !identical(_pendingPreview, preview) || !_saving) {
      return const StudentFunnelMutationIgnored();
    }
    _pendingPreview = null;
    try {
      final result = await _gateway.publish(
        clientType: preview.clientType,
        branchId: preview.branchId,
        expectedVersion: preview.expectedVersion,
        reason: preview.reason,
        stages: preview.stages,
      );
      if (_disposed) return const StudentFunnelMutationIgnored();
      _changed = true;
      _draftDirty = false;
      _reason = '';
      _clearCanonicalState();
      await load();
      return StudentFunnelMutationSuccess(result);
    } catch (error) {
      return _mutationFailure(error, 'Не удалось опубликовать воронку.');
    }
  }

  Future<StudentFunnelMutationOutcome> rollback(int targetVersion) async {
    if (_disposed) return const StudentFunnelMutationIgnored();
    final configuration = _configuration;
    if (configuration == null || _saving) {
      return const StudentFunnelMutationIgnored();
    }
    _saving = true;
    _error = null;
    _notify();
    try {
      final result = await _gateway.rollback(
        clientType: _clientType,
        branchId: _branchId,
        expectedVersion: configuration.scopeVersion,
        targetVersion: targetVersion,
        reason: 'Откат к версии $targetVersion',
      );
      if (_disposed) return const StudentFunnelMutationIgnored();
      _changed = true;
      _draftDirty = false;
      _clearCanonicalState();
      await load();
      return StudentFunnelMutationSuccess(result);
    } catch (error) {
      return _mutationFailure(error, 'Не удалось вернуть версию.');
    }
  }

  Future<bool> changeScope(
    String? branchId, {
    required bool discardConfirmed,
  }) async {
    if (_disposed || _saving || (_draftDirty && !discardConfirmed)) {
      return false;
    }
    if (_branchId == branchId) return true;
    _discardCurrentIdentity();
    _branchId = branchId;
    await load();
    return true;
  }

  Future<bool> changeClientType(
    String clientType, {
    required bool discardConfirmed,
  }) async {
    if (_disposed || _saving || (_draftDirty && !discardConfirmed)) {
      return false;
    }
    if (_clientType == clientType) return true;
    _discardCurrentIdentity();
    _clientType = clientType;
    await load();
    return true;
  }

  void _discardCurrentIdentity() {
    _pendingPreview = null;
    _clearCanonicalState();
    _reason = '';
    _error = null;
    _saving = false;
    _draftDirty = false;
  }

  void _clearCanonicalState() {
    _configuration = null;
    _stages = const [];
    _revisions = const [];
  }

  StudentFunnelPreviewRejected? _validateDraft() {
    String? message;
    if (_configuration == null || _saving) {
      message = 'Воронка ещё не готова к публикации.';
    } else if (_reason.trim().isEmpty) {
      message = 'Укажите причину изменения.';
    } else if (_stages.every((stage) => !stage.active)) {
      message = 'Оставьте хотя бы один активный этап.';
    }
    if (message == null) return null;
    _error = message;
    _notify();
    return StudentFunnelPreviewRejected(message);
  }

  StudentFunnelMutationFailure _mutationFailure(Object error, String fallback) {
    final message = userErrorMessage(error, fallback: fallback);
    if (!_disposed) {
      _saving = false;
      _error = message;
      _notify();
    }
    return StudentFunnelMutationFailure(message);
  }

  String _blockingMessage(Map<String, dynamic> preview) {
    final message = (preview['blockingIssues'] as List? ?? const [])
        .whereType<Map>()
        .map((issue) => issue['message']?.toString().trim())
        .whereType<String>()
        .where((message) => message.isNotEmpty)
        .join('\n');
    return message.isEmpty
        ? 'Публикация заблокирована. Проверьте настройки воронки.'
        : message;
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _loadGeneration;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loadGeneration++;
    super.dispose();
  }
}
