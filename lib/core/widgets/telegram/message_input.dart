import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show File, Platform;
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/widgets/voice_recorder_widget.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:file_picker/file_picker.dart';

/// Telegram-style message input bar with text field, attachment, and voice recording.
class MessageInput extends StatefulWidget {
  final Future<void> Function(
    String text, {
    String? replyToId,
    String? editingMessageId,
  })
  onSendText;
  final Future<void> Function(Uint8List bytes, int durationMs, String ext)?
  onSendVoice;
  final Future<void> Function(
    Uint8List bytes,
    String fileName,
    int fileSize, {
    String? caption,
  })?
  onSendFile;
  final void Function(bool isTyping)? onTyping;
  final bool enabled;
  final Map<String, dynamic>? replyingTo;
  final Map<String, dynamic>? editingMessage;
  final VoidCallback? onCancelMode;

  const MessageInput({
    super.key,
    required this.onSendText,
    this.onSendVoice,
    this.onSendFile,
    this.onTyping,
    this.enabled = true,
    this.replyingTo,
    this.editingMessage,
    this.onCancelMode,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isRecording = false;
  bool _isSendingFile = false;
  bool _hasText = false;
  bool _showEmojiPicker = false;
  DateTime? _lastTypingTime;

  bool get _isDesktop {
    try {
      return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final text = _controller.text;
      final hasText = text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }

      // Typing indicator logic
      if (widget.onTyping != null && text.isNotEmpty) {
        final now = DateTime.now();
        if (_lastTypingTime == null ||
            now.difference(_lastTypingTime!) > const Duration(seconds: 2)) {
          _lastTypingTime = now;
          widget.onTyping!(true);
        }
      }
    });

    // Tapping the text field while the emoji panel is open should close the
    // panel, so the keyboard and emoji panel never both occupy space (KVA-172).
    _focusNode.addListener(_handleFocusChange);

    if (widget.editingMessage != null) {
      _controller.text = widget.editingMessage!['content'] ?? '';
    }
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus && _showEmojiPicker && mounted) {
      setState(() => _showEmojiPicker = false);
    }
  }

  @override
  void didUpdateWidget(MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editingMessage != oldWidget.editingMessage &&
        widget.editingMessage != null) {
      _controller.text = widget.editingMessage!['content'] ?? '';
      _focusNode.requestFocus();
    }
    if (widget.replyingTo != oldWidget.replyingTo &&
        widget.replyingTo != null) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final replyId = widget.replyingTo?['id']?.toString();
    final editId = widget.editingMessage?['id']?.toString();

    _controller.clear();
    setState(() => _hasText = false);

    await widget.onSendText(text, replyToId: replyId, editingMessageId: editId);

    if (widget.onCancelMode != null && (replyId != null || editId != null)) {
      widget.onCancelMode!();
    }

    _focusNode.requestFocus();
  }

  // ... (pickAndSendFile and handleKeyEvent remain similar but check widget.enabled)

  /// Open a chooser so the user picks the image gallery or a generic file,
  /// then route to the matching picker. Falls back to the file picker if the
  /// sheet is dismissed without a choice.
  Future<void> _openAttachMenu() async {
    if (_isSendingFile || widget.onSendFile == null || !widget.enabled) return;
    final choice = await showMagicSheet<_AttachSource>(
      context,
      title: 'Вложение',
      subtitle: 'Выберите тип файла',
      icon: Icons.attach_file_rounded,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AttachOption(
            icon: Icons.image_rounded,
            label: 'Фото из галереи',
            onTap: () => Navigator.of(sheetContext).pop(_AttachSource.image),
          ),
          const SizedBox(height: AppSpace.sm),
          _AttachOption(
            icon: Icons.insert_drive_file_rounded,
            label: 'Файл',
            onTap: () => Navigator.of(sheetContext).pop(_AttachSource.file),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await _pickAndSendFile(
      choice == _AttachSource.image ? FileType.image : FileType.any,
    );
  }

  Future<void> _pickAndSendFile(FileType pickerType) async {
    if (_isSendingFile || widget.onSendFile == null) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: pickerType,
        withData: false,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.size > ChatAttachmentService.maxFileSizeBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Файл слишком большой (макс. 25 МБ)'),
              backgroundColor: AppColor.danger,
            ),
          );
        }
        return;
      }
      final bytes = file.bytes ?? await _readPickedFileBytes(file);
      if (bytes == null) return;
      setState(() => _isSendingFile = true);
      await widget.onSendFile!(bytes, file.name, file.size);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось добавить файл.'),
            ),
            backgroundColor: AppColor.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingFile = false);
    }
  }

  Future<Uint8List?> _readPickedFileBytes(PlatformFile file) async {
    final path = file.path;
    if (path == null || path.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось прочитать файл'),
            backgroundColor: AppColor.danger,
          ),
        );
      }
      return null;
    }
    return File(path).readAsBytes();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_isDesktop) return KeyEventResult.ignored;
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored; // Allow newline
      }
      _sendMessage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isRecording && widget.onSendVoice != null) {
      return VoiceRecorderWidget(
        onVoiceRecorded: (bytes, durationMs, ext) async {
          await widget.onSendVoice!(bytes, durationMs, ext);
        },
        onCancel: () {
          if (mounted) setState(() => _isRecording = false);
        },
      );
    }

    final isModeActive =
        widget.replyingTo != null || widget.editingMessage != null;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColor.surface : TelegramColors.lightBg,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColor.divider : TelegramColors.lightDivider,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        // When the emoji panel is open it provides its own bottom SafeArea,
        // so avoid double-padding the bottom inset here.
        bottom: !_showEmojiPicker,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isModeActive)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? AppColor.divider
                          : TelegramColors.lightDivider,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.replyingTo != null
                          ? Icons.reply_rounded
                          : Icons.edit_rounded,
                      size: 20,
                      color: AppColor.gold,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.replyingTo != null
                                ? 'Ответ пользователю'
                                : 'Редактирование',
                            style: const TextStyle(
                              color: AppColor.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            (widget.replyingTo?['content'] ??
                                    widget.editingMessage?['content'] ??
                                    '')
                                .toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark
                                  ? AppColor.text2
                                  : TelegramColors.lightTextSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: widget.onCancelMode,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      tooltip: 'Отменить',
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Emoji button
                  IconButton(
                    icon: Icon(
                      _showEmojiPicker
                          ? Icons.keyboard_rounded
                          : Icons.emoji_emotions_outlined,
                      color: _showEmojiPicker
                          ? AppColor.gold
                          : isDark
                          ? AppColor.text2
                          : TelegramColors.lightTextSecondary,
                    ),
                    onPressed: widget.enabled ? _toggleEmojiPicker : null,
                    splashRadius: 20,
                    tooltip: _showEmojiPicker ? 'Клавиатура' : 'Эмодзи',
                  ),
                  // Attach button
                  if (widget.onSendFile != null &&
                      widget.editingMessage == null)
                    IconButton(
                      icon: _isSendingFile
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isDark
                                    ? AppColor.text2
                                    : TelegramColors.lightTextSecondary,
                              ),
                            )
                          : Icon(
                              Icons.attach_file_rounded,
                              color: isDark
                                  ? AppColor.text2
                                  : TelegramColors.lightTextSecondary,
                            ),
                      onPressed: _isSendingFile || !widget.enabled
                          ? null
                          : _openAttachMenu,
                      splashRadius: 20,
                      tooltip: 'Прикрепить файл',
                    ),
                  // Text field
                  Expanded(
                    child: Focus(
                      onKeyEvent: _handleKeyEvent,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: widget.enabled,
                        maxLines: 6,
                        minLines: 1,
                        textInputAction: _isDesktop
                            ? TextInputAction.newline
                            : TextInputAction.send,
                        onSubmitted: _isDesktop ? null : (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'Сообщение...',
                          filled: true,
                          fillColor: isDark
                              ? AppColor.input
                              : TelegramColors.lightInputBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Mic / Send button
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(scale: animation, child: child);
                    },
                    child: _hasText || widget.editingMessage != null
                        ? IconButton(
                            key: const ValueKey('send'),
                            icon: Icon(
                              widget.editingMessage != null
                                  ? Icons.check_rounded
                                  : Icons.send_rounded,
                            ),
                            color: AppColor.gold,
                            onPressed: widget.enabled ? _sendMessage : null,
                            splashRadius: 20,
                            tooltip: 'Отправить',
                          )
                        : widget.onSendVoice != null
                        ? IconButton(
                            key: const ValueKey('mic'),
                            icon: const Icon(Icons.mic_rounded),
                            color: isDark
                                ? AppColor.text2
                                : TelegramColors.lightTextSecondary,
                            onPressed: widget.enabled
                                ? () => setState(() => _isRecording = true)
                                : null,
                            splashRadius: 20,
                            tooltip: 'Голосовое сообщение',
                          )
                        : IconButton(
                            key: const ValueKey('send_disabled'),
                            icon: const Icon(Icons.send_rounded),
                            color: isDark
                                ? AppColor.text2
                                : TelegramColors.lightTextSecondary,
                            onPressed: null,
                            splashRadius: 20,
                            tooltip: 'Отправить',
                          ),
                  ),
                ],
              ),
            ),
            if (_showEmojiPicker) _buildEmojiPanel(isDark),
          ],
        ),
      ),
    );
  }

  void _toggleEmojiPicker() {
    final willShow = !_showEmojiPicker;
    setState(() => _showEmojiPicker = willShow);
    if (willShow) {
      // KVA-172: dismiss the soft keyboard so the emoji panel occupies the
      // freed space in the layout instead of colliding with the keyboard.
      FocusScope.of(context).unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  void _insertEmoji(String emoji) {
    final text = _controller.text;
    final selection = _controller.selection;
    final offset = selection.isValid ? selection.baseOffset : text.length;
    final newText = text.substring(0, offset) + emoji + text.substring(offset);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset + emoji.length),
    );
  }

  Widget _buildEmojiPanel(bool isDark) {
    // KVA-171/172: cap the panel height to a fraction of the available screen
    // so it never overflows on short viewports, and respect the bottom inset
    // via SafeArea. The grid inside scrolls, so content is always reachable.
    final maxPanelHeight = MediaQuery.of(context).size.height * 0.4;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: maxPanelHeight < 250 ? maxPanelHeight : 250,
        child: _EmojiGrid(onEmojiSelected: _insertEmoji, isDark: isDark),
      ),
    );
  }
}

