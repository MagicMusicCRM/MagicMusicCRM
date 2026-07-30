import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';

enum EntityLifecycleState { active, archived, deleted }

enum EntityRouteState { resolved, forbidden, archived, deleted, unknown }

enum EntityProjection { full, limited }

class EntityRouteResolution {
  const EntityRouteResolution({
    required this.link,
    required this.state,
    this.location,
    this.projection,
  });

  final EntityLink link;
  final EntityRouteState state;
  final String? location;
  final EntityProjection? projection;

  bool get canOpen => state == EntityRouteState.resolved;
}

typedef EntityRouteBuilder =
    String Function(EntityLink link, CapabilitySnapshot snapshot);
typedef EntityCapabilityPolicy =
    bool Function(EntityLink link, CapabilitySnapshot snapshot);

class EntityRouteRegistration {
  const EntityRouteRegistration({
    required this.buildLocation,
    required this.isAllowed,
  });

  final EntityRouteBuilder buildLocation;
  final EntityCapabilityPolicy isAllowed;
}

class EntityRouteRegistry {
  EntityRouteRegistry({
    Map<EntityLinkType, EntityRouteRegistration>? registrations,
  }) : _registrations = registrations ?? _defaultRegistrations;

  final Map<EntityLinkType, EntityRouteRegistration> _registrations;

  EntityRouteResolution resolve(
    EntityLink link,
    CapabilitySnapshot snapshot, {
    EntityLifecycleState lifecycle = EntityLifecycleState.active,
  }) {
    final registration = _registrations[link.entityType];
    if (!link.isSupported || registration == null) {
      return EntityRouteResolution(link: link, state: EntityRouteState.unknown);
    }
    if (!registration.isAllowed(link, snapshot)) {
      return EntityRouteResolution(
        link: link,
        state: EntityRouteState.forbidden,
      );
    }
    if (lifecycle == EntityLifecycleState.deleted) {
      return EntityRouteResolution(link: link, state: EntityRouteState.deleted);
    }
    if (lifecycle == EntityLifecycleState.archived) {
      return EntityRouteResolution(
        link: link,
        state: EntityRouteState.archived,
      );
    }
    return EntityRouteResolution(
      link: link,
      state: EntityRouteState.resolved,
      location: registration.buildLocation(link, snapshot),
      projection: _projectionFor(link, snapshot),
    );
  }

  static EntityProjection _projectionFor(
    EntityLink link,
    CapabilitySnapshot snapshot,
  ) {
    if (link.entityType == EntityLinkType.client &&
        snapshot.role == 'teacher') {
      return EntityProjection.limited;
    }
    return EntityProjection.full;
  }

  static bool _hasAny(
    CapabilitySnapshot snapshot,
    Iterable<String> capabilities,
  ) {
    return capabilities.any(snapshot.allows);
  }

  static String _staffSection(EntityLink link, String section, String home) {
    return Uri(
      path: home,
      queryParameters: {
        'section': section,
        'entityId': link.entityId,
        'entityType': link.rawEntityType,
      },
    ).toString();
  }

  static String _staffHome(CapabilitySnapshot snapshot) {
    return switch (snapshot.role) {
      'teacher' => '/teacher',
      'client' => '/client',
      'admin' || 'system_admin' => '/admin',
      _ => '/manager',
    };
  }

  static String _staffRoute(
    EntityLink link,
    CapabilitySnapshot snapshot,
    String section,
  ) {
    return _staffSection(link, section, _staffHome(snapshot));
  }

