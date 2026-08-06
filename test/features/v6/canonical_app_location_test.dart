import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';

void main() {
  const capabilities = <String>{
    'crm.client.read.basic',
    'crm.client.write',
    'schedule.lesson.read.assigned',
    'schedule.lesson.write',
    'workflow.task.read',
    'commerce.client_finance.read',
    'commerce.package.read',
    'system.settings.manage',
    'report.status.read',
  };
  const snapshot = CapabilitySnapshot(
    accountId: 'account-1',
    role: 'director',
    accessVersion: 1,
    capabilities: capabilities,
    scopes: {},
  );

  test('typed link and direct URL resolve to one canonical location', () {
    final registry = EntityRouteRegistry();
    final link = EntityLink.typed(
      entityType: EntityLinkType.client,
      entityId: 'student-1',
      variant: 'student',
    );

    final fromLink = registry.resolve(link, snapshot);
    final fromUrl = registry.resolveLocation('/students/student-1', snapshot);

    expect(fromLink.state, EntityRouteState.resolved);
    expect(fromUrl.state, EntityRouteState.resolved);
    expect(fromUrl.canonicalLocation?.routeName, 'entity:student');
    expect(
      fromUrl.canonicalLocation?.toJson(),
      fromLink.canonicalLocation?.toJson(),
    );
    expect(fromUrl.canonicalLocation?.ancestors.single.title, 'Клиенты');
    expect(fromLink.location, startsWith('/manager?'));
    expect(
      Uri.parse(fromLink.location!).queryParameters,
      containsPair('section', 'clients'),
    );
    expect(
      fromUrl.canonicalLocation?.requiredCapabilities,
      contains('crm.client.read.basic'),
    );
  });

  test('client title survives the canonical staff route', () {
    final registry = EntityRouteRegistry();
    final resolved = registry.resolve(
      EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: 'lead-1',
        variant: 'lead',
        presentation: const EntityPresentationReference(
          primary: 'Анна Соколова',
          context: 'Лид',
        ),
      ),
      snapshot,
    );

    final restored = registry.resolveLocation(resolved.location!, snapshot);

    expect(restored.canonicalLocation?.ancestors.single.title, 'Клиенты');
    expect(restored.presentation.primary, 'Анна Соколова');
    expect(restored.presentation.context, 'Лид');
    expect(restored.canonicalLocation?.title, 'Лид · Анна Соколова');
  });

  test('query deep link uses the same entity registry policy', () {
    final registry = EntityRouteRegistry();
    final resolution = registry.resolveLocation(
      '/manager?section=tasks&entityId=task-1&entityType=task',
      snapshot,
    );

    expect(resolution.state, EntityRouteState.resolved);
    expect(resolution.link.entityType, EntityLinkType.task);
    expect(resolution.canonicalLocation?.routeName, 'entity:task');
    expect(resolution.canonicalLocation?.ancestors.single.title, 'Задачи');
  });

  test(
    'query deep link round-trips typed focus without display-name lookup',
    () {
      final registry = EntityRouteRegistry();
      final link = EntityLink.typed(
        entityType: EntityLinkType.lesson,
        entityId: 'lesson-1',
        optionalFocus: EntityLinkFocus(
          focus: 'lesson',
          filter: const {
            'date': '2026-08-04T00:00:00.000',
            'branchId': 'branch-1',
            'clientId': 'student-1',
          },
        ),
      );

      final location = registry.resolve(link, snapshot).location!;
      final restored = registry.resolveLocation(location, snapshot);

      expect(restored.state, EntityRouteState.resolved);
      expect(restored.link.entityType, EntityLinkType.lesson);
      expect(restored.link.entityId, 'lesson-1');
      expect(restored.link.optionalFocus?.focus, 'lesson');
      expect(restored.link.optionalFocus?.filter, link.optionalFocus?.filter);
    },
  );

  test('forbidden direct URL fails closed before canonical metadata', () {
    const teacher = CapabilitySnapshot(
      accountId: 'teacher-1',
      role: 'teacher',
      accessVersion: 1,
      capabilities: {'crm.client.read.basic'},
      scopes: {},
    );

    final resolution = EntityRouteRegistry().resolveLocation(
      '/manager?section=finance&entityId=payment-1&entityType=payment',
      teacher,
    );

    expect(resolution.state, EntityRouteState.forbidden);
    expect(resolution.canonicalLocation, isNull);
  });

  test('schedule path metadata keeps schedule capability semantics', () {
    final resolution = EntityRouteRegistry().resolve(
      EntityLink.typed(
        entityType: EntityLinkType.report,
        entityId: '__section__',
        variant: 'lesson_list',
        optionalFocus: EntityLinkFocus(focus: 'schedule'),
      ),
      snapshot,
    );

    expect(resolution.canonicalLocation?.title, 'Расписание');
    expect(
      resolution.canonicalLocation?.requiredCapabilities,
      contains('schedule.lesson.read.assigned'),
    );
    expect(
      resolution.canonicalLocation?.requiredCapabilities,
      isNot(contains('report.status.read')),
    );
  });

  test('CRM configuration has a director destination and capability guard', () {
    const director = CapabilitySnapshot(
      accountId: 'director-1',
      role: 'director',
      accessVersion: 1,
      capabilities: {'config.crm.read'},
      scopes: {},
    );
    final link = EntityRouteRegistry.sectionRootLink('configuration');
    final resolution = EntityRouteRegistry().resolve(link, director);

    expect(resolution.state, EntityRouteState.resolved);
    expect(resolution.canonicalLocation?.title, 'Настройки');
    expect(resolution.canonicalLocation?.requiredCapabilities, {
      'config.crm.read',
      'system.settings.manage',
    });
    expect(
      EntityRouteRegistry().resolve(link, snapshot).state,
      EntityRouteState.resolved,
    );
  });

  test('view state has a fail-closed schema version', () {
    final encoded = ContextViewState(
      filters: const {'branch': 'branch-1'},
      scrollOffset: 42,
    ).toJson();

    expect(encoded['version'], ContextViewState.schemaVersion);
    expect(ContextViewState.fromJson(encoded).scrollOffset, 42);
    expect(
      () => ContextViewState.fromJson({...encoded, 'version': 99}),
      throwsFormatException,
    );
  });
}
