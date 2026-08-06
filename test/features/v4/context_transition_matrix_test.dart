import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/context_transition_registry.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';

void main() {
  const allCapabilities = <String>{
    'access.user.role.assign',
    'access.user.override.manage',
    'crm.client.read.basic',
    'crm.client.read.contacts',
    'crm.client.write',
    'crm.comment.read.shared',
    'schedule.lesson.read.assigned',
    'schedule.lesson.write',
    'commerce.client_finance.read',
    'commerce.school_finance.read',
    'commerce.package.read',
    'commerce.package.manage',
    'commerce.subscription.issue',
    'workflow.task.read',
    'workflow.task.write',
    'report.status.read',
    'report.export.xlsx',
    'system.settings.manage',
  };

  CapabilitySnapshot actor(String role) {
    final capabilities = switch (role) {
      'client' => const <String>{
        'crm.client.read.basic',
        'commerce.client_finance.read',
      },
      'teacher' => const <String>{
        'crm.client.read.basic',
        'crm.comment.read.shared',
        'schedule.lesson.read.assigned',
      },
      'admin' => const <String>{
        'crm.client.read.basic',
        'crm.client.write',
        'schedule.lesson.write',
        'workflow.task.read',
        'workflow.task.write',
        'commerce.client_finance.read',
        'commerce.package.read',
      },
      'manager' => allCapabilities.difference(const {
        'access.user.role.assign',
        'access.user.override.manage',
        'commerce.school_finance.read',
        'commerce.package.manage',
        'system.settings.manage',
      }),
      _ => allCapabilities,
    };
    return CapabilitySnapshot(
      accountId: '$role-account',
      role: role,
      accessVersion: 1,
      capabilities: capabilities,
      scopes: const {},
    );
  }

  test('PRD section 8 has a typed definition for every source and target', () {
    const registry = ContextTransitionRegistry();
    expect(
      ContextTransitionRegistry.definitions.map((item) => item.source).toSet(),
      ContextSourceType.values.toSet(),
    );
    expect(ContextTransitionRegistry.definitions, hasLength(53));

    for (final definition in ContextTransitionRegistry.definitions) {
      final transition = registry.create(
        source: definition.source,
        target: definition.target,
        entityId: 'entity-${definition.target.name}',
        sourceState: ContextViewState(
          filters: {'source': definition.source.name},
          date: DateTime.utc(2026, 7, 30),
          scrollOffset: 144,
          selectedColumn: 'active',
        ),
        targetFilter: {'period': '2026-07'},
        rawEntityType: definition.target == ContextTargetType.changedEntity
            ? 'lesson'
            : null,
      );
      expect(transition.target.isSupported, isTrue);
      expect(transition.sourceState.scrollOffset, 144);
      expect(transition.sourceState.selectedColumn, 'active');
    }
  });

  test(
    'all six actors resolve every matrix edge to target or safe forbidden',
    () {
      const transitionRegistry = ContextTransitionRegistry();
      final routeRegistry = EntityRouteRegistry();

      for (final role in const [
        'client',
        'teacher',
        'admin',
        'manager',
        'director',
        'system_admin',
      ]) {
        for (final definition in ContextTransitionRegistry.definitions) {
          final transition = transitionRegistry.create(
            source: definition.source,
            target: definition.target,
            entityId: 'entity-id',
            sourceState: ContextViewState(),
            rawEntityType: definition.target == ContextTargetType.changedEntity
                ? 'student'
                : null,
          );
          final resolved = routeRegistry.resolve(
            transition.target,
            actor(role),
          );
          expect(
            resolved.state,
            anyOf(EntityRouteState.resolved, EntityRouteState.forbidden),
            reason: '$role ${definition.source} → ${definition.target}',
          );
          expect(resolved.state, isNot(EntityRouteState.unknown));
          if (resolved.canOpen) {
            expect(resolved.location, isNotEmpty);
          }
        }
      }
    },
  );

  test(
    'source filters/date/scroll survive transition and back serialization',
    () {
      final source = ContextViewState(
        filters: const {'branch': 'branch-1', 'status': 'active'},
        date: DateTime.utc(2026, 7, 30),
        scrollOffset: 312,
        selectedColumn: 'students',
      );
      final transition = const ContextTransitionRegistry().create(
        source: ContextSourceType.studentCard,
        target: ContextTargetType.lesson,
        entityId: 'lesson-1',
        sourceState: source,
      );
      final restored = ContextViewState.fromJson(
        transition.sourceState.toJson(),
      );

      expect(restored.filters, source.filters);
      expect(restored.date, source.date);
      expect(restored.scrollOffset, source.scrollOffset);
      expect(restored.selectedColumn, source.selectedColumn);
    },
  );

  test('shell destination mapping is EntityLink-based and role-safe', () {
    final schedule = CrmNavigationRequest.schedule(
      date: DateTime.utc(2026, 7, 30),
      lessonId: 'lesson-1',
    );
    final permissions = CrmNavigationRequest.userRolesSearch(
      'user@example.com',
    );

    expect(schedule.link.rawEntityType, 'lesson_list');
    expect(schedule.link.optionalFocus?.filter['lessonId'], 'lesson-1');
    expect(crmTabForEntityLink(schedule.link, 'manager'), 2);
    expect(crmTabForEntityLink(schedule.link, 'teacher'), 1);
    expect(crmTabForEntityLink(permissions.link, 'manager'), 8);
    expect(permissions.link.optionalFocus?.filter['query'], 'user@example.com');
    expect(crmTabForEntityLink(permissions.link, 'teacher'), isNull);
  });
}
