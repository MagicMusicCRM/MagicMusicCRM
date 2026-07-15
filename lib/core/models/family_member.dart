/// Typed view over a family member in the legacy map shape produced by
/// `MagicCrmService`'s `_legacyFamilyMember` mapper (snake_case keys). F0 family
/// domain: replaces `member['key']` access with typed getters. All fields are
/// strings / ids / a bool, so there is no numeric-format faithfulness concern.
///
/// Getters mirror the widgets' prior expressions: string getters carry the
/// `?.toString() ?? ''` fallback, [isPrimaryContact] matches the mapper's
/// `== true`, and [raw] is the underlying map for any API still taking one.
class FamilyMember {
  final Map<String, dynamic> _m;

  const FamilyMember(this._m);

  factory FamilyMember.fromMap(Map<String, dynamic> map) => FamilyMember(map);

  /// The underlying legacy map — escape hatch for APIs not yet typed.
  Map<String, dynamic> get raw => _m;

  String get id => _m['id']?.toString() ?? '';
  String? get entityType => _m['entity_type']?.toString();
  String? get entityId => _m['entity_id']?.toString();
  String? get role => _m['role']?.toString();
  bool get isPrimaryContact => _m['is_primary_contact'] == true;
  String get name => _m['name']?.toString() ?? '';
}
