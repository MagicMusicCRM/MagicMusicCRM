/// Typed view over a student balance in the legacy map shape produced by
/// `MagicCrmService`'s `_legacyStudentBalance` mapper (snake_case keys). F0
/// domain. Money fields expose both a `*Raw` value (for faithful `'${x} ₽'`
/// interpolation, avoiding format drift) and [balance] as a lenient number.
class StudentBalance {
  final Map<String, dynamic> _m;

  const StudentBalance(this._m);

  factory StudentBalance.fromMap(Map<String, dynamic> map) =>
      StudentBalance(map);

  String? get studentId => _m['student_id']?.toString();

  Object? get balanceRaw => _m['balance'];
  Object? get totalPaidRaw => _m['total_paid'];
  Object? get totalCostRaw => _m['total_cost'];

  /// Balance as a number, or null when absent/unparseable — matches the card's
  /// defensive `raw is num ? raw : num.tryParse(...)`.
  num? get balance {
    final raw = _m['balance'];
    return raw is num ? raw : num.tryParse(raw?.toString() ?? '');
  }

  String? get updatedAt => _m['updated_at']?.toString();
}
