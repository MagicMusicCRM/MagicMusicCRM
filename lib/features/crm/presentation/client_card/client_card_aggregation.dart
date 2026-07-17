import 'package:flutter/material.dart';

import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// Resolution mode for the unified «Карточка клиента».
///
/// - [leadOnly]    — opened as a lead with no linked student (Phase 1).
/// - [studentOnly] — opened as a student with no originating lead (Phase 2).
/// - [converted]   — a lead that became a student (linked via
///   `students.lead_id`); both halves are aggregated in one card (Phase 4).
enum ClientMode { leadOnly, studentOnly, converted }

extension ClientModeX on ClientMode {
  bool get isConverted => this == ClientMode.converted;

  /// Whether the card should surface the full student tab set / actions. True
  /// for a plain student and for a converted client (a converted client always
  /// has a student half).
  bool get hasStudentHalf =>
      this == ClientMode.studentOnly || this == ClientMode.converted;

  /// Whether the card has a lead half (lead card, status history, source info).
  bool get hasLeadHalf =>
      this == ClientMode.leadOnly || this == ClientMode.converted;
}

/// An (entityType, entityId) address used to fetch a comment / task / history
/// stream and to badge each merged item with its origin half.
typedef ClientHalfRef = ({String entityType, String entityId});

/// Merges several already-loaded lists of map rows into one list, de-duped by
/// each row's `id` (first occurrence wins) and sorted by [dateKey] descending.
///
/// Rows missing an `id` are kept (they can't collide) but contribute a synthetic
/// key so two id-less rows never silently collapse into one.
List<Map<String, dynamic>> mergeByIdSorted(
  List<List<Map<String, dynamic>>> sources, {
  required String dateKey,
}) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  var synthetic = 0;
  for (final source in sources) {
    for (final row in source) {
      final rawId = row['id']?.toString();
      final key = (rawId != null && rawId.isNotEmpty)
          ? 'id:$rawId'
          : 'syn:${synthetic++}';
      if (!seen.add(key)) continue;
      out.add(row);
    }
  }
  out.sort((a, b) {
    final da = (a[dateKey] as String?) ?? '';
    final db = (b[dateKey] as String?) ?? '';
    return db.compareTo(da);
  });
  return out;
}

/// Collapses comment rows identical in visible text + `created_at` + lesson
/// linkage, keeping the first occurrence and preserving order.
///
/// WHY: a converted client aggregates both its lead and student halves, and the
/// importer copied some notes onto BOTH (different ids, identical text). Id-based
/// [mergeByIdSorted] therefore keeps both, so the same note showed twice in the
/// «Комментарии» ленте while single-half notes showed once — exactly the
/// duplication staff reported. Keyed on `lesson_at` too, so two *distinct*
/// per-lesson notes that happen to share text and date are NOT merged. Rows with
/// empty text are always kept (they can't be confidently matched).
List<Map<String, dynamic>> dedupeCommentsByContent(
  List<Map<String, dynamic>> rows,
) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final row in rows) {
    final text = (row['content'] ?? row['body'] ?? '').toString().trim();
    if (text.isEmpty) {
      out.add(row);
      continue;
    }
    final key = '$text|${row['created_at'] ?? ''}|${row['lesson_at'] ?? ''}';
    if (seen.add(key)) out.add(row);
  }
  return out;
}

/// Small «Лид» / «Ученик» origin chip shown on merged comment / task / history
/// items so staff can tell which half each row came from.
class ClientOriginChip extends StatelessWidget {
  final String entityType;
  const ClientOriginChip({super.key, required this.entityType});

  @override
  Widget build(BuildContext context) {
    final isLead = entityType == 'lead';
    final label = isLead ? 'Лид' : 'Ученик';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColor.goldSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColor.goldLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLead ? Icons.person_outline_rounded : Icons.school_outlined,
            size: 10,
            color: AppColor.gold,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: AppColor.gold,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
