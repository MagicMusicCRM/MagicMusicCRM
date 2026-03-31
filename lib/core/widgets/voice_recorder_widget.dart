import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

/// Widget for recording voice messages.
/// Calls [onVoiceRecorded] with the recorded bytes and duration when done.
class VoiceRecorderWidget extends StatefulWidget {
  final Future<void> Function(Uint8List bytes, int durationMs, String extension) onVoiceRecorded;
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
  Timer? _timer;
  late AnimationController _pulseController;
  String? _recordPath;

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
        _recordPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        const config = RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
        );

        await _recorder.start(config, path: _recordPath!);

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
              content: Text('Нет разрешения на запись аудио', style: TextStyle(color: Colors.white)),
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
            content: Text('Ошибка записи: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: AppTheme.danger,
          ),
        );
        widget.onCancel();
      }
    }
  }

  Future<void> _stopAndSend() async {
    if (_isSending || !_isRecording) return;
    setState(() => _isSending = true);
    _timer?.cancel();

    try {
      final path = await _recorder.stop();
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (mounted) {
            await widget.onVoiceRecorded(
              bytes,
              _durationSeconds * 1000,
              '.m4a',
            );
          }
          // Clean up temp file
          try { await file.delete(); } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }

    if (mounted) widget.onCancel();
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    try {
      final path = await _recorder.stop();
      if (path != null) {
        try { await File(path).delete(); } catch (_) {}
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
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Cancel button
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
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
            const Spacer(),
            // Send button
            if (_isSending)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryPurple),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  color: AppTheme.primaryPurple,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  onPressed: _isRecording ? _stopAndSend : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
