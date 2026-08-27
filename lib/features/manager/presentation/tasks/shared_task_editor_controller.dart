import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor_gateway.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor_view_contract.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_models.dart';

sealed class SharedTaskSubmitOutcome {
  const SharedTaskSubmitOutcome();
}

class SharedTaskSubmitSuccess extends SharedTaskSubmitOutcome {
  const SharedTaskSubmitSuccess({required this.result, required this.created});

  final Map<String, dynamic> result;
  final bool created;
}

class SharedTaskSubmitFailure extends SharedTaskSubmitOutcome {
  const SharedTaskSubmitFailure(this.error);

  final Object error;
}

class SharedTaskSubmitIgnored extends SharedTaskSubmitOutcome {
  const SharedTaskSubmitIgnored();
}

class _MutationAttempt {
  const _MutationAttempt({
    required this.payloadFingerprint,
    required this.identity,
  });

  final String payloadFingerprint;
  final MagicMutationIdentity identity;
}

class SharedTaskEditorController extends ChangeNotifier
    implements SharedTaskEditorViewContract {
  SharedTaskEditorController({
    required this.dataSource,
    Map<String, dynamic>? task,
    Map<String, dynamic>? linkedEntity,
    SharedTaskAudiencePreviewLoader? previewLoader,
    DateTime? now,
  }) : _draft = SharedTaskEditorDraft.initial(
         task: task,
         linkedEntity: linkedEntity,
         now: now,
       ),
       _previewLoader = previewLoader ?? dataSource.previewAudience;

  final SharedTaskEditorGateway dataSource;
  final SharedTaskAudiencePreviewLoader _previewLoader;

  SharedTaskEditorDraft _draft;
  Map<String, dynamic>? _preview;
  Object? _previewError;
  Object? _saveError;
  bool _previewLoading = false;
  bool _saving = false;
  bool _terminalSuccess = false;
  bool _disposed = false;
  int _previewGeneration = 0;
  _MutationAttempt? _attempt;

  SharedTaskEditorDraft get draft => _draft;
  Map<String, dynamic>? get preview => _preview;
  Object? get previewError => _previewError;
  Object? get saveError => _saveError;
  bool get previewLoading => _previewLoading;
  bool get saving => _saving;
  bool get terminalSuccess => _terminalSuccess;
  bool get draftFrozen => _saving || _terminalSuccess;
  DateTime get effectiveReminderAt =>
      _draft.reminderAt ??
      SharedTaskEditorDraft.defaultReminderAt(_draft.allDay, _draft.start);
  bool get canAddAudience => !draftFrozen && _draft.canAddAudience;
  bool get canSubmit =>
      !draftFrozen &&
      _draft.title.trim().isNotEmpty &&
      _draft.hasValidInterval &&
      !_previewLoading &&
      _previewError == null &&
      _preview != null;

  List<Map<String, dynamic>> get previewSelectors {
    final selectors = _preview?['selectors'];
    return selectors is List
        ? selectors.whereType<Map<String, dynamic>>().toList(growable: false)
        : const [];
  }

  @override
  SharedTaskEditorViewSnapshot get snapshot => SharedTaskEditorViewSnapshot(
    draft: _draft,
    preview: _preview,
    previewError: _previewError,
    saveError: _saveError,
    previewLoading: _previewLoading,
    draftFrozen: draftFrozen,
    canAddAudience: canAddAudience,
    canSubmit: canSubmit,
    effectiveReminderAt: effectiveReminderAt,
    previewSelectors: List.unmodifiable(previewSelectors),
  );

  @override
  void setTitle(String value) => _updateDraft(_draft.copyWith(title: value));

  @override
  void setBody(String value) => _updateDraft(_draft.copyWith(body: value));

  @override
  void setPriority(String? value) {
    if (value == null) return;
    _updateDraft(_draft.copyWith(priority: value));
  }

  @override
  void setAllDay(bool value) => _updateDraft(_draft.setAllDay(value));

  @override
  void setStart(DateTime value) => _updateDraft(_draft.setStart(value));

  @override
  void setEnd(DateTime value) => _updateDraft(_draft.copyWith(end: value));

  @override
  void setAudienceType(Set<String> selection) {
    if (selection.isEmpty) return;
    _updateDraft(
      _draft.copyWith(audienceType: selection.first, targetId: null),
    );
  }

  @override
  void setAudienceTarget(String? value) =>
      _updateDraft(_draft.copyWith(targetId: value));

  @override
  void setReminder(bool value) => _updateDraft(_draft.setReminder(value));

  @override
  void setReminderAt(DateTime value) =>
      _updateDraft(_draft.setReminderAt(value));

  @override
  void addAudience() {
    if (_disposed || draftFrozen) return;
    final next = _draft.addAudience();
    if (identical(next, _draft)) return;
    _draft = next;
    _notify();
    unawaited(refreshAudiencePreview());
  }

  @override
  void removeAudience(Map<String, dynamic> audience) {
    if (_disposed || draftFrozen || _draft.audiences.length == 1) return;
    _draft = _draft.removeAudience(audience);
    _notify();
    unawaited(refreshAudiencePreview());
  }

  @override
  Future<void> refreshAudiencePreview() async {
    if (_disposed || draftFrozen) return;
    final generation = ++_previewGeneration;
    _previewLoading = true;
    _previewError = null;
    _preview = null;
    _notify();
    try {
      final preview = await _previewLoader(
        _draft.audiences.map(Map<String, dynamic>.from).toList(),
      );
      if (!_isCurrentPreview(generation)) return;
      _preview = Map<String, dynamic>.unmodifiable(preview);
      _previewLoading = false;
      _notify();
    } catch (error) {
      if (!_isCurrentPreview(generation)) return;
      _previewError = error;
      _previewLoading = false;
      _notify();
    }
  }

  Future<SharedTaskSubmitOutcome> submit() async {
    if (_disposed || !canSubmit) return const SharedTaskSubmitIgnored();
    final payload = _immutablePayload(_draft.payload());
    final fingerprint = _payloadFingerprint(payload);
    final created = _draft.created;
    final previousAttempt = _attempt;
    final attempt = previousAttempt?.payloadFingerprint == fingerprint
        ? previousAttempt!
        : _MutationAttempt(
            payloadFingerprint: fingerprint,
            identity: MagicMutationIdentity.create(
              created ? 'shared-task-create' : 'shared-task-update',
            ),
          );
    _attempt = attempt;
    _saving = true;
    _saveError = null;
    _notify();
    try {
      final result = created
          ? await dataSource.create(payload, attempt.identity)
          : await dataSource.update(_draft.taskId!, payload, attempt.identity);
      if (!_disposed) {
        _terminalSuccess = true;
        _saving = false;
        _notify();
      }
      return SharedTaskSubmitSuccess(result: result, created: created);
    } catch (error) {
      if (!_disposed) {
        _saving = false;
        _saveError = error;
        _notify();
      }
      return SharedTaskSubmitFailure(error);
    }
  }

  void _updateDraft(SharedTaskEditorDraft next) {
    if (_disposed || draftFrozen || identical(next, _draft)) return;
    _draft = next;
    _notify();
  }

  bool _isCurrentPreview(int generation) =>
      !_disposed && generation == _previewGeneration;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _previewGeneration++;
    super.dispose();
  }
}

String _payloadFingerprint(Map<String, dynamic> payload) =>
    jsonEncode(_canonicalJson(payload));

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalJson(value[key])};
  }
  if (value is Iterable) {
    return value.map(_canonicalJson).toList(growable: false);
  }
  return value;
}

Map<String, dynamic> _immutablePayload(Map<String, dynamic> payload) =>
    Map<String, dynamic>.unmodifiable(
      payload.map((key, value) => MapEntry(key, _immutableJson(value))),
    );

Object? _immutableJson(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map(
        (key, nested) => MapEntry(key.toString(), _immutableJson(nested)),
      ),
    );
  }
  if (value is Iterable) {
    return List<Object?>.unmodifiable(value.map(_immutableJson));
  }
  return value;
}
