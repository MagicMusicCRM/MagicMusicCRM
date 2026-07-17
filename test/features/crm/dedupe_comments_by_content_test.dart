import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/client_card_aggregation.dart';

/// The client card aggregates a converted client's lead + student halves; the
/// importer copied some notes onto BOTH (different ids, identical text), so
/// id-based dedup kept two copies. [dedupeCommentsByContent] collapses those.
void main() {
  Map<String, dynamic> c({
    required String id,
    required String origin,
    required String content,
    String createdAt = '2026-05-01T10:00:00Z',
    String? lessonAt,
  }) =>
      {
        'id': id,
        '_origin': origin,
        'content': content,
        'created_at': createdAt,
        if (lessonAt != null) 'lesson_at': lessonAt,
      };

  test('collapses the same note copied onto lead and student', () {
    final rows = [
      c(id: '1', origin: 'lead', content: 'Перезвонить в среду'),
      c(id: '2', origin: 'student', content: 'Перезвонить в среду'),
      c(id: '3', origin: 'student', content: 'Оплатил абонемент'),
    ];
    final out = dedupeCommentsByContent(rows);
    expect(out.length, 2);
    expect(out.map((r) => r['content']),
        ['Перезвонить в среду', 'Оплатил абонемент']);
    // First occurrence (the lead copy) is the one kept.
    expect(out.first['_origin'], 'lead');
  });

  test('keeps two distinct per-lesson notes sharing text and date', () {
    final rows = [
      c(
        id: '1',
        origin: 'student',
        content: 'Молодец',
        lessonAt: '2026-05-01T12:00:00Z',
      ),
      c(
        id: '2',
        origin: 'student',
        content: 'Молодец',
        lessonAt: '2026-05-01T15:00:00Z',
      ),
    ];
    expect(dedupeCommentsByContent(rows).length, 2);
  });

  test('different text is never collapsed', () {
    final rows = [
      c(id: '1', origin: 'lead', content: 'A'),
      c(id: '2', origin: 'student', content: 'B'),
    ];
    expect(dedupeCommentsByContent(rows).length, 2);
  });

  test('empty-text rows are always kept', () {
    final rows = [
      c(id: '1', origin: 'lead', content: ''),
      c(id: '2', origin: 'student', content: ''),
    ];
    expect(dedupeCommentsByContent(rows).length, 2);
  });

  test('same text but different created_at is kept (re-comment later)', () {
    final rows = [
      c(id: '1', origin: 'student', content: 'Ок', createdAt: '2026-05-01T10:00:00Z'),
      c(id: '2', origin: 'student', content: 'Ок', createdAt: '2026-06-01T10:00:00Z'),
    ];
    expect(dedupeCommentsByContent(rows).length, 2);
  });
}
