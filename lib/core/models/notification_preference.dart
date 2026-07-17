/// One cell of the notification routing matrix: does [role] receive
/// [eventType], and over which channels.
///
/// Unlike the older models in this folder, this reads the API's camelCase JSON
/// directly — it is a new endpoint with no legacy snake_case mapper behind it.
class NotificationPreference {
  final String role;
  final String eventType;
  final bool enabled;
  final List<String> channels;

  const NotificationPreference({
    required this.role,
    required this.eventType,
    required this.enabled,
    required this.channels,
  });

  factory NotificationPreference.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'];
    return NotificationPreference(
      role: json['role']?.toString() ?? '',
      eventType: json['eventType']?.toString() ?? '',
      enabled: json['enabled'] == true,
      channels: rawChannels is List
          ? rawChannels.map((channel) => channel.toString()).toList()
          : const <String>[],
    );
  }

  NotificationPreference copyWith({bool? enabled, List<String>? channels}) {
    return NotificationPreference(
      role: role,
      eventType: eventType,
      enabled: enabled ?? this.enabled,
      channels: channels ?? this.channels,
    );
  }
}

/// Display order and labels for the matrix. Kept next to the model so the
/// screen never invents its own copy of the server's event vocabulary.
const notificationEventLabels = <String, String>{
  'new_lead': 'Новая заявка',
  'task_reminder_day': 'Задача: за сутки',
  'task_reminder_hour': 'Задача: за час',
  'task_reminder_min10': 'Задача: за 10 минут',
  'task_reminder_overdue': 'Задача просрочена',
};

const notificationRoleLabels = <String, String>{
  'admin': 'Админ',
  'manager': 'Управляющий',
  'director': 'Директор',
  'teacher': 'Педагог',
};

const notificationChannelLabels = <String, String>{
  'in_app': 'В приложении',
  'push': 'Push',
  'email': 'Почта',
};
