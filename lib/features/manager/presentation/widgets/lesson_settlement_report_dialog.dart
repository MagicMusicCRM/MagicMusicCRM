import 'package:magic_music_crm/core/widgets/app_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/core/widgets/lesson_settlement_corner.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart';

Future<void> showLessonSettlementReport(
  BuildContext context, {
  required DateTime from,
  required DateTime to,
  String? branchId,
  String? teacherId,
  String? initialType,
  bool teacherPayments = false,
}) => showMagicDialog<void>(
  context: context,
  builder: (_) => LessonSettlementReportDialog(
    from: from,
    to: to,
    branchId: branchId,
    teacherId: teacherId,
    initialType: initialType,
    teacherPayments: teacherPayments,
  ),
);

class LessonSettlementReportDialog extends ConsumerStatefulWidget {
  const LessonSettlementReportDialog({
    super.key,
    required this.from,
    required this.to,
    this.branchId,
    this.teacherId,
    this.initialType,
    this.teacherPayments = false,
  });
  final DateTime from, to;
  final String? branchId, teacherId, initialType;
  final bool teacherPayments;
  @override
  ConsumerState<LessonSettlementReportDialog> createState() => _ReportState();
}

class _ReportState extends ConsumerState<LessonSettlementReportDialog> {
  List<Map<String, dynamic>> _rows = [];
  List<LessonDecisionCatalogItem> _types = [];
  String? _type;
  Object? _error;
  bool _loading = true;
  int _page = 0, _sequence = 0;
  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _load();
  }

  Future<void> _load() async {
    final sequence = ++_sequence;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final access = await ref.read(capabilitySnapshotProvider.future);
      if (!mounted || sequence != _sequence) return;
      if (!access.allows('schedule.lesson.read.assigned')) {
        throw StateError('Нет доступа к занятиям');
      }
      final crm = ref.read(magicCrmServiceProvider);
      if (_types.isEmpty) {
        final catalog = LessonDecisionCatalog.fromJson(
          await crm.getLessonDecisionCatalog(branchId: widget.branchId),
          LessonDecisionOperation.settle,
        );
        if (!mounted || sequence != _sequence) return;
        _types = widget.teacherPayments
            ? catalog.compensationRules
            : catalog.settlementTypes;
      }
      final rows = await crm.listLessons(
        from: widget.from.toUtc().toIso8601String(),
        to: widget.to
            .subtract(const Duration(microseconds: 1))
            .toUtc()
            .toIso8601String(),
        branchId: widget.branchId,
        teacherId: widget.teacherId,
        settlementTypeKey: widget.teacherPayments ? null : _type,
        compensationRuleKey: widget.teacherPayments ? _type : null,
        includeClosed: true,
        limit: 100,
        offset: _page * 100,
        order: 'desc',
      );
      if (!mounted || sequence != _sequence) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || sequence != _sequence) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    try {
      final lesson = await ref
          .read(magicCrmServiceProvider)
          .reloadActionableLesson(row);
      if (!mounted) return;
      if (await CreateLessonDialog.show(context, lesson: lesson) == true &&
          mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(error, fallback: 'Не удалось открыть занятие'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite =
        ref
            .watch(capabilitySnapshotProvider)
            .asData
            ?.value
            .allows('schedule.lesson.write') ==
        true;
    return AlertDialog(
      title: Text(
        widget.teacherPayments
            ? 'Занятия по оплате преподавателю'
            : 'Типы списания с клиентов',
      ),
      content: SizedBox(
        width: 820,
        height: 560,
        child: Column(
          children: [
            AppDropdownButtonFormField<String>(
              menuMaxHeight: 256,
              key: ValueKey(_type),
              initialValue: _type,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: widget.teacherPayments
                    ? 'Тип оплаты преподавателю'
                    : 'Тип списания',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Все типы')),
                if (_type != null && !_types.any((item) => item.key == _type))
                  DropdownMenuItem(
                    value: _type,
                    child: Text(
                      LessonSettlementCorner.labelFor(_type) ?? _type!,
                    ),
                  ),
                for (final item in _types)
                  DropdownMenuItem(
                    value: item.key,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _loading
                  ? null
                  : (value) {
                      setState(() {
                        _type = value;
                        _page = 0;
                      });
                      _load();
                    },
            ),
            const SizedBox(height: 8),
            Text(
              '${DateFormat('dd.MM.yyyy').format(widget.from)} — ${DateFormat('dd.MM.yyyy').format(widget.to.subtract(const Duration(days: 1)))}',
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            userErrorMessage(
                              _error,
                              fallback: 'Не удалось загрузить занятия',
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    )
                  : _rows.isEmpty
                  ? const Center(child: Text('Занятия не найдены'))
                  : ListView.builder(
                      itemCount: _rows.length,
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        final key =
                            row[widget.teacherPayments
                                    ? 'teacher_compensation_rule_key'
                                    : 'settlement_type_key']
                                ?.toString();
                        final label =
                            _types
                                .where((item) => item.key == key)
                                .firstOrNull
                                ?.label ??
                            LessonSettlementCorner.labelFor(key) ??
                            'Тип не указан';
                        final date = DateTime.tryParse(
                          row['scheduled_at']?.toString() ?? '',
                        );
                        return ListTile(
                          title: Text(
                            '${row['student_name'] ?? row['lead_name'] ?? row['group_name'] ?? 'Занятие'} · $label',
                          ),
                          subtitle: Text(
                            '${date == null ? '' : DateFormat('dd.MM HH:mm').format(date.toLocal())} · ${row['teacher_name'] ?? ''} · ${row['room_name'] ?? ''}',
                          ),
                          trailing: canWrite
                              ? const Icon(Icons.edit_outlined)
                              : null,
                          onTap: canWrite ? () => _edit(row) : null,
                        );
                      },
                    ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _loading || _page == 0
                      ? null
                      : () {
                          setState(() => _page--);
                          _load();
                        },
                  child: const Text('Назад'),
                ),
                Text('Страница ${_page + 1} · ${_rows.length} занятий'),
                TextButton(
                  onPressed: _loading || _rows.length < 100 || _error != null
                      ? null
                      : () {
                          setState(() => _page++);
                          _load();
                        },
                  child: const Text('Далее'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
