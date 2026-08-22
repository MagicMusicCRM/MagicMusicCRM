import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/lesson_state_badges.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/homework_widget.dart';

// Provider for the active tab (0: Upcoming, 1: History)

final upcomingLessonsRichProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  // Scope to the selected linked student when present. If the signed-in client
  // is only linked to a lead, omit studentId so the backend can return lead
  // lessons through the actor scope.
  final studentId = ref.watch(magicCurrentStudentIdProvider).asData?.value;
  return ref
      .watch(magicCrmServiceProvider)
      .listLessons(
        studentId: studentId,
        // Send an absolute UTC instant (…Z). A naive local string was being
        // read by Postgres in the session TZ (UTC), shifting the boundary by
        // +3h so imminent lessons fell into История instead of Предстоящие.
        from: DateTime.now().toUtc().toIso8601String(),
        limit: 20,
      );
});

final pastLessonsRichProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final studentId = ref.watch(magicCurrentStudentIdProvider).asData?.value;
  return ref
      .watch(magicCrmServiceProvider)
      .listLessons(
        studentId: studentId,
        to: DateTime.now().toUtc().toIso8601String(),
        // Новейшие первыми. Сервер сортировал только asc и резал limit ПОСЛЕ
        // сортировки — у учеников с сотнями занятий вкладка «История» вечно
        // показывала 50 самых старых уроков 2024 года и ни одного свежего.
        order: 'desc',
        limit: 50,
      );
});

class UpcomingLessonsList extends ConsumerStatefulWidget {
  const UpcomingLessonsList({super.key});

  @override
  ConsumerState<UpcomingLessonsList> createState() =>
      _UpcomingLessonsListState();
}

class _UpcomingLessonsListState extends ConsumerState<UpcomingLessonsList> {
  int _activeTab = 0; // 0: Upcoming, 1: History, 2: Homework

  @override
  Widget build(BuildContext context) {
    final upcomingAsync = ref.watch(upcomingLessonsRichProvider);
    final pastAsync = ref.watch(pastLessonsRichProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.primaryGold.withAlpha(30)),
            ),
            child: Row(
              children: [
                _TabButton(
                  label: 'Предстоящие',
                  isActive: _activeTab == 0,
                  onTap: () => setState(() => _activeTab = 0),
                ),
                _TabButton(
                  label: 'История',
                  isActive: _activeTab == 1,
                  onTap: () => setState(() => _activeTab = 1),
                ),
                _TabButton(
                  label: 'Задания',
                  isActive: _activeTab == 2,
                  onTap: () => setState(() => _activeTab = 2),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _activeTab == 2
              ? const HomeworkWidget()
              : (_activeTab == 0 ? upcomingAsync : pastAsync).when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: ListSkeleton(count: 5),
                  ),
                  error: (_, _) => MagicPageState(
                    kind: MagicPageStateKind.error,
                    title: 'Не удалось загрузить занятия',
                    message: 'Проверьте подключение и повторите загрузку.',
                    actionLabel: 'Повторить',
                    onAction: () {
                      ref.invalidate(upcomingLessonsRichProvider);
                      ref.invalidate(pastLessonsRichProvider);
                    },
                  ),
                  data: (lessons) {
                    if (lessons.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _activeTab == 0
                                  ? Icons.calendar_today_rounded
                                  : Icons.history_rounded,
                              size: 64,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant.withAlpha(80),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _activeTab == 0
                                  ? 'Нет предстоящих занятий'
                                  : 'История занятий пуста',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () {
                                ref.invalidate(upcomingLessonsRichProvider);
                                ref.invalidate(pastLessonsRichProvider);
                              },
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Обновить'),
                            ),
                          ],
                        ),
                      );
                    }

                    return RefreshIndicator(
                      color: AppTheme.primaryGold,
                      onRefresh: () async {
                        ref.invalidate(upcomingLessonsRichProvider);
                        ref.invalidate(pastLessonsRichProvider);
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: lessons.length,
                        itemBuilder: (context, index) {
                          final lesson = lessons[index];
                          final branchName =
                              lesson['branch_name'] as String? ?? 'Без филиала';

                          // Unified name resolution from flattened fields
                          final teacherFirst =
                              lesson['teacher_first_name'] as String? ?? '';
                          final teacherLast =
                              lesson['teacher_last_name'] as String? ?? '';
                          final teacherName = '$teacherFirst $teacherLast'
                              .trim();

                          final room = lesson['room_name'] as String? ?? '';
                          final isTrial = lesson['is_trial'] == true;
                          final dt = DateTime.tryParse(
                            lesson['scheduled_at'] as String? ?? '',
                          );

                          final dateStr = dt != null
                              ? DateFormat('EEEE, d MMMM · HH:mm', 'ru').format(
                                  dt.toUtc().add(const Duration(hours: 3)),
                                )
                              : 'Не указано';
                          final duration =
                              lesson['duration_minutes'] as int? ?? 60;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryGold.withAlpha(25),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.music_note_rounded,
                                      color: AppTheme.primaryGold,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (isTrial) ...[
                                          const LessonTrialBadge(),
                                          const SizedBox(height: 4),
                                        ],
                                        Text(
                                          dateStr,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Преподаватель: ${teacherName.isEmpty ? 'Не назначен' : teacherName}',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          [
                                            'Филиал: $branchName',
                                            if (room.isNotEmpty) room,
                                            '$duration мин',
                                          ].join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  LessonStateBadge.fromMap(lesson),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primaryGold : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
