import 'package:magic_music_crm/core/models/audit_presentation_event.dart';

export 'package:magic_music_crm/core/models/audit_presentation_event.dart';

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

class ClientOperationalHistoryPage {
  const ClientOperationalHistoryPage({required this.items, this.nextCursor});

  final List<AuditPresentationEvent> items;
  final String? nextCursor;

  factory ClientOperationalHistoryPage.fromJson(Map<String, dynamic> json) =>
      ClientOperationalHistoryPage(
        items: [
          for (final item in json['items'] as List? ?? const [])
            if (item is Map)
              AuditPresentationEvent.fromJson(Map<String, dynamic>.from(item)),
        ],
        nextCursor: json['nextCursor']?.toString(),
      );
}
