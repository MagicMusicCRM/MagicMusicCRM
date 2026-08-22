import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/teacher_rate_selector.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';

/// KVA-238: отчёт «Статистика преподавателей» — учебные единицы (группа /
/// индивидуально с учеником / пробные), дни с часами, часы всего, ставка за
/// астр. час, начислено и оплачено за период. Клик по группе — drill-down:
/// «Ставка по данной группе» (процесс заказчика: в конце месяца пробные без
/// покупки вручную переводят в 0 — «входит в оклад»).
class TeacherStatsWidget extends ConsumerStatefulWidget {
  const TeacherStatsWidget({super.key, this.filterRange, this.branchId});

  final DateTimeRange? filterRange;
  final String? branchId;

  @override
  ConsumerState<TeacherStatsWidget> createState() => _TeacherStatsWidgetState();
}

class _TeacherStatsWidgetState extends ConsumerState<TeacherStatsWidget> {
  bool _loading = true;
  Object? _error;
  Map<String, dynamic> _report = const {};
  List<Map<String, dynamic>> _branches = const [];
  List<Map<String, dynamic>> _teachers = const [];

  late DateTime _from;
  late DateTime _to;
  String? _branchId;
  String? _teacherId;
  String? _unitType;
  String? _status;
  String? _discipline;
  String? _category;
  List<String> _categoryOptions = const [];
  List<Map<String, dynamic>> _disciplines = const [];
  bool _exporting = false;

  /// Units ticked for the month-end «в оклад» pass, keyed by the unit's first
  /// lesson id: a lesson belongs to exactly one unit, so that id identifies the
  /// unit without the report having to grow a key field. Value = legacy lesson
  /// ids that do not yet have an immutable compensation fact.
  final Map<String, List<String>> _selectedUnits = {};
  bool _applyingBulkRate = false;

  final _money = NumberFormat('#,##0', 'ru');
  final _dayFmt = DateFormat('dd.MM');

  bool get _canCorrectSettledPayroll => const {
    'director',
    'system_admin',
  }.contains(ref.read(capabilitySnapshotProvider).asData?.value.role);

  @override
  void initState() {
    super.initState();
    _applySharedFilter();
    _loadReferences();
    _loadReport();
  }

  void _applySharedFilter() {
    final range = widget.filterRange;
    final now = DateTime.now();
    _from = range?.start ?? DateTime(now.year, now.month, 1);
    _to = range == null
        ? DateTime(now.year, now.month + 1, 1)
        : range.end.add(const Duration(days: 1));
    _branchId = widget.branchId;
  }

