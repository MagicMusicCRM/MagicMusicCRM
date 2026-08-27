import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';
import 'package:magic_music_crm/core/widgets/telegram/chat_info_models.dart';

export 'chat_info_add_members_dialog.dart';

Future<bool> showChatInfoLeaveConfirmation(BuildContext context) async {
  return _showChatInfoDangerConfirmation(
    context,
    title: 'Выйти из группы',
    content: const Text('Вы уверены, что хотите выйти из этой группы?'),
    confirmLabel: 'Выйти',
  );
}

Future<bool> showChatInfoRemoveConfirmation(
  BuildContext context,
  String name,
) async {
  return _showChatInfoDangerConfirmation(
    context,
    title: 'Удалить из группы',
    content: Text('Удалить $name из группы? История сообщений сохранится.'),
    confirmLabel: 'Удалить',
  );
}

Future<bool> _showChatInfoDangerConfirmation(
  BuildContext context, {
  required String title,
  required Widget content,
  required String confirmLabel,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: content,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                confirmLabel,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ) ??
      false;
}

Future<String?> showChatInfoNoteEditor(BuildContext context) async {
  return showDialog<String>(
    context: context,
    builder: (_) => const _ChatInfoNoteEditorDialog(),
  );
}

class _ChatInfoNoteEditorDialog extends StatefulWidget {
  const _ChatInfoNoteEditorDialog();

  @override
  State<_ChatInfoNoteEditorDialog> createState() =>
      _ChatInfoNoteEditorDialogState();
}

class _ChatInfoNoteEditorDialogState extends State<_ChatInfoNoteEditorDialog> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Добавить заметку'),
    content: TextField(
      controller: _textController,
      autofocus: true,
      maxLines: 5,
      minLines: 3,
      decoration: const InputDecoration(hintText: 'Введите текст заметки'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      ElevatedButton(
        onPressed: () => Navigator.pop(context, _textController.text.trim()),
        child: const Text('Добавить'),
      ),
    ],
  );
}

class ChatInfoMembersDialog extends StatelessWidget {
  const ChatInfoMembersDialog({
    super.key,
    required this.members,
    required this.canManageGroup,
  });

  final List<Map<String, dynamic>> members;
  final bool canManageGroup;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Участники (${members.length})'),
    content: SizedBox(
      width: 480,
      height: 480,
      child: ListView.builder(
        itemCount: members.length,
        itemBuilder: (_, index) {
          final member = members[index];
          final name = member['_display_name']?.toString() ?? 'Участник';
          final canRemove = canManageGroup && member['is_current_user'] != true;
          return ListTile(
            leading: TelegramAvatar(
              name: name,
              uniqueId: member['user_id']?.toString() ?? name,
              radius: 18,
            ),
            title: Text(name),
            subtitle: Text(
              member['role'] == 'admin'
                  ? 'Администратор группы'
                  : chatInfoRoleLabel(
                      member['user_role']?.toString() ?? 'client',
                    ),
            ),
            trailing: canRemove
                ? IconButton(
                    tooltip: 'Удалить из группы',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () => Navigator.pop(context, member),
                  )
                : null,
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Закрыть'),
      ),
    ],
  );
}
