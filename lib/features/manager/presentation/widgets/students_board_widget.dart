import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/students_board_providers.dart';

/// Ученики board widget — per-branch discipline columns (read-only kanban).
///
/// Mirrors the visual structure of [LeadsWidget] (column header with count
/// badge, card layout, horizontal scroll, [KanbanSkeleton] loading) but is
/// read-only (no drag-and-drop in v1).
class StudentsBoardWidget extends ConsumerStatefulWidget {
  const StudentsBoardWidget({super.key});

  @override
  ConsumerState<StudentsBoardWidget> createState() =>
      _StudentsBoardWidgetState();
}

class _StudentsBoardWidgetState extends ConsumerState<StudentsBoardWidget> {
  final _boardScrollController = ScrollController();
  List<Map<String, dynamic>> _branches = [];
  String? _selectedBranchId;
  bool _branchesLoaded = false;
  String? _branchLoadError;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _boardScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final branches = await crm.listBranches(limit: 100);
      if (!mounted) return;
      setState(() {
        _branches = List<Map<String, dynamic>>.from(branches);
        if (_branches.isNotEmpty && _selectedBranchId == null) {
          _selectedBranchId = _branches.first['id']?.toString();
        }
        _branchesLoaded = true;
        _branchLoadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _branchLoadError = 'Не удалось загрузить филиалы';
        _branchesLoaded = true;
      });
    }
  }

  void _refreshBoard() {
    if (_selectedBranchId != null) {
      ref.invalidate(studentBoardProvider(_selectedBranchId!));
    }
  }

  void _openStudentInfo(BuildContext context, Map<String, dynamic> student) {
    final firstName = student['first_name']?.toString() ?? '';
    final lastName = student['last_name']?.toString() ?? '';
    final displayName = '$firstName $lastName'.trim();
    final phone = student['phone']?.toString() ?? '';
    final branchName = student['branch_name']?.toString() ?? '';
    final customData = student['custom_data'];
    final discipline = customData is Map
        ? customData['discipline']?.toString() ?? ''
        : '';
    final status = student['status']?.toString() ?? '';
    final openTasks = _intValue(student['open_tasks_count']);
    final lessonsCount = _intValue(student['lessons_count']);
    final groupsCount = _intValue(student['groups_count']);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(displayName.isEmpty ? 'Ученик' : displayName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (phone.isNotEmpty) _infoRow(Icons.phone_rounded, phone),
            if (branchName.isNotEmpty)
              _infoRow(Icons.location_on_outlined, branchName),
            if (discipline.isNotEmpty)
              _infoRow(Icons.school_rounded, discipline),
            if (status.isNotEmpty) _infoRow(Icons.info_outline_rounded, status),
            if (openTasks > 0 || lessonsCount > 0 || groupsCount > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (openTasks > 0)
                    _metricChip(
                      ctx,
                      Icons.task_alt_rounded,
                      '$openTasks задач',
                    ),
                  if (lessonsCount > 0)
                    _metricChip(
                      ctx,
                      Icons.event_rounded,
                      '$lessonsCount уроков',
                    ),
                  if (groupsCount > 0)
                    _metricChip(
                      ctx,
                      Icons.group_rounded,
                      '$groupsCount групп',
                    ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryGold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _metricChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(36),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.primaryGold),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.primaryGold,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchSelector() {
    final seen = <String>{};
    final items = _branches
        .where((b) => seen.add(b['id']?.toString() ?? ''))
        .map(
          (b) => DropdownMenuItem<String>(
            value: b['id']?.toString() ?? '',
            child: Text(
              b['name']?.toString() ?? b['id']?.toString() ?? '',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Icon(Icons.school_rounded, size: 20, color: AppTheme.primaryGold),
          const SizedBox(width: 10),
          const Text(
            'Ученики',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 16),
          if (!_branchesLoaded && _branchLoadError == null)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (_branchLoadError != null)
            // error inline placeholder — full error block is in build()
            const SizedBox.shrink()
          else if (_branches.isNotEmpty)
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                key: ValueKey('branch:$_selectedBranchId'),
                initialValue: _selectedBranchId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Филиал',
                  isDense: true,
                ),
                items: items,
                onChanged: (value) {
                  if (value != null && value.isNotEmpty) {
                    setState(() => _selectedBranchId = value);
                  }
                },
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshBoard,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Loading state — branches not yet fetched.
    if (!_branchesLoaded && _branchLoadError == null) {
      return Column(
        children: [
          _buildBranchSelector(),
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    // Error state — failed to load branches.
    if (_branchLoadError != null) {
      return Column(
        children: [
          _buildBranchSelector(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppTheme.danger,
                      size: 42,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _branchLoadError!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Проверьте подключение и попробуйте снова.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _branchesLoaded = false;
                          _branchLoadError = null;
                        });
                        _loadBranches();
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Loaded-empty state — no branches configured.
    if (_branches.isEmpty) {
      return Column(
        children: [
          _buildBranchSelector(),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_off_rounded, size: 42, color: Colors.grey),
                  SizedBox(height: 10),
                  Text(
                    'Нет филиалов',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Добавьте хотя бы один филиал в настройках.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_selectedBranchId == null) {
      return Column(
        children: [_buildBranchSelector(), const Expanded(child: KanbanSkeleton())],
      );
    }

    final boardAsync = ref.watch(studentBoardProvider(_selectedBranchId!));

    return Column(
      children: [
        _buildBranchSelector(),
        Expanded(
          child: boardAsync.when(
            loading: () => const KanbanSkeleton(),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppTheme.danger,
                      size: 42,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Не удалось загрузить учеников',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Проверьте подключение и попробуйте снова.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _refreshBoard,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
            data: (columns) {
              if (columns.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_outline_rounded,
                        size: 42,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Нет учеников',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Scrollbar(
                controller: _boardScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _boardScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: columns.map((column) {
                      final name = column['name']?.toString() ?? 'Без названия';
                      final students = column['students'] is List
                          ? (column['students'] as List)
                                .whereType<Map<String, dynamic>>()
                                .toList()
                          : <Map<String, dynamic>>[];
                      return _DisciplineColumn(
                        name: name,
                        students: students,
                        onTap: (s) => _openStudentInfo(context, s),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

// ── Column ────────────────────────────────────────────────────────────────────

class _DisciplineColumn extends StatelessWidget {
  final String name;
  final List<Map<String, dynamic>> students;
  final ValueChanged<Map<String, dynamic>> onTap;

  const _DisciplineColumn({
    required this.name,
    required this.students,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(127),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(
                  Icons.school_rounded,
                  size: 14,
                  color: AppTheme.primaryGold,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${students.length}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Cards ────────────────────────────────────────────────────────
          Expanded(
            child: students.isEmpty
                ? Center(
                    child: Text(
                      'Нет учеников',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: students.length,
                    itemBuilder: (context, index) => _StudentCard(
                      student: students[index],
                      onTap: onTap,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Card ─────────────────────────────────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final Map<String, dynamic> student;
  final ValueChanged<Map<String, dynamic>> onTap;

  const _StudentCard({required this.student, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final firstName = student['first_name']?.toString() ?? '';
    final lastName = student['last_name']?.toString() ?? '';
    final displayName = '$firstName $lastName'.trim();
    final name = displayName.isEmpty ? 'Без имени' : displayName;
    final phone = student['phone']?.toString() ?? '';
    final branchName = student['branch_name']?.toString() ?? '';
    final customData = student['custom_data'];
    final discipline = customData is Map
        ? customData['discipline']?.toString() ?? ''
        : '';
    final openTasks = _intValue(student['open_tasks_count']);
    final lessonsCount = _intValue(student['lessons_count']);
    final groupsCount = _intValue(student['groups_count']);

    return GestureDetector(
      onTap: () => onTap(student),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Name ──────────────────────────────────────────────────
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              // ── Phone ─────────────────────────────────────────────────
              if (phone.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    phone,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              // ── Discipline badge ───────────────────────────────────────
              if (discipline.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGold.withAlpha(51),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    discipline,
                    style: TextStyle(
                      color: AppTheme.primaryGold,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              // ── Branch badge ───────────────────────────────────────────
              if (branchName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _IconBadge(
                    icon: Icons.location_on_outlined,
                    text: branchName,
                  ),
                ),
              // ── Metric badges (tasks / lessons / groups) ───────────────
              if (openTasks > 0 || lessonsCount > 0 || groupsCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (openTasks > 0)
                        _MetricBadge(
                          icon: Icons.task_alt_rounded,
                          text: '$openTasks',
                        ),
                      if (lessonsCount > 0)
                        _MetricBadge(
                          icon: Icons.event_rounded,
                          text: '$lessonsCount',
                        ),
                      if (groupsCount > 0)
                        _MetricBadge(
                          icon: Icons.group_rounded,
                          text: '$groupsCount',
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

// ── Shared badge widgets ──────────────────────────────────────────────────────

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _IconBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetricBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(36),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.primaryGold),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.primaryGold,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
