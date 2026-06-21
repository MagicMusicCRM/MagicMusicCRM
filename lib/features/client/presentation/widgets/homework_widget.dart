import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

/// Legacy task-checklist provider — retained so any existing wiring that reads
/// `homeworkProvider` keeps compiling. The reskinned [HomeworkWidget] now loads
/// the real lesson-homework feature (see [_studentHomeworksProvider]); the old
/// togglable-task list lives on in [TasksChecklistWidget] below, unchanged.
final homeworkProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.watch(magicCrmServiceProvider).listTasks();
});

/// Loads the lesson homeworks for a given student (or, when [studentId] is
/// null, the caller's own homeworks — the server scopes a `client` actor to the
/// students they own). Family-keyed on the (nullable) student id so the widget
/// can be reused across student detail screens without provider collisions.
final _studentHomeworksProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>((
  ref,
  studentId,
) async {
  return ref
      .read(magicCrmServiceProvider)
      .listHomeworks(studentId: studentId);
});

/// v7 homework feed.
///
/// Renders each lesson homework as a v7 card (title, description, status pill,
/// due date, attachments) and exposes a «Сдать» action that calls
/// `submitHomework(id)` → [MagicToast] + refresh.
///
/// Theme-aware: surfaces come from `Theme.of(context).colorScheme`, accents
/// from [AppColor]. Constructible with no arguments (back-compat) or with an
/// explicit [studentId] when embedded on a student's detail screen.
class HomeworkWidget extends ConsumerWidget {
  const HomeworkWidget({super.key, this.studentId});

  /// The student whose homeworks to show. When null, the server returns the
  /// caller's own homeworks (client actor scope).
  final String? studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final homeworkAsync = ref.watch(_studentHomeworksProvider(studentId));

    return homeworkAsync.when(
      loading: () => const _HomeworkSkeletonList(),
      error: (err, _) => _HomeworkError(
        message: '$err',
        onRetry: () => ref.invalidate(_studentHomeworksProvider(studentId)),
      ),
      data: (homeworks) {
        if (homeworks.isEmpty) {
          return _HomeworkEmpty(scheme: scheme);
        }

        return RefreshIndicator(
          color: AppColor.gold,
          backgroundColor: scheme.surface,
          onRefresh: () async =>
              ref.invalidate(_studentHomeworksProvider(studentId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpace.md),
            itemCount: homeworks.length,
            itemBuilder: (context, index) {
              final hw = homeworks[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: _HomeworkCard(
                  homework: hw,
                  onSubmitted: () =>
                      ref.invalidate(_studentHomeworksProvider(studentId)),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// A single homework rendered as a v7 card.
class _HomeworkCard extends ConsumerStatefulWidget {
  const _HomeworkCard({required this.homework, required this.onSubmitted});

  final Map<String, dynamic> homework;
  final VoidCallback onSubmitted;

  @override
  ConsumerState<_HomeworkCard> createState() => _HomeworkCardState();
}

class _HomeworkCardState extends ConsumerState<_HomeworkCard> {
  bool _submitting = false;

  String get _status =>
      (widget.homework['status'] ?? 'assigned').toString().toLowerCase();

  bool get _canSubmit => _status == 'assigned';

  /// Attachments are not guaranteed to be inlined by the list endpoint; render
  /// defensively whatever the map exposes under common keys.
  List<Map<String, dynamic>> get _attachments {
    final raw = widget.homework['attachments'];
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  Future<void> _submit() async {
    final id = widget.homework['id']?.toString();
    if (id == null || id.isEmpty || _submitting) return;

    setState(() => _submitting = true);
    try {
      await ref.read(magicCrmServiceProvider).submitHomework(id);
      if (!mounted) return;
      MagicToast.show(
        context,
        'Задание отправлено',
        detail: widget.homework['title']?.toString(),
        type: MagicToastType.success,
      );
      widget.onSubmitted();
    } catch (err) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось сдать задание',
        detail: '$err',
        type: MagicToastType.danger,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = (widget.homework['title'] ?? 'Задание').toString();
    final description = widget.homework['description']?.toString();
    final dueLabel = _formatDate(widget.homework['dueAt']);
    final attachments = _attachments;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + status pill.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              _StatusPill(status: _status),
            ],
          ),
          if (description != null && description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              description,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          if (dueLabel != null) ...[
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Icon(
                  Icons.event_rounded,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Срок: $dueLabel',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final att in attachments)
                  _AttachmentChip(label: _attachmentLabel(att)),
              ],
            ),
          ],
          if (_canSubmit) ...[
            const SizedBox(height: AppSpace.lg),
            _SubmitButton(busy: _submitting, onPressed: _submit),
          ],
        ],
      ),
    );
  }

  String _attachmentLabel(Map<String, dynamic> att) {
    return (att['name'] ??
            att['fileName'] ??
            att['kind'] ??
            att['fileId'] ??
            'Файл')
        .toString();
  }
}

/// Flat gold submit button (gold bg, on-gold text, no shadow) per v7 rules.
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColor.gold,
          foregroundColor: AppColor.onGold,
          disabledBackgroundColor: AppColor.gold.withValues(alpha: 0.55),
          disabledForegroundColor: AppColor.onGold.withValues(alpha: 0.7),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColor.onGold),
                ),
              )
            : const Text('Сдать'),
      ),
    );
  }
}

