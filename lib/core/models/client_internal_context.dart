class ClientInternalNote {
  const ClientInternalNote({
    required this.body,
    required this.version,
    this.id,
    this.updatedBy,
    this.updatedByName,
    this.updatedAt,
  });

  final String? id;
  final String body;
  final int version;
  final String? updatedBy;
  final String? updatedByName;
  final DateTime? updatedAt;

  factory ClientInternalNote.fromJson(Map<String, dynamic> json) =>
      ClientInternalNote(
        id: json['id']?.toString(),
        body: json['body']?.toString() ?? '',
        version: int.tryParse(json['version']?.toString() ?? '') ?? 0,
        updatedBy: json['updatedBy']?.toString(),
        updatedByName: json['updatedByName']?.toString(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      );
}

class ClientOperationalHistoryItem {
  const ClientOperationalHistoryItem({
    required this.id,
    required this.actionKey,
    required this.action,
    required this.reason,
    required this.actorName,
    required this.occurredAt,
    this.summary,
  });

  final String id;
  final String actionKey;
  final String action;
  final String reason;
  final String? summary;
  final String actorName;
  final DateTime occurredAt;

  factory ClientOperationalHistoryItem.fromJson(Map<String, dynamic> json) =>
      ClientOperationalHistoryItem(
        id: json['id'].toString(),
        actionKey: json['actionKey'].toString(),
        action: json['action'].toString(),
        reason: json['reason'].toString(),
        summary: json['summary']?.toString(),
        actorName: json['actorName'].toString(),
        occurredAt: DateTime.parse(json['occurredAt'].toString()),
      );
}

class ClientOperationalHistoryPage {
  const ClientOperationalHistoryPage({required this.items, this.nextCursor});

  final List<ClientOperationalHistoryItem> items;
  final String? nextCursor;

  factory ClientOperationalHistoryPage.fromJson(Map<String, dynamic> json) =>
      ClientOperationalHistoryPage(
        items: [
          for (final item in json['items'] as List? ?? const [])
            if (item is Map<String, dynamic>)
              ClientOperationalHistoryItem.fromJson(item),
        ],
        nextCursor: json['nextCursor']?.toString(),
      );
}
