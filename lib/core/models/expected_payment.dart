/// Typed view over an expected/planned payment (invoice) in the legacy map shape
/// produced by `MagicCrmService`'s `_legacyExpectedPayment` mapper (snake_case).
/// F0 domain. [amountRaw] preserves the invoice tab's raw `'${amount} ₽'`
/// interpolation; string getters mirror the widget's prior expressions.
class ExpectedPayment {
  final Map<String, dynamic> _m;

  const ExpectedPayment(this._m);

  factory ExpectedPayment.fromMap(Map<String, dynamic> map) =>
      ExpectedPayment(map);

  Map<String, dynamic> get raw => _m;

  String? get id => _m['id']?.toString();
  String? get studentId => _m['student_id']?.toString();
  Object? get amountRaw => _m['amount'];
  String? get dueDate => _m['due_date']?.toString();
  String? get status => _m['status']?.toString();
  String? get description => _m['description']?.toString();
  String? get createdAt => _m['created_at']?.toString();
  String? get updatedAt => _m['updated_at']?.toString();
}