/// Status pill (assigned / submitted / reviewed) — tinted by semantic accent.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  ({String label, Color color}) get _spec {
    switch (status) {
      case 'submitted':
        return (label: 'Сдано', color: AppColor.gold);
      case 'reviewed':
        return (label: 'Проверено', color: AppColor.success);
      case 'assigned':
      default:
        return (label: 'Назначено', color: AppColor.text2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: spec.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: spec.color.withValues(alpha: 0.34)),
      ),
      child: Text(
        spec.label,
        style: TextStyle(
          color: spec.color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

/// Attachment chip.
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.attach_file_rounded,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// v7 skeleton placeholder list shown while homeworks load.
class _HomeworkSkeletonList extends StatelessWidget {
  const _HomeworkSkeletonList();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpace.md),
      itemCount: 4,
      itemBuilder: (context, _) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonLine(width: 160),
              SizedBox(height: 12),
              SkeletonLine(width: double.infinity),
              SizedBox(height: 8),
              SkeletonLine(width: 120),
              SizedBox(height: 16),
              SkeletonBox(width: double.infinity, height: 40, radius: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty state.
class _HomeworkEmpty extends StatelessWidget {
  const _HomeworkEmpty({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.assignment_turned_in_rounded,
            size: 64,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            'Нет домашних заданий',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Error state with a retry affordance.
class _HomeworkError extends StatelessWidget {
  const _HomeworkError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AppColor.danger),
            const SizedBox(height: AppSpace.md),
            Text(
              'Ошибка: $message',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: AppSpace.lg),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: AppColor.gold),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Retained legacy task-checklist UI (the previous body of [HomeworkWidget]).
///
/// Preserved verbatim so the togglable-task behavior — reading the legacy
/// [homeworkProvider] and calling `updateTaskStatus` — is not removed. It is no
/// longer mounted by [HomeworkWidget] (which now shows real homeworks) but
/// remains available for any caller that still needs the checklist.
class TasksChecklistWidget extends ConsumerWidget {
  const TasksChecklistWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeworkAsync = ref.watch(homeworkProvider);

    return homeworkAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: ListSkeleton(count: 5),
      ),
      error: (err, _) => Center(
        child: Text('Ошибка: $err', style: TextStyle(color: AppTheme.danger)),
      ),
      data: (tasks) {
        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.assignment_turned_in_rounded,
                  size: 64,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withAlpha(80),
                ),
                const SizedBox(height: 16),
                Text(
                  'Нет текущих заданий',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: AppTheme.primaryGold,
          onRefresh: () async => ref.invalidate(homeworkProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              final isDone = task['status'] == 'done';
              final dt = DateTime.tryParse(task['created_at'] ?? '');
              final dateStr = dt != null
                  ? DateFormat('d MMM', 'ru').format(dt.toLocal())
                  : '';

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: CheckboxListTile(
                  value: isDone,
                  activeColor: AppTheme.success,
                  checkColor: Colors.white,
                  title: Text(
                    task['title'] ?? 'Задание',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      color: isDone
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (task['description'] != null &&
                          task['description'].toString().isNotEmpty)
                        Text(
                          task['description'],
                          style: const TextStyle(fontSize: 12),
                        ),
                      Text(
                        'Назначено: $dateStr',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  onChanged: (val) async {
                    if (val == null) return;
                    await ref
                        .read(magicCrmServiceProvider)
                        .updateTaskStatus(
                          task['id'].toString(),
                          val ? 'done' : 'open',
                        );
                    ref.invalidate(homeworkProvider);
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Formats an ISO date/`DateTime` value as `d MMM` in Russian, or null when the
/// value is missing/unparseable.
String? _formatDate(Object? value) {
  if (value == null) return null;
  final dt = value is DateTime ? value : DateTime.tryParse(value.toString());
  if (dt == null) return null;
  return DateFormat('d MMM', 'ru').format(dt.toLocal());
}
