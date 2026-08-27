import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_controller.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_models.dart';

import 'messenger_test_api.dart';

class _DelayedChatInfoApi extends RecordingFakeApiClient {
  final chatResponse = Completer<Map<String, dynamic>>();
  List<Map<String, dynamic>> members = const [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) {
    if (path == '/messenger/chats/direct-1') {
      return chatResponse.future.then((response) => response as T);
    }
    if (path == '/messenger/chats/direct-1/members') {
      return Future<T>.value(<String, dynamic>{'items': members} as T);
    }
    if (path == '/messenger/chats/direct-1/messages') {
      return Future<T>.value(<String, dynamic>{'items': <dynamic>[]} as T);
    }
    return super.get<T>(
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
    );
  }
}

ChatInfoController _controller(
  _DelayedChatInfoApi api, {
  ChatInfoRequest request = const ChatInfoRequest(
    chatType: 'direct',
    chatId: 'direct-1',
    userRole: 'teacher',
  ),
}) {
  return ChatInfoController(
    request: request,
    initialIsMuted: false,
    messenger: MagicMessengerService(api),
    profiles: MagicProfileAdminService(api),
    settings: MagicSettingsService(api),
  );
}

void main() {
  test('late load success cannot mutate or notify after dispose', () async {
    final api = _DelayedChatInfoApi();
    final controller = _controller(api);
    var notificationCount = 0;
    controller.addListener(() => notificationCount++);

    final load = controller.load();
    final snapshotAtDispose = controller.snapshot;
    expect(notificationCount, 1);
    expect(snapshotAtDispose.loading, isTrue);
    controller.dispose();

    api.chatResponse.complete({
      'id': 'direct-1',
      'type': 'direct',
      'isMuted': false,
    });

    await expectLater(load, completes);
    expect(controller.snapshot, same(snapshotAtDispose));
    expect(notificationCount, 1);
  });

  test('late load error cannot mutate or notify after dispose', () async {
    final api = _DelayedChatInfoApi();
    final controller = _controller(api);
    var notificationCount = 0;
    controller.addListener(() => notificationCount++);

    final load = controller.load();
    final snapshotAtDispose = controller.snapshot;
    expect(notificationCount, 1);
    expect(snapshotAtDispose.loading, isTrue);
    controller.dispose();

    api.chatResponse.completeError(StateError('late failure'));

    await expectLater(load, completes);
    expect(controller.snapshot, same(snapshotAtDispose));
    expect(notificationCount, 1);
  });

  test('pending load cannot overwrite a newer optimistic mute', () async {
    final api = _DelayedChatInfoApi();
    final controller = _controller(api);
    addTearDown(controller.dispose);

    final load = controller.load();
    await controller.setMuted(true, null);
    expect(controller.snapshot.isMuted, isTrue);

    api.chatResponse.complete({
      'id': 'direct-1',
      'type': 'direct',
      'isMuted': false,
    });
    await load;

    expect(controller.snapshot.isMuted, isTrue);
  });

  test('disposed controllers cannot start new service I/O', () async {
    final groupApi = _DelayedChatInfoApi();
    final groupController = _controller(
      groupApi,
      request: const ChatInfoRequest(
        chatType: 'group',
        chatId: 'group-1',
        userRole: 'manager',
      ),
    );
    groupController.dispose();

    await groupController.addMembers({'user-2'});
    await groupController.removeMember('user-2');
    await groupController.leaveGroup();
    await expectLater(
      groupController.ensureDirectChat('user-2'),
      throwsStateError,
    );
    expect(await groupController.listProfilesForMembership(), isEmpty);
    expect(groupApi.calls, isEmpty);

    final directApi = _DelayedChatInfoApi()
      ..members = const [
        {'profileId': 'profile-2', 'userId': 'user-2', 'isCurrentUser': false},
      ];
    final directController = _controller(
      directApi,
      request: const ChatInfoRequest(
        chatType: 'direct',
        chatId: 'direct-1',
        userRole: 'manager',
      ),
    );
    final load = directController.load();
    directApi.chatResponse.complete({
      'id': 'direct-1',
      'type': 'direct',
      'isMuted': false,
    });
    await load;
    directApi.calls.clear();
    directController.dispose();

    await expectLater(directController.createNote('note'), throwsStateError);
    expect(directApi.calls, isEmpty);
  });
}
