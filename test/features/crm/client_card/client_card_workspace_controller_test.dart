import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_workspace_controller.dart';

void main() {
  test(
    'custom_fields restore normalizes section and restores overview offset',
    () {
      final controller = ClientCardWorkspaceController(
        initialSection: 'custom_fields',
        restoredOffset: 144,
      );
      addTearDown(controller.dispose);

      expect(controller.selectedSection, 'overview');
      expect(controller.customFieldsExpanded, isTrue);
      expect(controller.desktopScrollController.initialScrollOffset, 144);
      expect(controller.taskScrollController.initialScrollOffset, 0);
      expect(controller.paymentScrollController.initialScrollOffset, 0);
      expect(controller.subscriptionScrollController.initialScrollOffset, 0);
    },
  );

  test('restored offset belongs only to the selected compact section', () {
    for (final entry in const {
      'history_tasks': [81.0, 0.0, 0.0],
      'payments': [0.0, 81.0, 0.0],
      'subscriptions': [0.0, 0.0, 81.0],
      'lessons': [0.0, 0.0, 0.0],
    }.entries) {
      final controller = ClientCardWorkspaceController(
        initialSection: entry.key,
        restoredOffset: 81,
      );

      expect(
        controller.taskScrollController.initialScrollOffset,
        entry.value[0],
      );
      expect(
        controller.paymentScrollController.initialScrollOffset,
        entry.value[1],
      );
      expect(
        controller.subscriptionScrollController.initialScrollOffset,
        entry.value[2],
      );
      expect(controller.desktopScrollController.initialScrollOffset, 0);
      controller.dispose();
    }
  });

  test('only the newest post-frame intent runs and dispose makes it inert', () {
    final callbacks = <FrameCallback>[];
    final controller = ClientCardWorkspaceController(
      initialSection: 'overview',
      schedulePostFrame: callbacks.add,
    );
    final calls = <String>[];

    controller.schedulePostFrameIntent(() => calls.add('stale'));
    controller.schedulePostFrameIntent(() => calls.add('current'));
    callbacks[0](Duration.zero);
    callbacks[1](Duration.zero);
    expect(calls, ['current']);

    controller.schedulePostFrameIntent(() => calls.add('disposed'));
    controller.dispose();
    callbacks[2](Duration.zero);
    controller.dispose();
    expect(calls, ['current']);
  });

  test('edited and dirty remain distinct across the close-result matrix', () {
    final controller = ClientCardWorkspaceController(
      initialSection: 'overview',
    );
    addTearDown(controller.dispose);

    expect(controller.requiresDiscardConfirmation, isFalse);
    expect(controller.terminalCloseResult, isNull);

    controller.dirty = true;
    expect(controller.requiresDiscardConfirmation, isFalse);
    expect(controller.terminalCloseResult, isTrue);

    controller.edited = true;
    expect(controller.requiresDiscardConfirmation, isTrue);
    expect(controller.terminalCloseResult, isTrue);

    controller.dirty = false;
    expect(controller.requiresDiscardConfirmation, isTrue);
    expect(controller.terminalCloseResult, isNull);
  });

  test('section and expansion state are owned by the workspace controller', () {
    final controller = ClientCardWorkspaceController(
      initialSection: 'overview',
    );
    addTearDown(controller.dispose);

    controller
      ..selectSection('payments')
      ..desktopCalendarExpanded = true
      ..customFieldsExpanded = true;

    expect(controller.selectedSection, 'payments');
    expect(controller.desktopCalendarExpanded, isTrue);
    expect(controller.customFieldsExpanded, isTrue);
  });
}
