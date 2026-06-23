import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

final analyticsFunnelProvider =
    FutureProvider<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsFunnel(),
    );

final analyticsDebtsProvider =
    FutureProvider<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsDebts(),
    );

final analyticsBranchesProvider =
    FutureProvider<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsBranches(),
    );

final analyticsForecastProvider =
    FutureProvider<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsForecast(),
    );

final analyticsChurnProvider =
    FutureProvider<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsChurn(),
    );

final analyticsChatSlaProvider =
    FutureProvider<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsChatSla(),
    );

final analyticsLossReasonsProvider =
    FutureProvider<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsLossReasons(),
    );
