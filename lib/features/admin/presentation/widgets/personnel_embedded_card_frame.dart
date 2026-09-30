import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

class PersonnelCardSection {
  const PersonnelCardSection({
    required this.id,
    required this.label,
    required this.icon,
    required this.child,
  });

  final String id;
  final String label;
  final IconData icon;
  final Widget child;
}

class PersonnelSectionedCardBody extends StatelessWidget {
  const PersonnelSectionedCardBody({
    super.key,
    required this.keyPrefix,
    required this.sections,
  });

  final String keyPrefix;
  final List<PersonnelCardSection> sections;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections) ...[
          if (section.id == 'overview' || section.id == 'employment')
            KeyedSubtree(
              key: ValueKey('$keyPrefix-personnel-content-${section.id}'),
              child: section.child,
            )
          else
            ExpansionTile(
              key: PageStorageKey(
                '$keyPrefix-personnel-section-${section.id}',
              ),
              leading: Icon(section.icon, size: 20),
              title: Text(section.label),
              maintainState: true,
              children: [
                KeyedSubtree(
                  key: PageStorageKey(
                    '$keyPrefix-personnel-storage-${section.id}',
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(
                      '$keyPrefix-personnel-content-${section.id}',
                    ),
                    child: section.child,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
        ],
      ],
    ),
  );
}

/// Equal columns for short fields; long labels and validation may grow vertically.
class PersonnelFieldGrid extends StatelessWidget {
  const PersonnelFieldGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns =
          constraints.maxWidth >=
          620 * MediaQuery.textScalerOf(context).scale(1);
      final width = twoColumns
          ? (constraints.maxWidth - 16) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
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
    this.dirty = false,
    this.recordId,
    this.onDiscard,
    this.onClose,
  });

  final String title;
  final IconData icon;
  final Widget body;
  final Widget action;
  final bool saving;
  final bool dirty;
  final String? recordId;
  final VoidCallback? onDiscard;
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
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
            child: Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
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
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: ColoredBox(
              color: AppColor.bg,
              child: SingleChildScrollView(
                key: PageStorageKey('personnel-scroll-$recordId'),
                child: body,
              ),
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (dirty)
                  const Text(
                    'Есть изменения',
                    style: TextStyle(color: AppColor.text2),
                  ),
                if (dirty && onDiscard != null)
                  TextButton(
                    onPressed: saving ? null : onDiscard,
                    child: const Text('Отменить изменения'),
                  ),
                if (onClose != null)
                  OutlinedButton(
                    onPressed: saving ? null : onClose,
                    child: const Text('Закрыть'),
                  ),
                action,
              ],
            ),
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
