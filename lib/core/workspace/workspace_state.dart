import 'dart:collection';

import 'package:magic_music_crm/core/navigation/context_route_state.dart';

class WorkspaceFormState {
  WorkspaceFormState({
    required this.formKey,
    this.dirty = false,
    this.expectedVersion,
    Map<String, Object?> draft = const {},
  }) : draft = UnmodifiableMapView(Map<String, Object?>.from(draft));

  final String formKey;
  final bool dirty;
  final int? expectedVersion;
  final Map<String, Object?> draft;

  WorkspaceFormState copyWith({
    bool? dirty,
    int? expectedVersion,
    bool clearExpectedVersion = false,
    Map<String, Object?>? draft,
  }) {
    return WorkspaceFormState(
      formKey: formKey,
      dirty: dirty ?? this.dirty,
      expectedVersion: clearExpectedVersion
          ? null
          : expectedVersion ?? this.expectedVersion,
      draft: draft ?? this.draft,
    );
  }
}

class WorkspaceTabState {
  WorkspaceTabState({
    required this.tabId,
    required this.titleHint,
    required List<ContextRouteState> routeStack,
    Map<String, WorkspaceFormState> forms = const {},
  }) : routeStack = List.unmodifiable(routeStack),
       forms = UnmodifiableMapView(Map<String, WorkspaceFormState>.from(forms));

  final String tabId;
  final String titleHint;
  final List<ContextRouteState> routeStack;
  final Map<String, WorkspaceFormState> forms;

  ContextRouteState get currentRoute => routeStack.last;
  bool get hasDirtyForms => forms.values.any((form) => form.dirty);

  WorkspaceTabState copyWith({
    String? titleHint,
    List<ContextRouteState>? routeStack,
    Map<String, WorkspaceFormState>? forms,
  }) {
    return WorkspaceTabState(
      tabId: tabId,
      titleHint: titleHint ?? this.titleHint,
      routeStack: routeStack ?? this.routeStack,
      forms: forms ?? this.forms,
    );
  }
}

class WorkspaceState {
  WorkspaceState({
    required this.accountId,
    required this.activeTabId,
    required List<WorkspaceTabState> tabs,
    this.schemaVersion = currentSchemaVersion,
    this.loggedOut = false,
  }) : tabs = List.unmodifiable(tabs) {
    if (tabs.isEmpty && !loggedOut) {
      throw ArgumentError.value(tabs, 'tabs', 'Workspace requires one tab.');
    }
    if (tabs.isNotEmpty && !tabs.any((tab) => tab.tabId == activeTabId)) {
      throw ArgumentError.value(
        activeTabId,
        'activeTabId',
        'Active tab must exist.',
      );
    }
  }

  factory WorkspaceState.loggedOut(String accountId) {
    return WorkspaceState(
      accountId: accountId,
      activeTabId: '',
      tabs: const [],
      loggedOut: true,
    );
  }

  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final String accountId;
  final String activeTabId;
  final List<WorkspaceTabState> tabs;
  final bool loggedOut;

  WorkspaceTabState get activeTab =>
      tabs.firstWhere((tab) => tab.tabId == activeTabId);

  WorkspaceState copyWith({
    String? activeTabId,
    List<WorkspaceTabState>? tabs,
  }) {
    return WorkspaceState(
      accountId: accountId,
      activeTabId: activeTabId ?? this.activeTabId,
      tabs: tabs ?? this.tabs,
      schemaVersion: schemaVersion,
      loggedOut: loggedOut,
    );
  }
}
