import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';

enum EntityLifecycleState { active, archived, deleted }

enum EntityRouteState { resolved, forbidden, archived, deleted, unknown }

enum EntityProjection { full, limited }

enum AppSurfaceKind { primary, quickView, selection, confirmation, comparison }

class EntityPresentationResolver {
  const EntityPresentationResolver();

  EntityPresentationReference resolve(
    EntityLink link, {
    EntityRouteState state = EntityRouteState.resolved,
  }) {
    final saved = link.presentation;
    return switch (state) {
      EntityRouteState.forbidden ||
      EntityRouteState.unknown => const EntityPresentationReference(
        primary: 'Связанная запись недоступна',
      ),
      EntityRouteState.deleted => EntityPresentationReference(
        primary: 'Удалённая запись',
        context: _savedContext(saved),
      ),
      EntityRouteState.archived => EntityPresentationReference(
        primary: 'Архивная запись',
        context: _savedContext(saved),
      ),
      EntityRouteState.resolved =>
        saved?.isUsable == true
            ? saved!
            : EntityPresentationReference(primary: _entityTypeTitle(link)),
    };
  }

  String pageTitle(
    EntityLink link, {
    EntityRouteState state = EntityRouteState.resolved,
  }) {
    final resolved = resolve(link, state: state);
    if (state == EntityRouteState.resolved &&
        link.presentation?.isUsable == true) {
      return '${_entityTypeTitle(link)} · ${resolved.primary.trim()}';
    }
    return resolved.primary;
  }

  static String? _savedContext(EntityPresentationReference? saved) {
    if (saved?.isUsable != true) return null;
    return [
      saved!.primary.trim(),
      if (saved.context?.trim().isNotEmpty == true) saved.context!.trim(),
    ].join(' · ');
  }
}

class AppBreadcrumbNode {
  const AppBreadcrumbNode({
    required this.routeName,
    required this.title,
    required this.location,
    required this.link,
  });

  final String routeName;
  final String title;
  final String location;
  final EntityLink link;

  Map<String, Object?> toJson() => {
    'routeName': routeName,
    'title': title,
    'location': location,
    'link': link.toJson(),
  };
}

class CanonicalAppLocation {
  CanonicalAppLocation({
    required this.link,
    required this.routeName,
    required this.location,
    required this.title,
    required Set<String> requiredCapabilities,
    required this.surfaceKind,
    required List<AppBreadcrumbNode> ancestors,
    this.viewStateVersion = ContextViewState.schemaVersion,
  }) : ancestors = List.unmodifiable(ancestors),
       requiredCapabilities = Set.unmodifiable(requiredCapabilities);

  final EntityLink link;
  final String routeName;
  final String location;
  final String title;
  final Set<String> requiredCapabilities;
  final AppSurfaceKind surfaceKind;
  final List<AppBreadcrumbNode> ancestors;
  final int viewStateVersion;

  Map<String, Object?> toJson() => {
    'routeName': routeName,
    'location': location,
    'link': link.toJson(),
    'title': title,
    'requiredCapabilities': requiredCapabilities.toList()..sort(),
    'surfaceKind': surfaceKind.name,
    'ancestors': [for (final ancestor in ancestors) ancestor.toJson()],
    'viewStateVersion': viewStateVersion,
  };
}

class EntityRouteResolution {
  const EntityRouteResolution({
    required this.link,
    required this.state,
    this.location,
    this.projection,
    this.canonicalLocation,
  });

  final EntityLink link;
  final EntityRouteState state;
  final String? location;
  final EntityProjection? projection;
  final CanonicalAppLocation? canonicalLocation;

  bool get canOpen => state == EntityRouteState.resolved;

