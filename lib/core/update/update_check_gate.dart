class WindowsUpdateCheckGate {
  WindowsUpdateCheckGate({this.minimumInterval = const Duration(minutes: 5)});

  final Duration minimumInterval;

  DateTime? _lastStartedAt;
  bool _inFlight = false;

  bool get isRunning => _inFlight;
  DateTime? get lastStartedAt => _lastStartedAt;

  Future<bool> run(
    Future<void> Function() action, {
    bool force = false,
    DateTime? now,
  }) async {
    final startedAt = now ?? DateTime.now();
    if (_inFlight) return false;
    final lastStartedAt = _lastStartedAt;
    if (!force &&
        lastStartedAt != null &&
        startedAt.difference(lastStartedAt) < minimumInterval) {
      return false;
    }

    _inFlight = true;
    _lastStartedAt = startedAt;
    try {
      await action();
      return true;
    } finally {
      _inFlight = false;
    }
  }
}
