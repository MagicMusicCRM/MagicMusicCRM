import 'dart:async';

/// Tab-local draft coordination. No widget, provider or navigation dependencies.
class ClientCardDraftController {
  ClientCardDraftController({
    required this.isDirty,
    required this.isValid,
    required this.persist,
    required this.onChanged,
    this.delay = const Duration(milliseconds: 800),
  });
  final bool Function() isDirty, isValid;
  final Future<bool> Function(int revision) persist;
  final void Function() onChanged;
  final Duration delay;
  int revision = 0;
  bool pending = false, failed = false, conflict = false;
  final Map<String, int> leadCoreEdits = {},
      studentCoreEdits = {},
      leadCustomEdits = {},
      studentCustomEdits = {};
  int? leadStatusEdit,
      studentStatusEdit,
      leadResponsibleEdit,
      studentResponsibleEdit;
  Timer? _timer;
  Future<bool>? _inFlight;
  bool _queued = false, _disposed = false;

  void schedule() {
    if (_disposed || conflict) return;
    _timer?.cancel();
    pending = true;
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(run());
    });
  }

  Future<bool> run() async {
    if (_disposed) return false;
    pending = false;
    if (conflict || !isValid()) return false;
    if (!isDirty()) return true;
    final active = _inFlight;
    if (active != null) {
      _queued = true;
      return active;
    }
    final operation = persist(revision);
    _inFlight = operation;
    bool saved;
    try {
      saved = await operation;
    } catch (_) {
      saved = false;
    } finally {
      if (identical(_inFlight, operation)) _inFlight = null;
    }
    if (_disposed) return saved;
    failed = !saved;
    onChanged();
    final queued = _queued;
    _queued = false;
    if (queued && isDirty() && !conflict) return run();
    return saved;
  }

  Future<bool> flush() async {
    _timer?.cancel();
    _timer = null;
    pending = false;
    final active = _inFlight;
    if (active != null) await active;
    if (_disposed || conflict) return false;
    if (!isDirty()) return true;
    return run();
  }

  Future<bool> retry() {
    _timer?.cancel();
    _timer = null;
    pending = false;
    failed = false;
    if (!_disposed) onChanged();
    return run();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
