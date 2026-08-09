import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';

class CrmNavigationRequest {
  const CrmNavigationRequest({
    required this.link,
    required this.sourceState,
    this.openInNewTab = false,
  });

  factory CrmNavigationRequest.schedule({
    required DateTime date,
    String? lessonId,
    String? leadId,
    String? clientType,
    String? clientId,
  }) {
    return CrmNavigationRequest(
      link: EntityLink.typed(
        entityType: EntityLinkType.report,
        entityId: date.toUtc().toIso8601String(),
        variant: 'lesson_list',
        optionalFocus: EntityLinkFocus(
          focus: lessonId == null ? 'date' : 'lesson',
          filter: {
            'date': date.toUtc().toIso8601String(),
            if (lessonId != null && lessonId.isNotEmpty) 'lessonId': lessonId,
            if (leadId != null && leadId.isNotEmpty) 'leadId': leadId,
            if (clientType != null && clientType.isNotEmpty)
              'clientType': clientType,
            if (clientId != null && clientId.isNotEmpty) 'clientId': clientId,
          },
        ),
      ),
      sourceState: ContextViewState(date: date),
    );
  }

  factory CrmNavigationRequest.userRolesSearch(String query) {
    return CrmNavigationRequest(
      link: EntityLink.typed(
        entityType: EntityLinkType.user,
        entityId: 'user-search',
        optionalFocus: EntityLinkFocus(
          focus: 'permissions',
          filter: {'query': query},
        ),
      ),
      sourceState: ContextViewState(filters: {'query': query}),
    );
  }

  factory CrmNavigationRequest.directChat(String userId) {
    return CrmNavigationRequest(
      link: EntityLink.typed(
        entityType: EntityLinkType.chat,
        entityId: userId,
        optionalFocus: EntityLinkFocus(
          focus: 'direct',
          filter: {'partnerId': userId},
        ),
      ),
      sourceState: ContextViewState(filters: {'partnerId': userId}),
    );
  }

  final EntityLink link;
  final ContextViewState sourceState;
  final bool openInNewTab;
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

int? crmTabForEntityLink(EntityLink link, String role) {
  if (link.entityType == EntityLinkType.chat) return 0;
  final isScheduleReport =
      link.entityType == EntityLinkType.report &&
      link.rawEntityType == 'lesson_list' &&
      const {
        'date',
        'lesson',
        'schedule',
        'conflictList',
      }.contains(link.optionalFocus?.focus);
  if (isScheduleReport) {
    return role == 'teacher' ? 1 : 2;
  }
  if (link.entityType == EntityLinkType.report &&
      link.rawEntityType == 'overview') {
    return role == 'teacher' ? null : 1;
  }
  if (link.entityType == EntityLinkType.report &&
      link.rawEntityType == 'configuration') {
    return role == 'teacher' ? null : 8;
  }
  if (role == 'teacher') {
    return switch (link.entityType) {
      EntityLinkType.lesson ||
      EntityLinkType.teacher ||
      EntityLinkType.group ||
      EntityLinkType.room ||
      EntityLinkType.branch ||
      EntityLinkType.scheduleSeries ||
      EntityLinkType.report => 1,
      EntityLinkType.client ||
      EntityLinkType.clientStatus ||
      EntityLinkType.homework ||
      EntityLinkType.comment => 2,
      _ => null,
    };
  }
  return switch (link.entityType) {
    EntityLinkType.lesson ||
    EntityLinkType.teacher ||
    EntityLinkType.group ||
    EntityLinkType.room ||
    EntityLinkType.branch ||
    EntityLinkType.scheduleSeries => 2,
    EntityLinkType.payment
        when link.optionalFocus?.filter['studentId']?.toString().isNotEmpty ==
            true =>
      3,
    EntityLinkType.client ||
    EntityLinkType.subscription ||
    EntityLinkType.homework ||
    EntityLinkType.comment ||
    EntityLinkType.clientSource ||
    EntityLinkType.clientStatus ||
    EntityLinkType.subscriptionPackage => 3,
    EntityLinkType.user => 8,
    EntityLinkType.payment => 5,
    EntityLinkType.task => 6,
    EntityLinkType.report => 7,
    _ => null,
  };
}
