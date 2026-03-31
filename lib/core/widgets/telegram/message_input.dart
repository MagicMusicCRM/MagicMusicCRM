import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/widgets/voice_recorder_widget.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

/// Telegram-style message input bar with text field, attachment, and voice recording.
class MessageInput extends StatefulWidget {
  final Future<void> Function(String text) onSendText;
  final Future<void> Function(Uint8List bytes, int durationMs, String ext)? onSendVoice;
  final Future<void> Function(Uint8List bytes, String fileName, int fileSize, {String? caption})? onSendFile;
  final void Function(bool isTyping)? onTyping;
  final bool enabled;

  const MessageInput({
    super.key,
    required this.onSendText,
    this.onSendVoice,
    this.onSendFile,
    this.onTyping,
    this.enabled = true,
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
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    setState(() => _hasText = false);
    await widget.onSendText(text);
    _focusNode.requestFocus();
  }

  Future<void> _pickAndSendFile() async {
    if (_isSendingFile || widget.onSendFile == null) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;
      if (file.size > ChatAttachmentService.maxFileSizeBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Файл слишком большой (макс. 25 МБ)'),
              backgroundColor: TelegramColors.danger,
            ),
          );
        }
        return;
      }
      setState(() => _isSendingFile = true);
      await widget.onSendFile!(file.bytes!, file.name, file.size);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: TelegramColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingFile = false);
    }
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? TelegramColors.darkSurface : TelegramColors.lightBg,
        border: Border(
          top: BorderSide(
            color: isDark ? TelegramColors.darkDivider : TelegramColors.lightDivider,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Attach button
            if (widget.onSendFile != null)
              IconButton(
                icon: _isSendingFile
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isDark
                              ? TelegramColors.darkTextSecondary
                              : TelegramColors.lightTextSecondary,
                        ),
                      )
                    : Icon(
                        Icons.attach_file_rounded,
                        color: isDark
                            ? TelegramColors.darkTextSecondary
                            : TelegramColors.lightTextSecondary,
                      ),
                onPressed: _isSendingFile || !widget.enabled ? null : _pickAndSendFile,
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
                  textInputAction: _isDesktop ? TextInputAction.newline : TextInputAction.send,
                  onSubmitted: _isDesktop ? null : (_) => _sendMessage(),
                  decoration: InputDecoration(
                    hintText: 'Сообщение...',
                    filled: true,
                    fillColor: isDark
                        ? TelegramColors.darkInputBg
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
              child: _hasText
                  ? IconButton(
                      key: const ValueKey('send'),
                      icon: const Icon(Icons.send_rounded),
                      color: TelegramColors.accentBlue,
                      onPressed: widget.enabled ? _sendMessage : null,
                      splashRadius: 20,
                      tooltip: 'Отправить',
                    )
                  : widget.onSendVoice != null
                      ? IconButton(
                          key: const ValueKey('mic'),
                          icon: const Icon(Icons.mic_rounded),
                          color: isDark
                              ? TelegramColors.darkTextSecondary
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
                              ? TelegramColors.darkTextSecondary
                              : TelegramColors.lightTextSecondary,
                          onPressed: null,
                          splashRadius: 20,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
