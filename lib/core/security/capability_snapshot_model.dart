class CapabilitySnapshot {
  const CapabilitySnapshot({
    required this.accountId,
    required this.role,
    required this.accessVersion,
    required this.capabilities,
    required this.scopes,
  });

  factory CapabilitySnapshot.fromJson(Map<String, dynamic> json) {
    final rawCapabilities = json['capabilities'];
    final rawScopes = json['scopes'];
    return CapabilitySnapshot(
      accountId: json['accountId']?.toString() ?? '',
      role: json['role']?.toString() ?? 'client',
      accessVersion: (json['accessVersion'] as num?)?.toInt() ?? 0,
      capabilities: rawCapabilities is List
          ? rawCapabilities.map((value) => value.toString()).toSet()
          : const <String>{},
      scopes: rawScopes is Map
          ? rawScopes.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
    );
  }

  final String accountId;
  final String role;
  final int accessVersion;
  final Set<String> capabilities;
  final Map<String, String> scopes;

  String get cacheKey => '$accountId:$accessVersion';

  bool allows(String capability) => capabilities.contains(capability);
}
