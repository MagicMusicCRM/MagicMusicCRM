import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/reference_catalog_lifecycle_controller.dart';

void main() {
  test(
    'load prefers preview and normalizes lifecycle fields and versions',
    () async {
      final api = _LifecycleApi(
        entity: {
          'id': 'disc-1',
          'name': 'Серверное имя',
          'lifecycleState': 'archived',
          'version': '8',
        },
        canRestore: true,
        blockers: const [
          {
            'label': 'Активные записи',
            'count': 2,
            'remediation': 'Закройте их',
          },
        ],
        history: List.generate(12, (index) => {'operation': 'rename'}),
      );
      final controller = _controller(
        api,
        initialItem: const {
          'id': 'disc-1',
          'name': 'Локальное имя',
          'lifecycle_state': 'active',
          'version': 1,
        },
      );

      await controller.load();

      expect(controller.state.entity['name'], 'Серверное имя');
      expect(controller.state.archived, isTrue);
      expect(controller.state.version, 8);
      expect(controller.state.canCommit, isTrue);
      expect(controller.state.blockers, hasLength(1));
      expect(controller.state.history, hasLength(12));

      final snakeApi = _LifecycleApi(
        entity: const {
          'id': 'disc-1',
          'name': 'Архив',
          'lifecycle_state': 'archived',
          'version': 4.9,
        },
        canRestore: true,
      );
      final snakeController = _controller(snakeApi);
      await snakeController.load();
      expect(snakeController.state.archived, isTrue);
      expect(snakeController.state.version, 4);
    },
  );

  test(
    'branch discipline cannot rename and archives through unassign',
    () async {
      final api = _LifecycleApi(
        entity: const {
          'id': 'link-1',
          'name': 'Вокал',
          'lifecycleState': 'active',
          'version': 3,
        },
        canArchive: true,
        canRename: true,
      );
      final controller = _controller(
        api,
        entityType: 'branch_discipline',
        initialItem: const {'id': 'link-1', 'name': 'Вокал', 'version': 3},
      );
      await controller.load();

      expect(controller.state.canRename, isFalse);
      expect(
        await controller.rename(name: 'Новый вокал', reasonText: 'Уточнение'),
        isFalse,
      );
      expect(api.mutations, isEmpty);

      expect(
        await controller.commitLifecycle(reasonText: 'Больше не ведём'),
        isTrue,
      );
      expect(api.mutations.single, 'unassign');
      expect(api.lastBody, {
        'expectedVersion': 3,
        'confirm': true,
        'reasonText': 'Больше не ведём',
      });
    },
  );

  test(
    'rename reloads canonical entity, version and append-only history',
    () async {
      final api = _LifecycleApi(
        entity: const {
          'id': 'disc-1',
          'name': 'Вокал',
          'lifecycleState': 'active',
          'version': 1,
        },
        canArchive: true,
        canRename: true,
        appendRenameHistory: true,
      );
      final controller = _controller(api);
      await controller.load();

      final renamed = await controller.rename(
        name: '  Эстрадный вокал  ',
        reasonText: '  Уточнение названия  ',
      );

      expect(renamed, isTrue);
      expect(controller.state.entity['name'], 'Эстрадный вокал');
      expect(controller.state.version, 2);
      expect(controller.state.history.single['operation'], 'rename');
      expect(api.lastBody, {
        'name': 'Эстрадный вокал',
        'expectedVersion': 1,
        'confirm': true,
        'reasonText': 'Уточнение названия',
      });
    },
  );

  test(
    'validates reason and server blockers before issuing mutations',
    () async {
      final api = _LifecycleApi(
        entity: const {
          'id': 'disc-1',
          'name': 'Вокал',
          'lifecycleState': 'active',
          'version': 1,
        },
        canArchive: false,
        canRename: true,
        blockers: const [
          {'label': 'Связи', 'count': 1},
        ],
      );
      final controller = _controller(api);
      await controller.load();

      expect(
        await controller.rename(name: 'Эстрада', reasonText: ' x '),
        isFalse,
      );
      expect(
        controller.state.error,
        'Укажите понятную причину (минимум 3 символа).',
      );
      expect(
        await controller.rename(name: '  ', reasonText: 'Уточнение'),
        isFalse,
      );
      expect(controller.state.error, 'Укажите новое название.');
      expect(
        await controller.commitLifecycle(reasonText: 'Закрываем'),
        isFalse,
      );
      expect(api.mutations, isEmpty);
    },
  );

  test('restore uses current normalized version', () async {
    final api = _LifecycleApi(
      entity: const {
        'id': 'disc-1',
        'name': 'Вокал',
        'lifecycle_state': 'archived',
        'version': '6',
      },
      canRestore: true,
    );
    final controller = _controller(api);
    await controller.load();

    expect(
      await controller.commitLifecycle(reasonText: 'Возвращаем в работу'),
      isTrue,
    );
    expect(api.mutations.single, 'restore');
    expect(api.lastBody?['expectedVersion'], 6);
  });

  test(
    'mutation errors reconcile preview while preserving the API error',
    () async {
      final api = _LifecycleApi(
        entity: const {
          'id': 'disc-1',
          'name': 'Вокал',
          'lifecycleState': 'active',
          'version': 1,
        },
        canArchive: true,
        canRename: true,
        patchError: const MagicApiException(
          statusCode: 409,
          message: 'VERSION_CONFLICT',
        ),
        entityAfterPatchFailure: const {
          'id': 'disc-1',
          'name': 'Каноническое имя',
          'lifecycleState': 'active',
          'version': '5',
        },
      );
      final controller = _controller(api);
      await controller.load();

      expect(
        await controller.rename(
          name: 'Эстрадный вокал',
          reasonText: 'Уточнение',
        ),
        isFalse,
      );
      expect(controller.state.entity['name'], 'Каноническое имя');
      expect(controller.state.version, 5);
      expect(
        controller.state.error,
        'Данные изменились или уже заняты. Обновите их и повторите.',
      );
    },
  );

  test(
    'failed reconciliation refresh keeps the original mutation error',
    () async {
      final refresh = Completer<Map<String, dynamic>>();
      final api = _LifecycleApi(
        entity: const {
          'id': 'disc-1',
          'name': 'Вокал',
          'lifecycleState': 'active',
          'version': 1,
        },
        canArchive: true,
        canRename: true,
        patchError: const MagicApiException(
          statusCode: 409,
          message: 'VERSION_CONFLICT',
        ),
        previewQueue: [
          Future.value(_preview(name: 'Вокал')),
          refresh.future,
        ],
      );
      final controller = _controller(api);
      await controller.load();

      final rename = controller.rename(
        name: 'Эстрадный вокал',
        reasonText: 'Уточнение',
      );
      await Future<void>.delayed(Duration.zero);
      refresh.completeError(StateError('refresh failed'));

      expect(await rename, isFalse);
      expect(controller.state.loading, isFalse);
      expect(
        controller.state.error,
        'Данные изменились или уже заняты. Обновите их и повторите.',
      );
    },
  );

  test(
    'concurrent load cannot invalidate or finish a successful mutation',
    () async {
      final mutation = Completer<Map<String, dynamic>>();
      final api = _LifecycleApi(
        entity: const {
          'id': 'disc-1',
          'name': 'Вокал',
          'lifecycleState': 'active',
          'version': 1,
        },
        canArchive: true,
        mutationCompletion: mutation,
      );
      final controller = _controller(api);
      await controller.load();

      final commit = controller.commitLifecycle(reasonText: 'Закрываем');
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.saving, isTrue);

      await controller.load();
      expect(controller.state.saving, isTrue);
      mutation.complete({'preview': _preview(name: 'Вокал')});

      expect(await commit, isTrue);
      expect(controller.state.saving, isFalse);
    },
  );

  test('state deeply rejects entity preview and history mutations', () {
    final aliases = <String>['Вокал'];
    final studentIds = <String>['student-1'];
    final versions = <int>[1];
    final state = ReferenceCatalogLifecycleState(
      entityType: 'discipline',
      entity: {
        'id': 'disc-1',
        'metadata': {'aliases': aliases},
      },
      preview: {
        'impact': {'studentIds': studentIds},
      },
      history: [
        {
          'details': {'versions': versions},
        },
      ],
      loading: false,
      saving: false,
    );

    expect(
      () => ((state.entity['metadata'] as Map)['aliases'] as List).add('Хор'),
      throwsUnsupportedError,
    );
    expect(
      () => ((state.preview!['impact'] as Map)['studentIds'] as List).clear(),
      throwsUnsupportedError,
    );
    expect(
      () =>
          ((state.history.single['details'] as Map)['versions'] as List).add(2),
      throwsUnsupportedError,
    );
  });

  test('ignores stale loads and every completion after dispose', () async {
    final firstPreview = Completer<Map<String, dynamic>>();
    final firstHistory = Completer<Map<String, dynamic>>();
    final secondPreview = Completer<Map<String, dynamic>>();
    final secondHistory = Completer<Map<String, dynamic>>();
    final api = _LifecycleApi(
      entity: const {'id': 'disc-1', 'name': 'Начальное', 'version': 1},
      previewQueue: [firstPreview.future, secondPreview.future],
      historyQueue: [firstHistory.future, secondHistory.future],
    );
    final controller = _controller(api);
    final stale = controller.load();
    final current = controller.load();
    secondPreview.complete(_preview(name: 'Второй'));
    secondHistory.complete(const {'items': []});
    await current;
    expect(controller.state.entity['name'], 'Второй');
    firstPreview.complete(_preview(name: 'Первый'));
    firstHistory.complete(const {'items': []});
    await stale;
    expect(controller.state.entity['name'], 'Второй');

    final disposedPreview = Completer<Map<String, dynamic>>();
    final disposedHistory = Completer<Map<String, dynamic>>();
    final disposedApi = _LifecycleApi(
      entity: const {'id': 'disc-1', 'name': 'До dispose', 'version': 1},
      previewQueue: [disposedPreview.future],
      historyQueue: [disposedHistory.future],
    );
    final disposed = _controller(disposedApi);
    var notifications = 0;
    disposed.addListener(() => notifications += 1);
    final pending = disposed.load();
    final frozen = disposed.state;
    disposed.dispose();
    disposedPreview.complete(_preview(name: 'После dispose'));
    disposedHistory.complete(const {'items': []});
    await pending;
    expect(identical(disposed.state, frozen), isTrue);
    expect(notifications, 1);

    final callsAfterCompletion = disposedApi.previewCalls;
    await disposed.load();
    expect(disposedApi.previewCalls, callsAfterCompletion);

    final completedApi = _LifecycleApi(
      entity: const {
        'id': 'disc-1',
        'name': 'Вокал',
        'lifecycleState': 'active',
        'version': 1,
      },
      canArchive: true,
      canRename: true,
    );
    final completed = _controller(completedApi);
    await completed.load();
    completed.dispose();
    await completed.rename(name: 'Эстрада', reasonText: 'Уточнение');
    await completed.commitLifecycle(reasonText: 'Закрываем');
    expect(completedApi.mutations, isEmpty);
  });
}