  static final Map<EntityLinkType, EntityRouteRegistration>
  _defaultRegistrations = {
    EntityLinkType.client: EntityRouteRegistration(
      isAllowed: (_, snapshot) => snapshot.allows('crm.client.read.basic'),
      buildLocation: (link, _) {
        final segment = link.rawEntityType == 'lead' ? 'leads' : 'students';
        return '/$segment/${Uri.encodeComponent(link.entityId)}';
      },
    ),
    EntityLinkType.lesson: EntityRouteRegistration(
      isAllowed: (_, snapshot) => _hasAny(snapshot, const {
        'schedule.lesson.read.assigned',
        'schedule.lesson.write',
      }),
      buildLocation: (link, _) =>
          '/lessons/${Uri.encodeComponent(link.entityId)}',
    ),
    EntityLinkType.task: EntityRouteRegistration(
      isAllowed: (_, snapshot) => snapshot.allows('workflow.task.read'),
      buildLocation: (link, snapshot) => _staffRoute(link, snapshot, 'tasks'),
    ),
    EntityLinkType.subscription: EntityRouteRegistration(
      isAllowed: (_, snapshot) =>
          snapshot.allows('commerce.client_finance.read'),
      buildLocation: (link, snapshot) => _staffRoute(link, snapshot, 'clients'),
    ),
    EntityLinkType.payment: EntityRouteRegistration(
      isAllowed: (_, snapshot) =>
          snapshot.allows('commerce.client_finance.read'),
      buildLocation: (link, snapshot) => _staffRoute(link, snapshot, 'finance'),
    ),
    EntityLinkType.user: EntityRouteRegistration(
      isAllowed: (_, snapshot) => snapshot.allows('system.settings.manage'),
      buildLocation: (link, _) =>
          '/admin/profiles/${Uri.encodeComponent(link.entityId)}',
    ),
    EntityLinkType.homework: EntityRouteRegistration(
      isAllowed: (_, snapshot) => snapshot.allows('crm.client.read.basic'),
      buildLocation: (link, snapshot) {
        if (snapshot.role == 'teacher') {
          return Uri(
            path: '/teacher',
            queryParameters: {'section': 'homework', 'entityId': link.entityId},
          ).toString();
        }
        return _staffRoute(link, snapshot, 'clients');
      },
    ),
    EntityLinkType.chat: EntityRouteRegistration(
      isAllowed: (_, snapshot) => snapshot.accountId.isNotEmpty,
      buildLocation: (link, snapshot) {
        final home = switch (snapshot.role) {
          'teacher' => '/teacher',
          'client' => '/client',
          'admin' || 'system_admin' => '/admin',
          _ => '/manager',
        };
        return Uri(
          path: home,
          queryParameters: {'section': 'chat', 'entityId': link.entityId},
        ).toString();
      },
    ),
    EntityLinkType.report: EntityRouteRegistration(
      isAllowed: (link, snapshot) {
        if (link.rawEntityType == 'school_finance_month') {
          return snapshot.allows('commerce.school_finance.read');
        }
        if (link.rawEntityType == 'lesson_list' &&
            const {
              'date',
              'lesson',
              'schedule',
              'conflictList',
            }.contains(link.optionalFocus?.focus)) {
          return _hasAny(snapshot, const {
            'schedule.lesson.read.assigned',
            'schedule.lesson.write',
            'crm.client.read.basic',
          });
        }
        return snapshot.allows('report.status.read');
      },
      buildLocation: (link, snapshot) {
        final isSchedule =
            link.rawEntityType == 'lesson_list' &&
            const {
              'date',
              'lesson',
              'schedule',
              'conflictList',
            }.contains(link.optionalFocus?.focus);
        return _staffRoute(link, snapshot, isSchedule ? 'schedule' : 'reports');
      },
    ),
    EntityLinkType.teacher: EntityRouteRegistration(
      isAllowed: (_, snapshot) => _hasAny(snapshot, const {
        'schedule.lesson.read.assigned',
        'schedule.lesson.write',
      }),
      buildLocation: (link, snapshot) =>
          _staffRoute(link, snapshot, 'schedule'),
    ),
    EntityLinkType.group: EntityRouteRegistration(
      isAllowed: (_, snapshot) => _hasAny(snapshot, const {
        'schedule.lesson.read.assigned',
        'schedule.lesson.write',
      }),
      buildLocation: (link, snapshot) =>
          _staffRoute(link, snapshot, 'schedule'),
    ),
    EntityLinkType.room: EntityRouteRegistration(
      isAllowed: (_, snapshot) => _hasAny(snapshot, const {
        'schedule.lesson.read.assigned',
        'schedule.lesson.write',
      }),
      buildLocation: (link, snapshot) =>
          _staffRoute(link, snapshot, 'schedule'),
    ),
    EntityLinkType.branch: EntityRouteRegistration(
      isAllowed: (_, snapshot) => _hasAny(snapshot, const {
        'schedule.lesson.read.assigned',
        'schedule.lesson.write',
        'workflow.task.read',
      }),
      buildLocation: (link, snapshot) =>
          _staffRoute(link, snapshot, 'schedule'),
    ),
    EntityLinkType.scheduleSeries: EntityRouteRegistration(
      isAllowed: (_, snapshot) => _hasAny(snapshot, const {
        'schedule.lesson.read.assigned',
        'schedule.lesson.write',
      }),
      buildLocation: (link, snapshot) =>
          _staffRoute(link, snapshot, 'schedule'),
    ),
    EntityLinkType.comment: EntityRouteRegistration(
      isAllowed: (_, snapshot) => _hasAny(snapshot, const {
        'crm.comment.read.shared',
        'crm.client.read.basic',
      }),
      buildLocation: (link, snapshot) => _staffRoute(link, snapshot, 'clients'),
    ),
    EntityLinkType.clientSource: EntityRouteRegistration(
      isAllowed: (_, snapshot) => snapshot.allows('crm.client.write'),
      buildLocation: (link, snapshot) => _staffRoute(link, snapshot, 'clients'),
    ),
    EntityLinkType.clientStatus: EntityRouteRegistration(
      isAllowed: (_, snapshot) => snapshot.allows('crm.client.read.basic'),
      buildLocation: (link, snapshot) => _staffRoute(link, snapshot, 'clients'),
    ),
    EntityLinkType.subscriptionPackage: EntityRouteRegistration(
      isAllowed: (_, snapshot) => snapshot.allows('commerce.package.read'),
      buildLocation: (link, snapshot) => _staffRoute(link, snapshot, 'clients'),
    ),
  };
}
