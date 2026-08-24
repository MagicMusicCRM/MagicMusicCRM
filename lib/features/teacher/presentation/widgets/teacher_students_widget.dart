import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_launcher.dart';

class TeacherStudentsWidget extends ConsumerStatefulWidget {
  const TeacherStudentsWidget({super.key});

  @override
  ConsumerState<TeacherStudentsWidget> createState() =>
      _TeacherStudentsWidgetState();
}

class _TeacherStudentsWidgetState extends ConsumerState<TeacherStudentsWidget> {
  List<Map<String, dynamic>> _students = [];
  bool _loading = true;
  Object? _loadError;
  String? _nextCursor;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final teacher = (await crm.listTeachers(limit: 1)).firstOrNull;
      if (!mounted) return;

      if (teacher == null) {
        setState(() => _loading = false);
        return;
      }

      final page = await crm.searchStudents(limit: 100);
      if (!mounted) return;
      final students = (page['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>();

      setState(() {
        _students = students.map((s) {
          return {
            ...s,
            '_lesson_count':
                (s['lessons_count'] as num?)?.toInt() ??
                int.tryParse('${s['lessons_count']}') ??
                0,
          };
        }).toList();
        _nextCursor = page['next_cursor']?.toString();
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor?.trim();
    if (cursor == null || cursor.isEmpty || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(magicCrmServiceProvider)
          .searchStudents(cursor: cursor, limit: 100);
      if (!mounted) return;
      final known = _students
          .map((student) => student['id']?.toString())
          .whereType<String>()
          .toSet();
      setState(() {
        _students.addAll(
          (page['items'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .where((student) => known.add(student['id']?.toString() ?? ''))
              .map(
                (student) => {
                  ...student,
                  '_lesson_count':
                      (student['lessons_count'] as num?)?.toInt() ??
                      int.tryParse('${student['lessons_count']}') ??
                      0,
                },
              ),
        );
        _nextCursor = page['next_cursor']?.toString();
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGold),
      );
    }

    if (_loadError != null) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppColor.danger,
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'Не удалось загрузить учеников. Проверьте подключение и повторите попытку.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: AppSpace.lg),
              TextButton(
                onPressed: _loadStudents,
                style: TextButton.styleFrom(foregroundColor: AppColor.gold),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    if (_students.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_rounded,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withAlpha(80),
            ),
            const SizedBox(height: 16),
            Text(
              'Нет прикреплённых учеников',
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
      onRefresh: _loadStudents,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _students.length + (_nextCursor?.isNotEmpty == true ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _students.length) {
            return _TeacherStudentsPageLoader(
              cursor: _nextCursor!,
              loading: _loadingMore,
              onLoad: _loadMore,
            );
          }
          return _StudentCard(student: _students[i]);
        },
      ),
    );
  }
}

class _TeacherStudentsPageLoader extends StatefulWidget {
  final String cursor;
  final bool loading;
  final VoidCallback onLoad;

  const _TeacherStudentsPageLoader({
    required this.cursor,
    required this.loading,
    required this.onLoad,
  });

  @override
  State<_TeacherStudentsPageLoader> createState() =>
      _TeacherStudentsPageLoaderState();
}

class _TeacherStudentsPageLoaderState
    extends State<_TeacherStudentsPageLoader> {
  String? _requested;

  @override
  Widget build(BuildContext context) {
    if (!widget.loading && _requested != widget.cursor) {
      _requested = widget.cursor;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLoad();
      });
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final Map<String, dynamic> student;
  const _StudentCard({required this.student});

  @override
  Widget build(BuildContext context) {
    final student = this.student;
    final firstName = student['first_name'] ?? '';
    final lastName = student['last_name'] ?? '';
    final fullName = '$firstName $lastName'.trim().isEmpty
        ? 'Без имени'
        : '$firstName $lastName'.trim();
    final lessonCount = student['_lesson_count'] as int;
    final customData = student['custom_data'] as Map<String, dynamic>? ?? {};
    final level = customData['level'] as String? ?? '';
    final id = student['id']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        key: ValueKey('teacher-student-$id'),
        onTap: id.isEmpty
            ? null
            : () => showClientCard(
                context,
                entityType: 'student',
                entityId: id,
                seed: student,
              ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.primaryGold.withAlpha(30),
                    child: Text(
                      fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: AppTheme.primaryGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (level.isNotEmpty)
                          Text(
                            level,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGold.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$lessonCount занятий',
                      style: const TextStyle(
                        color: AppTheme.primaryGold,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
