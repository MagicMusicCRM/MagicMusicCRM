import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/providers/crm_section_focus_provider.dart';

/// The overview→section deep-link channel. The contract that matters:
/// consume() returns the focus for its section exactly ONCE and then clears —
/// so a filter deep-linked from a tile applies on open but does not re-apply on
/// every later rebuild (the failure mode the reports tab had).
void main() {
  test('consume returns the focus once, for the right section, then clears', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(crmSectionFocusProvider.notifier);

    notifier.focus(const CrmSectionFocus('tasks', {'due': 'overdue'}));

    // Wrong section — no consume, focus stays pending.
    expect(notifier.consume('leads'), isNull);
    expect(container.read(crmSectionFocusProvider), isNotNull);

    // Right section — returns the payload…
    final got = notifier.consume('tasks');
    expect(got, isNotNull);
    expect(got!.filters['due'], 'overdue');

    // …and it is now cleared (a rebuild re-consuming gets nothing).
    expect(notifier.consume('tasks'), isNull);
    expect(container.read(crmSectionFocusProvider), isNull);
  });

  test('a new focus replaces an unconsumed one', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(crmSectionFocusProvider.notifier);

    notifier.focus(const CrmSectionFocus('tasks', {'due': 'overdue'}));
    notifier.focus(const CrmSectionFocus('leads', {'status': 'new'}));

    expect(notifier.consume('tasks'), isNull);
    expect(notifier.consume('leads')!.filters['status'], 'new');
  });
}
