import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

typedef ClientCardPostFrameScheduler = void Function(FrameCallback callback);

class ClientCardWorkspaceController {
  ClientCardWorkspaceController({
    required String initialSection,
    double restoredOffset = 0,
    ClientCardPostFrameScheduler? schedulePostFrame,
  }) : selectedSection = _normalizedSection(initialSection),
       customFieldsExpanded = initialSection == 'custom_fields',
       _schedulePostFrame = schedulePostFrame,
       taskScrollController = ScrollController(
         initialScrollOffset:
             _normalizedSection(initialSection) == 'history_tasks'
             ? restoredOffset
             : 0,
       ),
       paymentScrollController = ScrollController(
         initialScrollOffset: _normalizedSection(initialSection) == 'payments'
             ? restoredOffset
             : 0,
       ),
       subscriptionScrollController = ScrollController(
         initialScrollOffset:
             _normalizedSection(initialSection) == 'subscriptions'
             ? restoredOffset
             : 0,
       ),
       desktopScrollController = ScrollController(
         initialScrollOffset: _normalizedSection(initialSection) == 'overview'
             ? restoredOffset
             : 0,
       );

  final ClientCardPostFrameScheduler? _schedulePostFrame;
  final ScrollController taskScrollController;
  final ScrollController paymentScrollController;
  final ScrollController subscriptionScrollController;
  final ScrollController desktopScrollController;

  String selectedSection;
  bool desktopCalendarExpanded = false;
  bool customFieldsExpanded;
  bool edited = false;
  bool dirty = false;

  bool _disposed = false;
  int _postFrameGeneration = 0;

  bool get requiresDiscardConfirmation => edited;
  bool? get terminalCloseResult => dirty ? true : null;

  void selectSection(String section) {
    if (_disposed) return;
    selectedSection = _normalizedSection(section);
    if (section == 'custom_fields') customFieldsExpanded = true;
  }

  void restoreSection(String section) {
    if (_disposed) return;
    customFieldsExpanded = section == 'custom_fields';
    selectedSection = _normalizedSection(section);
  }

  void schedulePostFrameIntent(VoidCallback intent) {
    if (_disposed) return;
    final generation = ++_postFrameGeneration;
    final schedule =
        _schedulePostFrame ?? WidgetsBinding.instance.addPostFrameCallback;
    schedule((_) {
      if (_disposed || generation != _postFrameGeneration) return;
      intent();
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _postFrameGeneration++;
    taskScrollController.dispose();
    paymentScrollController.dispose();
    subscriptionScrollController.dispose();
    desktopScrollController.dispose();
  }

  static String _normalizedSection(String section) =>
      section == 'custom_fields' ? 'overview' : section;
}
