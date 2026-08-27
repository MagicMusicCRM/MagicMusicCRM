import 'dart:async';

import 'package:flutter/widgets.dart';

class StudentsBoardAutoScrollController {
  StudentsBoardAutoScrollController({ScrollController? scrollController})
    : scrollController = scrollController ?? ScrollController(),
      _ownsScrollController = scrollController == null;

  static const double _minSpeed = 8;
  static const double _maxSpeed = 24;
  static const double _dragThreshold = 12;
  static const double _edge = 110;

  final ScrollController scrollController;
  final bool _ownsScrollController;
  Timer? _timer;
  int _direction = 0;
  double _speed = 0;
  Offset? _start;
  bool _movedEnough = false;
  bool _disposed = false;

  bool get isActive => !_disposed && _direction != 0 && _timer != null;

  void updateDrag({
    required Offset globalPosition,
    required double viewportWidth,
    required bool reducedMotion,
  }) {
    if (_disposed) return;
    if (reducedMotion) {
      stop();
      return;
    }
    _start ??= globalPosition;
    if (!_movedEnough) {
      if ((globalPosition - _start!).distance < _dragThreshold) return;
      _movedEnough = true;
    }

    var penetration = 0.0;
    if (globalPosition.dx < _edge) {
      _direction = -1;
      penetration = ((_edge - globalPosition.dx) / _edge).clamp(0, 1);
    } else if (globalPosition.dx > viewportWidth - _edge) {
      _direction = 1;
      penetration = ((globalPosition.dx - (viewportWidth - _edge)) / _edge)
          .clamp(0, 1);
    } else {
      _direction = 0;
    }
    if (_direction == 0) {
      _cancelTimer();
      return;
    }
    _speed = _minSpeed + (_maxSpeed - _minSpeed) * penetration * penetration;
    _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _tick() {
    if (_disposed || !scrollController.hasClients || _direction == 0) return;
    final position = scrollController.position;
    final next = (position.pixels + _direction * _speed).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if (next != position.pixels) scrollController.jumpTo(next);
  }

  void stop() {
    if (_disposed) return;
    _direction = 0;
    _speed = 0;
    _start = null;
    _movedEnough = false;
    _cancelTimer();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _speed = 0;
  }

  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    if (_ownsScrollController) scrollController.dispose();
  }
}
