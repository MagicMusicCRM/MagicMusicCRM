import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store_contract.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';

import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final raw = Platform.environment['HTTP_JOURNEY_FIXTURE'];

  testWidgets(
    'Windows creates a lesson through the real HTTP API',
    (tester) async {
      final fixture = jsonDecode(raw!) as Map<String, dynamic>;
      final uri = Uri.parse(fixture['baseUrl'] as String);
      expect(uri.scheme, 'http');
      expect(uri.host, '127.0.0.1');
      await initializeDateFormatting('ru');
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = MagicApiClient(
        baseUrl: uri.toString(),
        tokenStore: MemoryMagicTokenStore(),
      );
      addTearDown(() => api.rawDio.close(force: true));
      final login = await api.post<Map<String, dynamic>>(
        '/auth/login',
        authenticated: false,
        data: {'email': fixture['email'], 'password': fixture['password']},
      );
      await api.saveTokens(
        MagicApiTokens.fromJson(
          Map<String, dynamic>.from(login['session'] as Map),
        ),
      );
      final scope = ProviderContainer(
        overrides: [magicApiClientProvider.overrideWithValue(api)],
      );
      addTearDown(scope.dispose);
      final access = await scope.read(capabilitySnapshotProvider.future);
      expect(access.role, 'system_admin');
      final created = <Map<String, dynamic>>[];
      final httpResults = <String>[];
      api.rawDio.interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            httpResults.add(
              '${response.requestOptions.method} '
              '${response.requestOptions.uri.path} ${response.statusCode}',
            );
            if (response.requestOptions.method == 'POST' &&
                response.requestOptions.uri.path == '/api/crm/lessons') {
              created.add(Map<String, dynamic>.from(response.data as Map));
            }
            handler.next(response);
          },
          onError: (error, handler) {
            httpResults.add(
              '${error.requestOptions.method} '
              '${error.requestOptions.uri.path} '
              '${error.response?.statusCode ?? error.type.name}',
            );
            handler.next(error);
          },
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: RepaintBoundary(
            key: evidenceRootKey,
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: FilledButton(
                      onPressed: () => CreateLessonDialog.show(
                        context,
                        initialDate: DateTime.parse(
                          fixture['scheduledAt'] as String,
                        ).toLocal(),
                        clientType: 'student',
                        clientId: fixture['studentId'] as String,
                        clientName: 'Student1 HTTP test',
                        initialBranchId: fixture['branchId'] as String,
                        initialRoomId: fixture['roomId'] as String,
                      ),
                      child: const Text('Открыть форму'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть форму'));
      await tester.pumpAndSettle();
      final teacher = find.byKey(const ValueKey('lesson-teacher-field'));
      await Scrollable.ensureVisible(tester.element(teacher), alignment: 0.4);
      await tester.tap(teacher);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: teacher, matching: find.byType(TextField)),
        'Teacher0',
      );
      // Native search debounces for 350 ms; pumpAndSettle alone does not wait
      // for the network response or guarantee that the menu result is visible.
      await tester.pump(const Duration(milliseconds: 400));
      final result = find
          .widgetWithText(MenuItemButton, 'Teacher0 HTTP test')
          .hitTestable();
      for (
        var attempt = 0;
        attempt < 100 && result.evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(result, findsOneWidget);
      await tester.tap(result);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SearchablePickerField>(teacher).selectedId,
        fixture['teacherId'],
      );
      expect(find.text('Student1 HTTP test'), findsWidgets);
      final payer = find.byKey(
        ValueKey('lesson-client-payer-${fixture['studentId']}'),
      );
      await tester.ensureVisible(payer);
      expect(payer, findsOneWidget);
      final source = find.byKey(
        ValueKey('lesson-client-charge-type-${fixture['studentId']}'),
      );
      await tester.ensureVisible(source);
      await tester.tap(source);
      await tester.pumpAndSettle();
      await tester.tap(find.text('С личного счёта').last);
      await tester.pumpAndSettle();
      final price = find.byKey(
        ValueKey('lesson-client-price-${fixture['studentId']}'),
      );
      await tester.ensureVisible(price);
      await tester.enterText(price, '1500');
      await tester.pumpAndSettle();
      await captureEvidence(tester, 'live-http-lesson-before-save');
      await tester.ensureVisible(find.text('Создать'));
      await tester.tap(find.text('Создать'));
      await tester.pump(const Duration(seconds: 1));
      await captureEvidence(tester, 'live-http-lesson-after-submit');
      for (var attempt = 0; attempt < 100 && created.isEmpty; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(created, hasLength(1), reason: httpResults.join('\n'));
      expect(created.single['clientRef'], {
        'type': 'student',
        'id': fixture['studentId'],
      });
      expect(created.single['teacherId'], fixture['teacherId']);
      await tester.pumpAndSettle();
      await captureEvidence(tester, 'live-http-lesson-saved');
      expect(tester.takeException(), isNull);
    },
    // The launcher supplies only disposable local fixture credentials.
    skip: raw == null,
  );
}
