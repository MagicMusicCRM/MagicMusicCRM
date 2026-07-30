import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';

enum ContextSourceType {
  schedule,
  teacherSchedule,
  studentCard,
  leadCard,
  lessonDetails,
  scheduleSeries,
  subscription,
  payment,
  task,
  chat,
  statusMetric,
  user,
  audit,
}

enum ContextTargetType {
  lesson,
  client,
  teacher,
  group,
  room,
  branch,
  homework,
  schedule,
  scheduleSeries,
  task,
  subscription,
  payment,
  lead,
  comment,
  clientSource,
  clientStatus,
  subscriptionPackage,
  conflictList,
  user,
  role,
  permissions,
  actions,
  changedEntity,
}

class ContextTransitionDefinition {
  const ContextTransitionDefinition({
    required this.source,
    required this.target,
    required this.entityType,
    this.variant,
  });

  final ContextSourceType source;
  final ContextTargetType target;
  final EntityLinkType entityType;
  final String? variant;
}

class ContextTransition {
  const ContextTransition({
    required this.source,
    required this.sourceState,
    required this.target,
  });

  final ContextSourceType source;
  final ContextViewState sourceState;
  final EntityLink target;
}

class ContextTransitionRegistry {
  const ContextTransitionRegistry();

  static const definitions = <ContextTransitionDefinition>[
    ContextTransitionDefinition(
      source: ContextSourceType.schedule,
      target: ContextTargetType.lesson,
      entityType: EntityLinkType.lesson,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.schedule,
      target: ContextTargetType.client,
      entityType: EntityLinkType.client,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.schedule,
      target: ContextTargetType.teacher,
      entityType: EntityLinkType.teacher,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.schedule,
      target: ContextTargetType.group,
      entityType: EntityLinkType.group,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.schedule,
      target: ContextTargetType.room,
      entityType: EntityLinkType.room,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.schedule,
      target: ContextTargetType.branch,
      entityType: EntityLinkType.branch,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.teacherSchedule,
      target: ContextTargetType.lesson,
      entityType: EntityLinkType.lesson,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.teacherSchedule,
      target: ContextTargetType.client,
      entityType: EntityLinkType.client,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.teacherSchedule,
      target: ContextTargetType.homework,
      entityType: EntityLinkType.homework,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.studentCard,
      target: ContextTargetType.schedule,
      entityType: EntityLinkType.report,
      variant: 'lesson_list',
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.studentCard,
      target: ContextTargetType.lesson,
      entityType: EntityLinkType.lesson,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.studentCard,
      target: ContextTargetType.scheduleSeries,
      entityType: EntityLinkType.scheduleSeries,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.studentCard,
      target: ContextTargetType.homework,
      entityType: EntityLinkType.homework,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.studentCard,
      target: ContextTargetType.task,
      entityType: EntityLinkType.task,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.studentCard,
      target: ContextTargetType.subscription,
      entityType: EntityLinkType.subscription,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.studentCard,
      target: ContextTargetType.payment,
      entityType: EntityLinkType.payment,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.studentCard,
      target: ContextTargetType.lead,
      entityType: EntityLinkType.client,
      variant: 'lead',
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.leadCard,
      target: ContextTargetType.lesson,
      entityType: EntityLinkType.lesson,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.leadCard,
      target: ContextTargetType.task,
      entityType: EntityLinkType.task,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.leadCard,
      target: ContextTargetType.comment,
      entityType: EntityLinkType.comment,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.leadCard,
      target: ContextTargetType.clientSource,
      entityType: EntityLinkType.clientSource,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.leadCard,
      target: ContextTargetType.clientStatus,
      entityType: EntityLinkType.clientStatus,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.leadCard,
      target: ContextTargetType.client,
      entityType: EntityLinkType.client,
      variant: 'student',
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.lessonDetails,
      target: ContextTargetType.client,
      entityType: EntityLinkType.client,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.lessonDetails,
      target: ContextTargetType.group,
      entityType: EntityLinkType.group,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.lessonDetails,
      target: ContextTargetType.teacher,
      entityType: EntityLinkType.teacher,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.lessonDetails,
      target: ContextTargetType.room,
      entityType: EntityLinkType.room,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.lessonDetails,
      target: ContextTargetType.branch,
      entityType: EntityLinkType.branch,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.lessonDetails,
      target: ContextTargetType.lesson,
      entityType: EntityLinkType.lesson,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.scheduleSeries,
      target: ContextTargetType.schedule,
      entityType: EntityLinkType.report,
      variant: 'lesson_list',
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.scheduleSeries,
      target: ContextTargetType.client,
      entityType: EntityLinkType.client,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.scheduleSeries,
      target: ContextTargetType.group,
      entityType: EntityLinkType.group,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.scheduleSeries,
      target: ContextTargetType.conflictList,
      entityType: EntityLinkType.report,
      variant: 'lesson_list',
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.subscription,
      target: ContextTargetType.subscriptionPackage,
      entityType: EntityLinkType.subscriptionPackage,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.subscription,
      target: ContextTargetType.payment,
      entityType: EntityLinkType.payment,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.subscription,
      target: ContextTargetType.lesson,
      entityType: EntityLinkType.lesson,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.payment,
      target: ContextTargetType.client,
      entityType: EntityLinkType.client,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.payment,
      target: ContextTargetType.subscription,
      entityType: EntityLinkType.subscription,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.task,
      target: ContextTargetType.client,
      entityType: EntityLinkType.client,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.task,
      target: ContextTargetType.lead,
      entityType: EntityLinkType.client,
      variant: 'lead',
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.task,
      target: ContextTargetType.lesson,
      entityType: EntityLinkType.lesson,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.task,
      target: ContextTargetType.user,
      entityType: EntityLinkType.user,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.task,
      target: ContextTargetType.branch,
      entityType: EntityLinkType.branch,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.chat,
      target: ContextTargetType.client,
      entityType: EntityLinkType.client,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.chat,
      target: ContextTargetType.user,
      entityType: EntityLinkType.user,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.chat,
      target: ContextTargetType.task,
      entityType: EntityLinkType.task,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.statusMetric,
      target: ContextTargetType.client,
      entityType: EntityLinkType.client,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.statusMetric,
      target: ContextTargetType.schedule,
      entityType: EntityLinkType.report,
      variant: 'client_status_list',
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.user,
      target: ContextTargetType.user,
      entityType: EntityLinkType.user,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.user,
      target: ContextTargetType.role,
      entityType: EntityLinkType.user,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.user,
      target: ContextTargetType.permissions,
      entityType: EntityLinkType.user,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.user,
      target: ContextTargetType.actions,
      entityType: EntityLinkType.user,
    ),
    ContextTransitionDefinition(
      source: ContextSourceType.audit,
      target: ContextTargetType.changedEntity,
      entityType: EntityLinkType.unknown,
    ),
  ];

