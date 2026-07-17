import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';

/// v7 attendance sheet (P2-5 / v7p2-3 / KVA-237). Theme-aware (in-app screen):
/// surfaces follow the app theme, accents use the v7 tokens.
///
/// `show()` API and the participation shape are backward-compatible; KVA-237
/// added the 5 HolliHop-статусов (`kind`), долю списания для частично
/// оплачиваемого и чекбокс «Уведомить об изменениях».
class LessonAttendanceDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> lesson;

  const LessonAttendanceDialog({super.key, required this.lesson});

  static Future<void> show(BuildContext context, Map<String, dynamic> lesson) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColor.scrim,
      builder: (ctx) => LessonAttendanceDialog(lesson: lesson),
    );
  }

  @override
  ConsumerState<LessonAttendanceDialog> createState() =>
      _LessonAttendanceDialogState();
}

// KVA-237: 5 типов посещения (модель HolliHop) — (kind, подпись, цвет).
const List<(String, String)> kAttendanceKinds = [
  ('attended', 'Занятие'),
  ('unpaid_miss', 'Неоплачиваемый пропуск'),
  ('free_lesson', 'Бесплатное занятие'),
  ('paid_miss', 'Оплачиваемый пропуск'),
  ('partially_paid', 'Частично оплачиваемое'),
];

Color attendanceKindColor(String kind) {
  return switch (kind) {
    'attended' => AppColor.success,
    'unpaid_miss' => AppColor.danger,
    'free_lesson' => AppColor.gold,
    'paid_miss' => const Color(0xFFB8860B),
    'partially_paid' => const Color(0xFF8E6BC9),
    _ => AppColor.gold,
  };
}

String attendanceKindLabel(String kind) {
  for (final (k, label) in kAttendanceKinds) {
    if (k == kind) return label;
  }
  return kind;
}

