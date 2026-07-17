/// Typed view over a comment/note in the legacy map shape produced by
/// `MagicCrmService`'s `_legacyComment` mapper (snake_case keys). F0 domain —
/// all fields are strings. [origin] reads the synthetic `_origin` key the client
/// card adds when merging lead + student comments; [raw] is the underlying map
/// for APIs still taking one (e.g. the visibility toggle).
class Comment {
  final Map<String, dynamic> _m;

  const Comment(this._m);

  factory Comment.fromMap(Map<String, dynamic> map) => Comment(map);

  Map<String, dynamic> get raw => _m;

  String? get id => _m['id']?.toString();
  String? get entityType => _m['entity_type']?.toString();
  String? get entityId => _m['entity_id']?.toString();
  String? get authorId => _m['author_id']?.toString();
  String get authorName => _m['author_name']?.toString() ?? '';
  String? get body => _m['body']?.toString();
  String? get content => _m['content']?.toString();
  String? get kind => _m['kind']?.toString();
  Object? get progress => _m['progress'];
  String? get createdAt => _m['created_at']?.toString();

  /// Когда шло занятие, к которому оставлен комментарий; null у обычных.
  ///
  /// По нему лента и отличает «комментарий к клиенту» от «комментария к
  /// занятию 11.07»: комментарий живёт на занятии (у группового он один на
  /// всех), но человеку нужен в ленте клиента — вперемешку с остальными.
  String? get lessonAt => _m['lesson_at']?.toString();

  /// Комментарий оставлен к конкретному занятию.
  bool get isAboutLesson => (_m['lesson_at'] ?? '').toString().isNotEmpty;

  /// Synthetic origin tag ('lead' | 'student') added by the client card when it
  /// merges both halves; null for a single-side list.
  String? get origin => _m['_origin']?.toString();

  Map<String, dynamic>? get profiles => _m['profiles'] as Map<String, dynamic>?;

  /// «Имя Фамилия» from the nested author `profiles`; '' when absent.
  String get authorProfileName {
    final p = profiles;
    if (p == null) return '';
    return '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
  }
}
