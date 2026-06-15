import 'package:flutter_riverpod/flutter_riverpod.dart';

class CrmNavigationRequest {
  final int tabIndex;
  final String? userSearch;

  const CrmNavigationRequest({required this.tabIndex, this.userSearch});

  const CrmNavigationRequest.userRolesSearch(String query)
    : tabIndex = 4,
      userSearch = query;
}

class CrmNavigationRequestNotifier extends Notifier<CrmNavigationRequest?> {
  @override
  CrmNavigationRequest? build() => null;

  void navigateTo(CrmNavigationRequest? request) => state = request;

  void clear() => state = null;
}

final crmNavigationRequestProvider =
    NotifierProvider<CrmNavigationRequestNotifier, CrmNavigationRequest?>(
      CrmNavigationRequestNotifier.new,
    );