/// Attachment source picked from the v7 attach chooser sheet.
enum _AttachSource { image, file }

/// A single tappable row inside the attach chooser sheet (theme-aware,
/// gold-accented icon badge on a flat surface — no shadow).
class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AttachOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColor.goldSoft,
                  borderRadius: BorderRadius.circular(AppRadius.icon),
                  border: Border.all(color: AppColor.goldLine),
                ),
                child: Icon(icon, size: 20, color: AppColor.gold),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _emojiCategories = <({String label, IconData icon, List<String> emojis})>[
  (
    label: 'Смайлы',
    icon: Icons.emoji_emotions_outlined,
    emojis: [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '🤣',
      '😂',
      '🙂',
      '😊',
      '😇',
      '🥰',
      '😍',
      '🤩',
      '😘',
      '😗',
      '😚',
      '😙',
      '🥲',
      '😋',
      '😛',
      '😜',
      '🤪',
      '😝',
      '🤑',
      '🤗',
      '🤭',
      '🤫',
      '🤔',
      '🫡',
      '🤐',
      '🤨',
      '😐',
      '😑',
      '😶',
      '🫥',
      '😏',
      '😒',
      '🙄',
      '😬',
      '😮‍💨',
      '🤥',
      '🫠',
      '😌',
      '😔',
      '😪',
      '🤤',
      '😴',
      '😷',
      '🤒',
      '🤕',
      '🤢',
      '🤮',
      '🥵',
      '🥶',
      '🥴',
      '😵',
      '🤯',
      '🤠',
      '🥳',
      '🥸',
      '😎',
      '🤓',
      '🧐',
      '😕',
      '🫤',
      '😟',
      '🙁',
      '😮',
      '😯',
      '😲',
      '😳',
      '🥺',
      '🥹',
      '😦',
      '😧',
      '😨',
      '😰',
      '😥',
      '😢',
      '😭',
      '😱',
      '😖',
      '😣',
      '😞',
      '😓',
      '😩',
      '😫',
      '🥱',
      '😤',
      '😡',
      '😠',
      '🤬',
      '😈',
      '👿',
      '💀',
    ],
  ),
  (
    label: 'Жесты',
    icon: Icons.waving_hand_outlined,
    emojis: [
      '👋',
      '🤚',
      '🖐️',
      '✋',
      '🖖',
      '🫱',
      '🫲',
      '🫳',
      '🫴',
      '👌',
      '🤌',
      '🤏',
      '✌️',
      '🤞',
      '🫰',
      '🤟',
      '🤘',
      '🤙',
      '👈',
      '👉',
      '👆',
      '🖕',
      '👇',
      '☝️',
      '🫵',
      '👍',
      '👎',
      '✊',
      '👊',
      '🤛',
      '🤜',
      '👏',
      '🙌',
      '🫶',
      '👐',
      '🤲',
      '🤝',
      '🙏',
      '✍️',
      '💅',
      '🤳',
      '💪',
      '🦾',
      '🦿',
      '🦵',
      '🦶',
      '👂',
      '🦻',
    ],
  ),
  (
    label: 'Сердца',
    icon: Icons.favorite_border,
    emojis: [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '❤️‍🔥',
      '❤️‍🩹',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
      '♥️',
      '🫀',
      '💋',
    ],
  ),
  (
    label: 'Объекты',
    icon: Icons.lightbulb_outline,
    emojis: [
      '🎵',
      '🎶',
      '🎤',
      '🎧',
      '🎸',
      '🎹',
      '🎺',
      '🎻',
      '🥁',
      '🪘',
      '🎼',
      '🎷',
      '🪗',
      '💡',
      '🔥',
      '⭐',
      '🌟',
      '✨',
      '💫',
      '🎉',
      '🎊',
      '🎈',
      '🎁',
      '🏆',
      '🥇',
      '🥈',
      '🥉',
      '🏅',
      '📚',
      '📖',
      '✏️',
      '📝',
      '💰',
      '💵',
      '💳',
      '📱',
      '💻',
      '⏰',
      '📅',
      '📌',
      '🔔',
      '✅',
      '❌',
      '❓',
      '❗',
      '💯',
      '🆗',
      '🆕',
    ],
  ),
];

class _EmojiGrid extends StatefulWidget {
  final ValueChanged<String> onEmojiSelected;
  final bool isDark;

  const _EmojiGrid({required this.onEmojiSelected, required this.isDark});

  @override
  State<_EmojiGrid> createState() => _EmojiGridState();
}

class _EmojiGridState extends State<_EmojiGrid> {
  int _categoryIndex = 0;

  @override
  Widget build(BuildContext context) {
    final category = _emojiCategories[_categoryIndex];
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: List.generate(_emojiCategories.length, (i) {
              final cat = _emojiCategories[i];
              final selected = i == _categoryIndex;
              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => _categoryIndex = i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        cat.icon,
                        size: 20,
                        color: selected
                            ? AppColor.gold
                            : widget.isDark
                            ? AppColor.text2
                            : TelegramColors.lightTextSecondary,
                      ),
                      if (selected)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          height: 2,
                          width: 20,
                          decoration: BoxDecoration(
                            color: AppColor.gold,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 42,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: category.emojis.length,
            itemBuilder: (context, index) {
              final emoji = category.emojis[index];
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => widget.onEmojiSelected(emoji),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
