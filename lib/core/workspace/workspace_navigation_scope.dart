import 'package:flutter/widgets.dart';
import 'package:magic_music_crm/core/workspace/entity_navigation_scope.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';

class WorkspaceNavigationScope extends InheritedWidget {
  WorkspaceNavigationScope({
    required this.controller,
    required this.isDesktop,
    required Widget child,
    super.key,
  }) : super(
         child: EntityNavigationScope(
           isDesktop: isDesktop,
           preserveCurrentView: (viewState) => controller.updateCurrentView(
             controller.state.activeTabId,
             viewState,
           ),
           open: (link, {titleHint}) {
             try {
               controller.open(link, titleHint: titleHint, explicitNew: true);
               return EntityNavigationOpenResult.opened;
             } on WorkspaceLimitReached {
               return EntityNavigationOpenResult.limitReached;
             }
           },
           child: child,
         ),
       );

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
