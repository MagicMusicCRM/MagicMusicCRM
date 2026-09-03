part of 'messenger_screen.dart';

extension _MessengerPinnedMessages on _MessengerScreenState {
  Widget _buildPinnedBar() {
    if (_pinnedMessages.isEmpty ||
        _hiddenPinnedBars.contains(_selectedChatId)) {
      return const SizedBox.shrink();
    }

    final lastPinned = _pinnedMessages.first;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content =
        lastPinned['content']?.toString() ??
        (lastPinned['message_type'] == 'file' ? '📁 Файл' : 'Вложение');

    return Container(
      width: double.infinity,
      color: cs.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_pinnedMessages.length == 1) {
              _jumpToMessage(_pinnedMessages.first['id'].toString());
            } else {
              _showPinnedMessagesDialog();
            }
          },
          child: Row(
            children: [
              Container(
                width: 2,
                height: 35,
                decoration: BoxDecoration(
                  color: AppColor.gold,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _pinnedMessages.length > 1
                          ? 'Закрепленные сообщения'
                          : 'Закрепленное сообщение',
                      style: const TextStyle(
                        color: AppColor.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface.withAlpha(isDark ? 178 : 222),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (_pinnedMessages.length > 1)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.xs + 2,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColor.goldSoft,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      '${_pinnedMessages.length}',
                      style: const TextStyle(
                        color: AppColor.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'Скрыть панель',
                onPressed: () {
                  if (_selectedChatId != null) {
                    _emitState(() => _hiddenPinnedBars.add(_selectedChatId!));
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPinnedMessagesDialog() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showMagicDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          _pinnedDialogSetState = setDialogState;

          return AlertDialog(
            backgroundColor: cs.surface,
            title: const Row(
              children: [
                Icon(Icons.pin_drop_rounded, color: AppColor.gold),
                SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    'Закрепленные сообщения',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: _pinnedMessages.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('Пусто', textAlign: TextAlign.center),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _pinnedMessages.length,
                      separatorBuilder: (_, _) => Divider(
                        color: isDark
                            ? AppColor.divider
                            : TelegramColors.lightDivider,
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final msg = _pinnedMessages[index];
                        final content =
                            msg['content']?.toString() ??
                            (msg['message_type'] == 'file'
                                ? '📁 Файл'
                                : 'Сообщение');

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          title: Text(
                            content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Открепить',
                            onPressed: () async {
                              await _togglePin(msg['id'].toString(), false);
                              if (_pinnedMessages.isEmpty) {
                                if (context.mounted) Navigator.pop(context);
                              } else {
                                setDialogState(() {});
                              }
                            },
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _jumpToMessage(msg['id'].toString());
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _pinnedDialogSetState = null;
                  Navigator.pop(context);
                },
                child: const Text('Закрыть'),
              ),
            ],
          );
        },
      ),
    ).then((_) => _pinnedDialogSetState = null);
  }

  Future<void> _fetchPinnedMessages() async {
    if (_selectedChatId == null) return;
    final pinned = _messages
        .where((message) => message['pinned_at'] != null)
        .toList()
        .reversed
        .toList();
    if (mounted) {
      _emitState(() => _pinnedMessages = pinned);
      if (_pinnedDialogSetState != null) {
        _pinnedDialogSetState!(() {});
      }
    }
  }

  Future<void> _togglePin(String messageId, bool pin) async {
    try {
      final messenger = ref.read(magicMessengerServiceProvider);
      final updated = pin
          ? await messenger.pinMessage(messageId)
          : await messenger.unpinMessage(messageId);
      if (mounted) {
        _emitState(() {
          final index = _messages.indexWhere((m) => m['id'] == messageId);
          if (index != -1) _messages[index] = updated;
        });
      }
      await _fetchPinnedMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось закрепить сообщение.'),
            ),
          ),
        );
      }
    }
  }

  void _jumpToMessage(String messageId) {
    if (_messagesActionKey.currentState != null) {
      _messagesActionKey.currentState!._jumpToMessage(messageId);
    }
  }
}
