import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_shell.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_workspace_controller.dart';

import 'card_fake_api.dart';

void main() {
  testWidgets(
    'shell preserves dialog and routed layout at the 840 breakpoint',
    (tester) async {
      Future<void> pump({required bool routed, required double width}) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ClientCardShell(
                routed: routed,
                edited: false,
                dirty: false,
                header: const SizedBox(key: Key('header')),
                blacklistBanner: const SizedBox(key: Key('blacklist')),
                desktopWorkspaceBuilder: (_) =>
                    const SizedBox(key: Key('desktop-workspace')),
                compactWorkspaceBuilder: (_) =>
                    const SizedBox(key: Key('compact-workspace')),
                actionBar: const SizedBox(key: Key('actions')),
                onCloseRequested: () async {},
              ),
            ),
          ),
        );
        await tester.pump();
      }

      addTearDown(tester.view.reset);
      await pump(routed: false, width: 1000);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byKey(const Key('compact-workspace')), findsOneWidget);
      expect(find.byKey(const Key('desktop-workspace')), findsNothing);
      final dialogCard = tester.widget<Container>(
        find.byKey(const Key('client-card-shell-card')),
      );
      expect(dialogCard.constraints?.maxHeight, 680);
      expect(dialogCard.constraints?.maxWidth, 600);

      await pump(routed: true, width: 839);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(const Key('compact-workspace')), findsOneWidget);

      await pump(routed: true, width: 840);
      expect(find.byKey(const Key('desktop-workspace')), findsOneWidget);
      expect(find.byKey(const Key('header')), findsOneWidget);
      expect(find.byKey(const Key('blacklist')), findsOneWidget);
      expect(find.byKey(const Key('actions')), findsOneWidget);
    },
  );

  for (final routed in [false, true]) {
    final host = routed ? 'routed' : 'dialog';

    testWidgets(
      '$host dirty-only back reaches close handler with true result',
      (tester) async {
        final controller = ClientCardWorkspaceController(
          initialSection: 'overview',
        )..dirty = true;
        addTearDown(controller.dispose);
        final closeResults = <bool?>[];
        var closeRequests = 0;

        await _pumpShellHost(
          tester,
          routed: routed,
          controller: controller,
          edited: false,
          dirty: true,
          onCloseRequested: (context) async {
            closeRequests += 1;
            Navigator.pop(context, controller.terminalCloseResult);
          },
          onClosed: closeResults.add,
        );

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(closeRequests, 1);
        expect(closeResults, [true]);
        expect(find.byKey(const Key('shell-body')), findsNothing);
      },
    );

    testWidgets('$host clean back remains a direct native pop', (tester) async {
      final controller = ClientCardWorkspaceController(
        initialSection: 'overview',
      );
      addTearDown(controller.dispose);
      final closeResults = <bool?>[];
      var closeRequests = 0;

      await _pumpShellHost(
        tester,
        routed: routed,
        controller: controller,
        edited: false,
        dirty: false,
        onCloseRequested: (_) async {
          closeRequests += 1;
        },
        onClosed: closeResults.add,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(closeRequests, 0);
      expect(closeResults, [null]);
      expect(find.byKey(const Key('shell-body')), findsNothing);
    });
  }

  testWidgets('edited dialog back still asks for discard confirmation', (
    tester,
  ) async {
    final api = FakeCardApiClient(
      lead: const {
        'id': 'lead-1',
        'firstName': 'Иван',
        'lastName': 'Петров',
        'customData': <String, dynamic>{},
      },
    );
    await pumpClientCard(tester, api: api, seed: const {'id': 'lead-1'});
    final nameField = find.widgetWithText(TextFormField, 'Имя');
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField, 'Пётр');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Несохранённые изменения'), findsOneWidget);
    expect(find.text('Остаться'), findsOneWidget);
    await tester.tap(find.text('Остаться'));
    await tester.pumpAndSettle();
    expect(find.text('Несохранённые изменения'), findsNothing);
    expect(find.byType(ClientCardShell), findsOneWidget);
  });

  for (final routed in [false, true]) {
    final host = routed ? 'routed' : 'dialog';
    testWidgets(
      '$host mutation then immediate back returns true before refresh completes',
      (tester) async {
        final api = _BlockingDuplicateRefreshApi();
        addTearDown(api.releaseAll);
        final closeResults = <bool?>[];
        await pumpClientCard(
          tester,
          api: api,
          seed: const {'id': 'lead-1'},
          routed: routed,
          onClosed: closeResults.add,
        );
        final attach = find.widgetWithText(FilledButton, 'Связать');
        expect(attach, findsOneWidget);
        await tester.ensureVisible(attach);
        await tester.tap(attach);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Связать').last);
        await tester.pump(const Duration(milliseconds: 400));
        expect(api.mutationStarted.isCompleted, isTrue);
        api.releaseMutation();
        await tester.pump();
        expect(api.refreshStarted.isCompleted, isTrue);

        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(closeResults, [true]);
        expect(find.byType(ClientCardShell), findsNothing);
        expect(
          api.patchRequests.where(
            (request) => request.path == '/crm/duplicates/duplicate-1',
          ),
          hasLength(1),
        );
        api.releaseRefresh();
        await tester.pump();
      },
    );
  }

  test(
    'workspace access and shell owners keep the required dependency direction',
    () {
      const root = 'lib/features/crm/presentation/client_card';
      final workspace = File('$root/client_card_workspace_controller.dart');
      final access = File('$root/client_card_access_policy.dart');
      final shell = File('$root/client_card_shell.dart');
      final card = File('$root/client_card.dart').readAsStringSync();

      expect(workspace.existsSync(), isTrue);
      expect(access.existsSync(), isTrue);
      expect(shell.existsSync(), isTrue);
      if (!workspace.existsSync() ||
          !access.existsSync() ||
          !shell.existsSync()) {
        return;
      }

      final pureSources = [access.readAsStringSync(), shell.readAsStringSync()];
      for (final source in pureSources) {
        expect(source, isNot(contains('flutter_riverpod')));
        expect(source, isNot(contains('MagicCrmService')));
        expect(source, isNot(contains('magic_crm_service.dart')));
        expect(source, isNot(contains('magic_settings_service.dart')));
        expect(source, isNot(contains('MagicApiClient')));
        expect(source, isNot(contains('Navigator.')));
      }
      expect(card, contains('ClientCardWorkspaceController'));
      expect(card, contains('ClientCardAccessPolicy.project'));
      expect(card, contains('ClientCardShell('));
      expect(card, contains('dirty: _dirty,'));
      expect(card, contains('onCloseRequested: _handleClose,'));
      expect(card, contains('void _markDirty('));
      expect(card, contains('openEntityLink('));

      final rawDirtyWrites = Directory(root)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) {
            final source = file.readAsStringSync();
            return file.path.endsWith('client_card.dart') ||
                source.contains("part of 'client_card.dart';");
          })
          .expand(
            (file) => RegExp(
              r'_dirty\s*=\s*true',
            ).allMatches(file.readAsStringSync()),
          );
      expect(rawDirtyWrites, isEmpty);
    },
  );
}

