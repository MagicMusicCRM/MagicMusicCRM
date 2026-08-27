import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/payment.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';

import 'finance_state.dart';

export 'finance_state.dart';

@immutable
class FinanceExportResult {
  const FinanceExportResult({required this.filename, required this.file});

  final String filename;
  final ReportFileOpenResult file;
}

class FinanceController extends ChangeNotifier {
  FinanceController({
    required MagicCrmService crm,
    required ReportFileOpener reportFileOpener,
    required DateTimeRange? filterRange,
    required String? branchId,
    DateTime Function()? clock,
    Duration realtimeDebounce = const Duration(milliseconds: 350),
  }) : _crm = crm,
       _reportFileOpener = reportFileOpener,
       _clock = clock ?? DateTime.now,
       _realtimeDebounceDuration = realtimeDebounce,
       _state = FinanceState(
         customRange: filterRange,
         usesExternalRange: filterRange != null,
         branchId: branchId,
       );

  final MagicCrmService _crm;
  final ReportFileOpener _reportFileOpener;
  final DateTime Function() _clock;
  final Duration _realtimeDebounceDuration;
  FinanceState _state;
  Timer? _realtimeTimer;
  bool _disposed = false;
  int _paymentGeneration = 0;
  int _expenseGeneration = 0;
  int _mutationGeneration = 0;
  int _exportGeneration = 0;

  FinanceState get state => _state;

  bool _isCurrent(int actual, int expected) => !_disposed && actual == expected;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  ({DateTime from, DateTime to, String? branchId}) _query() {
    final range = _state.customRange;
    if (range != null) {
      return (
        from: range.start,
        to: range.end.add(const Duration(days: 1)),
        branchId: _state.branchId,
      );
    }
    final now = _clock();
    final from = switch (_state.period) {
      'week' => now.subtract(const Duration(days: 7)),
      'year' => DateTime(now.year, 1),
      _ => DateTime(now.year, now.month),
    };
    return (from: from, to: now, branchId: _state.branchId);
  }

  Future<void> load() async {
    if (_disposed) return;
    await Future.wait<void>([loadPayments(), loadExpenses()]);
  }

  Future<void> updateExternalQuery(
    DateTimeRange? filterRange,
    String? branchId,
  ) async {
    if (_disposed) return;
    _state = _state.copyWith(
      customRange: filterRange,
      usesExternalRange: filterRange != null,
      branchId: branchId,
    );
    _notify();
    await load();
  }

  Future<void> setCustomRange(DateTimeRange? range) async {
    if (_disposed || _state.usesExternalRange) return;
    _state = _state.copyWith(customRange: range);
    _notify();
    await load();
  }

  Future<void> setPeriod(String period) async {
    if (_disposed || _state.usesExternalRange) return;
    _state = _state.copyWith(period: period, customRange: null);
    _notify();
    await load();
  }

  Future<void> loadPayments() async {
    if (_disposed) return;
    final generation = ++_paymentGeneration;
    final query = _query();
    _state = _state.copyWith(loading: true, loadError: null);
    _notify();
    try {
      final result = await _crm.listPaymentsWithTotal(
        from: query.from.toUtc().toIso8601String(),
        to: query.to.toUtc().toIso8601String(),
        branchId: query.branchId,
        limit: 100,
      );
      if (!_isCurrent(generation, _paymentGeneration)) return;
      _state = _state.copyWith(
        payments: List<Payment>.unmodifiable(result.items),
        total: result.totalAmount.toDouble(),
        totalCount: result.totalCount,
        loading: false,
        loadError: null,
      );
    } catch (error) {
      if (!_isCurrent(generation, _paymentGeneration)) return;
      _state = _state.copyWith(loading: false, loadError: error);
    }
    _notify();
  }

