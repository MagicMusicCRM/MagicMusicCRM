import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_details_sheet.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('representative lesson surfaces follow the adaptive policy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const _ModalDeviceHome()),
    );

    await tester.tap(find.text('Быстрый просмотр'));
    await tester.pumpAndSettle();
    expect(find.text('Анна Смирнова'), findsNWidgets(2));
    expect(find.text('Изменить занятие'), findsOneWidget);
    if (const bool.fromEnvironment('V6_VISUAL_CHECK')) {
      debugPrint('V6_MODAL_SCREENSHOT_READY');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 30)),
      );
    }

    await tester.tap(find.text('Удалить занятие'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Удалить занятие?'), findsOneWidget);
    await tester.tap(find.text('Оставить'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать клиента'));
    await tester.pumpAndSettle();
    expect(find.text('Поиск по ФИО'), findsOneWidget);
    await tester.tap(find.text('Анна Смирнова').last);
    await tester.pumpAndSettle();
    expect(find.text('Выбрано: Анна Смирнова'), findsOneWidget);
    debugPrint('V6_MODAL_DEVICE_PASS');
  });
}

class _ModalDeviceHome extends StatefulWidget {
  const _ModalDeviceHome();

  @override
  State<_ModalDeviceHome> createState() => _ModalDeviceHomeState();
}

class _ModalDeviceHomeState extends State<_ModalDeviceHome> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('V6 surface QA')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          FilledButton(
            onPressed: () => showLessonDetailsSheet(
              context,
              teacherName: 'Пётр Педагогов',
              studentName: 'Анна Смирнова',
              roomName: 'Зал 1',
              timeRange: '14:00–15:00',
              currentStatus: 'scheduled',
              conflicts: const [],
              lessonId: 'lesson-1',
              onEdit: () {},
              onDelete: () async {},
            ),
            child: const Text('Быстрый просмотр'),
          ),
          FilledButton(
            onPressed: () => SearchableSelect.show(
              context: context,
              title: 'Выберите клиента',
              hintText: 'Поиск по ФИО',
              items: [
                SearchableSelectItem(id: 'student-1', label: 'Анна Смирнова'),
              ],
              isNullable: false,
              onSelected: (item) => setState(() => _selected = item?.label),
            ),
            child: const Text('Выбрать клиента'),
          ),
          Text('Выбрано: ${_selected ?? '—'}'),
        ],
      ),
    );
  }
}
