import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_task_editor_draft.dart';

@immutable
class SharedTaskEditorViewSnapshot {
  const SharedTaskEditorViewSnapshot({
    required this.draft,
    required this.preview,
    required this.previewError,
    required this.saveError,
    required this.previewLoading,
    required this.draftFrozen,
    required this.canAddAudience,
    required this.canSubmit,
    required this.effectiveReminderAt,
    required this.previewSelectors,
  });

  final SharedTaskEditorDraft draft;
  final Map<String, dynamic>? preview;
  final Object? previewError;
  final Object? saveError;
  final bool previewLoading;
  final bool draftFrozen;
  final bool canAddAudience;
  final bool canSubmit;
  final DateTime effectiveReminderAt;
  final List<Map<String, dynamic>> previewSelectors;
}

abstract interface class SharedTaskEditorViewContract {
  SharedTaskEditorViewSnapshot get snapshot;

  void setTitle(String value);
  void setBody(String value);
  void setPriority(String? value);
  void setAllDay(bool value);
  void setStart(DateTime value);
  void setEnd(DateTime value);
  void setAudienceType(Set<String> selection);
  void setAudienceTarget(String? value);
  void setReminder(bool value);
  void setReminderAt(DateTime value);
  void addAudience();
  void removeAudience(Map<String, dynamic> audience);
  Future<void> refreshAudiencePreview();
}
