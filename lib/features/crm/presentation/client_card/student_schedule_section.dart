import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

import 'preferred_schedule_editor.dart';

/// KVA-236: «График занятий» в карточке ученика — серии постоянного
/// расписания (UX HolliHop image2/3: строка «день · время · педагог ·
/// аудитория · период» с карандашом) + лента дат-квадратиков (прошедшие
/// серые, будущие зелёные, пропуски тёмные с красным уголком; tooltip со
/// статусом и заметкой).
class StudentScheduleSection extends ConsumerStatefulWidget {
  final String clientType;
  final String clientId;
  final List<Map<String, dynamic>> lessons;
  final List<Map<String, dynamic>> branches;
  final String? defaultBranchId;
  final String? legacyPreference;
  final bool canWrite;
  final VoidCallback onChanged;

  const StudentScheduleSection({
    super.key,
    required this.clientType,
    required this.clientId,
    required this.lessons,
    required this.branches,
    required this.defaultBranchId,
    required this.canWrite,
    this.legacyPreference,
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

  @override
  void didUpdateWidget(covariant StudentScheduleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientType != widget.clientType ||
        oldWidget.clientId != widget.clientId) {
      _seriesFuture = _loadSeries();
    }
  }

  Future<List<Map<String, dynamic>>> _loadSeries() {
    return ref
        .read(magicCrmServiceProvider)
        .listScheduleSeries(
          clientType: widget.clientType,
          clientId: widget.clientId,
        );
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
                'Предпочтительное расписание',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            if (widget.canWrite)
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
                label: const Text('Добавить предпочтение'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if ((widget.legacyPreference ?? '').trim().isNotEmpty) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: AppSpace.sm),
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              'Ранее записанное пожелание: ${widget.legacyPreference!.trim()}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
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
          if (widget.canWrite) ...[
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
      key: const Key('client-lesson-date-tray'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (dt, lesson) in window)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _dateSquare(dt, lesson),
            ),
        ],
      ),
    );
  }

  Widget _dateSquare(DateTime dt, Map<String, dynamic> lesson) {
    final projection = LessonStateProjection.fromMap(lesson);
    final accent = projection.token.accent;
    final isTrial = lesson['is_trial'] == true;
    final notes = (lesson['notes'] ?? '').toString().trim();
    // ✔ Владелец 17.07: «оплаты по дням в расписании». Считает сервер — сумма
    // платежей, привязанных к этому занятию. null означает «за этот день
    // платежа нет», а не «оплачено 0»: привязывать платёж к занятию не
    // обязательно (аванс на счёт, абонемент, импорт из HolliHop), поэтому
    // отсутствие метки НЕ значит «не оплачено».
    final paid = (lesson['paid_amount'] as num?)?.toDouble();
    final tooltip = [
      DateFormat('dd.MM.yyyy HH:mm', 'ru').format(dt.toLocal()),
      projection.label,
      if (isTrial) 'Пробное занятие',
      if (paid != null) 'Оплачено: ${_money(paid)} ₽',
      if (notes.isNotEmpty) notes,
    ].join('\n');
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: null,
        child: Stack(
          children: [
            Container(
              width: 46,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: projection.token.soft,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
              ),
              child: Text(
                DateFormat('d.MM').format(dt.toLocal()),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
            if (isTrial)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColor.gold,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(4),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'П',
                    style: TextStyle(
                      fontSize: 6,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
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
      final [teacherRows, roomRows] = await Future.wait([
        crm.listTeachers(limit: 100),
        crm.listRooms(limit: 100),
      ]);
      teachers = List<Map<String, dynamic>>.from(teacherRows);
      rooms = List<Map<String, dynamic>>.from(roomRows);
    } catch (error) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось загрузить справочники расписания',
          detail: '$error',
          type: MagicToastType.danger,
        );
      }
      return;
    }
    if (!mounted) return;

    final isEdit = series != null;
    final draft = await showMagicSheet<PreferredScheduleDraft>(
      context,
      title: isEdit
          ? 'Изменить предпочтительное расписание'
          : 'Добавить предпочтение',
      subtitle: isEdit
          ? 'Изменения применятся с выбранной даты'
          : 'План хранится отдельно от списка фактических занятий',
      icon: Icons.event_repeat_rounded,
      builder: (_) => PreferredScheduleEditor(
        branches: widget.branches,
        teachers: teachers,
        rooms: rooms,
        defaultBranchId: widget.defaultBranchId,
        series: series,
      ),
    );
    if (draft == null || !mounted) return;

    String slotTime(int index) {
      final parts = draft.beginTime.split(':');
      final totalMinutes =
          (int.tryParse(parts.first) ?? 0) * 60 +
          (int.tryParse(parts.last) ?? 0) +
          draft.durationMinutes * index;
      return '${(totalMinutes ~/ 60).toString().padLeft(2, '0')}:${(totalMinutes % 60).toString().padLeft(2, '0')}';
    }

    var saved = 0;
    try {
      final validFrom = DateFormat('yyyy-MM-dd').format(draft.validFrom);
      final validUntil = DateFormat('yyyy-MM-dd').format(draft.validUntil);
      if (isEdit) {
        await crm.updateScheduleSeries(
          series['id'].toString(),
          teacherId: draft.teacherId,
          roomId: draft.roomId,
          weekday: draft.weekdays.first,
          beginTime: draft.beginTime,
          durationMinutes: draft.durationMinutes,
          validUntil: validUntil,
          effectiveFrom: validFrom,
          notes: draft.notes,
        );
        saved = 1;
      } else {
        final weekdays = draft.weekdays.toList()..sort();
        for (final weekday in weekdays) {
          for (var slot = 0; slot < draft.lessonsPerDay; slot++) {
            await crm.createScheduleSeries(
              clientType: widget.clientType,
              clientId: widget.clientId,
              branchId: draft.branchId,
              teacherId: draft.teacherId,
              roomId: draft.roomId,
              weekday: weekday,
              beginTime: slotTime(slot),
              durationMinutes: draft.durationMinutes,
              validFrom: validFrom,
              validUntil: validUntil,
              notes: draft.notes,
            );
            saved++;
          }
        }
      }
      if (mounted) {
        _reloadSeries();
        widget.onChanged();
        MagicToast.show(
          context,
          isEdit ? 'Предпочтение обновлено' : 'Создано предпочтений: $saved',
          type: MagicToastType.success,
        );
      }
    } catch (error) {
      if (mounted) {
        _reloadSeries();
        widget.onChanged();
        MagicToast.show(
          context,
          saved == 0
              ? 'Не удалось сохранить предпочтение'
              : 'Сохранено $saved; остальные не созданы',
          detail: saved == 0
              ? '$error'
              : 'Обновите список перед повторной попыткой. $error',
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
