import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/homework_attachment_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/homework_attachment_widgets.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

/// Loads the lesson homeworks for a given student (or, when [studentId] is
/// null, the caller's own homeworks — including lead-bound trial homework
/// before subscription conversion). Family-keyed on the (nullable) student id
/// so the widget can be reused across student detail screens without provider
/// collisions.
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
    ref.listen(crmRealtimeProvider, (previous, next) {
      if (next.value?.entity == 'homework') {
        ref.invalidate(_studentHomeworksProvider(studentId));
      }
    });
    final scheme = Theme.of(context).colorScheme;
    final homeworkAsync = ref.watch(_studentHomeworksProvider(studentId));

    return homeworkAsync.when(
      loading: () => const _HomeworkSkeletonList(),
      error: (_, _) => _HomeworkError(
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

  List<Map<String, dynamic>> get _attachments =>
      homeworkAttachments(widget.homework['attachments']);

  Future<void> _chooseSubmission() async {
    if (_submitting) return;
    final hasSubmission = _attachments.any(
      (attachment) => attachment['kind']?.toString() == 'submission',
    );
    final choice = await showMagicSheet<String>(
      context,
      title: 'Сдать домашнее задание',
      subtitle: hasSubmission
          ? 'Решение уже прикреплено'
          : 'Можно приложить файл с решением',
      icon: Icons.task_alt_rounded,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('homework-submit-with-file'),
            leading: const Icon(Icons.attach_file_rounded),
            title: Text(hasSubmission ? 'Добавить ещё файл' : 'Выбрать файл'),
            subtitle: const Text(
              'Фото, PDF, документ, аудио или видео до 25 МБ',
            ),
            onTap: () => Navigator.of(sheetContext).pop('file'),
          ),
          ListTile(
            key: const ValueKey('homework-submit-without-file'),
            leading: const Icon(Icons.send_rounded),
            title: Text(
              hasSubmission ? 'Сдать прикреплённое решение' : 'Сдать без файла',
            ),
            onTap: () => Navigator.of(sheetContext).pop('plain'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    HomeworkPickedFile? file;
    if (choice == 'file') {
      file = await pickHomeworkAttachment(context);
      if (file == null || !mounted) return;
    }
    await _submit(file);
  }

  Future<void> _submit(HomeworkPickedFile? file) async {
    final id = widget.homework['id']?.toString();
    if (id == null || id.isEmpty || _submitting) return;

    setState(() => _submitting = true);
    var attachmentAdded = false;
    try {
      if (file != null) {
        await ref
            .read(homeworkAttachmentServiceProvider)
            .uploadAndAttach(
              homeworkId: id,
              bytes: file.bytes,
              fileName: file.name,
              kind: 'submission',
            );
        attachmentAdded = true;
      }
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
      if (attachmentAdded) widget.onSubmitted();
      MagicToast.show(
        context,
        attachmentAdded
            ? 'Решение прикреплено, но статус не обновлён'
            : 'Не удалось сдать задание',
        detail: attachmentAdded
            ? '$err. Повторите сдачу без повторной загрузки файла.'
            : '$err',
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
            HomeworkAttachmentList(attachments: attachments),
          ],
          if (_canSubmit) ...[
            const SizedBox(height: AppSpace.lg),
            _SubmitButton(busy: _submitting, onPressed: _chooseSubmission),
          ],
        ],
      ),
    );
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
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
  const _HomeworkError({required this.onRetry});

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
              'Не удалось загрузить домашние задания. Проверьте подключение и повторите попытку.',
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

/// Formats an ISO date/`DateTime` value as `d MMM` in Russian, or null when the
/// value is missing/unparseable.
String? _formatDate(Object? value) {
  if (value == null) return null;
  final dt = value is DateTime ? value : DateTime.tryParse(value.toString());
  if (dt == null) return null;
  return DateFormat('d MMM', 'ru').format(dt.toLocal());
}
