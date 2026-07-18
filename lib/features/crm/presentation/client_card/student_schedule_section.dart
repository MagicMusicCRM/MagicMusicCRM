import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/lesson_attendance_dialog.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';

/// KVA-236: «График занятий» в карточке ученика — серии постоянного
/// расписания (UX HolliHop image2/3: строка «день · время · педагог ·
/// аудитория · период» с карандашом) + лента дат-квадратиков (прошедшие
/// серые, будущие зелёные, пропуски тёмные с красным уголком; tooltip со
/// статусом и заметкой; клик — модалка посещаемости).
class StudentScheduleSection extends ConsumerStatefulWidget {
  final String studentId;
  final List<Map<String, dynamic>> lessons;
  final VoidCallback onChanged;

  const StudentScheduleSection({
    super.key,
    required this.studentId,
    required this.lessons,
    required this.onChanged,
  });

  @override
  ConsumerState<StudentScheduleSection> createState() =>
      _StudentScheduleSectionState();
}

class _StudentScheduleSectionState
    extends ConsumerState<StudentScheduleSection> {
  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  int _refreshKey = 0;
  // Cached so parent rebuilds don't re-fire the API call: a FutureBuilder
  // given a fresh future instance restarts on every build.
  late Future<List<Map<String, dynamic>>> _seriesFuture;

  @override
  void initState() {
    super.initState();
    _seriesFuture = _loadSeries();
  }

  Future<List<Map<String, dynamic>>> _loadSeries() {
    return ref
        .read(magicCrmServiceProvider)
        .listScheduleSeries(studentId: widget.studentId);
  }

  void _reloadSeries() {
    setState(() {
      _refreshKey++;
      _seriesFuture = _loadSeries();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'График занятий',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: () => _openEditor(),
              style: TextButton.styleFrom(
                foregroundColor: AppColor.gold,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 15),
              label: const Text('Добавить'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FutureBuilder<List<Map<String, dynamic>>>(
          key: ValueKey('series-$_refreshKey'),
          future: _seriesFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
                child: LinearProgressIndicator(color: AppColor.gold),
              );
            }
            if (snap.hasError) {
              // A failed load must not look like "no schedule configured".
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      'Не удалось загрузить график занятий',
                      style: TextStyle(color: cs.error, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _reloadSeries,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColor.gold,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    child: const Text('Повторить'),
                  ),
                ],
              );
            }
            final series = snap.data ?? const [];
            if (series.isEmpty) {
              return Text(
                'Постоянное расписание не задано',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              );
            }
            return Column(
              children: [for (final s in series) _seriesRow(cs, s)],
            );
          },
        ),
        const SizedBox(height: AppSpace.md),
        _lessonStrip(cs),
        _paidLegend(cs),
      ],
    );
  }

  /// Легенда к зелёному уголку с рублём.
  ///
  /// Показывается, только когда в ленте есть хоть один оплаченный день: иначе
  /// это подпись к тому, чего не видно. И важнее самой легенды — оговорка:
  /// отсутствие метки НЕ означает «не оплачено». Платёж к занятию привязывать
  /// не обязательно, а у импортированных из HolliHop такой связи нет вовсе.
  Widget _paidLegend(ColorScheme cs) {
    final anyPaid = widget.lessons.any((l) => l['paid_amount'] != null);
    if (!anyPaid) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColor.success,
              borderRadius: BorderRadius.circular(2),
            ),
            child: const Text(
              '₽',
              style: TextStyle(
                fontSize: 6,
                height: 1,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '— за день есть платёж. Без метки — платёж к этому дню не '
              'привязан (это не значит «не оплачено»).',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seriesRow(ColorScheme cs, Map<String, dynamic> s) {
    final weekday = (s['weekday'] is num)
        ? (s['weekday'] as num).toInt()
        : int.tryParse('${s['weekday']}') ?? 1;
    final day = _weekdays[(weekday - 1).clamp(0, 6)];
    final time = (s['begin_time'] ?? '').toString();
    final duration = s['duration_minutes'] ?? 60;
    final until = s['valid_until'];
    final untilLabel = until == null ? 'до ∞' : 'по ${_formatDate(until)}';
    final meta = [
      s['teacher_name'],
      s['room_name'],
      'с ${_formatDate(s['valid_from'])} $untilLabel',
    ].where((v) => v != null && '$v'.trim().isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColor.goldSoft,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: AppColor.goldLine),
            ),
            child: Text(
              '$day $time',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColor.gold,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              '$duration мин · $meta',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          IconButton(
            onPressed: () => _openEditor(series: s),
            icon: const Icon(Icons.edit_outlined, size: 16),
            color: AppColor.gold,
            visualDensity: VisualDensity.compact,
            tooltip: 'Изменить (со следующей даты)',
          ),
          IconButton(
            onPressed: () => _stopSeries(s),
            icon: const Icon(Icons.stop_circle_outlined, size: 16),
            color: cs.error,
            visualDensity: VisualDensity.compact,
            tooltip: 'Остановить серию',
          ),
        ],
      ),
    );
  }

  // ── Лента дат-квадратиков (HolliHop image2) ────────────────────────────────
  Widget _lessonStrip(ColorScheme cs) {
    final now = DateTime.now();
    final sorted =
        widget.lessons
            .map((l) {
              final dt = DateTime.tryParse(l['scheduled_at']?.toString() ?? '');
              return dt == null ? null : (dt, l);
            })
            .whereType<(DateTime, Map<String, dynamic>)>()
            .toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
    if (sorted.isEmpty) return const SizedBox.shrink();
    final past = sorted.where((e) => e.$1.isBefore(now)).toList();
    final future = sorted.where((e) => !e.$1.isBefore(now)).toList();
    final window = [
      ...past.skip(past.length > 12 ? past.length - 12 : 0),
      ...future.take(16),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (dt, lesson) in window)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _dateSquare(cs, dt, lesson, isPast: dt.isBefore(now)),
            ),
        ],
      ),
    );
  }

  Widget _dateSquare(
    ColorScheme cs,
    DateTime dt,
    Map<String, dynamic> lesson, {
    required bool isPast,
  }) {
    final status = (lesson['status'] ?? 'scheduled').toString();
    final missed = status == 'missed' || status == 'cancelled';
    final Color bg;
    final Color fg;
    if (missed) {
      bg = const Color(0xFF3A3A3E);
      fg = Colors.white;
    } else if (isPast) {
      bg = cs.surfaceContainerHighest;
      fg = cs.onSurfaceVariant;
    } else {
      bg = const Color(0xFF8BC34A);
      fg = Colors.white;
    }
    final notes = (lesson['notes'] ?? '').toString().trim();
    // ✔ Владелец 17.07: «оплаты по дням в расписании». Считает сервер — сумма
    // платежей, привязанных к этому занятию. null означает «за этот день
    // платежа нет», а не «оплачено 0»: привязывать платёж к занятию не
    // обязательно (аванс на счёт, абонемент, импорт из HolliHop), поэтому
    // отсутствие метки НЕ значит «не оплачено».
    final paid = (lesson['paid_amount'] as num?)?.toDouble();
    final tooltip = [
      DateFormat('dd.MM.yyyy HH:mm', 'ru').format(dt.toLocal()),
      _statusLabel(status),
      if (paid != null) 'Оплачено: ${_money(paid)} ₽',
      if (notes.isNotEmpty) notes,
    ].join('\n');
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () async {
          await LessonAttendanceDialog.show(context, lesson);
          widget.onChanged();
        },
        child: Stack(
          children: [
            Container(
              width: 46,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                DateFormat('d.MM').format(dt.toLocal()),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            if (missed)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColor.danger,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            // Оплаченный день — уголок с рублём внизу слева: правый верхний уже
            // занят пропуском, а день бывает и пропущенным, и оплаченным.
            if (paid != null)
              Positioned(
                bottom: 0,
                left: 0,
                child: Container(
                  width: 12,
                  height: 10,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColor.success,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                  child: const Text(
                    '₽',
                    style: TextStyle(
                      fontSize: 7,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// «1 500» вместо «1500.0»: сумма в тултипе читается человеком.
  String _money(double value) {
    final rounded = value.roundToDouble() == value ? value.round() : value;
    return NumberFormat.decimalPattern('ru').format(rounded);
  }

  String _statusLabel(String status) {
    return switch (status) {
      'completed' || 'done' => 'Проведено',
      'missed' => 'Пропуск',
      'cancelled' => 'Отменено',
      _ => 'Запланировано',
    };
  }

  String _formatDate(Object? value) {
    final dt = DateTime.tryParse(value?.toString() ?? '');
    return dt == null ? '—' : DateFormat('dd.MM.yyyy').format(dt);
  }

  // ── Редактор серии («карандаш», HolliHop image3) ──────────────────────────
  Future<void> _openEditor({Map<String, dynamic>? series}) async {
    final crm = ref.read(magicCrmServiceProvider);
    List<Map<String, dynamic>> teachers;
    List<Map<String, dynamic>> rooms;
    try {
      final [t, r] = await Future.wait([
        crm.listTeachers(limit: 100),
        crm.listRooms(limit: 100),
      ]);
      teachers = List<Map<String, dynamic>>.from(t);
      rooms = List<Map<String, dynamic>>.from(r);
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось загрузить данные',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
      return;
    }
    if (!mounted) return;

    final isEdit = series != null;
    var weekday = isEdit
        ? ((series['weekday'] as num?)?.toInt() ?? 1)
        : DateTime.now().weekday;
    var time = isEdit ? (series['begin_time'] ?? '15:00').toString() : '15:00';
    var duration = isEdit
        ? ((series['duration_minutes'] as num?)?.toInt() ?? 60)
        : 60;
    String? teacherId = isEdit ? series['teacher_id']?.toString() : null;
    String? roomId = isEdit ? series['room_id']?.toString() : null;
    // Создание: старт серии; правка: дата применения («со следующей даты»).
    DateTime startDate = DateTime.now().add(const Duration(days: 1));
    var infinite = isEdit ? series['valid_until'] == null : true;
    DateTime? untilDate = isEdit && series['valid_until'] != null
        ? DateTime.tryParse('${series['valid_until']}')
        : null;

    final cs = Theme.of(context).colorScheme;
    final confirmed = await showMagicSheet<bool>(
      context,
      title: isEdit ? 'Изменить расписание' : 'Постоянное расписание',
      subtitle: isEdit
          ? 'Правка применится с выбранной даты; прошедшие занятия не изменятся'
          : 'Занятия будут создаваться автоматически',
      icon: Icons.event_repeat_rounded,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: weekday,
                    decoration: const InputDecoration(
                      labelText: 'День недели',
                      isDense: true,
                    ),
                    items: [
                      for (var i = 1; i <= 7; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(_weekdays[i - 1]),
                        ),
                    ],
                    onChanged: (v) =>
                        setSheetState(() => weekday = v ?? weekday),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final parts = time.split(':');
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: int.tryParse(parts.first) ?? 15,
                          minute: int.tryParse(parts.last) ?? 0,
                        ),
                      );
                      if (picked != null) {
                        setSheetState(
                          () => time =
                              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
                        );
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Время',
                        isDense: true,
                      ),
                      child: Text(time),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: duration,
                    decoration: const InputDecoration(
                      labelText: 'Мин.',
                      isDense: true,
                    ),
                    items: const [30, 45, 60, 90, 120]
                        .map(
                          (d) => DropdownMenuItem(value: d, child: Text('$d')),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setSheetState(() => duration = v ?? duration),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            SearchablePickerField(
              label: 'Педагог',
              placeholder: 'Выберите педагога',
              selectedId: teacherId,
              items: [
                for (final t in teachers)
                  SearchableSelectItem(
                    id: t['id'].toString(),
                    label: '${t['first_name'] ?? ''} ${t['last_name'] ?? ''}'
                        .trim(),
                  ),
              ],
              onSelected: (item) => setSheetState(() => teacherId = item?.id),
            ),
            const SizedBox(height: AppSpace.md),
            SearchablePickerField(
              label: 'Аудитория',
              placeholder: 'Выберите аудиторию',
              selectedId: roomId,
              items: [
                for (final r in rooms)
                  SearchableSelectItem(
                    id: r['id'].toString(),
                    label: r['name']?.toString() ?? '—',
                  ),
              ],
              onSelected: (item) => setSheetState(() => roomId = item?.id),
            ),
            const SizedBox(height: AppSpace.md),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: startDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setSheetState(() => startDate = picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: isEdit ? 'Применить с даты' : 'Начало занятий',
                  isDense: true,
                ),
                child: Text(DateFormat('dd.MM.yyyy').format(startDate)),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Checkbox(
                  value: infinite,
                  activeColor: AppColor.gold,
                  onChanged: (v) => setSheetState(() => infinite = v ?? true),
                ),
                const Text('До бесконечности', style: TextStyle(fontSize: 13)),
                const Spacer(),
                if (!infinite)
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: untilDate ?? startDate,
                        firstDate: startDate,
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (picked != null) {
                        setSheetState(() => untilDate = picked);
                      }
                    },
                    child: Text(
                      untilDate == null
                          ? 'Дата окончания…'
                          : 'по ${DateFormat('dd.MM.yyyy').format(untilDate!)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColor.gold,
            foregroundColor: AppColor.onGold,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          child: Text(isEdit ? 'Применить' : 'Создать'),
        ),
      ],
    );
    if (confirmed != true) return;

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final untilStr = infinite || untilDate == null
          ? null
          : DateFormat('yyyy-MM-dd').format(untilDate!);
      String? branchId;
      for (final room in rooms) {
        if (room['id']?.toString() == roomId) {
          branchId = room['branch_id']?.toString();
          break;
        }
      }
      if (isEdit) {
        await crm.updateScheduleSeries(
          series['id'].toString(),
          teacherId: teacherId,
          roomId: roomId,
          weekday: weekday,
          beginTime: time,
          durationMinutes: duration,
          validUntil: untilStr,
          clearValidUntil: infinite,
          effectiveFrom: dateStr,
        );
      } else {
        await crm.createScheduleSeries(
          studentId: widget.studentId,
          teacherId: teacherId,
          roomId: roomId,
          branchId: branchId,
          weekday: weekday,
          beginTime: time,
          durationMinutes: duration,
          validFrom: dateStr,
          validUntil: untilStr,
        );
      }
      if (mounted) {
        _reloadSeries();
        widget.onChanged();
        MagicToast.show(
          context,
          isEdit ? 'Расписание обновлено' : 'Расписание создано',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка сохранения',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    }
  }

  Future<void> _stopSeries(Map<String, dynamic> series) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Остановить серию?'),
        content: const Text(
          'Будущие занятия этой серии будут сняты. Прошедшие не изменятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Остановить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(magicCrmServiceProvider)
          .deleteScheduleSeries(series['id'].toString());
      if (mounted) {
        _reloadSeries();
        widget.onChanged();
        MagicToast.show(
          context,
          'Серия остановлена',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    }
  }
}
