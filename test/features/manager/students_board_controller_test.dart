import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_auto_scroll_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_controller.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_models.dart';

void main() {
  group('StudentsBoardController', () {
    test('loads branches and selects the first branch', () async {
      final controller = StudentsBoardController(
        loadBranches: () async => [
          {'id': 'branch-a', 'name': 'Сокол'},
          {'id': 'branch-b', 'name': 'Центр'},
        ],
        loadStudentsPage: _unusedPageLoader,
        updateStudentStatus: _unusedStatusUpdater,
      );
      addTearDown(controller.dispose);

      await controller.loadBranches();

      expect(controller.state.branchesLoaded, isTrue);
      expect(controller.state.selectedBranchId, 'branch-a');
      expect(controller.state.branches, hasLength(2));
    });

    test(
      'loadBranches after dispose performs no I/O and freezes state',
      () async {
        var gatewayCalls = 0;
        final controller = StudentsBoardController(
          loadBranches: () async {
            gatewayCalls++;
            return const [];
          },
          loadStudentsPage: _unusedPageLoader,
          updateStudentStatus: _unusedStatusUpdater,
        );
        final frozenState = controller.state;
        controller.dispose();

        await controller.loadBranches();

        expect(gatewayCalls, 0);
        expect(identical(controller.state, frozenState), isTrue);
      },
    );

    test('keeps a transfer branch while the branch list is loading', () async {
      final branches = Completer<List<Map<String, dynamic>>>();
      final controller = StudentsBoardController(
        loadBranches: () => branches.future,
        loadStudentsPage: _unusedPageLoader,
        updateStudentStatus: _unusedStatusUpdater,
      );
      addTearDown(controller.dispose);

      final loading = controller.loadBranches();
      controller.selectBranch('branch-transfer');
      branches.complete([
        {'id': 'branch-a', 'name': 'Сокол'},
      ]);
      await loading;

      expect(controller.state.branchesLoaded, isTrue);
      expect(controller.state.selectedBranchId, 'branch-transfer');
    });

    test('deduplicates pages and rejects a stale branch completion', () async {
      final pages = <String, Completer<StudentsBoardPageResult>>{};
      final controller = StudentsBoardController(
        loadBranches: () async => const [],
        loadStudentsPage: ({required branchId, required cursor}) {
          return (pages[cursor] = Completer<StudentsBoardPageResult>()).future;
        },
        updateStudentStatus: _unusedStatusUpdater,
      );
      addTearDown(controller.dispose);
      controller.selectBranch('branch-a');

      final first = controller.loadMoreStudents(
        branchId: 'branch-a',
        cursor: 'cursor-1',
        initialStudents: const [
          {'id': 'student-1'},
        ],
      );
      pages['cursor-1']!.complete(
        StudentsBoardPageResult(
          items: [
            {'id': 'student-1'},
            {'id': 'student-2'},
          ],
          nextCursor: 'cursor-2',
        ),
      );
      await first;
      expect(controller.state.extraStudents.map((item) => item['id']), [
        'student-2',
      ]);

      final stale = controller.loadMoreStudents(
        branchId: 'branch-a',
        cursor: 'cursor-2',
        initialStudents: const [],
      );
      controller.selectBranch('branch-b');
      pages['cursor-2']!.complete(
        StudentsBoardPageResult(
          items: [
            {'id': 'student-3'},
          ],
          nextCursor: null,
        ),
      );
      await stale;

      expect(controller.state.selectedBranchId, 'branch-b');
      expect(controller.state.extraStudents, isEmpty);
      expect(controller.state.loadingMoreStudents, isFalse);
    });

    test('stale load-more callback is a no-op before gateway I/O', () async {
      var pageGatewayCalls = 0;
      final controller = StudentsBoardController(
        loadBranches: () async => const [],
        loadStudentsPage: ({required branchId, required cursor}) async {
          pageGatewayCalls++;
          return StudentsBoardPageResult(
            items: const [
              {'id': 'student-stale'},
            ],
            nextCursor: null,
          );
        },
        updateStudentStatus: _unusedStatusUpdater,
      );
      addTearDown(controller.dispose);
      controller.selectBranch('branch-a');
      controller.selectBranch('branch-b');
      final branchBState = controller.state;

      await controller.loadMoreStudents(
        branchId: 'branch-a',
        cursor: 'cursor-old',
        initialStudents: const [],
      );

      expect(pageGatewayCalls, 0);
      expect(identical(controller.state, branchBState), isTrue);
      expect(controller.state.loadingMoreStudents, isFalse);
    });

    test('rolls an optimistic move back when persistence fails', () async {
      final update = Completer<void>();
      final controller = StudentsBoardController(
        loadBranches: () async => const [],
        loadStudentsPage: _unusedPageLoader,
        updateStudentStatus: ({required studentId, required status}) =>
            update.future,
      );
      addTearDown(controller.dispose);
      controller.selectBranch('branch-a');

      final move = controller.moveStatus(
        const {'id': 'student-1', 'status': 'learning'},
        'paused',
        refreshAndReadback: (_) async {},
      );
      expect(controller.state.optimisticStatuses['student-1'], 'paused');
      expect(controller.state.pendingStudentIds, contains('student-1'));

      update.completeError(StateError('offline'));
      final result = await move;

      expect(result.succeeded, isFalse);
      expect(result.error, isA<StateError>());
      expect(controller.state.optimisticStatuses, isEmpty);
      expect(controller.state.pendingStudentIds, isEmpty);
    });

    test(
      'ignores a failed PATCH completion after the branch changes',
      () async {
        final update = Completer<void>();
        final controller = StudentsBoardController(
          loadBranches: () async => const [],
          loadStudentsPage: _unusedPageLoader,
          updateStudentStatus: ({required studentId, required status}) =>
              update.future,
        );
        addTearDown(controller.dispose);
        controller.selectBranch('branch-a');

        final move = controller.moveStatus(
          const {'id': 'student-1', 'status': 'learning'},
          'paused',
          refreshAndReadback: (_) async {},
        );
        expect(controller.state.pendingStudentIds, contains('student-1'));

        controller.selectBranch('branch-b');
        final branchBState = controller.state;
        update.completeError(StateError('offline'));
        final result = await move;

        expect(result.succeeded, isTrue);
        expect(result.error, isNull);
        expect(identical(controller.state, branchBState), isTrue);
        expect(controller.state.selectedBranchId, 'branch-b');
        expect(controller.state.optimisticStatuses, isEmpty);
        expect(controller.state.pendingStudentIds, isEmpty);
      },
    );

    test(
      'keeps a successful PATCH when readback fails and retries safely',
      () async {
        var patchCalls = 0;
        var readbackCalls = 0;
        final controller = StudentsBoardController(
          realtimeDebounce: const Duration(milliseconds: 50),
          loadBranches: () async => const [],
          loadStudentsPage: _unusedPageLoader,
          updateStudentStatus: ({required studentId, required status}) async {
            patchCalls++;
          },
        );
        addTearDown(controller.dispose);
        controller.selectBranch('branch-a');

        final result = await controller.moveStatus(
          const {'id': 'student-1', 'status': 'learning'},
          'paused',
          refreshAndReadback: (_) async {
            readbackCalls++;
            if (readbackCalls == 1) {
              throw StateError('readback offline');
            }
          },
        );

        expect(result.succeeded, isTrue);
        expect(result.error, isNull);
        expect(result.reconciliationPending, isTrue);
        expect(patchCalls, 1);
        expect(readbackCalls, 1);
        expect(controller.state.optimisticStatuses['student-1'], 'paused');
        expect(controller.state.pendingStudentIds, isEmpty);

        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(patchCalls, 1);
        expect(readbackCalls, 2);
        expect(controller.state.optimisticStatuses, isEmpty);
        expect(controller.state.pendingStudentIds, isEmpty);
      },
    );

    test(
      'successful realtime readback owns and completes pending reconciliation',
      () async {
        var readbackCalls = 0;
        final controller = StudentsBoardController(
          realtimeDebounce: const Duration(milliseconds: 20),
          loadBranches: () async => const [],
          loadStudentsPage: _unusedPageLoader,
          updateStudentStatus: ({required studentId, required status}) async {},
        );
        addTearDown(controller.dispose);
        controller.selectBranch('branch-a');

        final result = await controller.moveStatus(
          const {'id': 'student-1', 'status': 'learning'},
          'paused',
          refreshAndReadback: (_) async {
            readbackCalls++;
            throw StateError('initial readback offline');
          },
        );
        expect(result.reconciliationPending, isTrue);
        expect(controller.state.optimisticStatuses['student-1'], 'paused');

        controller.scheduleRealtimeRefresh(() async => readbackCalls++);
        await Future<void>.delayed(const Duration(milliseconds: 45));

        expect(readbackCalls, 2);
        expect(controller.state.optimisticStatuses, isEmpty);
        expect(controller.state.pendingStudentIds, isEmpty);
      },
    );

    test(
      'failed realtime readback restores the safe reconciliation retry',
      () async {
        var patchReadbackCalls = 0;
        var realtimeReadbackCalls = 0;
        final controller = StudentsBoardController(
          realtimeDebounce: const Duration(milliseconds: 20),
          loadBranches: () async => const [],
          loadStudentsPage: _unusedPageLoader,
          updateStudentStatus: ({required studentId, required status}) async {},
        );
        addTearDown(controller.dispose);
        controller.selectBranch('branch-a');

        await controller.moveStatus(
          const {'id': 'student-1', 'status': 'learning'},
          'paused',
          refreshAndReadback: (_) async {
            patchReadbackCalls++;
            if (patchReadbackCalls == 1) {
              throw StateError('readback offline');
            }
          },
        );
        controller.scheduleRealtimeRefresh(() async {
          realtimeReadbackCalls++;
          throw StateError('realtime readback offline');
        });
        await Future<void>.delayed(const Duration(milliseconds: 28));

        expect(patchReadbackCalls, 1);
        expect(realtimeReadbackCalls, 1);
        expect(controller.state.optimisticStatuses['student-1'], 'paused');
        expect(controller.state.pendingStudentIds, isEmpty);

        await Future<void>.delayed(const Duration(milliseconds: 28));

        expect(patchReadbackCalls, 2);
        expect(realtimeReadbackCalls, 1);
        expect(controller.state.optimisticStatuses, isEmpty);
      },
    );

    test(
      'late realtime completion cannot clear a newer branch reconciliation',
      () async {
        final staleRealtime = Completer<void>();
        final controller = StudentsBoardController(
          realtimeDebounce: const Duration(milliseconds: 10),
          loadBranches: () async => const [],
          loadStudentsPage: _unusedPageLoader,
          updateStudentStatus: ({required studentId, required status}) async {},
        );
        addTearDown(controller.dispose);
        controller.selectBranch('branch-a');
        await controller.moveStatus(
          const {'id': 'student-a', 'status': 'learning'},
          'paused',
          refreshAndReadback: (_) async => throw StateError('offline'),
        );
        controller.scheduleRealtimeRefresh(() => staleRealtime.future);
        await Future<void>.delayed(const Duration(milliseconds: 15));

        controller.selectBranch('branch-b');
        await controller.moveStatus(
          const {'id': 'student-b', 'status': 'learning'},
          'paused',
          refreshAndReadback: (_) async => throw StateError('offline'),
        );
        staleRealtime.complete();
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.selectedBranchId, 'branch-b');
        expect(controller.state.optimisticStatuses, {'student-b': 'paused'});
        expect(
          controller.state.optimisticStatuses,
          isNot(contains('student-a')),
        );
      },
    );

    test(
      'dispose cancels a scheduled reconciliation before retry I/O',
      () async {
        var readbackCalls = 0;
        final controller = StudentsBoardController(
          realtimeDebounce: const Duration(milliseconds: 30),
          loadBranches: () async => const [],
          loadStudentsPage: _unusedPageLoader,
          updateStudentStatus: ({required studentId, required status}) async {},
        );
        controller.selectBranch('branch-a');

        await controller.moveStatus(
          const {'id': 'student-1', 'status': 'learning'},
          'paused',
          refreshAndReadback: (_) async {
            readbackCalls++;
            throw StateError('readback offline');
          },
        );
        expect(readbackCalls, 1);

        controller.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 55));

        expect(readbackCalls, 1);
      },
    );

    test(
      'dispose rejects success follow-up I/O and realtime loses to pending',
      () async {
        final update = Completer<void>();
        var refreshes = 0;
        final controller = StudentsBoardController(
          realtimeDebounce: Duration.zero,
          loadBranches: () async => const [],
          loadStudentsPage: _unusedPageLoader,
          updateStudentStatus: ({required studentId, required status}) =>
              update.future,
        );
        controller.selectBranch('branch-a');
        final move = controller.moveStatus(
          const {'id': 'student-1', 'status': 'learning'},
          'paused',
          refreshAndReadback: (_) async => refreshes++,
        );

        controller.scheduleRealtimeRefresh(() async => refreshes++);
        await Future<void>.delayed(Duration.zero);
        expect(refreshes, 0);

        controller.dispose();
        update.complete();
        await move;
        await Future<void>.delayed(Duration.zero);
        expect(refreshes, 0);
      },
    );

    test(
      'latest branch load wins without replacing a transfer branch',
      () async {
        final first = Completer<List<Map<String, dynamic>>>();
        final second = Completer<List<Map<String, dynamic>>>();
        var loadCount = 0;
        final controller = StudentsBoardController(
          loadBranches: () => loadCount++ == 0 ? first.future : second.future,
          loadStudentsPage: _unusedPageLoader,
          updateStudentStatus: _unusedStatusUpdater,
        );
        addTearDown(controller.dispose);

        final staleLoad = controller.loadBranches();
        controller.selectBranch('branch-transfer');
        final latestLoad = controller.loadBranches();
        second.complete([
          {'id': 'branch-latest', 'name': 'Новый список'},
        ]);
        await latestLoad;
        first.complete([
          {'id': 'branch-stale', 'name': 'Старый список'},
        ]);
        await staleLoad;

        expect(controller.state.selectedBranchId, 'branch-transfer');
        expect(controller.state.branches.single['id'], 'branch-latest');
      },
    );

    test('resetPages invalidates an in-flight page completion', () async {
      final page = Completer<StudentsBoardPageResult>();
      final controller = StudentsBoardController(
        loadBranches: () async => const [],
        loadStudentsPage: ({required branchId, required cursor}) => page.future,
        updateStudentStatus: _unusedStatusUpdater,
      );
      addTearDown(controller.dispose);
      controller.selectBranch('branch-a');

      final loading = controller.loadMoreStudents(
        branchId: 'branch-a',
        cursor: 'cursor-1',
        initialStudents: const [],
      );
      controller.resetPages();
      final resetState = controller.state;
      page.complete(
        StudentsBoardPageResult(
          items: const [
            {'id': 'student-stale'},
          ],
          nextCursor: 'cursor-2',
        ),
      );
      await loading;

      expect(identical(controller.state, resetState), isTrue);
      expect(controller.state.extraStudents, isEmpty);
      expect(controller.state.loadingMoreStudents, isFalse);
    });

    test(
      'late direct readback cannot mutate a replacement branch context',
      () async {
        final readbackStarted = Completer<void>();
        final readback = Completer<void>();
        final controller = StudentsBoardController(
          loadBranches: () async => const [],
          loadStudentsPage: _unusedPageLoader,
          updateStudentStatus: ({required studentId, required status}) async {},
        );
        addTearDown(controller.dispose);
        controller.selectBranch('branch-a');

        final move = controller.moveStatus(
          const {'id': 'student-a', 'status': 'learning'},
          'paused',
          refreshAndReadback: (_) {
            readbackStarted.complete();
            return readback.future;
          },
        );
        await readbackStarted.future;
        controller.selectBranch('branch-b');
        final branchBState = controller.state;
        readback.complete();
        final result = await move;

        expect(result.succeeded, isTrue);
        expect(identical(controller.state, branchBState), isTrue);
        expect(controller.state.selectedBranchId, 'branch-b');
        expect(controller.state.optimisticStatuses, isEmpty);
      },
    );

    test('older failed readback cannot cancel a newer student retry', () async {
      final firstReadbacks = <String, Completer<void>>{
        'student-a': Completer<void>(),
        'student-b': Completer<void>(),
      };
      final readbackStarted = <String, Completer<void>>{
        'student-a': Completer<void>(),
        'student-b': Completer<void>(),
      };
      final readbackCalls = <String, int>{};
      final controller = StudentsBoardController(
        realtimeDebounce: const Duration(milliseconds: 20),
        loadBranches: () async => const [],
        loadStudentsPage: _unusedPageLoader,
        updateStudentStatus: ({required studentId, required status}) async {},
      );
      addTearDown(controller.dispose);
      controller.selectBranch('branch-a');

      Future<void> readback(String studentId) {
        final call = (readbackCalls[studentId] ?? 0) + 1;
        readbackCalls[studentId] = call;
        if (call == 1) {
          readbackStarted[studentId]!.complete();
          return firstReadbacks[studentId]!.future;
        }
        return Future.value();
      }

      final moveA = controller.moveStatus(
        const {'id': 'student-a', 'status': 'learning'},
        'paused',
        refreshAndReadback: (_) => readback('student-a'),
      );
      await readbackStarted['student-a']!.future;
      final moveB = controller.moveStatus(
        const {'id': 'student-b', 'status': 'learning'},
        'paused',
        refreshAndReadback: (_) => readback('student-b'),
      );
      await readbackStarted['student-b']!.future;

      firstReadbacks['student-b']!.completeError(StateError('offline-b'));
      expect((await moveB).reconciliationPending, isTrue);
      firstReadbacks['student-a']!.completeError(StateError('offline-a'));
      expect((await moveA).reconciliationPending, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 45));

      expect(readbackCalls['student-a'], 1);
      expect(readbackCalls['student-b'], 2);
      expect(controller.state.optimisticStatuses, isEmpty);
      expect(controller.state.pendingStudentIds, isEmpty);
    });

    test(
      'newer board readback settles an older move before its failure arrives',
      () async {
        final firstReadbacks = <String, Completer<void>>{
          'student-a': Completer<void>(),
          'student-b': Completer<void>(),
        };
        final readbackStarted = <String, Completer<void>>{
          'student-a': Completer<void>(),
          'student-b': Completer<void>(),
        };
        final readbackCalls = <String, int>{};
        final controller = StudentsBoardController(
          realtimeDebounce: const Duration(milliseconds: 20),
          loadBranches: () async => const [],
          loadStudentsPage: _unusedPageLoader,
          updateStudentStatus: ({required studentId, required status}) async {},
        );
        addTearDown(controller.dispose);
        controller.selectBranch('branch-a');

        Future<void> readback(String studentId) {
          readbackCalls[studentId] = (readbackCalls[studentId] ?? 0) + 1;
          readbackStarted[studentId]!.complete();
          return firstReadbacks[studentId]!.future;
        }

        final moveA = controller.moveStatus(
          const {'id': 'student-a', 'status': 'learning'},
          'paused',
          refreshAndReadback: (_) => readback('student-a'),
        );
        await readbackStarted['student-a']!.future;
        final moveB = controller.moveStatus(
          const {'id': 'student-b', 'status': 'learning'},
          'paused',
          refreshAndReadback: (_) => readback('student-b'),
        );
        await readbackStarted['student-b']!.future;

        firstReadbacks['student-b']!.complete();
        expect((await moveB).reconciliationPending, isFalse);
        expect(controller.state.optimisticStatuses, isEmpty);
        firstReadbacks['student-a']!.completeError(
          StateError('late-offline-a'),
        );
        expect((await moveA).reconciliationPending, isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 35));

        expect(readbackCalls, {'student-a': 1, 'student-b': 1});
        expect(controller.state.optimisticStatuses, isEmpty);
        expect(controller.state.pendingStudentIds, isEmpty);
      },
    );

    test(
      'older board snapshot cannot settle a move confirmed after it started',
      () async {
        final firstReadbacks = <String, Completer<void>>{
          'student-a': Completer<void>(),
          'student-b': Completer<void>(),
        };
        final readbackStarted = <String, Completer<void>>{
          'student-a': Completer<void>(),
          'student-b': Completer<void>(),
        };
        final readbackCalls = <String, int>{};
        final controller = StudentsBoardController(
          realtimeDebounce: const Duration(milliseconds: 20),
          loadBranches: () async => const [],
          loadStudentsPage: _unusedPageLoader,
          updateStudentStatus: ({required studentId, required status}) async {},
        );
        addTearDown(controller.dispose);
        controller.selectBranch('branch-a');

        Future<void> readback(String studentId) {
          final call = (readbackCalls[studentId] ?? 0) + 1;
          readbackCalls[studentId] = call;
          if (call == 1) {
            readbackStarted[studentId]!.complete();
            return firstReadbacks[studentId]!.future;
          }
          return Future.value();
        }

        final moveA = controller.moveStatus(
          const {'id': 'student-a', 'status': 'learning'},
          'paused',
          refreshAndReadback: (_) => readback('student-a'),
        );
        await readbackStarted['student-a']!.future;
        final moveB = controller.moveStatus(
          const {'id': 'student-b', 'status': 'learning'},
          'paused',
          refreshAndReadback: (_) => readback('student-b'),
        );
        await readbackStarted['student-b']!.future;

        firstReadbacks['student-a']!.complete();
        expect((await moveA).reconciliationPending, isFalse);
        expect(controller.state.optimisticStatuses, {'student-b': 'paused'});
        expect(controller.state.pendingStudentIds, {'student-b'});
        firstReadbacks['student-b']!.completeError(StateError('offline-b'));
        expect((await moveB).reconciliationPending, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 45));

        expect(readbackCalls, {'student-a': 1, 'student-b': 2});
        expect(controller.state.optimisticStatuses, isEmpty);
        expect(controller.state.pendingStudentIds, isEmpty);
      },
    );

    test('older successful snapshot cannot cancel a newer retry', () async {
      final firstReadbacks = <String, Completer<void>>{
        'student-a': Completer<void>(),
        'student-b': Completer<void>(),
      };
      final readbackStarted = <String, Completer<void>>{
        'student-a': Completer<void>(),
        'student-b': Completer<void>(),
      };
      final readbackCalls = <String, int>{};
      final controller = StudentsBoardController(
        realtimeDebounce: const Duration(milliseconds: 20),
        loadBranches: () async => const [],
        loadStudentsPage: _unusedPageLoader,
        updateStudentStatus: ({required studentId, required status}) async {},
      );
      addTearDown(controller.dispose);
      controller.selectBranch('branch-a');

      Future<void> readback(String studentId) {
        final call = (readbackCalls[studentId] ?? 0) + 1;
        readbackCalls[studentId] = call;
        if (call == 1) {
          readbackStarted[studentId]!.complete();
          return firstReadbacks[studentId]!.future;
        }
        return Future.value();
      }

      final moveA = controller.moveStatus(
        const {'id': 'student-a', 'status': 'learning'},
        'paused',
        refreshAndReadback: (_) => readback('student-a'),
      );
      await readbackStarted['student-a']!.future;
      final moveB = controller.moveStatus(
        const {'id': 'student-b', 'status': 'learning'},
        'paused',
        refreshAndReadback: (_) => readback('student-b'),
      );
      await readbackStarted['student-b']!.future;

      firstReadbacks['student-b']!.completeError(StateError('offline-b'));
      expect((await moveB).reconciliationPending, isTrue);
      firstReadbacks['student-a']!.complete();
      expect((await moveA).reconciliationPending, isFalse);
      expect(controller.state.optimisticStatuses, {'student-b': 'paused'});
      await Future<void>.delayed(const Duration(milliseconds: 45));

      expect(readbackCalls, {'student-a': 1, 'student-b': 2});
      expect(controller.state.optimisticStatuses, isEmpty);
      expect(controller.state.pendingStudentIds, isEmpty);
    });
  });

  test('auto-scroll owner stops permanently on dispose', () {
    final controller = StudentsBoardAutoScrollController();
    controller.updateDrag(
      globalPosition: const Offset(100, 0),
      viewportWidth: 1200,
      reducedMotion: false,
    );
    controller.updateDrag(
      globalPosition: const Offset(20, 0),
      viewportWidth: 1200,
      reducedMotion: false,
    );
    expect(controller.isActive, isTrue);

    controller.dispose();
    expect(controller.isActive, isFalse);
    controller.updateDrag(
      globalPosition: const Offset(1190, 0),
      viewportWidth: 1200,
      reducedMotion: false,
    );
    expect(controller.isActive, isFalse);
  });
}

Future<StudentsBoardPageResult> _unusedPageLoader({
  required String branchId,
  required String cursor,
}) => throw UnimplementedError();

Future<void> _unusedStatusUpdater({
  required String studentId,
  required String status,
}) => throw UnimplementedError();
