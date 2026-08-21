import 'package:magic_music_crm/core/navigation/entity_link.dart';

enum EntityRouteState { resolved, forbidden, archived, deleted, unknown }

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

String _entityTypeTitle(EntityLink link) => switch (link.entityType) {
  EntityLinkType.client => link.rawEntityType == 'lead' ? 'Лид' : 'Ученик',
  EntityLinkType.lesson => 'Занятие',
  EntityLinkType.task => 'Задача',
  EntityLinkType.subscription => 'Абонемент',
  EntityLinkType.payment => 'Оплата',
  EntityLinkType.user => 'Пользователь',
  EntityLinkType.homework => 'Домашнее задание',
  EntityLinkType.chat => 'Чат',
  EntityLinkType.report when link.rawEntityType == 'lesson_list' =>
    'Расписание',
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