  Future<void> loadExpenses() async {
    if (_disposed) return;
    final generation = ++_expenseGeneration;
    final query = _query();
    _state = _state.copyWith(expensesLoading: true);
    _notify();
    try {
      final response = await _crm.listExpenses(
        branchId: query.branchId,
        from: query.from.toUtc().toIso8601String(),
        to: query.to.toUtc().toIso8601String(),
        limit: 50,
      );
      if (!_isCurrent(generation, _expenseGeneration)) return;
      final items = (response['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      _state = _state.copyWith(
        expenses: List<Map<String, dynamic>>.unmodifiable(items),
        expensesTotal: (response['total'] as num?)?.toDouble() ?? 0,
        expensesLoading: false,
      );
    } catch (_) {
      if (!_isCurrent(generation, _expenseGeneration)) return;
      _state = _state.copyWith(
        expenses: const [],
        expensesTotal: 0,
        expensesLoading: false,
      );
    }
    _notify();
  }

  Future<void> createExpense({
    required num amount,
    required String category,
    String? description,
    String? branchId,
  }) {
    return _mutateExpense(
      () => _crm.createExpense(
        amount: amount,
        category: category,
        description: description,
        branchId: branchId ?? _state.branchId,
      ),
    );
  }

  Future<void> updateExpense({
    required String expenseId,
    required num amount,
    required String category,
    String? description,
    String? branchId,
  }) {
    return _mutateExpense(
      () => _crm.updateExpense(
        expenseId: expenseId,
        amount: amount,
        category: category,
        description: description,
        branchId: branchId ?? _state.branchId,
      ),
    );
  }

  Future<void> deleteExpense(String expenseId) {
    return _mutateExpense(() => _crm.deleteExpense(expenseId));
  }

  Future<void> _mutateExpense(Future<Object?> Function() mutation) async {
    if (_disposed || _state.savingExpense) return;
    final generation = ++_mutationGeneration;
    _state = _state.copyWith(savingExpense: true, expenseError: null);
    _notify();
    try {
      await mutation();
      if (!_isCurrent(generation, _mutationGeneration)) return;
      await loadExpenses();
    } catch (error) {
      if (_isCurrent(generation, _mutationGeneration)) {
        _state = _state.copyWith(expenseError: error);
        _notify();
      }
      rethrow;
    } finally {
      if (_isCurrent(generation, _mutationGeneration)) {
        _state = _state.copyWith(savingExpense: false);
        _notify();
      }
    }
  }

  Future<FinanceExportResult?> export(String format) async {
    if (_disposed || _state.exporting) return null;
    final generation = ++_exportGeneration;
    final query = _query();
    _state = _state.copyWith(exporting: true, exportError: null);
    _notify();
    try {
      final bytes = await _crm.exportFinanceMonthly(
        format: format,
        from: query.from.toUtc(),
        to: query.to.toUtc(),
        branchId: query.branchId,
      );
      if (!_isCurrent(generation, _exportGeneration)) return null;
      final stamp = DateFormat('yyyyMM').format(query.from);
      final filename = 'finance-$stamp.$format';
      final file = await _reportFileOpener(bytes, filename);
      if (!_isCurrent(generation, _exportGeneration)) return null;
      return FinanceExportResult(filename: filename, file: file);
    } catch (error) {
      if (_isCurrent(generation, _exportGeneration)) {
        _state = _state.copyWith(exportError: error);
        _notify();
      }
      rethrow;
    } finally {
      if (_isCurrent(generation, _exportGeneration)) {
        _state = _state.copyWith(exporting: false);
        _notify();
      }
    }
  }

  static String exportErrorMessage(Object error) {
    if (error is MagicApiException) {
      return error.toUserMessage(fallback: 'Не удалось выгрузить отчёт.');
    }
    return 'Не удалось сохранить файл';
  }

  void queueRealtimeRefresh() {
    if (_disposed || _state.loading || _state.savingExpense) return;
    _realtimeTimer?.cancel();
    _realtimeTimer = Timer(_realtimeDebounceDuration, () {
      if (_disposed || _state.loading || _state.savingExpense) return;
      unawaited(load());
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _realtimeTimer?.cancel();
    _paymentGeneration += 1;
    _expenseGeneration += 1;
    _mutationGeneration += 1;
    _exportGeneration += 1;
    super.dispose();
  }
}