class _BlockingDuplicateRefreshApi extends FakeCardApiClient {
  _BlockingDuplicateRefreshApi()
    : super(
        lead: const {
          'id': 'lead-1',
          'firstName': 'Иван',
          'lastName': 'Петров',
          'customData': <String, dynamic>{},
        },
      );

  final refreshStarted = Completer<void>();
  final mutationStarted = Completer<void>();
  final _mutation = Completer<void>();
  final _refresh = Completer<void>();
  var _attached = false;

  static const _candidate = <String, dynamic>{
    'id': 'duplicate-1',
    'entityTypeA': 'lead',
    'entityIdA': 'lead-1',
    'entityTypeB': 'student',
    'entityIdB': 'student-1',
    'entityA': {'name': 'Иван Петров'},
    'entityB': {'name': 'Иван Петров', 'phone': '+79990000000'},
    'matchType': 'phone',
    'matchValue': '+79990000000',
    'status': 'pending',
  };

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/duplicates') {
      getRequests.add(path);
      getCalls.add((path: path, query: {...?queryParameters}));
      if (_attached) {
        if (!refreshStarted.isCompleted) refreshStarted.complete();
        await _refresh.future;
      }
      return <String, dynamic>{
            'items': _attached ? <dynamic>[] : [_candidate],
          }
          as T;
    }
    if (_attached && path == '/crm/leads/lead-1/card') {
      if (!refreshStarted.isCompleted) refreshStarted.complete();
      await _refresh.future;
      return <String, dynamic>{
            'lead': lead,
            'linkedStudents': <dynamic>[],
            'otherLeads': <dynamic>[],
            'comments': <dynamic>[],
            'tasks': <dynamic>[],
            'trials': <dynamic>[],
            'timeline': <dynamic>[],
            'customFieldValues': <String, dynamic>{},
          }
          as T;
    }
    return super.get<T>(
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }

  @override
  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (path == '/crm/duplicates/duplicate-1') {
      patchRequests.add((
        path: path,
        data: data is Map
            ? Map<String, dynamic>.from(data)
            : <String, dynamic>{},
      ));
      if (!mutationStarted.isCompleted) mutationStarted.complete();
      await _mutation.future;
      _attached = true;
      return {..._candidate, 'status': 'attached'} as T;
    }
    return super.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }

  void releaseRefresh() {
    if (_refresh.isCompleted) return;
    _refresh.complete();
  }

  void releaseMutation() {
    if (_mutation.isCompleted) return;
    _mutation.complete();
  }

  void releaseAll() {
    releaseMutation();
    releaseRefresh();
  }
}

Future<void> _pumpShellHost(
  WidgetTester tester, {
  required bool routed,
  required ClientCardWorkspaceController controller,
  required bool edited,
  required bool dirty,
  required Future<void> Function(BuildContext context) onCloseRequested,
  required ValueChanged<bool?> onClosed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (hostContext) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                Widget buildShell(BuildContext shellContext) => ClientCardShell(
                  routed: routed,
                  edited: edited,
                  dirty: dirty,
                  header: const SizedBox(),
                  desktopWorkspaceBuilder: (_) =>
                      const SizedBox(key: Key('shell-body')),
                  compactWorkspaceBuilder: (_) =>
                      const SizedBox(key: Key('shell-body')),
                  actionBar: const SizedBox(),
                  onCloseRequested: () => onCloseRequested(shellContext),
                );

                final result = routed
                    ? await Navigator.push<bool?>(
                        hostContext,
                        MaterialPageRoute(builder: buildShell),
                      )
                    : await showDialog<bool?>(
                        context: hostContext,
                        builder: buildShell,
                      );
                onClosed(result);
              },
              child: const Text('open shell'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open shell'));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('shell-body')), findsOneWidget);
  expect(controller.edited, edited);
  expect(controller.dirty, dirty);
}
