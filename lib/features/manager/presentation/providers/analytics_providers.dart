import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

final analyticsFunnelProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsFunnel(),
    );

final analyticsDebtsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsDebts(),
    );

final analyticsBranchesProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsBranches(),
    );

final analyticsForecastProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsForecast(),
    );

final analyticsChurnProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsChurn(),
    );

final analyticsChatSlaProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsChatSla(),
    );

final analyticsLossReasonsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>(
      (ref) => ref.watch(magicCrmServiceProvider).getAnalyticsLossReasons(),
    );
