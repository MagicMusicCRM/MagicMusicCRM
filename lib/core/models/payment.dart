/// A payment record.
///
/// M2 (Map→DTO) pattern reference: unlike the earlier F0 "typed view over the
/// raw map", this is a real immutable DTO — [Payment.fromMap] parses the legacy
/// snake_case map produced by `MagicCrmService`'s `_legacyPayment` mapper once,
/// into typed `final` fields, and holds no reference to the source map. The
/// public getter surface is byte-for-byte the same as the old wrapper, so every
/// call site is unchanged (behaviour-preserving); the win is that the shape is
/// now a genuine parsed contract instead of live `map['key']` access.
///
/// Migration recipe for the remaining domains (lead, subscription, comment, …):
/// lift each wrapper getter into a `final` field, parse it once in `fromMap`,
/// keep derived getters ([methodLabel], [note], [studentName]) as computed
/// members, and collapse the mapper's duplicate keys into a single field here.
class Payment {
  final String? id;
  final String? studentId;

  /// Untouched amount (num or numeric string) — for faithful raw interpolation.
  final Object? amountRaw;

  /// Amount as a number, tolerating a num or a numeric string; 0 when absent.
  final num amount;

  final String? currency;
  final String? paymentDate;
  final String? createdAt;
  final String? createdBy;
  final String? method;
  final String? type;
  final String? notes;
  final String? description;
  final String? externalId;

  /// True when a linked student is present (the payment row is tappable).
  final bool hasStudent;

  /// Linked student id from the nested `students` map.
  final String? studentEntityId;
  final String? studentFirstName;
  final String? studentLastName;

  const Payment({
    this.id,
    this.studentId,
    this.amountRaw,
    this.amount = 0,
    this.currency,
    this.paymentDate,
    this.createdAt,
    this.createdBy,
    this.method,
    this.type,
    this.notes,
    this.description,
    this.externalId,
    this.hasStudent = false,
    this.studentEntityId,
    this.studentFirstName,
    this.studentLastName,
  });

  factory Payment.fromMap(Map<String, dynamic> map) {
    final amountRaw = map['amount'];
    final students = map['students'] is Map<String, dynamic>
        ? map['students'] as Map<String, dynamic>
        : null;
    return Payment(
      id: map['id']?.toString(),
      studentId: map['student_id']?.toString(),
      amountRaw: amountRaw,
      amount: amountRaw is num
          ? amountRaw
          : num.tryParse(amountRaw?.toString() ?? '') ?? 0,
      currency: map['currency']?.toString(),
      paymentDate: map['payment_date']?.toString(),
      createdAt: map['created_at']?.toString(),
      createdBy: map['created_by']?.toString(),
      method: map['method']?.toString(),
      type: map['type']?.toString(),
      notes: map['notes']?.toString(),
      description: map['description']?.toString(),
      externalId: map['external_id']?.toString(),
      hasStudent: students != null,
      studentEntityId: students?['id']?.toString(),
      studentFirstName: students?['first_name']?.toString(),
      studentLastName: students?['last_name']?.toString(),
    );
  }

  /// Method label, falling back to [type] then '' — matches `method ?? type`.
  String get methodLabel => (method ?? type ?? '').trim();

  /// Note, falling back to [description] then '' — matches `notes ?? description`.
  String get note => (notes ?? description ?? '').trim();

  /// «Имя Фамилия» from the linked student; '' when absent.
  String get studentName => hasStudent
      ? '${studentFirstName ?? ''} ${studentLastName ?? ''}'.trim()
      : '';
}
