import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';

abstract interface class UtilizationDataSource {
  Future<Map<String, dynamic>> load(DashboardFilter filter);
}

final utilizationDataSourceProvider = Provider<UtilizationDataSource>(
  (ref) => MagicCrmUtilizationDataSource(ref),
);

class MagicCrmUtilizationDataSource implements UtilizationDataSource {
  MagicCrmUtilizationDataSource(Ref ref) : _ref = ref;

  final Ref _ref;

  MagicCrmService get _crm => _ref.read(magicCrmServiceProvider);

  @override
  Future<Map<String, dynamic>> load(DashboardFilter filter) {
    final apiFilter = filter.apiFilter;
    return _crm.getV4Utilization(
      branchId: apiFilter['branchId']?.toString(),
      from: apiFilter['from']?.toString(),
      to: apiFilter['to']?.toString(),
    );
  }
}
