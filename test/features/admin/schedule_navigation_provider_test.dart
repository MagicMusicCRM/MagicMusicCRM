import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/admin/presentation/providers/schedule_navigation_provider.dart';

void main() {
  test('lead card request carries date and lead preset into Schedule', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final date = DateTime(2026, 7, 18);

    container
        .read(scheduleNavigationProvider.notifier)
        .createForLead(date, leadId: 'lead-1', leadName: 'Иван Петров');

    final focus = container.read(scheduleNavigationProvider)!;
    expect(focus.focusDate, date);
    expect(focus.highlightLessonId, isNull);
    expect(focus.leadId, 'lead-1');
    expect(focus.leadName, 'Иван Петров');

    container.read(scheduleNavigationProvider.notifier).clear();
    expect(container.read(scheduleNavigationProvider), isNull);
  });
}
