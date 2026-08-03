import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';

/// A predictive-back-safe local history boundary.
///
/// Native Navigator routes (dialogs, sheets and pushed pages) keep priority.
/// This scope only consumes Back when the current page declares local history.
class AppBackScope extends StatelessWidget {
  const AppBackScope({
    required this.hasLocalHistory,
    required this.onBack,
    required this.child,
    super.key,
  });

  final bool hasLocalHistory;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !hasLocalHistory,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && hasLocalHistory) onBack();
      },
      child: child,
    );
  }
}

/// One UI Back action: current Navigator route first, then desktop tab history.
Future<bool> maybeNavigateBack(BuildContext context) async {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) return navigator.maybePop();

  final workspace = WorkspaceNavigationScope.maybeOf(context);
  if (workspace != null) {
    final controller = workspace.controller;
    final tab = controller.state.activeTab;
    if (tab.routeStack.length > 1) {
      controller.back(tab.tabId);
      return true;
    }
  }
  return false;
}

/// Removes an in-app deep-link host, but gives a cold external link a safe home.
void returnFromDeepLink(
  BuildContext context, {
  required String fallbackLocation,
}) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallbackLocation);
  }
}

class AppBackButton extends StatelessWidget {
  const AppBackButton({this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return BackButton(
      onPressed: onPressed ?? () => unawaited(maybeNavigateBack(context)),
    );
  }
}
