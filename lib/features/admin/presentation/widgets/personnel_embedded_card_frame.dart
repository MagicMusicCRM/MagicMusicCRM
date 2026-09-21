import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

class PersonnelCardSection {
  const PersonnelCardSection({
    required this.id,
    required this.label,
    required this.icon,
    required this.child,
    this.lazy = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final Widget child;
  final bool lazy;
}

class PersonnelSectionedCardBody extends StatefulWidget {
  const PersonnelSectionedCardBody({
    super.key,
    required this.keyPrefix,
    required this.sections,
  });

  final String keyPrefix;
  final List<PersonnelCardSection> sections;

  @override
  State<PersonnelSectionedCardBody> createState() =>
      _PersonnelSectionedCardBodyState();
}

class _PersonnelSectionedCardBodyState
    extends State<PersonnelSectionedCardBody> {
  String? _selected;
  final Set<String> _visited = {};

  void _select(String section) {
    setState(() {
      _selected = section;
      _visited.add(section);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sections = widget.sections;
    if (sections.isEmpty) return const SizedBox.shrink();
    final selected = sections.any((section) => section.id == _selected)
        ? _selected!
        : sections.first.id;
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final navigation = constraints.maxWidth >= 720
            ? Container(
                width: 190,
                color: colors.surface,
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: AppColor.surfaceSoft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      child: const Text(
                        'КАРТОЧКА',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final section in sections)
                      InkWell(
                        key: Key(
                          '${widget.keyPrefix}-personnel-section-${section.id}',
                        ),
                        onTap: () => _select(section.id),
                        child: Container(
                          decoration: BoxDecoration(
                            color: section.id == selected
                                ? AppColor.surfaceSoft
                                : null,
                            border: section.id == selected
                                ? const Border(
                                    left: BorderSide(
                                      color: AppColor.actionBlue,
                                      width: 2,
                                    ),
                                  )
                                : null,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                section.icon,
                                size: 14,
                                color: section.id == selected
                                    ? AppColor.actionBlue
                                    : AppColor.text3,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  section.label,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppColor.actionBlue,
                                    fontWeight: section.id == selected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final section in sections)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          key: Key(
                            '${widget.keyPrefix}-personnel-section-${section.id}',
                          ),
                          selected: section.id == selected,
                          avatar: Icon(section.icon, size: 16),
                          label: Text(section.label),
                          onSelected: (_) => _select(section.id),
                        ),
                      ),
                  ],
                ),
              );
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final section in sections)
              if (!section.lazy ||
                  section.id == selected ||
                  _visited.contains(section.id))
                Offstage(
                  offstage: section.id != selected,
                  child: TickerMode(
                    enabled: section.id == selected,
                    child: KeyedSubtree(
                      key: ValueKey(
                        '${widget.keyPrefix}-personnel-content-${section.id}',
                      ),
                      child: section.child,
                    ),
                  ),
                ),
          ],
        );
        if (constraints.maxWidth < 720) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [navigation, const SizedBox(height: 12), content],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            navigation,
            VerticalDivider(width: 1, color: colors.outlineVariant),
            Expanded(
              child: Padding(padding: const EdgeInsets.all(10), child: content),
            ),
          ],
        );
      },
    );
  }
}

class PersonnelHistorySummary extends StatelessWidget {
  const PersonnelHistorySummary({
    super.key,
    required this.createdAt,
    required this.lifecycleState,
    this.offboardedAt,
    this.offboardReason,
  });

  final Object? createdAt;
  final String lifecycleState;
  final Object? offboardedAt;
  final Object? offboardReason;

  @override
  Widget build(BuildContext context) {
    final created = DateTime.tryParse(createdAt?.toString() ?? '')?.toLocal();
    final offboarded = DateTime.tryParse(
      offboardedAt?.toString() ?? '',
    )?.toLocal();
    final reason = offboardReason?.toString().trim() ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'История карточки',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
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
            const Text(
              'Изменения ставок и расчётов сохраняются в финансовой истории и не переписывают прошлые занятия.',
            ),
          ],
        ),
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

class PersonnelEmbeddedCardFrame extends StatelessWidget {
  const PersonnelEmbeddedCardFrame({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
    required this.action,
    required this.saving,
    this.onClose,
  });

  final String title;
  final IconData icon;
  final Widget body;
  final Widget action;
  final bool saving;
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
              child: SingleChildScrollView(child: body),
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
    required this.color,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? 220 : 132,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        border: Border.all(color: color.withAlpha(54)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
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
