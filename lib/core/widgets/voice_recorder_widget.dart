import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// Widget for recording voice messages.
/// Calls [onVoiceRecorded] with the recorded bytes and duration when done.
class VoiceRecorderWidget extends StatefulWidget {
  final Future<void> Function(Uint8List bytes, int durationMs, String extension)
  onVoiceRecorded;
  final VoidCallback onCancel;

  const VoiceRecorderWidget({
    super.key,
    required this.onVoiceRecorded,
    required this.onCancel,
  });

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget>
    with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isSending = false;
  int _durationSeconds = 0;
  final Stopwatch _elapsed = Stopwatch();
  Timer? _timer;
  late AnimationController _pulseController;
  String? _recordPath;
  Uint8List? _recordedBytes;
  int? _recordedDurationMs;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _startRecording();
  }

  Future<void> _startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        _recordPath =
            '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        const config = RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
        );

        await _recorder.start(config, path: _recordPath!);
        _elapsed
          ..reset()
          ..start();

        if (mounted) {
          setState(() => _isRecording = true);
          _timer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() => _durationSeconds++);
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Нет разрешения на запись аудио',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: AppTheme.danger,
            ),
          );
          widget.onCancel();
        }
      }
    } catch (e) {
      debugPrint('Voice recording error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось начать запись.'),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
        widget.onCancel();
      }
    }
  }

  Future<void> _stopAndSend() async {
    if (_isSending || (!_isRecording && _recordedBytes == null)) return;
    setState(() => _isSending = true);
    _timer?.cancel();

    try {
      if (_recordedBytes == null) {
        _elapsed.stop();
        final path = await _recorder.stop();
        _isRecording = false;
        if (path == null || path.isEmpty) {
          throw StateError('Файл записи не создан');
        }
        final file = File(path);
        if (!await file.exists()) throw StateError('Файл записи недоступен');
        _recordedBytes = await file.readAsBytes();
        _recordedDurationMs = _elapsed.elapsedMilliseconds.clamp(1, 3600000);
      }
      await widget.onVoiceRecorded(
        _recordedBytes!,
        _recordedDurationMs!,
        '.m4a',
      );
      final path = _recordPath;
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) widget.onCancel();
      return;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      if (mounted) {
        setState(() {
          _isSending = false;
          _sendError = 'Не удалось отправить. Запись сохранена для повтора.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось сохранить запись.'),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    _elapsed.stop();
    try {
      final path = await _recorder.stop();
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) widget.onCancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(top: BorderSide(color: AppColor.divider)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Cancel button
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppTheme.danger,
              ),
              tooltip: 'Отменить',
              onPressed: _cancel,
            ),
            const SizedBox(width: 8),
            // Recording indicator with pulse animation
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.danger.withAlpha(
                      (100 + 155 * _pulseController.value).toInt(),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            // Duration display
            Text(
              _formatDuration(_durationSeconds),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 12),
            // "Recording..." label
            if (_isRecording)
              const Text(
                'Запись...',
                style: TextStyle(color: AppTheme.danger, fontSize: 13),
              ),
            if (_sendError != null)
              Flexible(
                child: Text(
                  _sendError!,
                  style: const TextStyle(color: AppTheme.danger, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Spacer(),
            // Send button
            if (_isSending)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primaryGold,
                ),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  color: AppTheme.primaryGold,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  tooltip: 'Остановить и отправить запись',
                  icon: const Icon(Icons.send_rounded, color: AppColor.onGold),
                  onPressed: (_isRecording || _recordedBytes != null)
                      ? _stopAndSend
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
