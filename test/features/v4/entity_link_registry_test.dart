import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_state_view.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';

void main() {
  const allCapabilities = {
    'crm.client.read.basic',
    'schedule.lesson.read.assigned',
    'workflow.task.read',
    'commerce.client_finance.read',
    'commerce.school_finance.read',
    'system.settings.manage',
    'report.status.read',
  };

  CapabilitySnapshot snapshot({
    String role = 'director',
    Set<String> capabilities = allCapabilities,
  }) {
    return CapabilitySnapshot(
      accountId: 'account-1',
      role: role,
      accessVersion: 1,
      capabilities: capabilities,
      scopes: const {},
    );
  }

  test('all v1 entity types resolve to one canonical target', () {
    final registry = EntityRouteRegistry();
    final links = [
      EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: 'client-1',
        variant: 'student',
      ),
      EntityLink.typed(entityType: EntityLinkType.lesson, entityId: 'lesson-1'),
      EntityLink.typed(entityType: EntityLinkType.task, entityId: 'task-1'),
      EntityLink.typed(
        entityType: EntityLinkType.subscription,
        entityId: 'subscription-1',
      ),
      EntityLink.typed(
        entityType: EntityLinkType.payment,
        entityId: 'payment-1',
      ),
      EntityLink.typed(entityType: EntityLinkType.user, entityId: 'user-1'),
      EntityLink.typed(
        entityType: EntityLinkType.homework,
        entityId: 'homework-1',
      ),
      EntityLink.typed(entityType: EntityLinkType.chat, entityId: 'chat-1'),
      EntityLink.typed(entityType: EntityLinkType.report, entityId: 'report-1'),
    ];

    for (final link in links) {
      final resolution = registry.resolve(link, snapshot());
      expect(resolution.state, EntityRouteState.resolved);
      expect(resolution.location, isNotEmpty);
    }
    expect(
      links.map((link) => registry.resolve(link, snapshot()).location).toSet(),
      hasLength(links.length),
    );
  });

  test('server report links retain versioned focus/filter schema', () {
    final link = EntityLink.fromJson({
      'entityType': 'client_status_list',
      'entityId': 'lead:new',
      'optionalFocus': {
        'filter': {'version': 1, 'clientType': 'lead', 'status': 'new'},
      },
    });

    expect(link.entityType, EntityLinkType.report);
    expect(link.optionalFocus?.filter['status'], 'new');
    expect(link.toJson()['version'], 1);
    expect(
      EntityRouteRegistry().resolve(link, snapshot()).state,
      EntityRouteState.resolved,
    );
  });

  test('human presentation survives serialization and replaces raw ids', () {
    final registry = EntityRouteRegistry();
    final links = <EntityLink>[
      EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: '8db5cf78-535d-4cbf-9689-c146a816e46a',
        variant: 'student',
        presentation: const EntityPresentationReference(
          primary: 'Иванов Иван',
          context: 'Сокол',
        ),
      ),
      EntityLink.typed(
        entityType: EntityLinkType.teacher,
        entityId: 'teacher-id',
        presentation: const EntityPresentationReference(primary: 'Петров Пётр'),
      ),
      EntityLink.typed(
        entityType: EntityLinkType.branch,
        entityId: 'branch-id',
        presentation: const EntityPresentationReference(primary: 'Сокол'),
      ),
      EntityLink.typed(
        entityType: EntityLinkType.room,
        entityId: 'room-id',
        presentation: const EntityPresentationReference(
          primary: 'Аудитория 3',
          context: 'Сокол',
        ),
      ),
      EntityLink.typed(
        entityType: EntityLinkType.lesson,
        entityId: 'lesson-id',
        presentation: const EntityPresentationReference(
          primary: '05.08.2026 12:00 · Иванов Иван',
        ),
      ),
      EntityLink.typed(
        entityType: EntityLinkType.payment,
        entityId: 'payment-id',
        presentation: const EntityPresentationReference(primary: '№ MM-42'),
      ),
      EntityLink.typed(
        entityType: EntityLinkType.subscription,
        entityId: 'subscription-id',
        presentation: const EntityPresentationReference(
          primary: 'Вокал · 8 занятий',
        ),
      ),
      EntityLink.typed(
        entityType: EntityLinkType.task,
        entityId: 'task-id',
        presentation: const EntityPresentationReference(
          primary: 'Позвонить клиенту',
        ),
      ),
      EntityLink.typed(
        entityType: EntityLinkType.user,
        entityId: 'user-id',
        presentation: const EntityPresentationReference(
          primary: 'Сидорова Анна',
        ),
      ),
    ];

    for (final link in links) {
      final restored = EntityLink.fromJson(link.toJson());
      final title = registry
          .resolve(restored, snapshot())
          .canonicalLocation!
          .title;
      expect(restored.presentation?.primary, link.presentation?.primary);
      expect(title, contains(link.presentation!.primary));
      expect(title, isNot(contains(link.entityId)));
    }
  });

  test('missing, forbidden and deleted references never expose raw ids', () {
    final link = EntityLink.typed(
      entityType: EntityLinkType.payment,
      entityId: 'f890877f-ef34-4fe6-9584-a3ec66783e21',
      presentation: const EntityPresentationReference(
        primary: '№ MM-42',
        context: 'Иванов Иван · Сокол',
      ),
    );
    const resolver = EntityPresentationResolver();

    expect(resolver.pageTitle(link), 'Оплата · № MM-42');
    expect(
      resolver.resolve(link, state: EntityRouteState.forbidden).primary,
      'Связанная запись недоступна',
    );
    final deleted = resolver.resolve(link, state: EntityRouteState.deleted);
    expect(deleted.primary, 'Удалённая запись');
    expect(deleted.context, '№ MM-42 · Иванов Иван · Сокол');
    expect(
      '${deleted.primary} ${deleted.context}',
      isNot(contains(link.entityId)),
    );
  });

  test(
    'client section deep links round-trip through the canonical registry',
    () {
      final registry = EntityRouteRegistry();
      final link = EntityLink.typed(
        entityType: EntityLinkType.client,
        entityId: 'student-1',
        variant: 'student',
        optionalFocus: EntityLinkFocus(
          focus: 'section',
          filter: const {'section': 'payments'},
        ),
      );

      final resolved = registry.resolve(link, snapshot());
      expect(resolved.location, '/students/student-1?section=payments');
      final restored = registry.resolveLocation(resolved.location!, snapshot());
      expect(restored.state, EntityRouteState.resolved);
      expect(restored.link.optionalFocus?.filter['section'], 'payments');
    },
  );

  test('policy is fail-closed and teacher client projection is limited', () {
    final registry = EntityRouteRegistry();
    final client = EntityLink.typed(
      entityType: EntityLinkType.client,
      entityId: 'student-1',
      variant: 'student',
    );
    final teacher = snapshot(
      role: 'teacher',
      capabilities: const {'crm.client.read.basic'},
    );
    expect(
      registry.resolve(client, teacher).projection,
      EntityProjection.limited,
    );

    final finance = EntityLink.fromJson({
      'entityType': 'school_finance_month',
      'entityId': '2026-07-01',
    });
    expect(
      registry.resolve(finance, teacher).state,
      EntityRouteState.forbidden,
    );

    final unknown = EntityLink.fromJson({
      'entityType': 'future_entity',
      'entityId': 'id-1',
    });
    expect(
      registry.resolve(unknown, snapshot()).state,
      EntityRouteState.unknown,
    );
  });

  testWidgets('forbidden/deleted/archived/unknown states terminate safely', (
    tester,
  ) async {
    const expectedTitles = {
      EntityRouteState.forbidden: 'Нет доступа',
      EntityRouteState.deleted: 'Запись удалена',
      EntityRouteState.archived: 'Запись в архиве',
      EntityRouteState.unknown: 'Ссылка не поддерживается',
    };
    for (final entry in expectedTitles.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EntityLinkStateView(state: entry.key)),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(entry.value), findsOneWidget);
    }
  });
}
