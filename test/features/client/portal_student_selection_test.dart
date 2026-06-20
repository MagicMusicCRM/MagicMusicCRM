import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

/// KVA-156: the client portal lets a parent with 2+ linked students switch
/// between them. magicCurrentStudentIdProvider derives the focused student from
/// the explicit switcher selection, falling back to the first linked student so
/// existing single-student widgets keep working untouched.
void main() {
  const students = [
    {'id': 'student-a', 'first_name': 'Аня', 'last_name': 'Иванова'},
    {'id': 'student-b', 'first_name': 'Боря', 'last_name': 'Иванов'},
  ];

  ProviderContainer makeContainer(List<Map<String, dynamic>> linked) {
    final container = ProviderContainer(
      overrides: [
        myStudentsProvider.overrideWith((ref) async => linked),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('falls back to the first student when nothing is selected', () async {
    final container = makeContainer(students);

    final id = await container.read(magicCurrentStudentIdProvider.future);

    expect(id, 'student-a');
  });

  test('honours an explicit selection of another linked student', () async {
    final container = makeContainer(students);
    // Resolve once so the default is in place before switching.
    await container.read(magicCurrentStudentIdProvider.future);

    container.read(selectedStudentIdProvider.notifier).state = 'student-b';
    final id = await container.read(magicCurrentStudentIdProvider.future);

    expect(id, 'student-b');
  });

  test('ignores a stale selection that no longer matches any student', () async {
    final container = makeContainer(students);

    container.read(selectedStudentIdProvider.notifier).state = 'student-gone';
    final id = await container.read(magicCurrentStudentIdProvider.future);

    expect(id, 'student-a');
  });

  test('returns null when the account has no linked students', () async {
    final container = makeContainer(const []);

    final id = await container.read(magicCurrentStudentIdProvider.future);

    expect(id, isNull);
  });
}