ReferenceCatalogLifecycleController _controller(
  _LifecycleApi api, {
  String entityType = 'discipline',
  Map<String, dynamic> initialItem = const {
    'id': 'disc-1',
    'name': 'Вокал',
    'lifecycle_state': 'active',
    'version': 1,
  },
}) => ReferenceCatalogLifecycleController(
  service: MagicCrmService(api),
  entityType: entityType,
  initialItem: initialItem,
);

Map<String, dynamic> _preview({required String name}) => {
  'entity': {
    'id': 'disc-1',
    'name': name,
    'lifecycleState': 'active',
    'version': 1,
  },
  'canArchive': true,
  'canRestore': false,
  'canRename': true,
  'blockers': const [],
  'impact': const {},
};

class _LifecycleApi extends MagicApiClient {
  _LifecycleApi({
    required Map<String, dynamic> entity,
    this.canArchive = false,
    this.canRestore = false,
    this.canRename = false,
    this.blockers = const [],
    List<Map<String, dynamic>> history = const [],
    this.appendRenameHistory = false,
    this.patchError,
    this.entityAfterPatchFailure,
    this.mutationCompletion,
    List<Future<Map<String, dynamic>>> previewQueue = const [],
    List<Future<Map<String, dynamic>>> historyQueue = const [],
  }) : entity = Map<String, dynamic>.from(entity),
       history = List<Map<String, dynamic>>.from(history),
       previewQueue = List.of(previewQueue),
       historyQueue = List.of(historyQueue),
       super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  Map<String, dynamic> entity;
  final bool canArchive;
  final bool canRestore;
  final bool canRename;
  final List<Map<String, dynamic>> blockers;
  final List<Map<String, dynamic>> history;
  final bool appendRenameHistory;
  final Object? patchError;
  final Map<String, dynamic>? entityAfterPatchFailure;
  final Completer<Map<String, dynamic>>? mutationCompletion;
  final List<Future<Map<String, dynamic>>> previewQueue;
  final List<Future<Map<String, dynamic>>> historyQueue;
  final List<String> mutations = [];
  Map<String, dynamic>? lastBody;
  int previewCalls = 0;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (!path.endsWith('/history')) throw StateError('Unexpected GET $path');
    final response = historyQueue.isEmpty
        ? <String, dynamic>{'items': List.of(history)}
        : await historyQueue.removeAt(0);
    return response as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path.endsWith('/lifecycle-preview')) {
      previewCalls += 1;
      final response = previewQueue.isEmpty
          ? _previewPayload()
          : await previewQueue.removeAt(0);
      return response as T;
    }
    final operation = path.split('/').last;
    if (!const {'archive', 'unassign', 'restore'}.contains(operation)) {
      throw StateError('Unexpected POST $path');
    }
    mutations.add(operation);
    lastBody = Map<String, dynamic>.from(data! as Map);
    if (mutationCompletion != null) {
      return await mutationCompletion!.future as T;
    }
    return <String, dynamic>{'preview': _previewPayload()} as T;
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    mutations.add('rename');
    lastBody = Map<String, dynamic>.from(data! as Map);
    if (patchError != null) {
      if (entityAfterPatchFailure != null) {
        entity = Map<String, dynamic>.from(entityAfterPatchFailure!);
      }
      throw patchError!;
    }
    entity = {
      ...entity,
      'name': lastBody!['name'],
      'version': _version(entity['version']) + 1,
    };
    if (appendRenameHistory) {
      history.add({
        'operation': 'rename',
        'reasonText': lastBody!['reasonText'],
      });
    }
    return <String, dynamic>{'preview': _previewPayload()} as T;
  }

  Map<String, dynamic> _previewPayload() => {
    'entity': Map<String, dynamic>.from(entity),
    'canArchive': canArchive,
    'canRestore': canRestore,
    'canRename': canRename,
    'blockers': List<Map<String, dynamic>>.from(blockers),
    'impact': const <String, dynamic>{},
  };

  int _version(Object? raw) =>
      raw is num ? raw.toInt() : int.tryParse('$raw') ?? 1;
}
