import 'package:flutter/widgets.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';

enum EntityNavigationOpenResult { opened, limitReached }

typedef EntityNavigationOpen =
    EntityNavigationOpenResult Function(EntityLink link, {String? titleHint});
typedef EntityNavigationViewPreserver =
    void Function(ContextViewState viewState);

class EntityNavigationScope extends InheritedWidget {
  const EntityNavigationScope({
    required this.isDesktop,
    required this.open,
    required this.preserveCurrentView,
    required super.child,
    super.key,
  });

  final bool isDesktop;
  final EntityNavigationOpen open;
  final EntityNavigationViewPreserver preserveCurrentView;

  static EntityNavigationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<EntityNavigationScope>();
  }

  @override
  bool updateShouldNotify(EntityNavigationScope oldWidget) {
    return isDesktop != oldWidget.isDesktop ||
        open != oldWidget.open ||
        preserveCurrentView != oldWidget.preserveCurrentView;
  }
}
