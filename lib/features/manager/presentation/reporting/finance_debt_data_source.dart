import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

abstract interface class FinanceDebtDataSource {
  Future<Map<String, dynamic>> loadSummary(DashboardFilter filter);

  Future<Map<String, dynamic>> loadItems(
    DashboardFilter filter, {
    required String segment,
    int limit = 50,
    int offset = 0,
  });
}

final financeDebtDataSourceProvider = Provider<FinanceDebtDataSource>(
  (ref) => MagicCrmFinanceDebtDataSource(ref),
);

class MagicCrmFinanceDebtDataSource implements FinanceDebtDataSource {
  MagicCrmFinanceDebtDataSource(Ref ref) : _ref = ref;

  final Ref _ref;

  MagicCrmService get _crm => _ref.read(magicCrmServiceProvider);

  @override
  Future<Map<String, dynamic>> loadSummary(DashboardFilter filter) {
    final apiFilter = filter.apiFilter;
    return _crm.getV4FinanceDebtSummary(
      branchId: apiFilter['branchId']?.toString(),
      from: apiFilter['from']?.toString(),
      to: apiFilter['to']?.toString(),
    );
  }

  @override
  Future<Map<String, dynamic>> loadItems(
    DashboardFilter filter, {
    required String segment,
    int limit = 50,
    int offset = 0,
  }) {
    return _crm.getV4FinanceDebtItems(
      filter: filter.apiFilter,
      segment: segment,
      limit: limit,
      offset: offset,
    );
  }
}