  @override
  void didUpdateWidget(covariant TeacherStatsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterRange != widget.filterRange ||
        oldWidget.branchId != widget.branchId) {
      _applySharedFilter();
      _loadReport();
    }
  }

  Future<void> _loadReferences() async {
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final results = await Future.wait([
        if (widget.filterRange == null) crm.listBranches(limit: 100),
        crm.listTeachers(limit: 100),
        crm.listDisciplines(),
      ]);
      if (!mounted) return;
      setState(() {
        final offset = widget.filterRange == null ? 1 : 0;
        if (offset == 1) _branches = results[0];
        _teachers = results[offset];
        _disciplines = results[offset + 1];
      });
      try {
        final fields = await ref
            .read(magicSettingsServiceProvider)
            .getCrmCustomFields();
        final categories =
            fields
                .where(
                  (field) =>
                      field.entity == 'teachers' && field.key == 'categories',
                )
                .expand((field) => field.options)
                .toSet()
                .toList()
              ..sort();
        if (mounted) setState(() => _categoryOptions = categories);
      } catch (_) {
        // The report remains usable when optional custom-field settings fail.
      }
    } catch (_) {
      // Фильтры-справочники не критичны для отчёта — молча оставляем пустыми.
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
      // The report is about to be rebuilt from a different set of lessons, so
      // any held selection would point at rows that are no longer on screen.
      _selectedUnits.clear();
    });
    try {
      final report = await ref
          .read(magicCrmServiceProvider)
          .getTeacherStatsReport(
            from: _from.toUtc().toIso8601String(),
            to: _to.toUtc().toIso8601String(),
            branchId: _branchId,
            teacherId: _teacherId,
            unitType: _unitType,
            status: _status,
            discipline: _discipline,
            category: _category,
          );
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _pickPeriod() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(
        start: _from,
        end: _to.subtract(const Duration(days: 1)),
      ),
    );
    if (picked == null) return;
    setState(() {
      _from = picked.start;
      // Конец диапазона включительно → верхняя граница = следующий день.
      _to = picked.end.add(const Duration(days: 1));
    });
    await _loadReport();
  }

  /// Sets the per-lesson rate on every lesson of an individual/trial unit.
  Future<void> _editUnitLessonRate(Map<String, dynamic> unit) async {
    final allLessonIds = [
      for (final id in (unit['lessonIds'] as List? ?? const []))
        if (id != null) id.toString(),
    ];
    final lessonIds = [
      for (final id
          in (_canCorrectSettledPayroll
              ? allLessonIds
              : (unit['editableLessonIds'] as List? ?? const [])))
        if (id != null) id.toString(),
    ];
    if (lessonIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Расчёт занятия уже зафиксирован. Исправление выполняется через корректировку расчёта в карточке занятия.',
          ),
        ),
      );
      return;
    }

    num? picked;
    var touched = false;
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(unit['unitName']?.toString() ?? 'Занятия'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _canCorrectSettledPayroll
                    ? 'Ставка применится к ${lessonIds.length} занятиям этого периода. '
                          'Зафиксированные расчёты будут исправлены с сохранением прежних фактов в аудите.'
                    : 'Ставка применится к ${lessonIds.length} незакрытым занятиям этого периода. '
                          'Зафиксированные расчёты не изменяются.',
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 12),
              TeacherRateSelector(
                initialRate: unit['rate'] as num?,
                allowInherit: true,
                onChanged: (value) => setDialogState(() {
                  picked = value;
                  touched = true;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Причина изменения *',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: touched
                  ? () {
                      if (reasonController.text.trim().isEmpty) return;
                      Navigator.pop(ctx, true);
                    }
                  : null,
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
    final reasonText = reasonController.text.trim();
    if (confirmed != true || !mounted) return;

    try {
      // One request, one transaction. This used to PATCH each lesson in a loop,
      // so a failure halfway repriced some lessons and left the rest — with no
      // way to tell which from the report.
      await ref
          .read(magicCrmServiceProvider)
          .setLessonsTeacherRate(
            lessonIds: lessonIds,
            teacherRate: picked,
            reasonText: reasonText,
          );
      if (!mounted) return;
      await _loadReport();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(e, fallback: 'Не удалось сохранить ставку.'),
          ),
        ),
      );
    }
  }

  /// Month-end bulk pass (spec §3): tick the trials nobody bought, set them all
  /// to «входит в оклад» in one go.
  Future<void> _applyBulkRate() async {
    final lessonIds = [for (final ids in _selectedUnits.values) ...ids];
    if (lessonIds.isEmpty || _applyingBulkRate) return;

    num? picked;
    var touched = false;
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Ставка выбранным'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Применится к ${_selectedUnits.length} юнитам '
                '(${lessonIds.length} занятий) за выбранный период.',
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 12),
              TeacherRateSelector(
                allowInherit: true,
                onChanged: (value) => setDialogState(() {
                  picked = value;
                  touched = true;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Причина изменения *',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: touched
                  ? () {
                      if (reasonController.text.trim().isEmpty) return;
                      Navigator.pop(ctx, true);
                    }
                  : null,
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
    final reasonText = reasonController.text.trim();
    if (confirmed != true || !mounted) return;

    setState(() => _applyingBulkRate = true);
    try {
      final updated = await ref
          .read(magicCrmServiceProvider)
          .setLessonsTeacherRate(
            lessonIds: lessonIds,
            teacherRate: picked,
            reasonText: reasonText,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Обновлено занятий: $updated')));
      await _loadReport();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(e, fallback: 'Не удалось применить ставку.'),
          ),
          backgroundColor: AppColor.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _applyingBulkRate = false);
    }
  }

  Future<void> _editGroupRate(Map<String, dynamic> unit) async {
    final groupId = unit['groupId']?.toString();
    if (groupId == null || groupId.isEmpty) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _GroupRateDialog(
        groupId: groupId,
        groupName: unit['unitName']?.toString() ?? 'Группа',
        currentRate: unit['rate'] as num?,
      ),
    );
    if (saved == true) await _loadReport();
  }

  @override
  Widget build(BuildContext context) {
    // The role is loaded asynchronously. Subscribe here so a report that
    // arrives before /access/me is rebuilt with the Director-only controls as
    // soon as the capability snapshot becomes available.
    ref.watch(capabilitySnapshotProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.all(12), child: _buildFilters()),
        if (_selectedUnits.isNotEmpty) _buildSelectionBar(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildSelectionBar() {
    final lessons = _selectedUnits.values.fold<int>(
      0,
      (sum, ids) => sum + ids.length,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(24),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryGold.withAlpha(60)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Выбрано: ${_selectedUnits.length} · занятий: $lessons',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: _applyingBulkRate
                ? null
                : () => setState(_selectedUnits.clear),
            child: const Text('Снять'),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: _applyingBulkRate ? null : _applyBulkRate,
            icon: _applyingBulkRate
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.payments_outlined, size: 18),
            label: const Text('Проставить ставку'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.filterRange == null) ...[
          OutlinedButton.icon(
            onPressed: _pickPeriod,
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(
              '${_dayFmt.format(_from)} - '
              '${_dayFmt.format(_to.subtract(const Duration(days: 1)))}',
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String?>(
              menuMaxHeight: 256,
              // Fixed-width filter box: without isExpanded the selected label plus
              // the arrow overflow the 180px SizedBox and paint the stripes.
              isExpanded: true,
              key: ValueKey('branch-$_branchId'),
              initialValue: _branchId,
              decoration: const InputDecoration(
                labelText: 'Филиал',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Все филиалы'),
                ),
                ..._branches.map(
                  (branch) => DropdownMenuItem<String?>(
                    value: branch['id']?.toString(),
                    child: Text(
                      branch['name']?.toString() ?? 'Филиал',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => _branchId = value);
                _loadReport();
              },
            ),
          ),
        ],
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            menuMaxHeight: 256,
            // Fixed-width filter box: without isExpanded the selected label plus
            // the arrow overflow the 180px SizedBox and paint the stripes.
            isExpanded: true,
            key: ValueKey('teacher-$_teacherId'),
            initialValue: _teacherId,
            decoration: const InputDecoration(
              labelText: 'Педагог',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Все педагоги'),
              ),
              ..._teachers.map((teacher) {
                final name =
                    '${teacher['first_name'] ?? ''} ${teacher['last_name'] ?? ''}'
                        .trim();
                return DropdownMenuItem<String?>(
                  value: teacher['id']?.toString(),
                  child: Text(
                    name.isEmpty ? 'Без имени' : name,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ],
            onChanged: (value) {
              setState(() => _teacherId = value);
              _loadReport();
            },
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String?>(
            menuMaxHeight: 256,
            // Fixed-width filter box: without isExpanded the selected label plus
            // the arrow overflow the 180px SizedBox and paint the stripes.
            isExpanded: true,
            key: ValueKey('unit-$_unitType'),
            initialValue: _unitType,
            decoration: const InputDecoration(
              labelText: 'Уч. единицы',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Все')),
              DropdownMenuItem<String?>(
                value: 'individual',
                child: Text('Индивидуальные'),
              ),
              DropdownMenuItem<String?>(
                value: 'group',
                child: Text('Групповые'),
              ),
              DropdownMenuItem<String?>(value: 'trial', child: Text('Пробные')),
              // ✔ Владелец 17.07: «Индивидуальный пробный» — свой разрез.
              // «Пробные» выше остались как есть (любое пробное): их разрезом
              // уже пользуются, и сузить его молча значило бы поменять цифры
              // под теми, кто на него смотрит.
              DropdownMenuItem<String?>(
                value: 'individual_trial',
                child: Text('Индивидуальные'),
              ),
              DropdownMenuItem<String?>(
                value: 'group_trial',
                child: Text('Групповые'),
              ),
            ],
            onChanged: (value) {
              setState(() => _unitType = value);
              _loadReport();
            },
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String?>(
            menuMaxHeight: 256,
            // Fixed-width filter box: without isExpanded the selected label plus
            // the arrow overflow the 180px SizedBox and paint the stripes.
            isExpanded: true,
            key: ValueKey('status-$_status'),
            initialValue: _status,
            decoration: const InputDecoration(
              labelText: 'Статус преподавателя',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Любой')),
              DropdownMenuItem<String?>(
                value: 'active',
                child: Text('Работает'),
              ),
              DropdownMenuItem<String?>(
                value: 'inactive',
                child: Text('Не работает'),
              ),
            ],
            onChanged: (value) {
              setState(() => _status = value);
              _loadReport();
            },
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String?>(
            menuMaxHeight: 256,
            // Fixed-width filter box: without isExpanded the selected label plus
            // the arrow overflow the 180px SizedBox and paint the stripes.
            isExpanded: true,
            key: ValueKey('disc-$_discipline'),
            initialValue: _discipline,
            decoration: const InputDecoration(
              labelText: 'Дисциплина',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Все')),
              for (final discipline in _disciplines)
                DropdownMenuItem<String?>(
                  value: discipline['name']?.toString(),
                  child: Text(discipline['name']?.toString() ?? 'Не указано'),
                ),
            ],
            onChanged: (value) {
              setState(() => _discipline = value);
              _loadReport();
            },
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String?>(
            menuMaxHeight: 256,
            // Fixed-width filter box: without isExpanded the selected label plus
            // the arrow overflow the 180px SizedBox and paint the stripes.
            isExpanded: true,
            key: ValueKey('cat-$_category'),
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Категория',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Все')),
              for (final category in _categoryOptions)
                DropdownMenuItem<String?>(
                  value: category,
                  child: Text(category, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              setState(() => _category = value);
              _loadReport();
            },
          ),
        ),
        IconButton(
          tooltip: 'Обновить',
          onPressed: _loadReport,
          icon: const Icon(Icons.refresh_rounded),
        ),
        FilledButton.icon(
          onPressed: _exporting ? null : _export,
          icon: _exporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('Экспорт'),
        ),
      ],
    );
  }

  /// Saves the report as CSV and opens it — the month-end process is "export,
  /// check the trial lessons, hand it over".
  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final csv = await ref
          .read(magicCrmServiceProvider)
          .exportTeacherStatsReport(
            from: _from.toUtc().toIso8601String(),
            to: _to.toUtc().toIso8601String(),
            branchId: _branchId,
            teacherId: _teacherId,
            unitType: _unitType,
            status: _status,
            discipline: _discipline,
            category: _category,
          );
      final stamp = DateFormat('yyyy-MM-dd').format(_from);
      final filename = 'teacher-stats-$stamp.csv';
      final bytes = utf8.encode(csv);
      validateReportExportBytes(bytes, 'csv');
      final result = await ref.read(reportFileOpenerProvider)(bytes, filename);
      if (!mounted) return;
      final message = result.opened
          ? 'Файл открыт: $filename'
          : 'Файл сохранён: ${result.path}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(e, fallback: 'Не удалось выгрузить отчёт.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGold),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить отчёт'),
            const SizedBox(height: 4),
            Text(
              'Проверьте подключение и повторите загрузку.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loadReport,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    final items = (_report['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (items.isEmpty) {
      return const Center(child: Text('Нет проведённых занятий за период'));
    }
    final totals = _report['totals'] as Map<String, dynamic>? ?? const {};
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        if (_branchId != null &&
            _report['movementsScope'] == 'teacher_period_all_branches') ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Занятия отфильтрованы по филиалу. Выплаты, доплаты и '
                    'вычеты показаны по преподавателю за период по всем филиалам.',
                  ),
                ),
              ],
            ),
          ),
        ],
        ...items.map(_buildTeacherCard),
        const SizedBox(height: 8),
        _buildTotals(totals),
      ],
    );
  }

  Widget _buildTeacherCard(Map<String, dynamic> item) {
    final units = (item['units'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item['teacherName']?.toString() ?? 'Без имени',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _rateBadge(item),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  '${_asInt(item['completedLessons'])} занятий · '
                  '${_asInt(item['payableLessons'])} оплачиваемых',
                ),
                Text(_hours(item['hoursTotal'])),
                Text('начислено ${_rub(item['accruedTotal'])}'),
                if (_num(item['bonusTotal']) != 0)
                  Text('доплаты ${_rub(item['bonusTotal'])}'),
                if (_num(item['deductionTotal']) != 0)
                  Text('вычеты ${_rub(item['deductionTotal'])}'),
                Text('выплачено ${_rub(item['paidTotal'])}'),
                Text(
                  'сальдо периода ${_rub(item['periodBalance'])}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...units.map(_buildUnitRow),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitRow(Map<String, dynamic> unit) {
    // Групповое пробное — тоже группа: его ставка групповая. Проверка на одну
    // строку 'group' отправила бы его в поурочную правку, а та молча
    // перекрыла бы ставку группы — ровно то, от чего оберегает комментарий ниже.
    final isGroup =
        unit['unitType'] == 'group' || unit['unitType'] == 'group_trial';
    final editableLessonIds = [
      for (final id in (unit['editableLessonIds'] as List? ?? const []))
        if (id != null) id.toString(),
    ];
    final allLessonIds = [
      for (final id in (unit['lessonIds'] as List? ?? const []))
        if (id != null) id.toString(),
    ];
    final settledLessons = _asInt(unit['settledLessons']);
    // Groups are excluded from the bulk pass on purpose: their rate knob is the
    // GROUP rate (a per-lesson override would silently shadow it). The customer
    // asked for the trials pass, and that is what this selects.
    final selectedLessonIds = _canCorrectSettledPayroll
        ? allLessonIds
        : editableLessonIds;
    final selectable =
        selectedLessonIds.isNotEmpty && (_canCorrectSettledPayroll || !isGroup);
    final unitKey = selectable ? selectedLessonIds.first : null;
    final days = (unit['days'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((day) {
          final date = DateTime.tryParse(day['date']?.toString() ?? '');
          final label = date == null
              ? day['date'].toString()
              : _dayFmt.format(date);
          return '$label (${_hours(day['hours'])})';
        })
        .join(', ');
    final typeLabel = switch (unit['unitType']) {
      'group' => 'Группа',
      'group_trial' => 'Групп. пробный',
      'individual_trial' => 'Индив. пробный',
      _ => 'Индивид.',
    };
    return InkWell(
      // Drill-down: a group edits its group rate; an individual/trial unit
      // edits the per-lesson rate of the lessons behind it — that is the
      // month-end move (a trial nobody bought becomes «входит в оклад»).
      onTap: isGroup
          ? () => _editGroupRate(unit)
          : () => _editUnitLessonRate(unit),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectable)
              SizedBox(
                width: 28,
                height: 28,
                child: Checkbox(
                  value: _selectedUnits.containsKey(unitKey),
                  onChanged: _applyingBulkRate
                      ? null
                      : (checked) => setState(() {
                          if (checked == true) {
                            _selectedUnits[unitKey!] = selectedLessonIds;
                          } else {
                            _selectedUnits.remove(unitKey);
                          }
                        }),
                ),
              )
            else
              // Keeps group rows aligned with the ticked ones above/below.
              const SizedBox(width: 28),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryGold.withAlpha(24),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(typeLabel, style: const TextStyle(fontSize: 11)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unit['unitName']?.toString() ?? 'Не указано',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (days.isNotEmpty)
                    Text(
                      '$days · ${_asInt(unit['completedLessons'])} зан. · '
                      '${_asInt(unit['payableLessons'])} оплач.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  if (settledLessons > 0)
                    Text(
                      _canCorrectSettledPayroll
                          ? 'Зафиксировано расчётов: $settledLessons · директор может исправить массово'
                          : 'Зафиксировано расчётов: $settledLessons · исправление через карточку занятия',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_hours(unit['hoursTotal'])} × ${_rateLabel(unit['rate'])}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                Text(
                  _rub(unit['accruedTotal']),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (settledLessons > 0 && !_canCorrectSettledPayroll) ...[
              const SizedBox(width: 4),
              const Tooltip(
                message: 'Расчёт зафиксирован и не меняется задним числом',
                child: Icon(Icons.lock_outline_rounded, size: 14),
              ),
            ] else if (isGroup) ...[
              const SizedBox(width: 4),
              const Icon(Icons.edit_rounded, size: 14),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTotals(Map<String, dynamic> totals) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryGold.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Итого', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                '${_asInt(totals['completedLessons'])} занятий · '
                '${_asInt(totals['payableLessons'])} оплачиваемых',
              ),
              Text(_hours(totals['hoursTotal'])),
              Text('начислено ${_rub(totals['accruedTotal'])}'),
              Text('доплаты ${_rub(totals['bonusTotal'])}'),
              Text('вычеты ${_rub(totals['deductionTotal'])}'),
              Text('выплачено ${_rub(totals['paidTotal'])}'),
              Text(
                'сальдо периода ${_rub(totals['periodBalance'])}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _rub(dynamic value) => '${_money.format(_num(value))} ₽';

  String _hours(dynamic value) {
    final hours = _num(value);
    final text = hours == hours.roundToDouble()
        ? hours.toStringAsFixed(0)
        : hours.toStringAsFixed(2);
    return '$text астр.ч.';
  }

  String _rateLabel(dynamic value) {
    final rate = _num(value);
    return rate == 0 ? 'оклад' : '${_money.format(rate)} ₽';
  }

  num _num(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _asInt(dynamic value) => _num(value).toInt();

  Widget _rateBadge(Map<String, dynamic> item) {
    final salary = item['salary'];
    final rate = _num(item['currentRate']);
    final label = rate == 0
        ? 'Входит в оклад'
        : '${_money.format(rate)} ₽/астр.ч.';
    final suffix = salary == null ? '' : ' · оклад ${_rub(salary)}';
    return Text(
      '$label$suffix',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
      ),
    );
  }
}

/// KVA-238: drill-down диалог «Ставка по данной группе».
class _GroupRateDialog extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;
  final num? currentRate;

  const _GroupRateDialog({
    required this.groupId,
    required this.groupName,
    this.currentRate,
  });

  @override
  ConsumerState<_GroupRateDialog> createState() => _GroupRateDialogState();
}

class _GroupRateDialogState extends ConsumerState<_GroupRateDialog> {
  num? _rate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rate = widget.currentRate;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .updateGroup(
            widget.groupId,
            teacherRate: _rate,
            setTeacherRate: true,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось сохранить изменение.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.groupName),
      content: SizedBox(
        width: 360,
        child: TeacherRateSelector(
          initialRate: widget.currentRate,
          allowInherit: true,
          label: 'Ставка по данной группе',
          onChanged: (rate) => _rate = rate,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
