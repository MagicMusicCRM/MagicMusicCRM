import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A one-shot request to open a CRM section with a filter already applied —
/// e.g. tapping «Просроченные задачи» on the overview opens Tasks showing only
/// overdue ones. Set by the overview tile, consumed once by the target widget
/// on open (see [CrmSectionFocusNotifier.consume]); re-entering the section
/// without a tap shows the section's normal default view.
class CrmSectionFocus {
  /// Which section this focus targets: 'tasks' | 'leads' | 'schedule'.
  final String section;

  /// Filter key→value pairs the target widget knows how to apply. Kept as a
  /// plain map so a new section/filter needs no change here — only in the
  /// producer (overview tile) and the consumer (that section's widget).
  final Map<String, String> filters;

  const CrmSectionFocus(this.section, this.filters);
}

class CrmSectionFocusNotifier extends Notifier<CrmSectionFocus?> {
  @override
  CrmSectionFocus? build() => null;

  void focus(CrmSectionFocus value) => state = value;

  /// Returns the pending focus if it targets [section], and CLEARS it so it
  /// fires exactly once. Clear-on-consume is what stops the filter from
  /// re-applying every time the widget rebuilds (the bug the reports tab had).
  CrmSectionFocus? consume(String section) {
    final current = state;
    if (current == null || current.section != section) return null;
    state = null;
    return current;
  }
}

final crmSectionFocusProvider =
    NotifierProvider<CrmSectionFocusNotifier, CrmSectionFocus?>(
      CrmSectionFocusNotifier.new,
    );
