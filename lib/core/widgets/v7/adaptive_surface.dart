import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_drawer.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_sheet.dart';

enum AdaptiveSurfaceContainer { route, sheet, drawer, dialog }

abstract final class AdaptiveSurfacePolicy {
  static const desktopBreakpoint = 840.0;

  static AdaptiveSurfaceContainer containerFor(
    AppSurfaceKind kind,
    double width,
  ) {
    return switch (kind) {
      AppSurfaceKind.primary ||
      AppSurfaceKind.comparison => AdaptiveSurfaceContainer.route,
      AppSurfaceKind.quickView || AppSurfaceKind.selection =>
        width < desktopBreakpoint
            ? AdaptiveSurfaceContainer.sheet
            : AdaptiveSurfaceContainer.drawer,
      AppSurfaceKind.confirmation => AdaptiveSurfaceContainer.dialog,
    };
  }
}

Future<T?> showMagicAdaptiveSurface<T>(
  BuildContext context, {
  required AppSurfaceKind kind,
  required String title,
  WidgetBuilder? builder,
  Future<T?> Function()? openRoute,
  String? subtitle,
  IconData? icon,
  List<Widget>? actions,
}) {
  final container = AdaptiveSurfacePolicy.containerFor(
    kind,
    MediaQuery.sizeOf(context).width,
  );
  if (container == AdaptiveSurfaceContainer.route) {
    if (openRoute == null) {
      throw ArgumentError.value(
        kind,
        'kind',
        'Primary and comparison jobs require an existing route callback.',
      );
    }
    return openRoute();
  }
  if (builder == null) {
    throw ArgumentError.notNull('builder');
  }

  return switch (container) {
    AdaptiveSurfaceContainer.sheet => showMagicSheet<T>(
      context,
      title: title,
      subtitle: subtitle,
      icon: icon,
      actions: actions,
      builder: builder,
    ),
    AdaptiveSurfaceContainer.drawer => showMagicDrawer<T>(
      context,
      title: title,
      subtitle: subtitle,
      icon: icon,
      actions: actions,
      builder: builder,
    ),
    AdaptiveSurfaceContainer.dialog => showDialog<T>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: builder(dialogContext),
        actions: actions,
      ),
    ),
    AdaptiveSurfaceContainer.route => throw StateError(
      'Route jobs are handled before content construction.',
    ),
  };
}
