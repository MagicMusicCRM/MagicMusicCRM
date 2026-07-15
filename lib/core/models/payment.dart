/// Typed view over a payment record in the legacy map shape produced by
/// `MagicCrmService`'s `_legacyPayment` mapper (snake_case keys). F0 first
/// domain: replaces `payment['key']` string access with typed getters so the
/// analyzer catches key typos and the shape lives in one place.
///
/// Getters mirror the exact expressions the widgets previously used against the
/// raw map, so migrating call sites is behaviour-preserving (verified per site):
///  - [amount] parses leniently (num or numeric string) — matches finance's
///    `double.tryParse(...)` and the dashboard's `is num ? ... : num.tryParse`;
///  - [amountRaw] is the untouched value, for the student tab's raw
///    `'${payment['amount']} ₽'` interpolation (avoids any format drift);
///  - the `??` fallbacks ([methodLabel], [note]) match the widgets' chains.
class Payment {
  final Map<String, dynamic> _m;

  const Payment(this._m);

  factory Payment.fromMap(Map<String, dynamic> map) => Payment(map);

  String? get id => _m['id']?.toString();
  String? get studentId => _m['student_id']?.toString();

  /// Untouched amount (num or numeric string) — for faithful raw interpolation.
  Object? get amountRaw => _m['amount'];

  /// Amount as a number, tolerating a num or a numeric string; 0 when absent.
  num get amount {
    final a = _m['amount'];
    return a is num ? a : num.tryParse(a?.toString() ?? '') ?? 0;
  }

  String? get currency => _m['currency']?.toString();
  String? get paymentDate => _m['payment_date']?.toString();
  String? get createdAt => _m['created_at']?.toString();
  String? get createdBy => _m['created_by']?.toString();
  String? get method => _m['method']?.toString();
  String? get type => _m['type']?.toString();
  String? get notes => _m['notes']?.toString();
  String? get description => _m['description']?.toString();
  String? get externalId => _m['external_id']?.toString();

  /// Method label, falling back to [type] then '' — matches `method ?? type`.
  String get methodLabel => (method ?? type ?? '').trim();

  /// Note, falling back to [description] then '' — matches `notes ?? description`.
  String get note => (notes ?? description ?? '').trim();

  Map<String, dynamic>? get _students =>
      _m['students'] as Map<String, dynamic>?;

  /// True when a linked student is present (the payment row is tappable).
  bool get hasStudent => _students != null;

  /// Linked student id from the nested `students` map (may differ from a raw
  /// top-level `student_id` only in absence; the mapper sets both alike).
  String? get studentEntityId => _students?['id']?.toString();

  String? get studentFirstName => _students?['first_name']?.toString();
  String? get studentLastName => _students?['last_name']?.toString();

  /// «Имя Фамилия» from the nested `students` map; '' when absent.
  String get studentName {
    final s = _students;
    if (s == null) return '';
    return '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'.trim();
  }
}
