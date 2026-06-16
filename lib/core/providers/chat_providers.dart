import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/services/magic_realtime_service.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';

// ── Current user info ────────────────────────────────────────────────────────

final currentProfileProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final profile = await ref.watch(magicAuthServiceProvider).currentProfile();
  return {
    'id': profile.userId,
    'user_id': profile.userId,
    'email': profile.email,
    'role': profile.role,
    'first_name': profile.firstName,
    'last_name': profile.lastName,
    'phone': profile.phone,
    'dob': profile.dob,
    'avatar_file_id': profile.avatarFileId,
    'email_otp_2fa_enabled': profile.emailOtp2faEnabled,
  };
});

final currentRoleProvider = FutureProvider<String>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  return (profile?['role'] as String?) ?? 'client';
});

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

final adminIdsProvider = FutureProvider<List<String>>((ref) async {
  final profiles = await ref
      .watch(magicProfileAdminServiceProvider)
      .listProfiles(limit: 100);
  return profiles
      .where((profile) {
        final role = profile['role']?.toString();
        return role == 'admin' || role == 'manager' || role == 'system_admin';
      })
      .map((profile) => profile['user_id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toList();
});

// ── Chats ────────────────────────────────────────────────────────────────────

final clientConversationsProvider = StreamProvider<List<Map<String, dynamic>>>((
  ref,
) async* {
  final chats = await ref
      .watch(magicMessengerServiceProvider)
      .listChats(limit: 100);
  yield chats
      .where(
        (chat) => chat['type'] == 'direct' || chat['type'] == 'administration',
      )
      .toList();
});

final conversationMessagesProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String?>((
      ref,
      partnerId,
    ) async* {
      final messenger = ref.watch(magicMessengerServiceProvider);
      final chat = partnerId == null
          ? await messenger.ensureAdministrationChat()
          : await messenger.ensureDirectChat(partnerId);
      final chatId = chat['id']?.toString();
      if (chatId == null || chatId.isEmpty) {
        yield const <Map<String, dynamic>>[];
        return;
      }
      yield await messenger.listMessages(chatId, limit: 100);
    });

final userGroupChatsProvider = StreamProvider<List<Map<String, dynamic>>>((
  ref,
) async* {
  final chats = await ref
      .watch(magicMessengerServiceProvider)
      .listChats(limit: 100);
  yield chats
      .where((chat) => chat['type'] == 'group')
      .map(
        (chat) => {
          ...chat,
          '_type': 'group',
          '_item_type': 'group',
          '_display_name': chat['title'] ?? 'Группа',
          'name': chat['title'] ?? 'Группа',
        },
      )
      .toList();
});

final groupMessagesProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      groupChatId,
    ) async* {
      yield await ref
          .watch(magicMessengerServiceProvider)
          .listMessages(groupChatId, limit: 100);
    });

final groupMembersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      groupChatId,
    ) async {
      return ref
          .watch(magicMessengerServiceProvider)
          .listChatMembers(groupChatId);
    });

// ── Presence ─────────────────────────────────────────────────────────────────

final chatPresenceProvider = StreamProvider.family<List<String>, String>((
  ref,
  chatId,
) {
  final controller = StreamController<List<String>>();
  final onlineUserIds = <String>{};
  MagicRealtimeConnection? connection;

  unawaited(
    Future<void>(() async {
      try {
        final profile = await ref
            .read(magicAuthServiceProvider)
            .currentProfile();
        connection = await ref.read(magicRealtimeServiceProvider).connect();
        connection?.joinChat(chatId);
        connection?.updatePresence();
        connection?.onPresenceUpdated((payload) {
          final userId = payload['userId']?.toString();
          if (userId == null || userId == profile.userId) return;
          final status = payload['status']?.toString();
          if (status == 'offline') {
            onlineUserIds.remove(userId);
          } else {
            onlineUserIds.add(userId);
          }
          if (!controller.isClosed) {
            controller.add(List<String>.unmodifiable(onlineUserIds));
          }
        });
        if (!controller.isClosed) {
          controller.add(const <String>[]);
        }
      } catch (_) {
        if (!controller.isClosed) {
          controller.add(const <String>[]);
        }
      }
    }),
  );

  ref.onDispose(() {
    connection?.leaveRoom(chatId);
    connection?.dispose();
    unawaited(controller.close());
  });

  return controller.stream;
});

// ── Channels ─────────────────────────────────────────────────────────────────

final channelsProvider = StreamProvider<List<Map<String, dynamic>>>((
  ref,
) async* {
  yield await ref.watch(magicMessengerServiceProvider).listChannels();
});

final channelPostsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      channelId,
    ) async* {
      yield await ref
          .watch(magicMessengerServiceProvider)
          .listChannelPosts(channelId, limit: 100);
    });

final channelUserPermissionProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((
      ref,
      channelId,
    ) async {
      return ref
          .watch(magicMessengerServiceProvider)
          .getChannelAccess(channelId);
    });

final channelAllPermissionsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      channelId,
    ) async {
      return ref
          .watch(magicMessengerServiceProvider)
          .listChannelPermissions(channelId);
    });

final allProfilesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(magicProfileAdminServiceProvider).listProfiles(limit: 100);
});
