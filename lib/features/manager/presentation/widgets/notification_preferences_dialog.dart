import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/notification_preference.dart';
import 'package:magic_music_crm/core/services/magic_notifications_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/magic_page_state.dart';

/// Who gets which notification, per role (spec §4).
///
/// Recipients used to be a literal in two SQL queries, so "перестаньте будить
/// педагогов" was a deploy. This edits app.notification_preferences instead.
///
/// Note it does NOT cover two rules that stay in code: the task assignee always
/// hears about their own task, and lesson reminders follow the lesson's
/// students. Neither is a role broadcast.
class NotificationPreferencesDialog extends ConsumerStatefulWidget {
  const NotificationPreferencesDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const NotificationPreferencesDialog(),
    );
  }

  @override
  ConsumerState<NotificationPreferencesDialog> createState() =>
      _NotificationPreferencesDialogState();
}

class _NotificationPreferencesDialogState
    extends ConsumerState<NotificationPreferencesDialog> {
  late Future<List<NotificationPreference>> _future = _fetch();
  List<NotificationPreference> _items = const [];
  final Set<String> _saving = {};

  Future<List<NotificationPreference>> _fetch() async {
    final items = await ref
        .read(magicNotificationsServiceProvider)
        .listPreferences();
    _items = items;
    return items;
  }

  String _key(NotificationPreference pref) => '${pref.role}:${pref.eventType}';

  Future<void> _save(
    NotificationPreference pref, {
    bool? enabled,
    List<String>? channels,
  }) async {
    final key = _key(pref);
    if (_saving.contains(key)) return;
    final updated = pref.copyWith(enabled: enabled, channels: channels);
    // Optimistic: the switch has to move under the finger, not after a
    // round-trip. Rolled back below if the server refuses.
    setState(() {
      _saving.add(key);
      _items = [for (final item in _items) _key(item) == key ? updated : item];
    });
    try {
      await ref
          .read(magicNotificationsServiceProvider)
          .updatePreference(
            role: updated.role,
            eventType: updated.eventType,
            enabled: updated.enabled,
            channels: updated.channels,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = [for (final item in _items) _key(item) == key ? pref : item];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(e, fallback: 'Не удалось сохранить настройки.'),
          ),
          backgroundColor: AppColor.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Настройки уведомлений',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                'Кому уходят рассылки. Исполнитель всегда получает уведомления '
                'по своей задаче. Это правило не настраивается.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<NotificationPreference>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const MagicPageState.loading();
                    }
                    if (snapshot.hasError) {
                      return MagicPageState(
                        kind: MagicPageStateKind.error,
                        title: 'Не удалось загрузить настройки',
                        message: userErrorMessage(
                          snapshot.error,
                          fallback: 'Не удалось загрузить настройки.',
                        ),
                        actionLabel: 'Повторить',
                        onAction: () => setState(() => _future = _fetch()),
                      );
                    }
                    if (_items.isEmpty) {
                      return const MagicPageState(
                        kind: MagicPageStateKind.empty,
                        title: 'Настройки не заведены',
                      );
                    }
                    final events = notificationEventLabels.keys
                        .where(
                          (event) =>
                              _items.any((item) => item.eventType == event),
                        )
                        .toList();
                    return ListView.separated(
                      itemCount: events.length,
                      separatorBuilder: (_, _) => const Divider(height: 24),
                      itemBuilder: (context, index) {
                        final event = events[index];
                        return _EventSection(
                          label: notificationEventLabels[event] ?? event,
                          prefs: _items
                              .where((item) => item.eventType == event)
                              .toList(),
                          isSaving: (pref) => _saving.contains(_key(pref)),
                          onToggle: (pref, value) =>
                              _save(pref, enabled: value),
                          onChannels: (pref, channels) =>
                              _save(pref, channels: channels),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventSection extends StatelessWidget {
  final String label;
  final List<NotificationPreference> prefs;
  final bool Function(NotificationPreference) isSaving;
  final void Function(NotificationPreference, bool) onToggle;
  final void Function(NotificationPreference, List<String>) onChannels;

  const _EventSection({
    required this.label,
    required this.prefs,
    required this.isSaving,
    required this.onToggle,
    required this.onChannels,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        for (final pref in prefs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    notificationRoleLabels[pref.role] ?? pref.role,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Switch(
                  value: pref.enabled,
                  onChanged: isSaving(pref)
                      ? null
                      : (value) => onToggle(pref, value),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final entry in notificationChannelLabels.entries)
                        FilterChip(
                          label: Text(entry.value),
                          selected: pref.channels.contains(entry.key),
                          // Channels are meaningless while the row is off —
                          // showing them live would imply the role still gets
                          // something.
                          onSelected: (!pref.enabled || isSaving(pref))
                              ? null
                              : (selected) {
                                  final next = [...pref.channels];
                                  if (selected) {
                                    next.add(entry.key);
                                  } else {
                                    next.remove(entry.key);
                                  }
                                  onChannels(pref, next);
                                },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
