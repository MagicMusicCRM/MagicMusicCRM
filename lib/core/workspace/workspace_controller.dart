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

enum DirtyCloseDecision { save, discard, cancel }

typedef DirtyCloseResolver =
    Future<DirtyCloseDecision> Function(WorkspaceTabState tab);
typedef DirtyTabSaver = Future<void> Function(WorkspaceTabState tab);
typedef DirtyTabDiscarder = Future<void> Function(WorkspaceTabState tab);
typedef WorkspaceFormSaver = Future<bool> Function();
typedef WorkspaceTitleResolver = String Function(EntityLink link);

class _WorkspaceFormActions {
  const _WorkspaceFormActions({required this.save, required this.discard});

  final WorkspaceFormSaver? save;
  final VoidCallback? discard;
}

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    required String accountId,
    required EntityLink initialLink,
    required this.sharedScope,
    String initialTitle = 'Главная',
    WorkspaceTitleResolver? titleResolver,
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
       ),
       _titleResolver = titleResolver;

  static const maxTabs = 10;

  final WorkspaceSharedScope sharedScope;
  final WorkspaceTitleResolver? _titleResolver;
  final Map<String, _WorkspaceFormActions> _formActions = {};
  WorkspaceState _state;
  var _nextTabNumber = 2;

  WorkspaceState get state => _state;

  void restore(WorkspaceState restored) {
    if (restored.accountId != _state.accountId) {
      throw StateError('Cannot restore another account workspace.');
    }
    _formActions.clear();
    _state = restored.copyWith(
      tabs: [
        for (final tab in restored.tabs)
          tab.copyWith(titleHint: _titleFor(tab.currentRoute.link)),
      ],
    );
    _nextTabNumber = _nextAvailableTabNumber(restored.tabs);
    notifyListeners();
  }

  void handleGlobalLogout() {
    if (_state.loggedOut) return;
    _formActions.clear();
    _state = WorkspaceState.loggedOut(_state.accountId);
    notifyListeners();
  }

  void selectTab(String tabId) {
    _tabIndex(tabId);
    if (_state.activeTabId == tabId) return;
    _state = _state.copyWith(activeTabId: tabId);
    notifyListeners();
  }

  String open(EntityLink link, {String? titleHint, bool explicitNew = false}) {
    if (_state.loggedOut) {
      throw StateError('Cannot open a route after global logout.');
    }
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
      titleHint: titleHint ?? _titleFor(link),
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
      return tab.copyWith(
        titleHint: _titleFor(link),
        routeStack: routes,
        forwardStack: const [],
      );
    });
  }

  ContextRouteState? back(String tabId) {
    ContextRouteState? removed;
    _updateTab(tabId, (tab) {
      if (tab.routeStack.length == 1) return tab;
      removed = tab.routeStack.last;
      return tab.copyWith(
        titleHint: _titleFor(tab.routeStack[tab.routeStack.length - 2].link),
        routeStack: tab.routeStack.sublist(0, tab.routeStack.length - 1),
        forwardStack: [...tab.forwardStack, removed!],
      );
    });
    return removed;
  }

  ContextRouteState? forward(String tabId) {
    ContextRouteState? restored;
    _updateTab(tabId, (tab) {
      if (tab.forwardStack.isEmpty) return tab;
      restored = tab.forwardStack.last;
      return tab.copyWith(
        titleHint: _titleFor(restored!.link),
        routeStack: [...tab.routeStack, restored!],
        forwardStack: tab.forwardStack.sublist(0, tab.forwardStack.length - 1),
      );
    });
    return restored;
  }

  ContextRouteState? pop(String tabId) => back(tabId);

  void reorderTab(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _state.tabs.length) {
      throw RangeError.index(oldIndex, _state.tabs, 'oldIndex');
    }
    if (newIndex < 0 || newIndex > _state.tabs.length) {
      throw RangeError.range(newIndex, 0, _state.tabs.length, 'newIndex');
    }
    final tabs = [..._state.tabs];
    if (newIndex > oldIndex) newIndex -= 1;
    final tab = tabs.removeAt(oldIndex);
    tabs.insert(newIndex, tab);
    _state = _state.copyWith(tabs: tabs);
    notifyListeners();
  }

  String duplicateTab(String tabId) {
    final tab = _state.tabs[_tabIndex(tabId)];
    return open(
      tab.currentRoute.link,
      titleHint: tab.titleHint,
      explicitNew: true,
    );
  }

  Future<bool> closeTab(
    String tabId, {
    required DirtyCloseResolver resolveDirty,
    required DirtyTabSaver saveDirty,
    DirtyTabDiscarder? discardDirty,
  }) async {
    if (_state.tabs.length == 1) return false;
    _tabIndex(tabId);
    final canClose = await resolveDirtyTab(
      tabId,
      resolveDirty: resolveDirty,
      saveDirty: saveDirty,
      discardDirty: discardDirty,
    );
    if (!canClose) return false;

    final currentIndex = _state.tabs.indexWhere((item) => item.tabId == tabId);
    if (currentIndex < 0) return true;
    final tabs = [..._state.tabs]..removeAt(currentIndex);
    _formActions.removeWhere((key, _) => key.startsWith('$tabId:'));
    var activeTabId = _state.activeTabId;
    if (activeTabId == tabId) {
      activeTabId = tabs[currentIndex.clamp(0, tabs.length - 1)].tabId;
    }
    _state = _state.copyWith(activeTabId: activeTabId, tabs: tabs);
    notifyListeners();
    return true;
  }

  Future<void> closeOtherTabs(
    String tabId, {
    required DirtyCloseResolver resolveDirty,
    required DirtyTabSaver saveDirty,
    DirtyTabDiscarder? discardDirty,
  }) async {
    _tabIndex(tabId);
    final otherIds = _state.tabs
        .where((tab) => tab.tabId != tabId)
        .map((tab) => tab.tabId)
        .toList(growable: false);
    for (final otherId in otherIds) {
      final closed = await closeTab(
        otherId,
        resolveDirty: resolveDirty,
        saveDirty: saveDirty,
        discardDirty: discardDirty,
      );
      if (!closed) break;
    }
    selectTab(tabId);
  }

  Future<bool> resolveDirtyTab(
    String tabId, {
    required DirtyCloseResolver resolveDirty,
    required DirtyTabSaver saveDirty,
    DirtyTabDiscarder? discardDirty,
  }) async {
    final tab = _state.tabs[_tabIndex(tabId)];
    if (!tab.hasDirtyForms) return true;
    final decision = await resolveDirty(tab);
    if (decision == DirtyCloseDecision.cancel) return false;
    try {
      if (decision == DirtyCloseDecision.save) {
        await saveDirty(tab);
        _clearDirtyForms(tabId, discard: false);
      } else {
        await discardDirty?.call(tab);
        _clearDirtyForms(tabId, discard: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void updateCurrentView(String tabId, ContextViewState viewState) {
    _updateTab(tabId, (tab) {
      final routes = [...tab.routeStack];
      routes[routes.length - 1] = routes.last.copyWith(viewState: viewState);
      return tab.copyWith(routeStack: routes);
    });
  }

  /// Replaces a lateral section root without adding it to chronological
  /// history. Entity drill-downs are pushed on top of this route, so Back
  /// returns to the section the user was actually viewing.
  void replaceCurrentLink(
    String tabId,
    EntityLink link, {
    ContextViewState? viewState,
  }) {
    _requireSupported(link);
    _updateTab(tabId, (tab) {
      final routes = [...tab.routeStack];
      routes[routes.length - 1] = routes.last.copyWith(
        link: link,
        viewState: viewState ?? ContextViewState(),
      );
      return tab.copyWith(
        titleHint: _titleFor(link),
        routeStack: routes,
        forwardStack: const [],
      );
    });
  }

  void updateEntityTitle(EntityLink link, String title) {
    final normalized = title.trim();
    if (normalized.isEmpty) return;
    final tabs = [
      for (final tab in _state.tabs)
        _sameEntity(tab.currentRoute.link, link)
            ? tab.copyWith(titleHint: normalized)
            : tab,
    ];
    if (listEquals(tabs, _state.tabs)) return;
    _state = _state.copyWith(tabs: tabs);
    notifyListeners();
  }

  void registerForm(
    String tabId,
    String formKey, {
    int? expectedVersion,
    Map<String, Object?> draft = const {},
    WorkspaceFormSaver? onSave,
    VoidCallback? onDiscard,
  }) {
    _formActions[_formActionKey(tabId, formKey)] = _WorkspaceFormActions(
      save: onSave,
      discard: onDiscard,
    );
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
    _formActions.remove(_formActionKey(tabId, formKey));
    _updateTab(tabId, (tab) {
      if (!tab.forms.containsKey(formKey)) return tab;
      final forms = {...tab.forms}..remove(formKey);
      return tab.copyWith(forms: forms);
    });
  }

  Future<void> saveDirtyForms(WorkspaceTabState tab) async {
    for (final form in tab.forms.values.where((form) => form.dirty)) {
      final save = _formActions[_formActionKey(tab.tabId, form.formKey)]?.save;
      if (save == null || !await save()) {
        throw StateError('Form "${form.formKey}" was not saved.');
      }
    }
  }

  Future<void> discardDirtyForms(WorkspaceTabState tab) async {
    for (final form in tab.forms.values.where((form) => form.dirty)) {
      _formActions[_formActionKey(tab.tabId, form.formKey)]?.discard?.call();
    }
  }

  void _clearDirtyForms(String tabId, {required bool discard}) {
    if (!_state.tabs.any((tab) => tab.tabId == tabId)) return;
    _updateTab(tabId, (tab) {
      final forms = {
        for (final entry in tab.forms.entries)
          entry.key: entry.value.dirty
              ? entry.value.copyWith(
                  dirty: false,
                  draft: discard ? const {} : entry.value.draft,
                  clearConflict: discard,
                )
              : entry.value,
      };
      return tab.copyWith(forms: forms);
    });
  }

  void markFormConflict(
    String tabId,
    String formKey, {
    required int serverVersion,
    required String source,
  }) {
    _updateTab(tabId, (tab) {
      final current = tab.forms[formKey];
      if (current == null || !current.dirty) return tab;
      return tab.copyWith(
        forms: {
          ...tab.forms,
          formKey: current.copyWith(
            conflict: WorkspaceFormConflict(
              serverVersion: serverVersion,
              source: source,
            ),
          ),
        },
      );
    });
  }

  void reloadConflictedForm(
    String tabId,
    String formKey, {
    required int serverVersion,
    Map<String, Object?> serverDraft = const {},
  }) {
    _resolveFormConflict(
      tabId,
      formKey,
      serverVersion: serverVersion,
      draft: serverDraft,
      dirty: false,
    );
  }

  void mergeConflictedForm(
    String tabId,
    String formKey, {
    required int serverVersion,
    required Map<String, Object?> mergedDraft,
  }) {
    _resolveFormConflict(
      tabId,
      formKey,
      serverVersion: serverVersion,
      draft: mergedDraft,
      dirty: true,
    );
  }

  void _resolveFormConflict(
    String tabId,
    String formKey, {
    required int serverVersion,
    required Map<String, Object?> draft,
    required bool dirty,
  }) {
    _updateTab(tabId, (tab) {
      final current = tab.forms[formKey];
      if (current == null || current.conflict == null) {
        throw StateError('Form "$formKey" has no active conflict.');
      }
      return tab.copyWith(
        forms: {
          ...tab.forms,
          formKey: current.copyWith(
            dirty: dirty,
            expectedVersion: serverVersion,
            clearConflict: true,
            draft: draft,
          ),
        },
      );
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

  String _titleFor(EntityLink link) =>
      _titleResolver?.call(link) ?? _defaultTitle(link);

  static void _requireSupported(EntityLink link) {
    if (!link.isSupported) {
      throw const FormatException('Unsupported workspace route.');
    }
  }

  static int _nextAvailableTabNumber(List<WorkspaceTabState> tabs) {
    var maximum = 0;
    for (final tab in tabs) {
      final match = RegExp(r'^tab-(\d+)$').firstMatch(tab.tabId);
      final value = int.tryParse(match?.group(1) ?? '');
      if (value != null && value > maximum) maximum = value;
    }
    return maximum + 1;
  }

  static String _formActionKey(String tabId, String formKey) =>
      '$tabId:$formKey';
}
