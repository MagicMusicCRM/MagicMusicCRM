import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/subscription_status_card.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/upcoming_lessons_list.dart';

/// Client-facing portal: shows the student's balance/subscription, upcoming
/// lessons and attendance history in one place. Reachable from the client chat
/// shell. Composes the existing (data-wired) client widgets.
///
/// When the signed-in account has two or more linked students (e.g. a parent
/// with several children), a horizontal child switcher is shown at the top so
/// the parent can flip between them (KVA-156). With zero or one student the
/// switcher is hidden and behaviour is identical to before.
class ClientPortalScreen extends ConsumerWidget {
  const ClientPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(myStudentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Моя школа'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
            onPressed: () {
              ref.invalidate(subscriptionProvider);
              ref.invalidate(upcomingLessonsRichProvider);
              ref.invalidate(pastLessonsRichProvider);
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          // Keep the portal readable on wide desktop windows.
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Child switcher — only meaningful with 2+ linked students.
              _ChildSwitcher(studentsAsync: studentsAsync),
              // Balance / subscription status.
              const SubscriptionStatusCard(),
              // Upcoming lessons + attendance history (own tab switcher).
              const Expanded(child: UpcomingLessonsList()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal row of child chips. Renders nothing unless the account has two
/// or more linked students. The selected chip drives [selectedStudentIdProvider],
/// which the portal's data providers derive from.
class _ChildSwitcher extends ConsumerWidget {
  const _ChildSwitcher({required this.studentsAsync});

  final AsyncValue<List<Map<String, dynamic>>> studentsAsync;

  static String _displayName(Map<String, dynamic> student) {
    final first = (student['first_name'] as String?)?.trim() ?? '';
    final last = (student['last_name'] as String?)?.trim() ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Ученик' : full;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final students = studentsAsync.asData?.value ?? const [];
    // Zero or one student: keep the original single-student layout.
    if (students.length < 2) return const SizedBox.shrink();

    final selectedId = ref.watch(selectedStudentIdProvider);
    // Highlight the effective student: the explicit selection when it still
    // matches a linked student, otherwise the first one (the default).
    final effectiveId =
        (selectedId != null &&
            students.any((s) => s['id']?.toString() == selectedId))
        ? selectedId
        : students.first['id']?.toString();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: students.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final student = students[index];
            final id = student['id']?.toString();
            final isActive = id != null && id == effectiveId;

            return ChoiceChip(
              label: Text(_displayName(student)),
              selected: isActive,
              showCheckmark: false,
              selectedColor: AppTheme.primaryGold.withAlpha(40),
              side: BorderSide(
                color: isActive
                    ? AppTheme.primaryGold
                    : AppTheme.primaryGold.withAlpha(40),
              ),
              labelStyle: TextStyle(
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? AppTheme.primaryGold
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
              onSelected: id == null
                  ? null
                  : (_) =>
                        ref.read(selectedStudentIdProvider.notifier).state = id,
            );
          },
        ),
      ),
    );
  }
}
