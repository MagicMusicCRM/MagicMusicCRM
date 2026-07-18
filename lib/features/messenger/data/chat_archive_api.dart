import 'package:magic_music_crm/core/api/magic_api_client.dart';

/// Архивация чата по закреплённому контракту №3:
/// `PATCH /api/chats/:chatId/archive` с телом `{archived: boolean}` → `{ok:true}`.
///
/// Живёт расширением на [MagicApiClient] в папке фичи (общие core-файлы не
/// трогаем — так договорились параллельные агенты).
extension ChatArchiveApi on MagicApiClient {
  Future<Map<String, dynamic>> setChatArchived(
    String chatId, {
    required bool archived,
  }) {
    return patch<Map<String, dynamic>>(
      '/chats/$chatId/archive',
      data: {'archived': archived},
    );
  }
}
