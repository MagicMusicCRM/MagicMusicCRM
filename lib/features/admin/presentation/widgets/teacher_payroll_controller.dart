import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

class TeacherPayrollController extends ChangeNotifier {
  TeacherPayrollController({
    required MagicCrmService service,
    required this.teacherId,
  }) : _service = service;

  final MagicCrmService _service;
  final String teacherId;

  Map<String, dynamic>? _payroll;
  Object? _error;
  Object? _mutationError;
  bool _mutating = false;
  bool _disposed = false;

  Map<String, dynamic>? get payroll => _payroll;
  Object? get error => _error;
  Object? get mutationError => _mutationError;
  bool get mutating => _mutating;
  bool get loading => _payroll == null && _error == null;
  num get debt => _number(_payroll?['debt']);
  int? get expectedVersion =>
      _payroll == null ? null : _number(_payroll!['version']).toInt();

  Future<void> load() async {
    _error = null;
    _notify();
    try {
      _payroll = await _service.getTeacherPayroll(teacherId);
    } catch (error) {
      _error = error;
    }
    _notify();
  }

  Future<void> payAllDebt() async {
    final amount = debt;
    final version = expectedVersion;
    if (amount <= 0 || version == null) return;
    await _runMutation(
      () => _service.createTeacherPayout(
        teacherId: teacherId,
        kind: 'payout',
        amount: amount,
        expectedVersion: version,
        reasonText: 'Оплата всей задолженности',
        comment: 'Оплата всей задолженности',
      ),
    );
  }

  Future<void> createPayout({
    required String kind,
    required num amount,
    required String reasonText,
    String? comment,
  }) async {
    final version = expectedVersion;
    if (version == null) return;
    await _runMutation(
      () => _service.createTeacherPayout(
        teacherId: teacherId,
        kind: kind,
        amount: amount,
        expectedVersion: version,
        reasonText: reasonText,
        comment: comment,
      ),
    );
  }

  Future<void> updateRateEntry({
    required String entryId,
    required num rate,
    required String effectiveFrom,
    required String reasonText,
  }) async {
    final version = expectedVersion;
    if (version == null) return;
    await _runMutation(
      () => _service.updateTeacherRateEntry(
        teacherId: teacherId,
        entryId: entryId,
        rate: rate,
        effectiveFrom: effectiveFrom,
        expectedVersion: version,
        reasonText: reasonText,
      ),
    );
  }

  Future<void> updatePayoutEntry({
    required String entryId,
    required String kind,
    required num amount,
    required String paidAt,
    required String reasonText,
    String? comment,
  }) async {
    final version = expectedVersion;
    if (version == null) return;
    await _runMutation(
      () => _service.updateTeacherPayoutEntry(
        teacherId: teacherId,
        entryId: entryId,
        kind: kind,
        amount: amount,
        paidAt: paidAt,
        expectedVersion: version,
        reasonText: reasonText,
        comment: comment,
      ),
    );
  }

  Future<void> deleteEntry({
    required String entryId,
    required bool rate,
    required String reasonText,
  }) async {
    final version = expectedVersion;
    if (version == null) return;
    await _runMutation(
      () => rate
          ? _service.deleteTeacherRateEntry(
              teacherId: teacherId,
              entryId: entryId,
              expectedVersion: version,
              reasonText: reasonText,
            )
          : _service.deleteTeacherPayoutEntry(
              teacherId: teacherId,
              entryId: entryId,
              expectedVersion: version,
              reasonText: reasonText,
            ),
    );
  }

  Future<void> _runMutation(
    Future<Map<String, dynamic>> Function() mutation,
  ) async {
    _mutating = true;
    _mutationError = null;
    _notify();
    try {
      await mutation();
      await load();
    } catch (error) {
      _mutationError = error;
    } finally {
      _mutating = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static num _number(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
