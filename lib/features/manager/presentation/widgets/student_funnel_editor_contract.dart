import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/models/student_funnel.dart';

@immutable
class StudentFunnelEditorSnapshot {
  StudentFunnelEditorSnapshot({
    required this.clientType,
    required this.branchId,
    required StudentFunnelConfiguration? configuration,
    required List<StudentFunnelStage> stages,
    required List<Map<String, dynamic>> revisions,
    required this.reason,
    required this.error,
    required this.loading,
    required this.saving,
    required this.changed,
    required this.draftDirty,
  }) : configuration = configuration == null
           ? null
           : immutableStudentFunnelConfiguration(configuration),
       stages = immutableStudentFunnelStages(stages),
       revisions = immutableStudentFunnelRecords(revisions);

  final String clientType;
  final String? branchId;
  final StudentFunnelConfiguration? configuration;
  final List<StudentFunnelStage> stages;
  final List<Map<String, dynamic>> revisions;
  final String reason;
  final String? error;
  final bool loading;
  final bool saving;
  final bool changed;
  final bool draftDirty;
}

abstract interface class StudentFunnelEditorViewContract implements Listenable {
  StudentFunnelEditorSnapshot get snapshot;

  void setReason(String value);

  void updateStage(int index, StudentFunnelStage stage);

  void moveStage(int from, int delta);

  void addStage();
}

abstract interface class StudentFunnelEditorGateway {
  Future<StudentFunnelConfiguration> getConfiguration({
    required String clientType,
    String? branchId,
  });

  Future<List<Map<String, dynamic>>> listRevisions({
    required String clientType,
    String? branchId,
  });

  Future<Map<String, dynamic>> preview({
    required String clientType,
    String? branchId,
    required int expectedVersion,
    required List<StudentFunnelStage> stages,
  });

  Future<Map<String, dynamic>> publish({
    required String clientType,
    String? branchId,
    required int expectedVersion,
    required String reason,
    required List<StudentFunnelStage> stages,
  });

  Future<Map<String, dynamic>> rollback({
    required String clientType,
    String? branchId,
    required int expectedVersion,
    required int targetVersion,
    required String reason,
  });
}

sealed class StudentFunnelPreviewOutcome {
  const StudentFunnelPreviewOutcome();
}

class StudentFunnelPreviewRejected extends StudentFunnelPreviewOutcome {
  const StudentFunnelPreviewRejected(this.message);

  final String message;
}

class StudentFunnelPreviewBlocked extends StudentFunnelPreviewOutcome {
  const StudentFunnelPreviewBlocked(this.preview, this.message);

  final Map<String, dynamic> preview;
  final String message;
}

class StudentFunnelPreviewFailure extends StudentFunnelPreviewOutcome {
  const StudentFunnelPreviewFailure(this.message);

  final String message;
}

class StudentFunnelPublishPreview extends StudentFunnelPreviewOutcome {
  StudentFunnelPublishPreview({
    required Map<String, dynamic> preview,
    required this.clientType,
    required this.branchId,
    required this.expectedVersion,
    required this.reason,
    required List<StudentFunnelStage> stages,
  }) : preview = immutableStudentFunnelMap(preview),
       stages = immutableStudentFunnelStages(stages);

  final Map<String, dynamic> preview;
  final String clientType;
  final String? branchId;
  final int expectedVersion;
  final String reason;
  final List<StudentFunnelStage> stages;
}

Object? _immutableStudentFunnelValue(Object? value) {
  final domainValue = _immutableStudentFunnelDomain(value);
  return identical(domainValue, value)
      ? _immutableStudentFunnelCollection(value)
      : domainValue;
}

Object? _immutableStudentFunnelDomain(Object? value) {
  if (value is StudentFunnelConfiguration) {
    return StudentFunnelConfiguration(
      clientType: value.clientType,
      branchId: value.branchId,
      source: value.source,
      schoolVersion: value.schoolVersion,
      branchVersion: value.branchVersion,
      stages:
          _immutableStudentFunnelValue(value.stages)
              as List<StudentFunnelStage>,
      remediationStatuses:
          _immutableStudentFunnelValue(value.remediationStatuses)
              as List<Map<String, dynamic>>,
    );
  }
  if (value is StudentFunnelStage) {
    return StudentFunnelStage(
      key: value.key,
      label: value.label,
      style: value.style,
      active: value.active,
      terminal: value.terminal,
      requiresReason: value.requiresReason,
      allowedTransitions:
          _immutableStudentFunnelValue(value.allowedTransitions)
              as List<String>,
    );
  }
  return value;
}

Object? _immutableStudentFunnelCollection(Object? value) {
  if (value is List<StudentFunnelStage>) {
    return List<StudentFunnelStage>.unmodifiable(
      value.map(
        (stage) => _immutableStudentFunnelValue(stage) as StudentFunnelStage,
      ),
    );
  }
  if (value is List<Map<String, dynamic>>) {
    return List<Map<String, dynamic>>.unmodifiable(
      value.map(
        (record) =>
            _immutableStudentFunnelValue(record) as Map<String, dynamic>,
      ),
    );
  }
  if (value is List<String>) return List<String>.unmodifiable(value);
  if (value is Map<String, dynamic>) {
    return UnmodifiableMapView<String, dynamic>({
      for (final entry in value.entries)
        entry.key: _immutableStudentFunnelValue(entry.value),
    });
  }
  if (value is Map) {
    return UnmodifiableMapView<Object?, Object?>({
      for (final entry in value.entries)
        entry.key: _immutableStudentFunnelValue(entry.value),
    });
  }
  if (value is List) {
    return UnmodifiableListView<Object?>(
      value.map(_immutableStudentFunnelValue).toList(),
    );
  }
  return value;
}

StudentFunnelStage immutableStudentFunnelStage(StudentFunnelStage stage) =>
    _immutableStudentFunnelValue(stage) as StudentFunnelStage;

List<StudentFunnelStage> immutableStudentFunnelStages(
  Iterable<StudentFunnelStage> stages,
) =>
    _immutableStudentFunnelValue(List<StudentFunnelStage>.of(stages))
        as List<StudentFunnelStage>;

StudentFunnelConfiguration immutableStudentFunnelConfiguration(
  StudentFunnelConfiguration configuration,
) => _immutableStudentFunnelValue(configuration) as StudentFunnelConfiguration;

List<Map<String, dynamic>> immutableStudentFunnelRecords(
  Iterable<Map<String, dynamic>> records,
) =>
    _immutableStudentFunnelValue(List<Map<String, dynamic>>.of(records))
        as List<Map<String, dynamic>>;

Map<String, dynamic> immutableStudentFunnelMap(Map<String, dynamic> value) =>
    _immutableStudentFunnelValue(value) as Map<String, dynamic>;

sealed class StudentFunnelMutationOutcome {
  const StudentFunnelMutationOutcome();
}

class StudentFunnelMutationSuccess extends StudentFunnelMutationOutcome {
  const StudentFunnelMutationSuccess(this.result);

  final Map<String, dynamic> result;
}

class StudentFunnelMutationFailure extends StudentFunnelMutationOutcome {
  const StudentFunnelMutationFailure(this.message);

  final String message;
}

class StudentFunnelMutationIgnored extends StudentFunnelMutationOutcome {
  const StudentFunnelMutationIgnored();
}
