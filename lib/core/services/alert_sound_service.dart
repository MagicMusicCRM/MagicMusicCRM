import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Plays the app's own alert tone for new leads and due tasks.
///
/// Only used while the app is in the foreground. A backgrounded app is told by
/// the system push, which carries the system sound — playing this on top would
/// mean the user hears two different sounds for one event.
class AlertSoundService {
  static const _asset = 'assets/sounds/alarm.wav';

  final AudioPlayer _player = AudioPlayer();
  bool _loaded = false;

  /// Fire-and-forget: a notification must never be lost because audio failed
  /// (no output device, asset missing, platform without a just_audio impl).
  Future<void> play() async {
    try {
      if (!_loaded) {
        await _player.setAsset(_asset);
        _loaded = true;
      }
      // Rewind: a second alert arriving while the first is still playing must
      // restart the tone, not be silently ignored by an already-playing player.
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (error) {
      if (kDebugMode) debugPrint('Alert sound failed: $error');
    }
  }

  void dispose() {
    unawaited(_player.dispose());
  }
}


/// Kept alive for the app's lifetime so the asset is decoded once, not on
/// every alert.
final alertSoundServiceProvider = Provider<AlertSoundService>((ref) {
  final service = AlertSoundService();
  ref.onDispose(service.dispose);
  return service;
});
