import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';

class WorkspaceSharedScope {
  const WorkspaceSharedScope({
    required this.session,
    required this.cache,
    required this.realtime,
  });

  final Object session;
  final Object cache;
  final Object realtime;
}

class WorkspaceLimitReached implements Exception {
  const WorkspaceLimitReached();

  @override
  String toString() => 'WorkspaceLimitReached(maxTabs: 10)';
}

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    required String accountId,
    required EntityLink initialLink,
    required this.sharedScope,
    String initialTitle = 'Главная',
  }) : _state = WorkspaceState(
         accountId: accountId,
         activeTabId: 'tab-1',
         tabs: [
           WorkspaceTabState(
             tabId: 'tab-1',
             titleHint: initialTitle,
             routeStack: [
               ContextRouteState(
                 link: initialLink,
                 viewState: ContextViewState(),
               ),
             ],
           ),
         ],
       );

  static const maxTabs = 10;

  final WorkspaceSharedScope sharedScope;
  WorkspaceState _state;
  var _nextTabNumber = 2;

  WorkspaceState get state => _state;

  void selectTab(String tabId) {
    _tabIndex(tabId);
    if (_state.activeTabId == tabId) return;
    _state = _state.copyWith(activeTabId: tabId);
    notifyListeners();
  }

  String open(EntityLink link, {String? titleHint, bool explicitNew = false}) {
    _requireSupported(link);
    if (!explicitNew) {
      final existing = _state.tabs
          .where((tab) => _sameEntity(tab.currentRoute.link, link))
          .firstOrNull;
      if (existing != null) {
        selectTab(existing.tabId);
        return existing.tabId;
      }
    }
    if (_state.tabs.length >= maxTabs) {
      throw const WorkspaceLimitReached();
    }

    final tabId = 'tab-${_nextTabNumber++}';
    final next = WorkspaceTabState(
      tabId: tabId,
      titleHint: titleHint ?? _defaultTitle(link),
      routeStack: [
        ContextRouteState(link: link, viewState: ContextViewState()),
      ],
    );
    _state = _state.copyWith(activeTabId: tabId, tabs: [..._state.tabs, next]);
    notifyListeners();
    return tabId;
  }

  void push(
    String tabId,
    EntityLink link, {
    ContextViewState? currentViewState,
  }) {
    _requireSupported(link);
    _updateTab(tabId, (tab) {
      final routes = [...tab.routeStack];
      if (currentViewState != null) {
        routes[routes.length - 1] = routes.last.copyWith(
          viewState: currentViewState,
        );
      }
      routes.add(ContextRouteState(link: link, viewState: ContextViewState()));
      return tab.copyWith(routeStack: routes);
    });
  }

  ContextRouteState? pop(String tabId) {
    ContextRouteState? removed;
    _updateTab(tabId, (tab) {
      if (tab.routeStack.length == 1) return tab;
      removed = tab.routeStack.last;
      return tab.copyWith(
        routeStack: tab.routeStack.sublist(0, tab.routeStack.length - 1),
      );
    });
    return removed;
  }

  void updateCurrentView(String tabId, ContextViewState viewState) {
    _updateTab(tabId, (tab) {
      final routes = [...tab.routeStack];
      routes[routes.length - 1] = routes.last.copyWith(viewState: viewState);
      return tab.copyWith(routeStack: routes);
    });
  }

  void registerForm(
    String tabId,
    String formKey, {
    int? expectedVersion,
    Map<String, Object?> draft = const {},
  }) {
    _updateTab(tabId, (tab) {
      final forms = {...tab.forms};
      forms[formKey] = WorkspaceFormState(
        formKey: formKey,
        expectedVersion: expectedVersion,
        draft: draft,
      );
      return tab.copyWith(forms: forms);
    });
  }

  void updateForm(
    String tabId,
    String formKey, {
    required bool dirty,
    int? expectedVersion,
    Map<String, Object?>? draft,
  }) {
    _updateTab(tabId, (tab) {
      final current = tab.forms[formKey];
      if (current == null) {
        throw StateError('Unknown form "$formKey" in tab "$tabId".');
      }
      return tab.copyWith(
        forms: {
          ...tab.forms,
          formKey: current.copyWith(
            dirty: dirty,
            expectedVersion: expectedVersion,
            draft: draft,
          ),
        },
      );
    });
  }

  void unregisterForm(String tabId, String formKey) {
    _updateTab(tabId, (tab) {
      if (!tab.forms.containsKey(formKey)) return tab;
      final forms = {...tab.forms}..remove(formKey);
      return tab.copyWith(forms: forms);
    });
  }

  void _updateTab(
    String tabId,
    WorkspaceTabState Function(WorkspaceTabState tab) update,
  ) {
    final index = _tabIndex(tabId);
    final tabs = [..._state.tabs];
    final updated = update(tabs[index]);
    if (identical(updated, tabs[index])) return;
    tabs[index] = updated;
    _state = _state.copyWith(tabs: tabs);
    notifyListeners();
  }

  int _tabIndex(String tabId) {
    final index = _state.tabs.indexWhere((tab) => tab.tabId == tabId);
    if (index < 0) throw StateError('Unknown workspace tab "$tabId".');
    return index;
  }

  static bool _sameEntity(EntityLink left, EntityLink right) {
    return left.rawEntityType == right.rawEntityType &&
        left.entityId == right.entityId;
  }

  static String _defaultTitle(EntityLink link) {
    return '${link.rawEntityType}: ${link.entityId}';
  }

  static void _requireSupported(EntityLink link) {
    if (!link.isSupported) {
      throw const FormatException('Unsupported workspace route.');
    }
  }
}