class _LessonAttendanceDialogState
    extends ConsumerState<LessonAttendanceDialog> {
  bool _loading = true;
  bool _saving = false;
  bool _notifyClient = false;

  /// Статус/посещаемость меняет только администратор и выше — педагог видит урок
  /// в режиме просмотра (правила ролей заказчика; сервер тоже это гейтит). ДЗ и
  /// комментарий педагога педагог оставляет в карточке ученика, не здесь.
  bool get _canEditAttendance {
    final role = ref.read(releaseGateStatusProvider).asData?.value.role;
    return role == 'admin' ||
        role == 'manager' ||
        role == 'director' ||
        role == 'system_admin';
  }
  List<Map<String, dynamic>> _participations = [];
  List<Map<String, dynamic>> _students = [];
  final Map<String, TextEditingController> _reasonControllers = {};

  /// Комментарии админа к ЭТОМУ занятию.
  ///
  /// ✔ Решение заказчика: комментарий к групповому занятию относится к занятию
  /// целиком, а не к каждому ученику, и писать его — отсюда, из диалога
  /// занятия. В карточку клиента он попадёт сам: её лента подмешивает
  /// комментарии к занятиям ученика (includeLessonComments).
  ///
  /// Это не «причина пропуска» (та своя у каждого участника и живёт в
  /// _reasonControllers) — это заметка про сам урок: «миши не будет»,
  /// «захотели убрать это время вообще».
  List<Map<String, dynamic>> _lessonComments = [];
  final TextEditingController _newComment = TextEditingController();
  bool _commentBusy = false;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
    _loadComments();
  }

  @override
  void dispose() {
    for (final c in _reasonControllers.values) {
      c.dispose();
    }
    _newComment.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final rows = await ref
          .read(magicCrmServiceProvider)
          .listComments(
            entityType: 'lesson',
            entityId: (widget.lesson['id'] ?? '').toString(),
            limit: 20,
          );
      if (mounted) setState(() => _lessonComments = rows);
    } catch (_) {
      // Комментарии — не главное в этом диалоге: посещаемость важнее, и ронять
      // её из-за них нельзя. Молчим, список останется пустым.
    }
  }

  Future<void> _addComment() async {
    final body = _newComment.text.trim();
    if (body.isEmpty || _commentBusy) return;
    setState(() => _commentBusy = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createComment(
            entityType: 'lesson',
            entityId: (widget.lesson['id'] ?? '').toString(),
            body: body,
          );
      _newComment.clear();
      await _loadComments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Не удалось добавить: $e')));
      }
    } finally {
      if (mounted) setState(() => _commentBusy = false);
    }
  }

  Future<void> _loadAttendance() async {
    setState(() => _loading = true);
    try {
      final lessonId = widget.lesson['id'];
      final attendance = await ref
          .read(magicCrmServiceProvider)
          .getLessonAttendance(lessonId);
      _students = List<Map<String, dynamic>>.from(attendance['students']);
      _participations = List<Map<String, dynamic>>.from(
        attendance['participations'],
      );
      // One persistent controller per student so the reason field keeps its
      // cursor across rebuilds (the old code recreated it every build).
      for (final p in _participations) {
        final id = (p['student_id'] ?? '').toString();
        _reasonControllers[id] = TextEditingController(
          text: (p['pass_reason'] ?? '').toString(),
        );
      }
      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Error loading attendance: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
        Navigator.pop(context);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final lessonId = widget.lesson['id'];
      await ref
          .read(magicCrmServiceProvider)
          .saveLessonAttendance(
            lessonId,
            _participations,
            notifyClient: _notifyClient,
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Посещаемость сохранена')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Комментарии админа к занятию: что уже написано + поле для нового.
  ///
  /// Здесь, а не в карточке клиента, потому что комментарий относится к
  /// ЗАНЯТИЮ: у групповой пары он один на всех, и писать его из карточки
  /// одного из учеников было бы неверно. В карточку он попадёт сам.
  Widget _commentsSection(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note_rounded, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Комментарии к занятию',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (_lessonComments.isNotEmpty) ...[
            const SizedBox(height: 6),
            // Ограничены по высоте: диалог всё-таки про посещаемость, а у
            // занятия комментариев может быть много.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 108),
              child: ListView(
                shrinkWrap: true,
                children: _lessonComments.map((c) {
                  final dt = DateTime.tryParse(
                    (c['created_at'] ?? '').toString(),
                  )?.toLocal();
                  final author = (c['author_name'] ?? '').toString().trim();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            (c['body'] ?? '').toString(),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          [
                            if (author.isNotEmpty) author,
                            if (dt != null) DateFormat('d MMM', 'ru').format(dt),
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newComment,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Заметка про это занятие…',
                  ),
                  onSubmitted: (_) => _addComment(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Добавить комментарий',
                onPressed: _commentBusy ? null : _addComment,
                icon: _commentBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18, color: AppColor.gold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final present = _participations
        .where(
          (p) => const [
            'attended',
            'free_lesson',
            'partially_paid',
          ].contains(p['kind']),
        )
        .length;
    final absent = _participations.length - present;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: media.size.height * 0.85,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.sheet),
              ),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Grabber.
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 2),
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                // Header.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColor.goldSoft,
                          borderRadius: BorderRadius.circular(AppRadius.icon),
                          border: Border.all(color: AppColor.goldLine),
                        ),
                        child: const Icon(
                          Icons.fact_check_outlined,
                          size: 20,
                          color: AppColor.gold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Посещаемость',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (!_loading)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '$present присутствуют · $absent отсутствуют',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        iconSize: 20,
                        color: cs.onSurfaceVariant,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Body.
                Flexible(
                  child: _loading
                      ? const SizedBox(
                          height: 120,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColor.gold,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: _students.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) => _studentRow(_students[i], cs),
                        ),
                ),
                const Divider(height: 1),
                if (!_loading) _commentsSection(cs),
                const Divider(height: 1),
                // «Уведомить об изменениях» (модалка HolliHop, image5). Only
                // meaningful for the admin+ who edits the attendance.
                if (!_loading && _canEditAttendance)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                    child: CheckboxListTile(
                      value: _notifyClient,
                      onChanged: (v) =>
                          setState(() => _notifyClient = v ?? false),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColor.gold,
                      title: const Text(
                        'Уведомить об изменениях',
                        style: TextStyle(fontSize: 13.5),
                      ),
                    ),
                  ),
                // Footer. Teachers get a read-only sheet — the status/charge is
                // an admin+ action (server also enforces this), so they only see
                // «Закрыть» and a hint.
                if (!_canEditAttendance)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Только просмотр. Статус занятия и посещаемость '
                          'ставит администратор.',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Закрыть'),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: Material(
                            color: AppColor.gold,
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                AppRadius.control,
                              ),
                              onTap: _saving ? null : _save,
                              child: Center(
                                child: _saving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColor.onGold,
                                        ),
                                      )
                                    : const Text(
                                        'Сохранить',
                                        style: TextStyle(
                                          color: AppColor.onGold,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _studentRow(Map<String, dynamic> student, ColorScheme cs) {
    final id = (student['id'] ?? '').toString();
    final participation = _participations.firstWhere(
      (p) => p['student_id'] == student['id'],
    );
    final kind = (participation['kind'] ?? 'attended').toString();
    final shareRaw = participation['charge_share'];
    final share = shareRaw is num
        ? shareRaw.toDouble()
        : double.tryParse(shareRaw?.toString() ?? '') ?? 0.5;
    final kindColor = attendanceKindColor(kind);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(name: (student['name'] ?? '?').toString()),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  (student['name'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: kindColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // KVA-237: статус занятия — 5 типов HolliHop.
          DropdownButtonFormField<String>(
            initialValue: kind,
            isExpanded: true,
            style: TextStyle(fontSize: 13.5, color: cs.onSurface),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: cs.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: const BorderSide(color: AppColor.gold, width: 2),
              ),
            ),
            items: [
              for (final (value, label) in kAttendanceKinds)
                DropdownMenuItem(
                  value: value,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: attendanceKindColor(value),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(label, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: _canEditAttendance
                ? (v) => setState(() {
                    participation['kind'] = v;
                    participation['is_present'] = const [
                      'attended',
                      'free_lesson',
                      'partially_paid',
                    ].contains(v);
                  })
                : null,
          ),
          if (kind == 'partially_paid') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: share.clamp(0.05, 1.0),
                    min: 0.05,
                    max: 1.0,
                    divisions: 19,
                    activeColor: attendanceKindColor(kind),
                    label: '${(share * 100).round()}%',
                    onChanged: _canEditAttendance
                        ? (v) => setState(
                            () => participation['charge_share'] =
                                (v * 100).round() / 100,
                          )
                        : null,
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${(share * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _reasonControllers[id],
            onChanged: (val) => participation['pass_reason'] = val,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Заметки к занятию…',
              isDense: true,
              filled: true,
              fillColor: cs.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: const BorderSide(color: AppColor.gold, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = TelegramColors.initialsFrom(name);
    final colors = TelegramColors.avatarGradientFor(name);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