  ContextTransition create({
    required ContextSourceType source,
    required ContextTargetType target,
    required String entityId,
    required ContextViewState sourceState,
    Map<String, dynamic> targetFilter = const {},
    String? rawEntityType,
  }) {
    final definition = definitions
        .where((item) => item.source == source && item.target == target)
        .firstOrNull;
    if (definition == null) {
      throw StateError('Unsupported context transition: $source → $target.');
    }

    final entityType = target == ContextTargetType.changedEntity
        ? _parseDynamicType(rawEntityType)
        : definition.entityType;
    final variant = target == ContextTargetType.changedEntity
        ? rawEntityType
        : definition.variant;
    final link = EntityLink.typed(
      entityType: entityType,
      entityId: entityId,
      variant: variant,
      optionalFocus: EntityLinkFocus(focus: target.name, filter: targetFilter),
    );
    if (!link.isSupported) {
      throw const FormatException('Transition target is unsupported.');
    }
    return ContextTransition(
      source: source,
      sourceState: sourceState,
      target: link,
    );
  }

  static EntityLinkType _parseDynamicType(String? rawType) {
    final probe = EntityLink.fromJson({
      'version': EntityLink.schemaVersion,
      'entityType': rawType,
      'entityId': 'probe',
    });
    return probe.entityType;
  }
}
