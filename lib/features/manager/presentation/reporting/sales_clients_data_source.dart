import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

abstract interface class SalesClientsDataSource {
  Future<Map<String, dynamic>> loadSummary(DashboardFilter filter);

  Future<Map<String, dynamic>> loadClients(
    DashboardFilter filter, {
    required String segment,
    String? sourceId,
    int limit = 50,
    int offset = 0,
  });
}

final salesClientsDataSourceProvider = Provider<SalesClientsDataSource>(
  (ref) => MagicCrmSalesClientsDataSource(ref),
);

class MagicCrmSalesClientsDataSource implements SalesClientsDataSource {
  MagicCrmSalesClientsDataSource(Ref ref) : _ref = ref;

  final Ref _ref;

  MagicCrmService get _crm => _ref.read(magicCrmServiceProvider);

  @override
  Future<Map<String, dynamic>> loadSummary(DashboardFilter filter) {
    final apiFilter = filter.apiFilter;
    return _crm.getV4SalesClientsSummary(
      branchId: apiFilter['branchId']?.toString(),
      from: apiFilter['from']?.toString(),
      to: apiFilter['to']?.toString(),
    );
  }

  @override
  Future<Map<String, dynamic>> loadClients(
    DashboardFilter filter, {
    required String segment,
    String? sourceId,
    int limit = 50,
    int offset = 0,
  }) {
    return _crm.getV4SalesClientsList(
      filter: filter.apiFilter,
      segment: segment,
      sourceId: sourceId,
      limit: limit,
      offset: offset,
    );
  }
}
