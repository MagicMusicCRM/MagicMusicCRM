import 'dart:async';

/// Raised when another update flow already owns the process-wide updater.
class WindowsUpdateInProgressException implements Exception {
  const WindowsUpdateInProgressException();

  @override
  String toString() =>
      'WindowsUpdateInProgressException: another update flow is active.';
}

/// Process-wide single-flight gate shared by update dialogs and the low-level
/// helper launch. A Zone token lets the dialog which owns the UI flow acquire
/// the nested launch gate, while unrelated callers are rejected immediately.
class WindowsUpdateCoordinator {
  WindowsUpdateCoordinator._();

  static final WindowsUpdateCoordinator instance = WindowsUpdateCoordinator._();
  static final Object _flowZoneKey = Object();

  final StreamController<bool> _activityController =
      StreamController<bool>.broadcast(sync: true);

  Object? _activeFlowToken;
  bool _launchActive = false;

  bool get isBusy => _activeFlowToken != null || _launchActive;

  /// Emits whenever [isBusy] may have changed. The controller intentionally
  /// lives for the process lifetime together with this singleton.
  Stream<bool> get activity => _activityController.stream;

  /// Runs one complete prompt/progress/error UI flow. Duplicate prompt or
  /// overlay triggers are ignored and return `false` without invoking [action].
  Future<bool> runFlow(Future<void> Function() action) async {
    if (isBusy) return false;

    final token = Object();
    _activeFlowToken = token;
    _emitActivity();
    try {
      await runZoned(action, zoneValues: <Object, Object>{_flowZoneKey: token});
      return true;
    } finally {
      if (identical(_activeFlowToken, token)) {
        _activeFlowToken = null;
        _emitActivity();
      }
    }
  }

  /// Guards the actual helper creation. Calls from the Zone that owns the
  /// active UI flow are allowed; every other concurrent launch is rejected.
  Future<T> runLaunch<T>(Future<T> Function() action) async {
    final activeFlow = _activeFlowToken;
    final ownsActiveFlow =
        activeFlow != null && identical(Zone.current[_flowZoneKey], activeFlow);
    if (_launchActive || (activeFlow != null && !ownsActiveFlow)) {
      throw const WindowsUpdateInProgressException();
    }

    _launchActive = true;
    _emitActivity();
    try {
      return await action();
    } finally {
      _launchActive = false;
      _emitActivity();
    }
  }

  void _emitActivity() {
    if (!_activityController.isClosed) {
      _activityController.add(isBusy);
    }
  }
}

final WindowsUpdateCoordinator windowsUpdateCoordinator =
    WindowsUpdateCoordinator.instance;
