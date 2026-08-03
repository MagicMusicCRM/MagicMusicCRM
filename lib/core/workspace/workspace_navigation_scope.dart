import 'package:flutter/widgets.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';

class WorkspaceNavigationScope extends InheritedWidget {
  const WorkspaceNavigationScope({
    required this.controller,
    required this.isDesktop,
    required super.child,
    super.key,
  });

  final WorkspaceController controller;
  final bool isDesktop;

  static WorkspaceNavigationScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<WorkspaceNavigationScope>();
  }

  @override
  bool updateShouldNotify(WorkspaceNavigationScope oldWidget) {
    return controller != oldWidget.controller ||
        isDesktop != oldWidget.isDesktop;
  }
}
