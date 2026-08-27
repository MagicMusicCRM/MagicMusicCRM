import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/student_funnel.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/student_funnel_editor_controller.dart';

StudentFunnelConfiguration _configuration({
  String? branchId,
  int schoolVersion = 1,
  int branchVersion = 0,
  String label = 'Обучается',
}) => StudentFunnelConfiguration(
  clientType: 'student',
  branchId: branchId,
  source: branchId == null ? 'school' : 'branch',
  schoolVersion: schoolVersion,
  branchVersion: branchVersion,
  stages: [
    StudentFunnelStage(
      key: 'active',
      label: label,
      style: 'green',
      active: true,
      allowedTransitions: const [],
    ),
  ],
  remediationStatuses: const [],
);

class _Gateway implements StudentFunnelEditorGateway {
  StudentFunnelConfiguration configuration = _configuration();
  Map<String, dynamic> previewResult = {
    'valid': true,
    'changes': {'created': 0, 'updated': 1, 'archived': 0},
    'affectedClients': 0,
    'blockingIssues': <Map<String, dynamic>>[],
  };
  final events = <String>[];
  final configurationLoads = <String, Completer<StudentFunnelConfiguration>>{};
  final revisionLoads = <String, Completer<List<Map<String, dynamic>>>>{};
  Completer<Map<String, dynamic>>? previewCompletion;
  Completer<Map<String, dynamic>>? publishCompletion;
  Completer<Map<String, dynamic>>? rollbackCompletion;
  int? lastPreviewVersion;
  int? lastPublishVersion;
  int? lastRollbackVersion;
  int? lastRollbackTarget;
  int rollbackVersion = 2;
  int publishCalls = 0;
  Object? configurationError;

  String _scope(String? branchId) => branchId ?? 'school';

  @override
  Future<StudentFunnelConfiguration> getConfiguration({
    required String clientType,
    String? branchId,
  }) {
    events.add('load:${_scope(branchId)}');
    if (configurationError != null) {
      return Future.error(configurationError!);
    }
    return configurationLoads[_scope(branchId)]?.future ??
        Future.value(configuration);
  }

  @override
  Future<List<Map<String, dynamic>>> listRevisions({
    required String clientType,
    String? branchId,
  }) {
    events.add('revisions:${_scope(branchId)}');
    return revisionLoads[_scope(branchId)]?.future ?? Future.value(const []);
  }

  @override
  Future<Map<String, dynamic>> preview({
    required String clientType,
    String? branchId,
    required int expectedVersion,
    required List<StudentFunnelStage> stages,
  }) {
    lastPreviewVersion = expectedVersion;
    events.add('preview:$expectedVersion');
    return previewCompletion?.future ?? Future.value(previewResult);
  }

  @override
  Future<Map<String, dynamic>> publish({
    required String clientType,
    String? branchId,
    required int expectedVersion,
    required String reason,
    required List<StudentFunnelStage> stages,
  }) {
    publishCalls++;
    lastPublishVersion = expectedVersion;
    events.add('publish:$expectedVersion');
    if (publishCompletion != null) return publishCompletion!.future;
    configuration = _configuration(schoolVersion: expectedVersion + 1);
    return Future.value({'version': expectedVersion + 1});
  }

  @override
  Future<Map<String, dynamic>> rollback({
    required String clientType,
    String? branchId,
    required int expectedVersion,
    required int targetVersion,
    required String reason,
  }) {
    lastRollbackVersion = expectedVersion;
    lastRollbackTarget = targetVersion;
    events.add('rollback:$expectedVersion');
    if (rollbackCompletion != null) return rollbackCompletion!.future;
    configuration = _configuration(schoolVersion: rollbackVersion);
    return Future.value({'version': rollbackVersion});
  }
}

Map<String, Object?> _snapshotData(StudentFunnelEditorSnapshot snapshot) => {
  'clientType': snapshot.clientType,
  'branchId': snapshot.branchId,
  'configuration': snapshot.configuration == null
      ? null
      : {
          'scopeVersion': snapshot.configuration!.scopeVersion,
          'source': snapshot.configuration!.source,
        },
  'stages': snapshot.stages.map((stage) => stage.toJson()).toList(),
  'revisions': snapshot.revisions.map(Map<String, dynamic>.from).toList(),
  'reason': snapshot.reason,
  'error': snapshot.error,
  'loading': snapshot.loading,
  'saving': snapshot.saving,
  'changed': snapshot.changed,
  'draftDirty': snapshot.draftDirty,
};

