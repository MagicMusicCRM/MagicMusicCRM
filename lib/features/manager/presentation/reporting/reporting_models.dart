import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';

enum ReportingSectionKey { status, lessons, tasks, finance }

enum DashboardPeriodPreset { week, month, year }

@immutable
class ReportingSection<T> {
  const ReportingSection({
    this.data,
    this.loading = false,
    this.error,
    this.forbidden = false,
  });

  final T? data;
  final bool loading;
  final Object? error;
  final bool forbidden;
}

@immutable
class ReportingState {
  const ReportingState({
    required this.loading,
    required this.forbidden,
    required this.status,
    required this.lessons,
    required this.tasks,
    required this.finance,
  });

  factory ReportingState.initial() => const ReportingState(
    loading: true,
    forbidden: false,
    status: ReportingSection(),
    lessons: ReportingSection(),
    tasks: ReportingSection(),
    finance: ReportingSection(),
  );

  final bool loading;
  final bool forbidden;
  final ReportingSection<Map<String, dynamic>> status;
  final ReportingSection<Map<String, dynamic>> lessons;
  final ReportingSection<Map<String, dynamic>> tasks;
  final ReportingSection<Map<String, dynamic>> finance;
}

@immutable
class DashboardFilter {
  const DashboardFilter({required this.from, required this.to, this.branchId});

  factory DashboardFilter.defaults() {
    final now = DateTime.now();
    return DashboardFilter(
      from: DateTime(now.year, now.month - 5, 1),
      to: DateTime(now.year, now.month, now.day),
    );
  }

  factory DashboardFilter.forPreset(
    DashboardPeriodPreset preset, {
    DateTime? now,
    String? branchId,
  }) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final from = switch (preset) {
      DashboardPeriodPreset.week => today.subtract(
        Duration(days: today.weekday - DateTime.monday),
      ),
      DashboardPeriodPreset.month => DateTime(today.year, today.month),
      DashboardPeriodPreset.year => DateTime(today.year),
    };
    return DashboardFilter(from: from, to: today, branchId: branchId);
  }

  factory DashboardFilter.fromContext(
    ContextViewState? state,
    Map<String, dynamic>? directFilter,
  ) {
    final fallback = DashboardFilter.defaults();
    final raw = <String, dynamic>{...?state?.filters, ...?directFilter};
    final from = DateTime.tryParse(
      raw['dashboardFrom']?.toString() ?? raw['from']?.toString() ?? '',
    );
    final to = DateTime.tryParse(
      raw['dashboardTo']?.toString() ?? raw['to']?.toString() ?? '',
    );
    final branch = raw['branchId']?.toString().trim();
    if (from == null || to == null || from.isAfter(to)) return fallback;
    return DashboardFilter(
      from: DateTime(from.year, from.month, from.day),
      to: DateTime(to.year, to.month, to.day),
      branchId: branch == null || branch.isEmpty ? null : branch,
    );
  }

  final DateTime from;
  final DateTime to;
  final String? branchId;

  Map<String, dynamic> get apiFilter => {
    'from': from.toUtc().toIso8601String(),
    'to': to.add(const Duration(days: 1)).toUtc().toIso8601String(),
    if (branchId != null) 'branchId': branchId,
  };

  ContextViewState toContextViewState() => ContextViewState(
    filters: {
      'dashboardFrom': from.toIso8601String(),
      'dashboardTo': to.toIso8601String(),
      if (branchId != null) 'branchId': branchId,
    },
  );

  DashboardFilter copyWithRange(DateTimeRange range) => DashboardFilter(
    from: DateTime(range.start.year, range.start.month, range.start.day),
    to: DateTime(range.end.year, range.end.month, range.end.day),
    branchId: branchId,
  );

  DashboardFilter copyWithBranch(String? value) =>
      DashboardFilter(from: from, to: to, branchId: value);

  DashboardFilter copyWithPreset(
    DashboardPeriodPreset preset, {
    DateTime? now,
  }) => DashboardFilter.forPreset(preset, now: now, branchId: branchId);

  bool matchesPreset(DashboardPeriodPreset preset, {DateTime? now}) {
    final expected = DashboardFilter.forPreset(
      preset,
      now: now,
      branchId: branchId,
    );
    return from == expected.from && to == expected.to;
  }

  @override
  bool operator ==(Object other) =>
      other is DashboardFilter &&
      other.from == from &&
      other.to == to &&
      other.branchId == branchId;

  @override
  int get hashCode => Object.hash(from, to, branchId);
}
