import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/forms/dirty_form_exit.dart';
import 'package:magic_music_crm/core/workspace/workspace_controller.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';

Future<bool> requestWorkspaceDirtyExit(
  BuildContext context, {
  required DirtyFormExitReason reason,
}) async {
  final workspace = WorkspaceNavigationScope.maybeOf(context);
  if (workspace == null || workspace.controller.state.loggedOut) return true;
  final controller = workspace.controller;
  if (!controller.state.tabs.any((tab) => tab.hasDirtyForms)) return true;
  final decision = switch (await showDirtyFormExitDialog(context)) {
    DirtyFormExitDecision.save => DirtyCloseDecision.save,
    DirtyFormExitDecision.discard => DirtyCloseDecision.discard,
    DirtyFormExitDecision.cancel || null => DirtyCloseDecision.cancel,
  };
  return controller.resolveAllDirtyTabs(
    decision: decision,
    saveDirty: controller.saveDirtyForms,
    discardDirty: controller.discardDirtyForms,
  );
}
