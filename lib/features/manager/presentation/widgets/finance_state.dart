import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/models/payment.dart';

const _unset = Object();

@immutable
class FinanceState {
  const FinanceState({
    this.payments = const [],
    this.loading = true,
    this.loadError,
    this.total = 0,
    this.totalCount = 0,
    this.period = 'month',
    this.customRange,
    this.usesExternalRange = false,
    this.branchId,
    this.expenses = const [],
    this.expensesLoading = true,
    this.expensesTotal = 0,
    this.savingExpense = false,
    this.expenseError,
    this.exporting = false,
    this.exportError,
  });

  final List<Payment> payments;
  final bool loading;
  final Object? loadError;
  final double total;
  final int totalCount;
  final String period;
  final DateTimeRange? customRange;
  final bool usesExternalRange;
  final String? branchId;
  final List<Map<String, dynamic>> expenses;
  final bool expensesLoading;
  final double expensesTotal;
  final bool savingExpense;
  final Object? expenseError;
  final bool exporting;
  final Object? exportError;

  FinanceState copyWith({
    List<Payment>? payments,
    bool? loading,
    Object? loadError = _unset,
    double? total,
    int? totalCount,
    String? period,
    Object? customRange = _unset,
    bool? usesExternalRange,
    Object? branchId = _unset,
    List<Map<String, dynamic>>? expenses,
    bool? expensesLoading,
    double? expensesTotal,
    bool? savingExpense,
    Object? expenseError = _unset,
    bool? exporting,
    Object? exportError = _unset,
  }) {
    return FinanceState(
      payments: payments ?? this.payments,
      loading: loading ?? this.loading,
      loadError: identical(loadError, _unset) ? this.loadError : loadError,
      total: total ?? this.total,
      totalCount: totalCount ?? this.totalCount,
      period: period ?? this.period,
      customRange: identical(customRange, _unset)
          ? this.customRange
          : customRange as DateTimeRange?,
      usesExternalRange: usesExternalRange ?? this.usesExternalRange,
      branchId: identical(branchId, _unset)
          ? this.branchId
          : branchId as String?,
      expenses: expenses ?? this.expenses,
      expensesLoading: expensesLoading ?? this.expensesLoading,
      expensesTotal: expensesTotal ?? this.expensesTotal,
      savingExpense: savingExpense ?? this.savingExpense,
      expenseError: identical(expenseError, _unset)
          ? this.expenseError
          : expenseError,
      exporting: exporting ?? this.exporting,
      exportError: identical(exportError, _unset)
          ? this.exportError
          : exportError,
    );
  }
}