Future<StudentFunnelPublishPreview> _loadedPreview(
  StudentFunnelEditorController controller,
) async {
  await controller.load();
  controller.setReason('Проверка lifecycle');
  return await controller.previewPublish() as StudentFunnelPublishPreview;
}

void main() {
  test('publish always previews and uses configuration scopeVersion', () async {
    final gateway = _Gateway()
      ..configuration = _configuration(schoolVersion: 7);
    final controller = StudentFunnelEditorController(
      gateway: gateway,
      initialClientType: 'student',
    );
    await controller.load();
    controller
      ..setReason('Новая логика')
      ..updateStage(
        0,
        controller.snapshot.stages.single.copyWith(label: 'Активный'),
      );

    final preview = await controller.previewPublish();
    expect(preview, isA<StudentFunnelPublishPreview>());
    final published = await controller.confirmPublish(
      preview as StudentFunnelPublishPreview,
    );

    expect(published, isA<StudentFunnelMutationSuccess>());
    expect(gateway.lastPreviewVersion, 7);
    expect(gateway.lastPublishVersion, 7);
    expect(
      gateway.events.indexOf('preview:7'),
      lessThan(gateway.events.indexOf('publish:7')),
    );
  });

  test('reason and blocking issues prevent publish', () async {
    final gateway = _Gateway();
    final controller = StudentFunnelEditorController(
      gateway: gateway,
      initialClientType: 'student',
    );
    await controller.load();

    expect(
      await controller.previewPublish(),
      isA<StudentFunnelPreviewRejected>(),
    );
    expect(
      gateway.events.where((event) => event.startsWith('preview')),
      isEmpty,
    );

    controller.setReason('Проверка блокеров');
    gateway.previewResult = {
      'valid': false,
      'blockingIssues': [
        {'message': 'Этап используется активными клиентами'},
      ],
    };
    expect(
      await controller.previewPublish(),
      isA<StudentFunnelPreviewBlocked>(),
    );
    expect(gateway.publishCalls, 0);
    expect(controller.snapshot.error, contains('Этап используется'));
  });

  test('nonempty blocking issues override a valid preview flag', () async {
    final gateway = _Gateway()
      ..previewResult = {
        'valid': true,
        'blockingIssues': [
          {'message': 'Сначала перенесите активных клиентов'},
        ],
      };
    final controller = StudentFunnelEditorController(
      gateway: gateway,
      initialClientType: 'student',
    );
    await controller.load();
    controller.setReason('Проверка серверных блокеров');

    final outcome = await controller.previewPublish();

    expect(outcome, isA<StudentFunnelPreviewBlocked>());
    expect(gateway.publishCalls, 0);
    expect(controller.snapshot.error, contains('перенесите активных клиентов'));
  });

  test('empty blocking issues expose a stable Russian fallback', () async {
    final gateway = _Gateway()
      ..previewResult = {
        'valid': false,
        'blockingIssues': <Map<String, dynamic>>[],
      };
    final controller = StudentFunnelEditorController(
      gateway: gateway,
      initialClientType: 'student',
    );
    await controller.load();
    controller.setReason('Проверка пустых блокеров');

    expect(
      await controller.previewPublish(),
      isA<StudentFunnelPreviewBlocked>(),
    );
    expect(
      controller.snapshot.error,
      'Публикация заблокирована. Проверьте настройки воронки.',
    );
  });

  test('rollback uses scopeVersion and reloads the new version', () async {
    final gateway = _Gateway()
      ..configuration = _configuration(schoolVersion: 5)
      ..rollbackVersion = 6;
    final controller = StudentFunnelEditorController(
      gateway: gateway,
      initialClientType: 'student',
    );
    await controller.load();

    final outcome = await controller.rollback(2);

    expect(outcome, isA<StudentFunnelMutationSuccess>());
    expect((outcome as StudentFunnelMutationSuccess).result['version'], 6);
    expect(gateway.lastRollbackVersion, 5);
    expect(gateway.lastRollbackTarget, 2);
    expect(controller.snapshot.configuration?.scopeVersion, 6);
  });

  for (final operation in ['publish', 'rollback']) {
    test(
      '$operation success with failed canonical reload stays terminal and fail-closed',
      () async {
        final revisions = Completer<List<Map<String, dynamic>>>()
          ..complete([
            {'version': 1, 'reason': 'Исходная версия'},
          ]);
        final gateway = _Gateway()..revisionLoads['school'] = revisions;
        final controller = StudentFunnelEditorController(
          gateway: gateway,
          initialClientType: 'student',
        );
        await controller.load();
        final StudentFunnelPublishPreview? preview;
        if (operation == 'publish') {
          controller.setReason('Терминальная публикация');
          preview =
              await controller.previewPublish() as StudentFunnelPublishPreview;
        } else {
          preview = null;
        }
        gateway.configurationError = StateError('canonical reload failed');

        final outcome = operation == 'publish'
            ? await controller.confirmPublish(preview!)
            : await controller.rollback(1);

        expect(outcome, isA<StudentFunnelMutationSuccess>());
        expect(controller.snapshot.changed, isTrue);
        expect(controller.snapshot.configuration, isNull);
        expect(controller.snapshot.stages, isEmpty);
        expect(controller.snapshot.revisions, isEmpty);
        expect(controller.snapshot.loading, isFalse);
        expect(controller.snapshot.saving, isFalse);
        expect(controller.snapshot.error, 'Не удалось загрузить воронку.');
        expect(
          await controller.previewPublish(),
          isA<StudentFunnelPreviewRejected>(),
        );

        if (operation == 'publish') {
          expect(
            await controller.confirmPublish(preview!),
            isA<StudentFunnelMutationIgnored>(),
          );
          expect(gateway.publishCalls, 1);
        } else {
          expect(
            await controller.rollback(1),
            isA<StudentFunnelMutationIgnored>(),
          );
          expect(
            gateway.events.where((event) => event.startsWith('rollback:')),
            hasLength(1),
          );
        }
      },
    );
  }

  test('stale load cannot replace a newer scope', () async {
    final gateway = _Gateway();
    final school = Completer<StudentFunnelConfiguration>();
    final schoolRevisions = Completer<List<Map<String, dynamic>>>();
    final branch = Completer<StudentFunnelConfiguration>();
    final branchRevisions = Completer<List<Map<String, dynamic>>>();
    gateway.configurationLoads['school'] = school;
    gateway.revisionLoads['school'] = schoolRevisions;
    gateway.configurationLoads['branch-a'] = branch;
    gateway.revisionLoads['branch-a'] = branchRevisions;
    final controller = StudentFunnelEditorController(
      gateway: gateway,
      initialClientType: 'student',
    );

    final stale = controller.load();
    final fresh = controller.changeScope('branch-a', discardConfirmed: true);
    branch.complete(
      _configuration(branchId: 'branch-a', branchVersion: 3, label: 'Филиал'),
    );
    branchRevisions.complete(const []);
    await fresh;
    school.complete(_configuration(schoolVersion: 9, label: 'Школа'));
    schoolRevisions.complete(const []);
    await stale;

    expect(controller.snapshot.branchId, 'branch-a');
    expect(controller.snapshot.stages.single.label, 'Филиал');
    expect(controller.snapshot.configuration?.scopeVersion, 3);
  });

  test('dirty scope and type changes require explicit discard', () async {
    final gateway = _Gateway();
    final controller = StudentFunnelEditorController(
      gateway: gateway,
      initialClientType: 'student',
    );
    await controller.load();
    controller.updateStage(
      0,
      controller.snapshot.stages.single.copyWith(label: 'Черновик'),
    );

    expect(
      await controller.changeScope('branch-a', discardConfirmed: false),
      isFalse,
    );
    expect(
      await controller.changeClientType('lead', discardConfirmed: false),
      isFalse,
    );
    expect(controller.snapshot.branchId, isNull);
    expect(controller.snapshot.clientType, 'student');
    expect(gateway.events.where((event) => event == 'load:branch-a'), isEmpty);
  });

  for (final changeType in [false, true]) {
    test(
      'failed confirmed ${changeType ? 'type' : 'scope'} load clears stale publish identity',
      () async {
        final gateway = _Gateway();
        final controller = StudentFunnelEditorController(
          gateway: gateway,
          initialClientType: 'student',
        );
        await controller.load();
        controller
          ..setReason('Черновик старой области')
          ..updateStage(
            0,
            controller.snapshot.stages.single.copyWith(label: 'Старый этап'),
          );
        final configuration = Completer<StudentFunnelConfiguration>();
        final revisions = Completer<List<Map<String, dynamic>>>();
        final scope = changeType ? 'school' : 'branch-a';
        gateway.configurationLoads[scope] = configuration;
        gateway.revisionLoads[scope] = revisions;

        final change = changeType
            ? controller.changeClientType('lead', discardConfirmed: true)
            : controller.changeScope('branch-a', discardConfirmed: true);
        configuration.completeError(StateError('target load failed'));
        revisions.complete(const []);
        await change;

        expect(controller.snapshot.configuration, isNull);
        expect(controller.snapshot.stages, isEmpty);
        expect(controller.snapshot.reason, isEmpty);
        expect(controller.snapshot.draftDirty, isFalse);
        expect(
          await controller.previewPublish(),
          isA<StudentFunnelPreviewRejected>(),
        );
        expect(
          gateway.events.where((event) => event.startsWith('preview:')),
          isEmpty,
        );
      },
    );
  }

  test(
    'publish preview recursively freezes response and transitions',
    () async {
      final impactIds = <String>['student-1'];
      final gateway = _Gateway()
        ..previewResult = {
          'valid': true,
          'blockingIssues': <Map<String, dynamic>>[],
          'impact': {'studentIds': impactIds},
        };
      final controller = StudentFunnelEditorController(
        gateway: gateway,
        initialClientType: 'student',
      );
      await controller.load();
      final transitions = <String>['paused'];
      controller
        ..setReason('Проверка frozen payload')
        ..updateStage(
          0,
          controller.snapshot.stages.single.copyWith(
            allowedTransitions: transitions,
          ),
        );

      final outcome = await controller.previewPublish();
      final preview = outcome as StudentFunnelPublishPreview;
      transitions.add('lost');

      expect(preview.stages.single.allowedTransitions, ['paused']);
      expect(
        () => preview.stages.single.allowedTransitions.add('archived'),
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((preview.preview['impact'] as Map)['studentIds'] as List).clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'loaded and mutated stage snapshots are recursively immutable',
    () async {
      final sourceTransitions = <String>['paused'];
      final gateway = _Gateway()
        ..configuration = StudentFunnelConfiguration(
          clientType: 'student',
          branchId: null,
          source: 'school',
          schoolVersion: 4,
          branchVersion: 0,
          stages: [
            StudentFunnelStage(
              key: 'active',
              label: 'Обучается',
              style: 'green',
              active: true,
              allowedTransitions: sourceTransitions,
            ),
          ],
          remediationStatuses: const [],
        );
      final controller = StudentFunnelEditorController(
        gateway: gateway,
        initialClientType: 'student',
      );
      await controller.load();
      sourceTransitions.add('lost');

      final loaded = controller.snapshot;
      expect(loaded.stages.single.allowedTransitions, ['paused']);
      expect(loaded.configuration!.stages.single.allowedTransitions, [
        'paused',
      ]);
      expect(
        () => loaded.stages.single.allowedTransitions.add('archived'),
        throwsUnsupportedError,
      );
      expect(
        () => loaded.configuration!.stages.single.allowedTransitions.clear(),
        throwsUnsupportedError,
      );

      final draftTransitions = <String>['lost'];
      controller.updateStage(
        0,
        loaded.stages.single.copyWith(allowedTransitions: draftTransitions),
      );
      draftTransitions.add('archived');
      final firstDraft = controller.snapshot;
      final secondDraft = controller.snapshot;

      expect(firstDraft.stages.single.allowedTransitions, ['lost']);
      expect(
        identical(firstDraft.stages.single, secondDraft.stages.single),
        isFalse,
      );
      expect(
        () => firstDraft.stages.single.allowedTransitions.add('paused'),
        throwsUnsupportedError,
      );
    },
  );

  test('loaded revisions reject nested source aliases and mutation', () async {
    final affectedClients = <String>['client-1'];
    final revisionMetadata = <String, dynamic>{
      'impact': <String, dynamic>{'clientIds': affectedClients},
    };
    final revisions = <Map<String, dynamic>>[
      {'version': 1, 'metadata': revisionMetadata},
    ];
    final revisionLoad = Completer<List<Map<String, dynamic>>>()
      ..complete(revisions);
    final gateway = _Gateway()..revisionLoads['school'] = revisionLoad;
    final controller = StudentFunnelEditorController(
      gateway: gateway,
      initialClientType: 'student',
    );

    await controller.load();
    affectedClients.add('client-2');
    revisionMetadata['late'] = true;

    final snapshot = controller.snapshot;
    final metadata = snapshot.revisions.single['metadata'] as Map;
    final impact = metadata['impact'] as Map;
    expect(impact['clientIds'], ['client-1']);
    expect(metadata.containsKey('late'), isFalse);
    expect(
      () => (impact['clientIds'] as List).add('client-3'),
      throwsUnsupportedError,
    );
    expect(() => metadata['late'] = true, throwsUnsupportedError);
    expect(
      () => snapshot.revisions.add({'version': 2}),
      throwsUnsupportedError,
    );
  });

  test(
    'loaded remediation rejects nested source aliases and mutation',
    () async {
      final blockedStages = <String>['paused'];
      final remediation = <String, dynamic>{
        'details': <String, dynamic>{'blockedStages': blockedStages},
      };
      final gateway = _Gateway()
        ..configuration = StudentFunnelConfiguration(
          clientType: 'student',
          branchId: null,
          source: 'school',
          schoolVersion: 4,
          branchVersion: 0,
          stages: _configuration().stages,
          remediationStatuses: [remediation],
        );
      final controller = StudentFunnelEditorController(
        gateway: gateway,
        initialClientType: 'student',
      );

      await controller.load();
      blockedStages.add('lost');
      (remediation['details'] as Map<String, dynamic>)['late'] = true;

      final snapshot = controller.snapshot;
      final details =
          snapshot.configuration!.remediationStatuses.single['details'] as Map;
      expect(details['blockedStages'], ['paused']);
      expect(details.containsKey('late'), isFalse);
      expect(
        () => (details['blockedStages'] as List).clear(),
        throwsUnsupportedError,
      );
      expect(() => details['late'] = true, throwsUnsupportedError);
      expect(
        () => snapshot.configuration!.remediationStatuses.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('direct snapshot recursively freezes every collection', () {
    final transitions = <String>['paused'];
    final revisionIds = <String>['client-1'];
    final remediationIds = <String>['client-2'];
    final stages = <StudentFunnelStage>[
      StudentFunnelStage(
        key: 'active',
        label: 'Обучается',
        style: 'green',
        active: true,
        allowedTransitions: transitions,
      ),
    ];
    final revisions = <Map<String, dynamic>>[
      {
        'version': 1,
        'impact': <String, dynamic>{'clientIds': revisionIds},
      },
    ];
    final configuration = StudentFunnelConfiguration(
      clientType: 'student',
      branchId: null,
      source: 'school',
      schoolVersion: 1,
      branchVersion: 0,
      stages: stages,
      remediationStatuses: [
        {
          'impact': <String, dynamic>{'clientIds': remediationIds},
        },
      ],
    );

    final snapshot = StudentFunnelEditorSnapshot(
      clientType: 'student',
      branchId: null,
      configuration: configuration,
      stages: stages,
      revisions: revisions,
      reason: '',
      error: null,
      loading: false,
      saving: false,
      changed: false,
      draftDirty: false,
    );
    transitions.add('lost');
    revisionIds.add('client-3');
    remediationIds.add('client-4');
    revisions.single['late'] = true;

    final revisionImpact = snapshot.revisions.single['impact'] as Map;
    final remediationImpact =
        snapshot.configuration!.remediationStatuses.single['impact'] as Map;
    expect(snapshot.stages.single.allowedTransitions, ['paused']);
    expect(revisionImpact['clientIds'], ['client-1']);
    expect(remediationImpact['clientIds'], ['client-2']);
    expect(snapshot.revisions.single.containsKey('late'), isFalse);
    expect(
      () => (revisionImpact['clientIds'] as List).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => (remediationImpact['clientIds'] as List).add('client-5'),
      throwsUnsupportedError,
    );
  });

  test(
    'disposed controller rejects public mutations without gateway IO',
    () async {
      final gateway = _Gateway();
      final controller = StudentFunnelEditorController(
        gateway: gateway,
        initialClientType: 'student',
      );
      final preview = await _loadedPreview(controller);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.dispose();
      final frozen = _snapshotData(controller.snapshot);
      final eventCount = gateway.events.length;

      await controller.load();
      controller
        ..setReason('После dispose')
        ..updateStage(0, controller.snapshot.stages.single)
        ..moveStage(0, 1)
        ..addStage();
      expect(
        await controller.previewPublish(),
        isA<StudentFunnelPreviewFailure>(),
      );
      expect(
        await controller.confirmPublish(preview),
        isA<StudentFunnelMutationIgnored>(),
      );
      expect(await controller.rollback(1), isA<StudentFunnelMutationIgnored>());
      expect(
        await controller.changeScope('branch-a', discardConfirmed: true),
        isFalse,
      );
      expect(
        await controller.changeClientType('lead', discardConfirmed: true),
        isFalse,
      );
      controller.cancelPublishPreview(preview);

      expect(gateway.events, hasLength(eventCount));
      expect(_snapshotData(controller.snapshot), frozen);
      expect(notifications, 0);
    },
  );

  for (final fails in [false, true]) {
    test(
      'late load ${fails ? 'failure' : 'success'} is inert after dispose',
      () async {
        final gateway = _Gateway();
        final configuration = Completer<StudentFunnelConfiguration>();
        final revisions = Completer<List<Map<String, dynamic>>>();
        gateway.configurationLoads['school'] = configuration;
        gateway.revisionLoads['school'] = revisions;
        final controller = StudentFunnelEditorController(
          gateway: gateway,
          initialClientType: 'student',
        );
        var notifications = 0;
        controller.addListener(() => notifications++);
        final operation = controller.load();
        final notificationCount = notifications;
        controller.dispose();
        final frozen = _snapshotData(controller.snapshot);

        if (fails) {
          configuration.completeError(StateError('late load failure'));
        } else {
          configuration.complete(_configuration(schoolVersion: 8));
        }
        revisions.complete(const []);
        await operation;

        expect(_snapshotData(controller.snapshot), frozen);
        expect(notifications, notificationCount);
      },
    );

    test(
      'late preview ${fails ? 'failure' : 'success'} is inert after dispose',
      () async {
        final gateway = _Gateway();
        final controller = StudentFunnelEditorController(
          gateway: gateway,
          initialClientType: 'student',
        );
        await controller.load();
        controller.setReason('Асинхронный preview');
        final completion = Completer<Map<String, dynamic>>();
        gateway.previewCompletion = completion;
        var notifications = 0;
        controller.addListener(() => notifications++);
        final operation = controller.previewPublish();
        final notificationCount = notifications;
        controller.dispose();
        final frozen = _snapshotData(controller.snapshot);

        fails
            ? completion.completeError(StateError('late preview failure'))
            : completion.complete(gateway.previewResult);
        await operation;

        expect(_snapshotData(controller.snapshot), frozen);
        expect(notifications, notificationCount);
      },
    );

    test(
      'late publish ${fails ? 'failure' : 'success'} is inert after dispose',
      () async {
        final gateway = _Gateway();
        final controller = StudentFunnelEditorController(
          gateway: gateway,
          initialClientType: 'student',
        );
        final preview = await _loadedPreview(controller);
        final completion = Completer<Map<String, dynamic>>();
        gateway.publishCompletion = completion;
        var notifications = 0;
        controller.addListener(() => notifications++);
        final operation = controller.confirmPublish(preview);
        final notificationCount = notifications;
        controller.dispose();
        final frozen = _snapshotData(controller.snapshot);

        fails
            ? completion.completeError(StateError('late publish failure'))
            : completion.complete({'version': 2});
        await operation;

        expect(_snapshotData(controller.snapshot), frozen);
        expect(notifications, notificationCount);
      },
    );

    test(
      'late rollback ${fails ? 'failure' : 'success'} is inert after dispose',
      () async {
        final gateway = _Gateway();
        final controller = StudentFunnelEditorController(
          gateway: gateway,
          initialClientType: 'student',
        );
        await controller.load();
        final completion = Completer<Map<String, dynamic>>();
        gateway.rollbackCompletion = completion;
        var notifications = 0;
        controller.addListener(() => notifications++);
        final operation = controller.rollback(1);
        final notificationCount = notifications;
        controller.dispose();
        final frozen = _snapshotData(controller.snapshot);

        fails
            ? completion.completeError(StateError('late rollback failure'))
            : completion.complete({'version': 2});
        await operation;

        expect(_snapshotData(controller.snapshot), frozen);
        expect(notifications, notificationCount);
      },
    );
  }

  test('view and state contract have no controller or service dependency', () {
    final view = File(
      'lib/features/manager/presentation/widgets/student_funnel_editor_view.dart',
    ).readAsStringSync();
    final contract = File(
      'lib/features/manager/presentation/widgets/'
      'student_funnel_editor_contract.dart',
    ).readAsStringSync();

    for (final source in [view, contract]) {
      expect(source, isNot(contains('student_funnel_editor_controller.dart')));
      expect(source, isNot(contains('magic_crm_service.dart')));
      expect(source, isNot(contains('flutter_riverpod')));
      expect(source, isNot(contains('magicCrmServiceProvider')));
    }
  });
}
