import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/models/audit_presentation_event.dart';

void main() {
  const fixture = <String, dynamic>{
    'id': 'audit-42',
    'actionKey': 'crm.student_updated',
    'title': 'Электронная почта изменена',
    'summary': 'Почта обновлена после обращения ученика',
    'reason': 'Уточнение контактных данных',
    'actor': <String, dynamic>{
      'id': 'user-7',
      'name': 'Мария Администратор',
      'role': 'admin',
    },
    'target': <String, dynamic>{
      'type': 'student',
      'id': 'student-3',
      'label': 'Ученик',
      'displayName': 'Анна Иванова',
      'routeType': 'student',
    },
    'changes': <Map<String, dynamic>>[
      <String, dynamic>{
        'key': 'email',
        'label': 'Электронная почта',
        'before': 'old@example.com',
        'after': 'new@example.com',
      },
      <String, dynamic>{
        'key': 'phone',
        'label': 'Телефон',
        'before': '+79990000000',
        'after': '+79991111111',
      },
    ],
    'occurredAt': '2026-08-30T10:15:00.000Z',
  };

  group('AuditPresentationEvent.fromJson', () {
    test('parses the complete nested presentation contract', () {
      final event = AuditPresentationEvent.fromJson(fixture);

      expect(event.id, 'audit-42');
      expect(event.actionKey, 'crm.student_updated');
      expect(event.title, 'Электронная почта изменена');
      expect(event.summary, 'Почта обновлена после обращения ученика');
      expect(event.reason, 'Уточнение контактных данных');
      expect(event.actor.id, 'user-7');
      expect(event.actor.name, 'Мария Администратор');
      expect(event.actor.role, 'admin');
      expect(event.target.type, 'student');
      expect(event.target.id, 'student-3');
      expect(event.target.label, 'Ученик');
      expect(event.target.displayName, 'Анна Иванова');
      expect(event.target.routeType, 'student');
      expect(event.changes, hasLength(2));
      expect(event.changes.first.before, 'old@example.com');
      expect(event.changes.last.after, '+79991111111');
      expect(event.occurredAt, DateTime.parse('2026-08-30T10:15:00.000Z'));
    });

    test('keeps only explicitly nullable contract fields nullable', () {
      final event = AuditPresentationEvent.fromJson(<String, dynamic>{
        'id': 'audit-empty',
        'actionKey': 'crm.student_archived',
        'title': 'Ученик архивирован',
        'summary': null,
        'reason': null,
        'actor': <String, dynamic>{'id': null, 'name': 'Система', 'role': null},
        'target': <String, dynamic>{
          'type': 'student',
          'id': null,
          'label': 'Ученик',
          'displayName': null,
          'routeType': null,
        },
        'changes': <dynamic>[],
        'occurredAt': '2026-08-30T10:15:00.000Z',
      });

      expect(event.summary, isNull);
      expect(event.reason, isNull);
      expect(event.actor.id, isNull);
      expect(event.actor.name, 'Система');
      expect(event.actor.role, isNull);
      expect(event.target.id, isNull);
      expect(event.target.displayName, isNull);
      expect(event.target.routeType, isNull);
      expect(event.changes, isEmpty);
      expect(event.occurredAt, DateTime.parse('2026-08-30T10:15:00.000Z'));
    });

    test(
      'fails fast when required event or nested DTO fields are malformed',
      () {
        final invalidPayloads = <Map<String, dynamic>>[
          {...fixture}..remove('id'),
          {...fixture}..remove('title'),
          {...fixture, 'occurredAt': 'not-a-date'},
          {...fixture, 'actor': null},
          {
            ...fixture,
            'actor': <String, dynamic>{'id': null, 'role': null},
          },
          {
            ...fixture,
            'target': <String, dynamic>{'id': null},
          },
          {...fixture, 'changes': null},
          {
            ...fixture,
            'changes': <Map<String, dynamic>>[
              <String, dynamic>{'key': 'email', 'before': null, 'after': null},
            ],
          },
        ];

        for (final payload in invalidPayloads) {
          expect(
            () => AuditPresentationEvent.fromJson(payload),
            throwsFormatException,
            reason: payload.toString(),
          );
        }
      },
    );

    test('exposes parsed changes as an unmodifiable list', () {
      final event = AuditPresentationEvent.fromJson(fixture);

      expect(event.changes.first.before, 'old@example.com');
      expect(
        () => event.changes[0] = const AuditPresentationChange(
          key: 'email',
          label: 'Электронная почта',
          before: 'replacement@example.com',
          after: 'new@example.com',
        ),
        throwsUnsupportedError,
      );
      expect(
        () => event.changes.add(
          const AuditPresentationChange(
            key: 'status',
            label: 'Статус',
            before: 'Новый',
            after: 'Активный',
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
