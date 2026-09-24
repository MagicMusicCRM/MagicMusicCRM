import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_desktop_scrollbar.dart';

class PersonnelCardCanvas extends StatelessWidget {
  const PersonnelCardCanvas({
    super.key,
    required this.summary,
    required this.desktopLeft,
    required this.desktopRight,
    required this.mobileSections,
  });

  final Widget summary;
  final List<Widget> desktopLeft;
  final List<Widget> desktopRight;
  final List<Widget> mobileSections;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summary,
          const SizedBox(height: AppSpace.md),
          if (constraints.maxWidth >= 960)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _column(desktopLeft)),
                const SizedBox(width: AppSpace.md),
                Expanded(child: _column(desktopRight)),
              ],
            )
          else
            _column(mobileSections),
        ],
      ),
    ),
  );

  Widget _column(List<Widget> sections) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < sections.length; index++) ...[
        if (index > 0) const SizedBox(height: AppSpace.md),
        sections[index],
      ],
    ],
  );
}

class PersonnelHistorySummary extends StatelessWidget {
  const PersonnelHistorySummary({
    super.key,
    required this.createdAt,
    required this.lifecycleState,
    this.offboardedAt,
    this.offboardReason,
    this.personId,
    this.personType,
    this.canViewActivity = false,
  });

  final Object? createdAt;
  final String lifecycleState;
  final Object? offboardedAt;
  final Object? offboardReason;
  final String? personId;
  final String? personType;
  final bool canViewActivity;

  @override
  Widget build(BuildContext context) {
    final created = DateTime.tryParse(createdAt?.toString() ?? '')?.toLocal();
    final offboarded = DateTime.tryParse(
      offboardedAt?.toString() ?? '',
    )?.toLocal();
    final reason = offboardReason?.toString().trim() ?? '';
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpace.xl,
              vertical: AppSpace.sm,
            ),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 19, color: AppColor.gold),
                SizedBox(width: AppSpace.sm),
                Text(
                  'История карточки',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.6),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_add_alt_1_outlined),
                  title: const Text('Карточка создана'),
                  subtitle: Text(_date(created)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    lifecycleState == 'archived'
                        ? Icons.archive_outlined
                        : Icons.verified_user_outlined,
                  ),
                  title: Text(
                    lifecycleState == 'archived' ? 'В архиве' : 'Активна',
                  ),
                  subtitle: offboarded == null
                      ? const Text('Текущий статус записи')
                      : Text(
                          '${_date(offboarded)}${reason.isEmpty ? '' : ' · $reason'}',
                        ),
                ),
                if (canViewActivity && personId != null && personType != null)
                  PersonnelActivityHistory(
                    personId: personId!,
                    personType: personType!,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _date(DateTime? value) {
    if (value == null) return 'Дата не указана';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}.${two(value.month)}.${value.year} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

class PersonnelActivityHistory extends ConsumerStatefulWidget {
  const PersonnelActivityHistory({
    super.key,
    required this.personId,
    required this.personType,
  });

  final String personId;
  final String personType;

  @override
  ConsumerState<PersonnelActivityHistory> createState() =>
      _PersonnelActivityHistoryState();
}

class _PersonnelActivityHistoryState
    extends ConsumerState<PersonnelActivityHistory> {
  late Future<Map<String, dynamic>> _history;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _history = ref
        .read(magicCrmServiceProvider)
        .getPersonHistory(
          personType: widget.personType,
          personId: widget.personId,
        );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _history,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return ListTile(
          title: const Text('Не удалось загрузить историю действий'),
          trailing: TextButton(
            onPressed: () => setState(_load),
            child: const Text('Повторить'),
          ),
        );
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final activity =
          (snapshot.data!['activity'] as List?)?.whereType<Map>().toList() ??
          const <Map>[];
      final lifecycle =
          (snapshot.data!['items'] as List?)?.whereType<Map>().toList() ??
          const <Map>[];
      if (activity.isEmpty && lifecycle.isEmpty) {
        return const ListTile(title: Text('Записанных действий пока нет'));
      }
      final events = <({String title, String date, String reason})>[
        for (final row in activity)
          (
            title: _activityLabel(row['action']?.toString() ?? ''),
            date: row['createdAt']?.toString() ?? '',
            reason: row['reasonText']?.toString() ?? '',
          ),
        for (final row in lifecycle)
          (
            title: row['operation'] == 'restore'
                ? 'Карточка восстановлена'
                : 'Карточка архивирована',
            date: row['createdAt']?.toString() ?? '',
            reason: row['reasonText']?.toString() ?? '',
          ),
      ]..sort((a, b) => b.date.compareTo(a.date));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Действия',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                key: const Key('personnel-history-refresh'),
                tooltip: 'Обновить историю',
                onPressed: () => setState(_load),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          for (final event in events.take(100))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.history_rounded, size: 20),
              title: Text(event.title),
              subtitle: Text(_eventDescription(event.date, event.reason)),
            ),
        ],
      );
    },
  );

  String _eventDescription(String rawDate, String reason) {
    final date = DateTime.tryParse(rawDate)?.toLocal();
    final formatted = date == null
        ? 'Дата не указана'
        : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return reason.isEmpty ? formatted : '$formatted · $reason';
  }

  String _activityLabel(String action) => switch (action) {
    'crm.teacher_created' => 'Преподаватель добавлен',
    'crm.staff_created' => 'Сотрудник добавлен',
    'crm.teacher_updated' => 'Данные преподавателя изменены',
    'crm.staff_updated' => 'Данные сотрудника изменены',
    'crm.teacher_branches_replaced' => 'Назначения по филиалам изменены',
    'crm.teacher_availability_replaced' => 'График и занятые периоды изменены',
    'crm.teacher_rate_set' ||
    'crm.teacher_rate_updated' => 'Ставка преподавателя изменена',
    'access.user.role_assigned' => 'Роль доступа изменена',
    'access.user.override_set' => 'Персональные права изменены',
    _ => 'Действие в карточке',
  };
}

class PersonnelEmbeddedCardFrame extends StatelessWidget {
  const PersonnelEmbeddedCardFrame({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
    required this.action,
    required this.saving,
    this.personName,
    this.statusLabel,
    this.onClose,
  });

  final String title;
  final IconData icon;
  final Widget body;
  final Widget action;
  final bool saving;
  final String? personName;
  final String? statusLabel;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.xl,
              AppSpace.lg,
              AppSpace.md,
              AppSpace.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColor.goldSoft,
                    borderRadius: BorderRadius.circular(AppRadius.icon),
                    border: Border.all(color: AppColor.goldLine),
                  ),
                  child: Icon(icon, size: 22, color: AppColor.gold),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        personName?.trim().isNotEmpty == true
                            ? personName!
                            : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: statusLabel == 'В архиве'
                                  ? AppColor.text3
                                  : AppColor.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '$title · ${statusLabel ?? 'Активен'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Закрыть карточку',
                    onPressed: saving ? null : onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.6),
          ),
          Expanded(
            child: ColoredBox(
              color: colors.surface,
              child: MagicDesktopScrollbar(
                axis: Axis.vertical,
                builder: (context, controller) =>
                    SingleChildScrollView(controller: controller, child: body),
              ),
            ),
          ),
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.6),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.xl,
              AppSpace.md,
              AppSpace.xl,
              AppSpace.lg,
            ),
            child: Align(alignment: Alignment.centerRight, child: action),
          ),
        ],
      ),
    );
  }
}

class PersonnelMetricChip extends StatelessWidget {
  const PersonnelMetricChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? 220 : 164,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColor.gold),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
