import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/services/notification_service.dart';
import 'package:magic_music_crm/core/widgets/app_logo.dart';
import 'package:magic_music_crm/features/auth/data/services/magic_auth_service.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/features/teacher/presentation/widgets/teacher_students_widget.dart';
import 'package:magic_music_crm/main.dart';

import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const password = String.fromEnvironment('STAGE9_UAT_PASSWORD');
  const apiBaseUrl = String.fromEnvironment(
    'MAGIC_API_BASE_URL',
    defaultValue: 'https://api.magicmusiccrm.ru/api',
  );

  testWidgets('five production accounts mount role-correct shells', (
    tester,
  ) async {
    expect(password, isNotEmpty, reason: 'Pass STAGE9_UAT_PASSWORD');

    const accounts = <(int, String, String)>[
      (1, 'client', 'Занятия'),
      (2, 'teacher', 'Ученики'),
      (3, 'admin', 'Клиенты'),
      (4, 'manager', 'Обзор'),
      (5, 'director', 'Обзор'),
    ];

    for (final (number, role, readyLabel) in accounts) {
      final tokens = MemoryMagicTokenStore();
      final api = MagicApiClient(baseUrl: apiBaseUrl, tokenStore: tokens);
      final auth = MagicAuthService(api);
      final response = await auth.signInWithPassword(
        email: 'magic$number@gmail.com',
        password: password,
      );

      expect(response.user?.role, role, reason: 'magic$number');
      expect(response.hasSession, isTrue, reason: 'magic$number');
      expect((await auth.currentProfile()).role, role, reason: 'magic$number');

      await tester.pumpWidget(
        RepaintBoundary(
          key: evidenceRootKey,
          child: ProviderScope(
            overrides: [
              magicTokenStoreProvider.overrideWithValue(tokens),
              magicApiClientProvider.overrideWithValue(api),
              magicAuthServiceProvider.overrideWithValue(auth),
              notificationServiceProvider.overrideWith(
                _NoopNotificationService.new,
              ),
            ],
            child: const MagicMusicApp(),
          ),
        ),
      );
      await _pumpUntilVisible(tester, find.text(readyLabel));
      _expectRoleShell(role);
      if (tester.view.physicalSize.width / tester.view.devicePixelRatio >=
          840) {
        expect(find.byType(AppLogo), findsWidgets, reason: 'magic$number logo');
      }
      await captureEvidence(tester, 'real-role-$number-$role');
      if (role == 'teacher') {
        await tester.tap(find.text('Ученики').first);
        await _pumpUntilVisible(tester, find.byType(TeacherStudentsWidget));
        await _pumpUntilGone(
          tester,
          find.descendant(
            of: find.byType(TeacherStudentsWidget),
            matching: find.byType(CircularProgressIndicator),
          ),
          timeout: const Duration(minutes: 2),
        );
        expect(find.textContaining('Ошибка:'), findsNothing);
        await captureEvidence(tester, 'real-role-2-teacher-students');
        await tester.tap(find.text('Расписание').first);
        await tester.pump(const Duration(seconds: 3));
        await captureEvidence(tester, 'real-role-2-teacher-schedule');
      }
      expect(tester.takeException(), isNull, reason: 'magic$number');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await auth.signOut();
    }
  });

  test(
    'secure session survives restart and allows account switching',
    () async {
      expect(password, isNotEmpty, reason: 'Pass STAGE9_UAT_PASSWORD');
      final namespace =
          'stage9-relogin-${DateTime.now().microsecondsSinceEpoch}';
      final firstStore = SecureMagicTokenStore(namespace: namespace);
      await firstStore.clear();
      try {
        final firstAuth = MagicAuthService(
          MagicApiClient(baseUrl: apiBaseUrl, tokenStore: firstStore),
        );
        expect(
          (await firstAuth.signInWithPassword(
            email: 'magic1@gmail.com',
            password: password,
          )).user?.role,
          'client',
        );

        // A fresh store instance is the same read path used after an app update
        // or cold restart: it must recover the persisted active account.
        final restartedStore = SecureMagicTokenStore(namespace: namespace);
        final restartedAuth = MagicAuthService(
          MagicApiClient(baseUrl: apiBaseUrl, tokenStore: restartedStore),
        );
        expect((await restartedAuth.currentProfile()).role, 'client');

        await restartedAuth.signOut();
        expect(await restartedAuth.currentSession(), isNull);
        expect(
          (await restartedAuth.signInWithPassword(
            email: 'magic5@gmail.com',
            password: password,
          )).user?.role,
          'director',
        );
        expect((await restartedAuth.currentProfile()).role, 'director');

        await restartedAuth.signOut();
        expect(
          (await restartedAuth.signInWithPassword(
            email: 'magic1@gmail.com',
            password: password,
          )).user?.role,
          'client',
        );
        expect((await restartedAuth.currentProfile()).role, 'client');
      } finally {
        await SecureMagicTokenStore(namespace: namespace).clear();
      }
    },
  );
}

void _expectRoleShell(String role) {
  void visible(String label) => expect(find.text(label), findsWidgets);
  void absent(String label) => expect(find.text(label), findsNothing);

  visible('Чат');
  switch (role) {
    case 'client':
      for (final label in const ['Занятия', 'Абонемент', 'Профиль']) {
        visible(label);
      }
      absent('Клиенты');
    case 'teacher':
      visible('Расписание');
      visible('Ученики');
      absent('Клиенты');
      absent('Задачи');
    case 'admin':
      visible('Расписание');
      visible('Клиенты');
      absent('Обзор');
      absent('Задачи');
      absent('Аналитика');
    case 'manager':
    case 'director':
      for (final label in const ['Обзор', 'Расписание', 'Клиенты']) {
        visible(label);
      }
      if (Platform.isWindows) {
        for (final label in const ['Задачи', 'Аналитика', 'Настройки']) {
          visible(label);
        }
      } else {
        visible('Ещё');
      }
      absent('Финансы');
  }
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder to disappear');
}

class _NoopNotificationService extends NotificationService {
  _NoopNotificationService(super.ref);

  @override
  Future<void> setupNotifications() async {}

  @override
  Future<void> syncCurrentDeviceToken() async {}
}
