import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'upcoming_lessons_list.dart';

class NextLessonCountdown extends ConsumerStatefulWidget {
  const NextLessonCountdown({super.key});

  @override
  ConsumerState<NextLessonCountdown> createState() => _NextLessonCountdownState();
}

class _NextLessonCountdownState extends ConsumerState<NextLessonCountdown> {
  Timer? _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}д ${d.inHours % 24}ч';
    if (d.inHours > 0) return '${d.inHours}ч ${d.inMinutes % 60}м';
    return '${d.inMinutes}м';
  }

  @override
  Widget build(BuildContext context) {
    final lessonsAsync = ref.watch(upcomingLessonsRichProvider);

    return lessonsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (lessons) {
        if (lessons.isEmpty) return const SizedBox.shrink();

        final next = lessons.first;
        final dt = DateTime.tryParse(next['scheduled_at'] as String? ?? '');
        if (dt == null) return const SizedBox.shrink();

        final now = DateTime.now();
        _timeLeft = dt.difference(now);

        if (_timeLeft.isNegative) return const SizedBox.shrink();

        final tFirst = next['teacher_first_name'] as String? ?? '';
        final tLast = next['teacher_last_name'] as String? ?? '';
        final tpFirst = next['teacher_profile_first_name'] as String? ?? '';
        final tpLast = next['teacher_profile_last_name'] as String? ?? '';
        
        var teacherFirst = tFirst.isNotEmpty ? tFirst : tpFirst;
        var teacherLast = tLast.isNotEmpty ? tLast : tpLast;
        final teacherName = '$teacherFirst $teacherLast'.trim();

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppTheme.primaryPurple,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ближайший урок', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('d MMMM, HH:mm', 'ru').format(dt.toLocal()),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (teacherName.isNotEmpty)
                        Text(teacherName, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.timer_outlined, color: Colors.white, size: 20),
                      const SizedBox(height: 2),
                      Text(
                        _formatDuration(_timeLeft),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
