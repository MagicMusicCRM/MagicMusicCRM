import 'package:flutter_riverpod/flutter_riverpod.dart';

class MessengerNavigationState {
  final String? partnerId;
  final String? groupChatId;

  const MessengerNavigationState({this.partnerId, this.groupChatId});
}

class MessengerNavigationNotifier extends Notifier<MessengerNavigationState?> {
  @override
  MessengerNavigationState? build() => null;

  void navigateTo(MessengerNavigationState? newState) => state = newState;

  void clear() => state = null;
}

final messengerNavigationProvider =
    NotifierProvider<MessengerNavigationNotifier, MessengerNavigationState?>(
      MessengerNavigationNotifier.new,
    );
