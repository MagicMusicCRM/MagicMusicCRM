import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:magic_music_crm/core/services/chat_attachment_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

/// Widget for playing back voice messages inside a message bubble.
class VoicePlayerWidget extends ConsumerStatefulWidget {
  final String audioUrl;
  final int? durationMs;
  final bool isMe;

  const VoicePlayerWidget({
    super.key,
    required this.audioUrl,
    this.durationMs,
    required this.isMe,
  });

  @override
  ConsumerState<VoicePlayerWidget> createState() => _VoicePlayerWidgetState();
}

class _VoicePlayerWidgetState extends ConsumerState<VoicePlayerWidget> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _resolvedAudioUrl;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void didUpdateWidget(covariant VoicePlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl) {
      _resolvedAudioUrl = null;
      _position = Duration.zero;
      _duration = widget.durationMs != null
          ? Duration(milliseconds: widget.durationMs!)
          : Duration.zero;
      unawaited(_player.stop());
    }
  }

  void _initPlayer() {
    // Set known duration from message metadata if available
    if (widget.durationMs != null) {
      _duration = Duration(milliseconds: widget.durationMs!);
    }

    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _duration = dur);
    });

    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          _isLoading =
              state.processingState == ProcessingState.loading ||
              state.processingState == ProcessingState.buffering;

          // When the audio completes
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
            _position = Duration.zero;
            _player.seek(Duration.zero);
            _player.pause();
          }
        });
      }
    });
  }

  Future<void> _togglePlay() async {
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        // If not loaded yet, resolve the short-lived download URL (via the
        // /files/:id/download-token flow inside the service) and load it first.
        if (_player.processingState == ProcessingState.idle) {
          if (mounted) setState(() => _isLoading = true);
          try {
            _resolvedAudioUrl ??= await ref
                .read(chatAttachmentServiceProvider)
                .resolveUrl(widget.audioUrl);
            if (_resolvedAudioUrl == null) {
              throw StateError('Аудиофайл недоступен');
            }
            await _player.setUrl(_resolvedAudioUrl!);
          } finally {
            // Clear the manual loading flag on the success path too — from here
            // on the player's processingState stream owns the buffering state.
            if (mounted) setState(() => _isLoading = false);
          }
        }
        await _player.play();
      }
    } catch (e) {
      debugPrint('Voice playback error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ошибка воспроизведения: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    final iconColor = widget.isMe ? Colors.white : AppTheme.primaryGold;
    final trackBg = widget.isMe
        ? Colors.white.withAlpha(50)
        : AppTheme.primaryGold.withAlpha(30);
    final trackActive = widget.isMe ? Colors.white : AppTheme.primaryGold;
    final textColor = widget.isMe
        ? Colors.white.withAlpha(200)
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Play/Pause button
        _isLoading
            ? SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: iconColor,
                ),
              )
            : GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconColor.withAlpha(25),
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: iconColor,
                    size: 22,
                  ),
                ),
              ),
        const SizedBox(width: 10),
        // Waveform and duration
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Waveform visualizer
              SizedBox(
                height: 24,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(24, (index) {
                    final normalizedProgress = progress.clamp(0.0, 1.0);
                    final isPlayed = (index / 24) <= normalizedProgress;
                    // Simple deterministic pseudo-random heights for the waveform
                    final heights = [
                      6,
                      10,
                      8,
                      14,
                      18,
                      12,
                      16,
                      20,
                      14,
                      10,
                      12,
                      18,
                      14,
                      20,
                      16,
                      12,
                      8,
                      14,
                      10,
                      6,
                      8,
                      12,
                      10,
                      4,
                    ];
                    final h = heights[index % heights.length].toDouble();

                    return Container(
                      width: 2,
                      height: h,
                      decoration: BoxDecoration(
                        color: isPlayed ? trackActive : trackBg,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _isPlaying || _position > Duration.zero
                    ? _formatDuration(_position)
                    : _formatDuration(_duration),
                style: TextStyle(fontSize: 10, color: textColor),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.mic_rounded, size: 14, color: iconColor.withAlpha(120)),
      ],
    );
  }
}
