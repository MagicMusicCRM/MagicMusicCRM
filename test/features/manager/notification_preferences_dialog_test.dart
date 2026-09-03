import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/notification_preference.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/notification_preferences_dialog.dart';

class _FakeNotifications implements MagicNotificationsService {
  final bool failWrites;
  int updateCalls = 0;
  Map<String, dynamic>? lastUpdate;

  _FakeNotifications({this.failWrites = false});

  @override
  Future<List<NotificationPreference>> listPreferences() async => const [
    NotificationPreference(
      role: 'manager',
      eventType: 'new_lead',
      enabled: true,
      channels: ['in_app', 'push'],
    ),
    NotificationPreference(
      role: 'teacher',
      eventType: 'new_lead',
      enabled: false,
      channels: ['push'],
    ),
  ];

  @override
  Future<NotificationPreference> updatePreference({
    required String role,
    required String eventType,
    required bool enabled,
    required List<String> channels,
  }) async {
    updateCalls += 1;
    lastUpdate = {
      'role': role,
      'eventType': eventType,
      'enabled': enabled,
      'channels': channels,
    };
    if (failWrites) throw Exception('server said no');
    return NotificationPreference(
      role: role,
      eventType: eventType,
      enabled: enabled,
      channels: channels,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Widget _host(_FakeNotifications fake) {
  return ProviderScope(
    overrides: [magicNotificationsServiceProvider.overrideWithValue(fake)],
    child: const MaterialApp(
      home: Scaffold(body: NotificationPreferencesDialog()),
    ),
  );
}

void main() {
  testWidgets('phone notification channels keep readable labels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicNotificationsServiceProvider.overrideWithValue(
            _FakeNotifications(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.android),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => NotificationPreferencesDialog.show(context),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final role = tester.getRect(find.text('Управляющий'));
    final firstChannel = tester.getRect(find.byType(FilterChip).first);
    expect(firstChannel.top, greaterThan(role.bottom));
    expect(tester.getSize(find.byType(Wrap).first).width, greaterThan(250));
  });

  testWidgets('renders a row per role and saves a toggle', (tester) async {
    final fake = _FakeNotifications();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    expect(find.text('Новая заявка'), findsOneWidget);
    expect(find.text('Управляющий'), findsOneWidget);
    expect(find.text('Педагог'), findsOneWidget);

    // Turn the teacher broadcast on.
    final teacherSwitch = find.byType(Switch).last;
    await tester.tap(teacherSwitch);
    await tester.pumpAndSettle();

    expect(fake.updateCalls, 1);
    expect(fake.lastUpdate?['role'], 'teacher');
    expect(fake.lastUpdate?['enabled'], true);
  });

  testWidgets('rolls the switch back when the server refuses', (tester) async {
    final fake = _FakeNotifications(failWrites: true);
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    final teacherSwitch = find.byType(Switch).last;
    expect(tester.widget<Switch>(teacherSwitch).value, isFalse);

    await tester.tap(teacherSwitch);
    await tester.pumpAndSettle();

    // The optimistic flip must not survive a failed write: leaving it on would
    // claim teachers are being notified when the server never agreed.
    expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
    expect(find.textContaining('Не удалось сохранить'), findsOneWidget);
  });

  testWidgets('channel chips are inert while the role is off', (tester) async {
    final fake = _FakeNotifications();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    // Teacher row is disabled, so its channel chips must not be actionable —
    // an editable channel on an off row implies mail still goes out.
    final teacherChips = find.byType(FilterChip);
    final pushChip = tester
        .widgetList<FilterChip>(teacherChips)
        .where((chip) => (chip.label as Text).data == 'Push')
        .toList();
    expect(pushChip.last.onSelected, isNull);
  });
}
