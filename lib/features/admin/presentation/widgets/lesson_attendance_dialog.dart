import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';

/// v7 attendance sheet (P2-5 / v7p2-3). Theme-aware (in-app screen): surfaces
/// follow the app theme, accents use the v7 gold/success/danger tokens.
///
/// Contract is LOCKED — `show()` API, `getLessonAttendance`/`saveLessonAttendance`
/// and the participation shape (`is_present`/`pass_reason`) are unchanged; the
/// backend only accepts present/absent, so the chips are binary.
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

class _LessonAttendanceDialogState
    extends ConsumerState<LessonAttendanceDialog> {
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _participations = [];
  List<Map<String, dynamic>> _students = [];
  final Map<String, TextEditingController> _reasonControllers = {};

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  @override
  void dispose() {
    for (final c in _reasonControllers.values) {
      c.dispose();
    }
    super.dispose();
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
          .saveLessonAttendance(lessonId, _participations);

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final present = _participations
        .where((p) => p['is_present'] == true)
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
                // Footer.
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
    final present = participation['is_present'] == true;

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
              _attChip(
                label: 'Был',
                color: AppColor.success,
                selected: present,
                onTap: () => setState(() => participation['is_present'] = true),
              ),
              const SizedBox(width: 6),
              _attChip(
                label: 'Н/Б',
                color: AppColor.danger,
                selected: !present,
                onTap: () => setState(() => participation['is_present'] = false),
              ),
            ],
          ),
          if (!present) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _reasonControllers[id],
              onChanged: (val) => participation['pass_reason'] = val,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Причина отсутствия…',
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
        ],
      ),
    );
  }

  Widget _attChip({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: selected ? color : Theme.of(context).dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
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
