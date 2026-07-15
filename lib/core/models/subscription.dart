/// Typed view over a subscription in the legacy map shape produced by
/// `MagicCrmService`'s `_legacySubscription` mapper (snake_case keys). F0 domain.
/// [packagePriceRaw] stays `Object?` so the remainder card's `price is num` guard
/// behaves exactly as before; [lessonsTotal]/[lessonsUsed] mirror the widget's
/// lenient num parse. String getters mirror the card's prior expressions.
class Subscription {
  final Map<String, dynamic> _m;

  const Subscription(this._m);

  factory Subscription.fromMap(Map<String, dynamic> map) => Subscription(map);

  Map<String, dynamic> get raw => _m;

  static num _num(Object? v) =>
      v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

  String? get id => _m['id']?.toString();
  String? get studentId => _m['student_id']?.toString();

  /// Lenient parse matching `_subscriptionRemainder`'s `toNum`.
  num get lessonsTotal => _num(_m['lessons_total']);
  num get lessonsUsed => _num(_m['lessons_used']);

  String? get startsAt => _m['starts_at']?.toString();
  String? get expiresAt => _m['expires_at']?.toString();
  String? get validUntil => _m['valid_until']?.toString();
  String? get status => _m['status']?.toString();

  /// Exact-equality convenience for the card's `s['status'] == 'active'` checks.
  bool get isActive => _m['status'] == 'active';

  String? get type => _m['type']?.toString();
  String? get packageName => _m['package_name']?.toString();

  /// Raw so the remainder card's `price is num` guard is preserved.
  Object? get packagePriceRaw => _m['package_price'];

  String? get createdAt => _m['created_at']?.toString();
  String? get updatedAt => _m['updated_at']?.toString();
}
