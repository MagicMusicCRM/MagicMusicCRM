import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_messenger_service.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/widgets/telegram/avatar_widget.dart';

enum _ChannelAccess { none, read, write }

/// Creates a channel or edits its title, description and complete ACL.
///
/// Channel publishing rights are intentionally separate from management:
/// a teacher may be granted `write`, but only administration roles can open
/// this editor or change its permission rules.
class ChannelEditorDialog extends ConsumerStatefulWidget {
  final String? channelId;
  final String initialTitle;
  final String initialDescription;

  const ChannelEditorDialog({
    super.key,
    this.channelId,
    this.initialTitle = '',
    this.initialDescription = '',
  });

  bool get isEditing => channelId != null;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    String? channelId,
    String initialTitle = '',
    String initialDescription = '',
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ChannelEditorDialog(
        channelId: channelId,
        initialTitle: initialTitle,
        initialDescription: initialDescription,
      ),
    );
  }

  @override
  ConsumerState<ChannelEditorDialog> createState() =>
      _ChannelEditorDialogState();
}

class _ChannelEditorDialogState extends ConsumerState<ChannelEditorDialog> {
  static const _roles = <String>[
    'client',
    'teacher',
    'admin',
    'manager',
    'director',
    'system_admin',
  ];

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  final _searchController = TextEditingController();
  final Map<String, _ChannelAccess> _access = {};
  List<Map<String, dynamic>> _users = const [];
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profilesFuture = ref
          .read(magicProfileAdminServiceProvider)
          .listProfiles(limit: 100);
      final permissionsFuture = widget.channelId == null
          ? Future.value(const <Map<String, dynamic>>[])
          : ref
                .read(magicMessengerServiceProvider)
                .listChannelPermissions(widget.channelId!);
      final results = await Future.wait([profilesFuture, permissionsFuture]);
      final profiles = results[0];
      final permissions = results[1];
      final usersById = <String, Map<String, dynamic>>{
        for (final profile in profiles)
          if (profile['user_id']?.toString().isNotEmpty == true)
            profile['user_id'].toString(): profile,
      };
      for (final permission in permissions) {
        final target = permission['user_id']?.toString().isNotEmpty == true
            ? 'user:${permission['user_id']}'
            : 'role:${permission['role']}';
        _access[target] = permission['can_write'] == true
            ? _ChannelAccess.write
            : _ChannelAccess.read;
        final userId = permission['user_id']?.toString();
        if (userId != null &&
            userId.isNotEmpty &&
            !usersById.containsKey(userId)) {
          final profile = permission['profiles'];
          usersById[userId] = {
            'user_id': userId,
            'email': profile is Map ? profile['email'] : null,
            'first_name': profile is Map ? profile['first_name'] : null,
            'last_name': profile is Map ? profile['last_name'] : null,
            'role': null,
          };
        }
      }
      if (!mounted) return;
      setState(() {
        _users = usersById.values.toList()
          ..sort((a, b) => _userName(a).compareTo(_userName(b)));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  String _userName(Map<String, dynamic> user) {
    final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'
        .trim();
    if (name.isNotEmpty) return name;
    return user['email']?.toString().trim().isNotEmpty == true
        ? user['email'].toString()
        : 'Пользователь';
  }

  String _roleLabel(String role) => switch (role) {
    'client' => 'Клиенты',
    'teacher' => 'Преподаватели',
    'admin' => 'Администраторы',
    'manager' => 'Управляющие',
    'director' => 'Директора',
    'system_admin' => 'Администраторы системы',
    _ => role,
  };

  String _accessLabel(_ChannelAccess access) => switch (access) {
    _ChannelAccess.none => 'Нет доступа',
    _ChannelAccess.read => 'Чтение',
    _ChannelAccess.write => 'Чтение и публикация',
  };

  List<Map<String, dynamic>> _permissionPayload() {
    final result = <Map<String, dynamic>>[];
    for (final entry in _access.entries) {
      if (entry.value == _ChannelAccess.none) continue;
      final separator = entry.key.indexOf(':');
      final kind = entry.key.substring(0, separator);
      final value = entry.key.substring(separator + 1);
      result.add({
        if (kind == 'user') 'userId': value else 'role': value,
        'canRead': true,
        'canWrite': entry.value == _ChannelAccess.write,
      });
    }
    return result;
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Укажите название канала')));
      return;
    }
    setState(() => _saving = true);
    try {
      final messenger = ref.read(magicMessengerServiceProvider);
      final permissions = _permissionPayload();
      final result = widget.channelId == null
          ? await messenger.createChannel(
              title: title,
              description: _descriptionController.text,
              permissions: permissions,
            )
          : await messenger.updateChannel(
              widget.channelId!,
              title: title,
              description: _descriptionController.text,
              permissions: permissions,
            );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(error, fallback: 'Не удалось сохранить канал.'),
          ),
          backgroundColor: TelegramColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _accessSelector(String target) {
    final value = _access[target] ?? _ChannelAccess.none;
    return DropdownButton<_ChannelAccess>(
      key: ValueKey('channel-access-$target'),
      value: value,
      underline: const SizedBox.shrink(),
      onChanged: _saving
          ? null
          : (next) => setState(() {
              _access[target] = next ?? _ChannelAccess.none;
            }),
      items: _ChannelAccess.values
          .map(
            (access) => DropdownMenuItem(
              value: access,
              child: Text(_accessLabel(access)),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final users = query.isEmpty
        ? _users
        : _users.where((user) {
            final haystack = '${_userName(user)} ${user['email'] ?? ''}'
                .toLowerCase();
            return haystack.contains(query);
          }).toList();

    return Dialog(
      child: SizedBox(
        width: 680,
        height: 720,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isEditing ? 'Настройки канала' : 'Новый канал',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('channel-title'),
                    controller: _titleController,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      prefixIcon: Icon(Icons.campaign_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('channel-description'),
                    controller: _descriptionController,
                    maxLength: 1000,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Описание'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          userErrorText(
                            _loadError ?? '',
                            fallback: 'Не удалось загрузить права доступа.',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      children: [
                        const Text(
                          'Доступ по ролям',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        ..._roles.map(
                          (role) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.groups_2_outlined),
                            title: Text(_roleLabel(role)),
                            trailing: _accessSelector('role:$role'),
                          ),
                        ),
                        const Divider(height: 28),
                        const Text(
                          'Индивидуальный доступ',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          key: const ValueKey('channel-user-search'),
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: 'Поиск пользователя',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        if (users.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: Text('Пользователи не найдены'),
                            ),
                          ),
                        ...users.map((user) {
                          final userId = user['user_id'].toString();
                          final name = _userName(user);
                          return ListTile(
                            dense: true,
                            leading: TelegramAvatar(
                              name: name,
                              uniqueId: userId,
                              radius: 18,
                            ),
                            title: Text(name),
                            subtitle: Text(
                              _roleLabel(user['role']?.toString() ?? ''),
                            ),
                            trailing: _accessSelector('user:$userId'),
                          );
                        }),
                      ],
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const ValueKey('save-channel'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(widget.isEditing ? 'Сохранить' : 'Создать'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
