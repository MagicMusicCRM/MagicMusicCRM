import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

class RecurringSchedulePlanController extends ChangeNotifier {
  RecurringSchedulePlanController({
    required MagicCrmService service,
    required this.studentId,
  }) : _service = service;

  final MagicCrmService _service;
  final String studentId;

  bool loading = false;
  String? error;
  List<SchedulePlan> plans = const [];
  final Map<String, SchedulePlanTrayPage> trays = {};
  final Set<String> loadingTrays = {};
  final Map<String, String> trayErrors = {};
  bool _disposed = false;

  Future<void> load() async {
    loading = true;
    error = null;
    _notify();
    try {
      plans = await _service.listSchedulePlans(studentId: studentId);
      trays.removeWhere((planId, _) => !plans.any((plan) => plan.id == planId));
      await Future.wait(plans.where((plan) => plan.isActive).map(ensureTray));
    } catch (exception) {
      error = '$exception';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> ensureTray(SchedulePlan plan) async {
    if (trays.containsKey(plan.id) || loadingTrays.contains(plan.id)) return;
    await _loadTray(plan.id);
  }

  Future<void> pageTray(SchedulePlan plan, String direction) async {
    final current = trays[plan.id];
    final cursor = direction == 'previous'
        ? current?.previousCursor
        : current?.nextCursor;
    if (cursor == null) return;
    await _loadTray(plan.id, cursor: cursor, direction: direction);
  }

  Future<void> retryTray(SchedulePlan plan) => _loadTray(plan.id);

  Future<void> _loadTray(
    String planId, {
    String? cursor,
    String? direction,
  }) async {
    loadingTrays.add(planId);
    trayErrors.remove(planId);
    _notify();
    try {
      trays[planId] = await _service.getSchedulePlanTray(
        planId,
        cursor: cursor,
        direction: direction,
      );
    } catch (exception) {
      trayErrors[planId] = '$exception';
    } finally {
      loadingTrays.remove(planId);
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
