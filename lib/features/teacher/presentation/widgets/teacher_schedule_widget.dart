import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';
import 'package:magic_music_crm/core/widgets/magic_shimmer.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';

/// Assigned-only, read-only projection of the canonical schedule surface.
class TeacherScheduleWidget extends ConsumerStatefulWidget {
  const TeacherScheduleWidget({super.key});

  @override
  ConsumerState<TeacherScheduleWidget> createState() =>
      _TeacherScheduleWidgetState();
}

class _TeacherScheduleWidgetState extends ConsumerState<TeacherScheduleWidget> {
  bool _loading = true;
  Object? _error;
  String? _teacherId;

  @override
  void initState() {
    super.initState();
    _resolveTeacher();
  }

  Future<void> _resolveTeacher() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await ref.read(magicAuthServiceProvider).currentProfile();
      final teachers = await ref
          .read(magicCrmServiceProvider)
          .listTeachers(q: profile.email, limit: 100);
      final teacher = teachers
          .where(
            (item) => item['profile_user_id']?.toString() == profile.userId,
          )
          .firstOrNull;
      if (!mounted) return;
      setState(() {
        _teacherId = teacher?['id']?.toString();
        _error = teacher == null
            ? StateError('Профиль преподавателя не найден')
            : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ListView.separated(
        padding: const EdgeInsets.all(AppSpace.lg),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpace.md),
        itemBuilder: (_, _) => const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 44, height: 14, radius: AppRadius.sm),
            SizedBox(width: AppSpace.md),
            Expanded(child: SkeletonBox(height: 54, radius: AppRadius.chip)),
          ],
        ),
      );
    }
    if (_error != null || _teacherId == null) {
      return MagicPageState(
        kind: MagicPageStateKind.error,
        title: 'Не удалось загрузить расписание',
        message: 'Проверьте соединение и повторите попытку.',
        actionLabel: 'Повторить',
        onAction: _resolveTeacher,
      );
    }
    return KeyedSubtree(
      key: const ValueKey('teacher-calendar-grid'),
      child: ScheduleWidget(
        title: 'Моё расписание',
        fixedTeacherId: _teacherId,
        canWrite: false,
        allowMonth: false,
        initialViewState: ContextViewState(
          filters: {'view': 'day', 'dayMode': 'byTeacher'},
          date: DateTime.now(),
        ),
      ),
    );
  }
}
