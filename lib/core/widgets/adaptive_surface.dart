import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/adaptive_surface_kind.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';

enum AdaptiveSurfaceContainer { route, sheet, dialog }

abstract final class AdaptiveSurfacePolicy {
  static const desktopBreakpoint = magicModalDesktopBreakpoint;

  static AdaptiveSurfaceContainer containerFor(
    AppSurfaceKind kind,
    double width, {
    bool? desktop,
  }) {
    return switch (kind) {
      AppSurfaceKind.primary ||
      AppSurfaceKind.comparison => AdaptiveSurfaceContainer.route,
      AppSurfaceKind.quickView ||
      AppSurfaceKind.selection ||
      AppSurfaceKind.confirmation =>
        !(desktop ?? width >= desktopBreakpoint)
            ? AdaptiveSurfaceContainer.sheet
            : AdaptiveSurfaceContainer.dialog,
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
    desktop: usesDesktopMagicModal(context),
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
    AdaptiveSurfaceContainer.sheet ||
    AdaptiveSurfaceContainer.dialog => showMagicSheet<T>(
      context,
      title: title,
      subtitle: subtitle,
      icon: icon,
      actions: actions,
      builder: builder,
    ),
    AdaptiveSurfaceContainer.route => throw StateError(
      'Route jobs are handled before content construction.',
    ),
  };
}