  EntityPresentationReference get presentation =>
      const EntityPresentationResolver().resolve(link, state: state);
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
    final location = registration.buildLocation(link, snapshot);
    return EntityRouteResolution(
      link: link,
      state: EntityRouteState.resolved,
      location: location,
      projection: _projectionFor(link, snapshot),
      canonicalLocation: _canonicalize(link, snapshot, location),
    );
  }

  EntityRouteResolution resolveLocation(
    String location,
    CapabilitySnapshot snapshot,
  ) {
    final uri = Uri.tryParse(location);
    if (uri == null) {
      return EntityRouteResolution(
        link: EntityLink.fromJson(const {}),
        state: EntityRouteState.unknown,
      );
    }
    final segments = uri.pathSegments;
    final clientSection = uri.queryParameters['section'];
    final clientFocus = clientSection == null || clientSection.isEmpty
        ? null
        : EntityLinkFocus(focus: 'section', filter: {'section': clientSection});
    EntityLink? link;
    if (segments.length == 2) {
      final id = Uri.decodeComponent(segments[1]);
      link = switch (segments.first) {
        'student' || 'students' => EntityLink.typed(
          entityType: EntityLinkType.client,
          entityId: id,
          optionalFocus: clientFocus,
          variant: 'student',
        ),
        'leads' => EntityLink.typed(
          entityType: EntityLinkType.client,
          entityId: id,
          optionalFocus: clientFocus,
          variant: 'lead',
        ),
        'lessons' => EntityLink.typed(
          entityType: EntityLinkType.lesson,
          entityId: id,
        ),
        _ => null,
      };
    } else if (segments.length == 3 &&
        segments[0] == 'admin' &&
        segments[1] == 'profiles') {
      link = EntityLink.typed(
        entityType: EntityLinkType.user,
        entityId: Uri.decodeComponent(segments[2]),
      );
    }

    final entityId = uri.queryParameters['entityId'];
    if (link == null && entityId != null && entityId.trim().isNotEmpty) {
      final rawType =
          uri.queryParameters['entityType'] ??
          switch (uri.queryParameters['section']) {
            'chat' => 'chat',
            'homework' => 'homework',
            'tasks' => 'task',
            'schedule' => 'lesson_list',
            'reports' => 'report',
            _ => '',
          };
      final focus = uri.queryParameters['focus'];
      final filter = <String, dynamic>{
        for (final entry in uri.queryParameters.entries)
          if (entry.key.startsWith('f.')) entry.key.substring(2): entry.value,
      };
      link = EntityLink.fromJson({
        'entityType': rawType,
        'entityId': entityId,
        if (uri.queryParameters['entityTitle']?.trim().isNotEmpty == true)
          'presentation': {
            'primary': uri.queryParameters['entityTitle'],
            if (uri.queryParameters['entityContext']?.trim().isNotEmpty == true)
              'context': uri.queryParameters['entityContext'],
          },
        if ((focus != null && focus.isNotEmpty) || filter.isNotEmpty)
          'optionalFocus': {
            if (focus != null && focus.isNotEmpty) 'focus': focus,
            if (filter.isNotEmpty) 'filter': filter,
          },
      });
    }
    if (link == null || !link.isSupported) {
      return EntityRouteResolution(
        link: link ?? EntityLink.fromJson(const {}),
        state: EntityRouteState.unknown,
      );
    }
    return resolve(link, snapshot);
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

  static CanonicalAppLocation _canonicalize(
    EntityLink link,
    CapabilitySnapshot snapshot,
    String location,
  ) {
    final section = _sectionFor(link);
    final home = _staffHome(snapshot);
    final rootLocation = Uri(
      path: home,
      queryParameters: {'section': section},
    ).toString();
    final isSectionRoot = link.entityId == '__section__';
    return CanonicalAppLocation(
      link: link,
      routeName: 'entity:${link.rawEntityType}',
      location: location,
      title: isSectionRoot
          ? _sectionTitle(section)
          : const EntityPresentationResolver().pageTitle(link),
      requiredCapabilities: _requiredCapabilitiesFor(link),
      surfaceKind: link.entityType == EntityLinkType.report
          ? AppSurfaceKind.comparison
          : AppSurfaceKind.primary,
      ancestors: isSectionRoot
          ? const []
          : [
              AppBreadcrumbNode(
                routeName: 'section:$section',
                title: _sectionTitle(section),
                location: rootLocation,
                link: sectionRootLink(section),
              ),
            ],
    );
  }

  static EntityLink sectionRootLink(String section) {
    final focus = EntityLinkFocus(focus: 'section');
    return switch (section) {
      'clients' => EntityLink.typed(
        entityType: EntityLinkType.clientStatus,
        entityId: '__section__',
        optionalFocus: focus,
      ),
      'schedule' => EntityLink.typed(
        entityType: EntityLinkType.report,
        entityId: '__section__',
        optionalFocus: EntityLinkFocus(focus: 'schedule'),
        variant: 'lesson_list',
      ),
      'tasks' => EntityLink.typed(
        entityType: EntityLinkType.task,
        entityId: '__section__',
        optionalFocus: focus,
      ),
      'finance' => EntityLink.typed(
        entityType: EntityLinkType.payment,
        entityId: '__section__',
        optionalFocus: focus,
      ),
      'users' => EntityLink.typed(
        entityType: EntityLinkType.report,
        entityId: '__section__',
        optionalFocus: EntityLinkFocus(focus: 'users', filter: focus.filter),
        variant: 'configuration',
      ),
      'homework' => EntityLink.typed(
        entityType: EntityLinkType.homework,
        entityId: '__section__',
        optionalFocus: focus,
      ),
      'reports' => EntityLink.typed(
        entityType: EntityLinkType.report,
        entityId: '__section__',
        optionalFocus: focus,
      ),
      'overview' => EntityLink.typed(
        entityType: EntityLinkType.report,
        entityId: '__section__',
        optionalFocus: focus,
        variant: 'overview',
      ),
      'configuration' => EntityLink.typed(
        entityType: EntityLinkType.report,
        entityId: '__section__',
        optionalFocus: focus,
        variant: 'configuration',
      ),
      _ => EntityLink.typed(
        entityType: EntityLinkType.chat,
        entityId: 'home',
        optionalFocus: focus,
      ),
    };
  }

  static String _sectionFor(EntityLink link) => switch (link.entityType) {
    EntityLinkType.report
        when link.rawEntityType == 'lesson_list' &&
            const {
              'date',
              'lesson',
              'schedule',
              'conflictList',
            }.contains(link.optionalFocus?.focus) =>
      'schedule',
    EntityLinkType.report when link.rawEntityType == 'overview' => 'overview',
    EntityLinkType.report when link.rawEntityType == 'configuration' =>
      'configuration',
    EntityLinkType.client ||
    EntityLinkType.subscription ||
    EntityLinkType.comment ||
    EntityLinkType.clientSource ||
    EntityLinkType.clientStatus ||
    EntityLinkType.subscriptionPackage => 'clients',
    EntityLinkType.lesson ||
    EntityLinkType.teacher ||
    EntityLinkType.group ||
    EntityLinkType.room ||
    EntityLinkType.branch ||
    EntityLinkType.scheduleSeries => 'schedule',
    EntityLinkType.task => 'tasks',
    EntityLinkType.payment
        when link.optionalFocus?.filter['studentId']?.toString().isNotEmpty ==
            true =>
      'clients',
    EntityLinkType.payment => 'finance',
    EntityLinkType.user => 'configuration',
    EntityLinkType.homework => 'homework',
    EntityLinkType.chat => 'chat',
    EntityLinkType.report => 'reports',
    EntityLinkType.unknown => 'home',
  };

  static String _sectionTitle(String section) => switch (section) {
    'clients' => 'Клиенты',
    'schedule' => 'Расписание',
    'tasks' => 'Задачи',
    'finance' => 'Финансы',
    'users' => 'Пользователи',
    'homework' => 'Домашние задания',
    'chat' => 'Чат',
    'reports' => 'Аналитика',
    'overview' => 'Обзор',
    'configuration' => 'Настройки',
    _ => 'Главная',
  };

  static Set<String> _requiredCapabilitiesFor(EntityLink link) {
    if (link.entityType == EntityLinkType.report &&
        link.rawEntityType == 'configuration') {
      return const {'config.crm.read', 'system.settings.manage'};
    }
    if (link.entityType == EntityLinkType.report &&
        link.rawEntityType == 'lesson_list' &&
        const {
          'date',
          'lesson',
          'schedule',
          'conflictList',
        }.contains(link.optionalFocus?.focus)) {
      return const {'schedule.lesson.read.assigned', 'schedule.lesson.write'};
    }
    return switch (link.entityType) {
      EntityLinkType.client ||
      EntityLinkType.homework ||
      EntityLinkType.comment ||
      EntityLinkType.clientStatus => const {'crm.client.read.basic'},
      EntityLinkType.lesson ||
      EntityLinkType.teacher ||
      EntityLinkType.group ||
      EntityLinkType.room ||
      EntityLinkType.branch ||
      EntityLinkType.scheduleSeries => const {
        'schedule.lesson.read.assigned',
        'schedule.lesson.write',
      },
      EntityLinkType.task => const {'workflow.task.read'},
      EntityLinkType.subscription ||
      EntityLinkType.payment => const {'commerce.client_finance.read'},
      EntityLinkType.user => const {'system.settings.manage'},
      EntityLinkType.report => const {'report.status.read'},
      EntityLinkType.clientSource => const {'crm.client.write'},
      EntityLinkType.subscriptionPackage => const {'commerce.package.read'},
      EntityLinkType.chat || EntityLinkType.unknown => const {},
    };
  }

  static bool _hasAny(
    CapabilitySnapshot snapshot,
    Iterable<String> capabilities,
  ) {
    return capabilities.any(snapshot.allows);
  }

  static String _staffSection(EntityLink link, String section, String home) {
    final focus = link.optionalFocus;
    return Uri(
      path: home,
      queryParameters: {
        'section': section,
        'entityId': link.entityId,
        'entityType': link.rawEntityType,
        if (link.presentation?.isUsable == true)
          'entityTitle': link.presentation!.primary.trim(),
        if (link.presentation?.context?.trim().isNotEmpty == true)
          'entityContext': link.presentation!.context!.trim(),
        if (focus?.focus?.isNotEmpty == true) 'focus': focus!.focus,
        for (final entry
            in focus?.filter.entries ?? const <MapEntry<String, dynamic>>[])
          'f.${entry.key}': entry.value.toString(),
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
      buildLocation: (link, snapshot) {
        if (snapshot.role != 'client') {
          return _staffRoute(link, snapshot, 'clients');
        }
        final segment = link.rawEntityType == 'lead' ? 'leads' : 'students';
        final section = link.optionalFocus?.filter['section']?.toString();
        return Uri(
          pathSegments: ['', segment, link.entityId],
          queryParameters: section == null || section.isEmpty
              ? null
              : {'section': section},
        ).toString();
      },
    ),
    EntityLinkType.lesson: EntityRouteRegistration(
      isAllowed: (_, snapshot) => _hasAny(snapshot, const {
        'schedule.lesson.read.assigned',
        'schedule.lesson.write',
      }),
      buildLocation: (link, snapshot) =>
          _staffRoute(link, snapshot, 'schedule'),
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
      buildLocation: (link, snapshot) => _staffRoute(
        link,
        snapshot,
        link.optionalFocus?.filter['studentId']?.toString().isNotEmpty == true
            ? 'clients'
            : 'finance',
      ),
    ),
    EntityLinkType.user: EntityRouteRegistration(
      isAllowed: (_, snapshot) => snapshot.allows('system.settings.manage'),
      buildLocation: (link, snapshot) =>
          _staffRoute(link, snapshot, 'configuration'),
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
      buildLocation: (link, snapshot) => _staffRoute(link, snapshot, 'chat'),
    ),
    EntityLinkType.report: EntityRouteRegistration(
      isAllowed: (link, snapshot) {
        if (link.rawEntityType == 'configuration') {
          return snapshot.allows('config.crm.read') ||
              snapshot.allows('system.settings.manage');
        }
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
        return _staffRoute(
          link,
          snapshot,
          link.rawEntityType == 'configuration'
              ? 'configuration'
              : isSchedule
              ? 'schedule'
              : link.rawEntityType == 'overview'
              ? 'overview'
              : 'reports',
        );
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

String _entityTypeTitle(EntityLink link) => switch (link.entityType) {
  EntityLinkType.client => link.rawEntityType == 'lead' ? 'Лид' : 'Ученик',
  EntityLinkType.lesson => 'Занятие',
  EntityLinkType.task => 'Задача',
  EntityLinkType.subscription => 'Абонемент',
  EntityLinkType.payment => 'Оплата',
  EntityLinkType.user => 'Пользователь',
  EntityLinkType.homework => 'Домашнее задание',
  EntityLinkType.chat => 'Чат',
  EntityLinkType.report => 'Отчёт',
  EntityLinkType.teacher => 'Преподаватель',
  EntityLinkType.group => 'Группа',
  EntityLinkType.room => 'Аудитория',
  EntityLinkType.branch => 'Филиал',
  EntityLinkType.scheduleSeries => 'Серия занятий',
  EntityLinkType.comment => 'Комментарий',
  EntityLinkType.clientSource => 'Источник',
  EntityLinkType.clientStatus => 'Статус клиента',
  EntityLinkType.subscriptionPackage => 'Тип абонемента',
  EntityLinkType.unknown => 'Запись',
};
