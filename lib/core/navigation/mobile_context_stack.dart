import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';

class MobileContextStackState {
  const MobileContextStackState({
    this.entries = const [],
    this.pendingDeepLink,
    this.awaitingAuthentication = false,
  });

  final List<ContextRouteState> entries;
  final EntityLink? pendingDeepLink;
  final bool awaitingAuthentication;

  ContextRouteState? get current => entries.isEmpty ? null : entries.last;
  bool get canPop => entries.length > 1;

  MobileContextStackState copyWith({
    List<ContextRouteState>? entries,
    EntityLink? pendingDeepLink,
    bool clearPendingDeepLink = false,
    bool? awaitingAuthentication,
  }) {
    return MobileContextStackState(
      entries: List.unmodifiable(entries ?? this.entries),
      pendingDeepLink: clearPendingDeepLink
          ? null
          : pendingDeepLink ?? this.pendingDeepLink,
      awaitingAuthentication:
          awaitingAuthentication ?? this.awaitingAuthentication,
    );
  }

  List<Map<String, dynamic>> serialize() {
    return entries.map((entry) => entry.toJson()).toList(growable: false);
  }
}

class MobileContextStackController extends Notifier<MobileContextStackState> {
  @override
  MobileContextStackState build() => const MobileContextStackState();

  void start(EntityLink root) {
    state = MobileContextStackState(
      entries: [
        ContextRouteState(link: root, viewState: ContextViewState()),
      ],
    );
  }

  void restore(List<Map<String, dynamic>> serialized) {
    final entries = <ContextRouteState>[];
    for (final item in serialized) {
      final entry = ContextRouteState.fromJson(item);
      if (!entry.link.isSupported) {
        throw const FormatException('Unsupported context route.');
      }
      entries.add(entry);
    }
    state = MobileContextStackState(entries: List.unmodifiable(entries));
  }

  void updateCurrentView(ContextViewState viewState) {
    if (state.entries.isEmpty) return;
    final next = [...state.entries];
    next[next.length - 1] = next.last.copyWith(viewState: viewState);
    state = state.copyWith(entries: next);
  }

  void push(
    EntityLink target, {
    ContextViewState? currentViewState,
  }) {
    if (!target.isSupported) {
      throw const FormatException('Unsupported context route.');
    }
    final next = [...state.entries];
    if (next.isNotEmpty && currentViewState != null) {
      next[next.length - 1] = next.last.copyWith(
        viewState: currentViewState,
      );
    }
    next.add(
      ContextRouteState(link: target, viewState: ContextViewState()),
    );
    state = state.copyWith(entries: next);
  }

  ContextRouteState? pop() {
    if (!state.canPop) return null;
    final removed = state.entries.last;
    state = state.copyWith(
      entries: state.entries.sublist(0, state.entries.length - 1),
    );
    return removed;
  }

  void openAuthenticatedDeepLink({
    required EntityLink home,
    required EntityLink target,
    required bool authenticated,
  }) {
    if (!target.isSupported || !home.isSupported) {
      throw const FormatException('Unsupported deep link.');
    }
    if (!authenticated) {
      state = MobileContextStackState(
        entries: state.entries,
        pendingDeepLink: target,
        awaitingAuthentication: true,
      );
      return;
    }
    state = MobileContextStackState(
      entries: [
        ContextRouteState(link: home, viewState: ContextViewState()),
        ContextRouteState(link: target, viewState: ContextViewState()),
      ],
    );
  }

  void completeAuthentication(EntityLink home) {
    final pending = state.pendingDeepLink;
    if (pending == null) {
      start(home);
      return;
    }
    state = MobileContextStackState(
      entries: [
        ContextRouteState(link: home, viewState: ContextViewState()),
        ContextRouteState(link: pending, viewState: ContextViewState()),
      ],
    );
  }

  void clear() {
    state = const MobileContextStackState();
  }
}

final mobileContextStackProvider =
    NotifierProvider<MobileContextStackController, MobileContextStackState>(
      MobileContextStackController.new,
    );
