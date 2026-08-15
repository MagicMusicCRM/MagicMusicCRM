import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

class RecurringSchedulePlanController extends ChangeNotifier {
  RecurringSchedulePlanController({
    required MagicCrmService service,
    this.studentId,
    this.groupId,
  }) : assert((studentId == null) != (groupId == null)),
       _service = service;

  final MagicCrmService _service;
  final String? studentId;
  final String? groupId;

  bool loading = false;
  String? error;
  List<SchedulePlan> plans = const [];
  final Map<String, SchedulePlanTrayPage> trays = {};
  final Set<String> loadingTrays = {};
  final Map<String, String> trayErrors = {};
  final Map<String, ({String? cursor, String? direction})> trayRetryRequests =
      {};
  bool _disposed = false;

  Future<void> load() async {
    loading = true;
    error = null;
    _notify();
    try {
      plans = await _service.listSchedulePlans(
        studentId: studentId,
        groupId: groupId,
      );
      final visiblePlanIds = plans.map((plan) => plan.id).toSet();
      trays.removeWhere((planId, _) => !visiblePlanIds.contains(planId));
      trayErrors.removeWhere((planId, _) => !visiblePlanIds.contains(planId));
      trayRetryRequests.removeWhere(
        (planId, _) => !visiblePlanIds.contains(planId),
      );
      await Future.wait(plans.where((plan) => plan.isActive).map(ensureTray));
    } catch (exception) {
      error = userErrorMessage(
        exception,
        fallback: 'Не удалось загрузить постоянное расписание.',
      );
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

  Future<void> retryTray(SchedulePlan plan) {
    final request = trayRetryRequests[plan.id];
    return _loadTray(
      plan.id,
      cursor: request?.cursor,
      direction: request?.direction,
    );
  }

  Future<void> _loadTray(
    String planId, {
    String? cursor,
    String? direction,
  }) async {
    if (loadingTrays.contains(planId)) return;
    loadingTrays.add(planId);
    trayErrors.remove(planId);
    _notify();
    try {
      trays[planId] = await _service.getSchedulePlanTray(
        planId,
        cursor: cursor,
        direction: direction,
      );
      trayRetryRequests.remove(planId);
    } catch (exception) {
      trayErrors[planId] = userErrorMessage(
        exception,
        fallback: 'Не удалось загрузить занятия по этому расписанию.',
      );
      trayRetryRequests[planId] = (cursor: cursor, direction: direction);
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
