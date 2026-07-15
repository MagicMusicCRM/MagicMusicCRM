part of 'manage_entities_widget.dart';

// ─────────────────────────────────────────────────
class _BranchesList extends ConsumerWidget {
  final String searchQuery;
  const _BranchesList({required this.searchQuery});

  String _offsetLabel(int minutes) {
    final sign = minutes >= 0 ? '+' : '-';
    final abs = minutes.abs();
    final h = abs ~/ 60;
    final m = abs % 60;
    final timeStr = m == 0
        ? 'UTC$sign$h'
        : 'UTC$sign$h:${m.toString().padLeft(2, '0')}';
    return switch (minutes) {
      180 => 'МСК ($timeStr)',
      120 => 'EET ($timeStr)',
      60 => 'CET ($timeStr)',
      0 => 'UTC',
      _ => timeStr,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('branches'));
    return async.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (e, _) => Center(
        child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger)),
      ),
      data: (items) {
        var filtered = items;
        if (searchQuery.isNotEmpty) {
          filtered = items.where((item) {
            final name = (item['name'] as String? ?? '').toLowerCase();
            final address = (item['address'] as String? ?? '').toLowerCase();
            final q = searchQuery.toLowerCase();
            return name.contains(q) || address.contains(q);
          }).toList();
        }

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty ? 'Нет филиалов' : 'Ничего не найдено',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: AppTheme.primaryGold,
          onRefresh: () async => ref.invalidate(entitiesProvider('branches')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              final name = item['name'] as String? ?? 'Без названия';
              final address = item['address'] as String? ?? '';
              final offsetMinutes =
                  (item['utc_offset_minutes'] as num?)?.toInt() ?? 180;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () async {
                    final res = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => BranchFormDialog(branch: item),
                    );
                    if (res == true) {
                      ref.invalidate(entitiesProvider('branches'));
                    }
                  },
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryGold.withAlpha(30),
                    child: Icon(
                      Icons.location_city_rounded,
                      color: AppTheme.primaryGold,
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text(
                    [
                      if (address.isNotEmpty) address,
                      _offsetLabel(offsetMinutes),
                    ].join(' • '),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Icon(
                    Icons.edit_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────
// Subscription Packages (Каталог абонементов) — P5b-5
// ─────────────────────────────────────────────────
class _PackagesList extends ConsumerWidget {
  final String searchQuery;
  const _PackagesList({required this.searchQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entitiesProvider('subscription_packages'));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: _PackagesSkeleton(),
      ),
      error: (e, _) => Center(
        child: Text('Ошибка: $e', style: TextStyle(color: AppTheme.danger)),
      ),
      data: (items) {
        var filtered = items;
        if (searchQuery.isNotEmpty) {
          final q = searchQuery.toLowerCase();
          filtered = items.where((item) {
            final name = (item['name'] as String? ?? '').toLowerCase();
            return name.contains(q);
          }).toList();
        }

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty ? 'Нет абонементов' : 'Ничего не найдено',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: AppColor.gold,
          onRefresh: () async =>
              ref.invalidate(entitiesProvider('subscription_packages')),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              return _PackageCard(item: item);
            },
          ),
        );
      },
    );
  }
}

class _PackageCard extends ConsumerWidget {
  final Map<String, dynamic> item;
  const _PackageCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name'] as String? ?? 'Без названия';
    final hoursNum = _asNum(item['lessons_total'] ?? item['lessonsTotal']);
    final hours = hoursNum % 1 == 0 ? hoursNum.toInt() : hoursNum;
    final price = _asNum(item['price']);
    final validity = item['validity_days'] ?? item['validityDays'];
    final validityDays = validity == null ? null : _asInt(validity);
    final branchName =
        (item['branches']?['name'] ?? item['branch_name'])?.toString() ?? '';
    final isActive =
        item['is_active'] == true ||
        item['isActive'] == true ||
        (item['is_active'] == null && item['isActive'] == null);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () async {
          final saved = await showPackageSheet(context, ref, existing: item);
          if (saved == true) {
            ref.invalidate(entitiesProvider('subscription_packages'));
          }
        },
        leading: CircleAvatar(
          backgroundColor: AppColor.goldSoft,
          child: const Icon(
            Icons.card_membership_rounded,
            color: AppColor.gold,
          ),
        ),
        title: Text(name),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StudentMetricChip(
                icon: Icons.event_available_rounded,
                label: 'Часов: $hours',
                color: AppColor.gold,
              ),
              _StudentMetricChip(
                icon: Icons.payments_rounded,
                label: '${_formatMoney(price)} ₽',
                color: AppTheme.secondaryGold,
              ),
              if (validityDays != null)
                _StudentMetricChip(
                  icon: Icons.schedule_rounded,
                  label: 'Срок: $validityDays дн.',
                  color: AppTheme.success,
                ),
              if (branchName.trim().isNotEmpty)
                _StudentMetricChip(
                  icon: Icons.location_on_outlined,
                  label: branchName.trim(),
                  color: AppColor.gold,
                ),
              _StudentMetricChip(
                icon: isActive
                    ? Icons.check_circle_outline_rounded
                    : Icons.pause_circle_outline_rounded,
                label: isActive ? 'Активен' : 'Неактивен',
                color: isActive ? AppTheme.success : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline_rounded, color: AppColor.danger),
          tooltip: 'Удалить',
          onPressed: () => _confirmDeletePackage(context, ref, item),
        ),
      ),
    );
  }
}

class _PackagesSkeleton extends StatelessWidget {
  const _PackagesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        6,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const SkeletonBox(width: 40, height: 40, radius: AppRadius.pill),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonLine(width: 160),
                    SizedBox(height: 8),
                    SkeletonLine(width: 220),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmDeletePackage(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> item,
) async {
  final id = item['id']?.toString();
  if (id == null || id.isEmpty) return;
  final name = item['name'] as String? ?? 'абонемент';

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Удалить абонемент?'),
      content: Text('«$name» будет удалён из каталога. Действие необратимо.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Удалить', style: TextStyle(color: AppColor.danger)),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  try {
    await ref.read(magicCrmServiceProvider).deleteSubscriptionPackage(id);
    ref.invalidate(entitiesProvider('subscription_packages'));
    if (context.mounted) {
      MagicToast.show(
        context,
        'Абонемент удалён',
        type: MagicToastType.success,
      );
    }
  } catch (e) {
    if (context.mounted) {
      MagicToast.show(
        context,
        'Не удалось удалить',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }
}

/// Opens the v7 create/edit sheet for a subscription package. Returns `true`
/// when a package was created or updated, so the caller can invalidate the list.
Future<bool?> showPackageSheet(
  BuildContext context,
  WidgetRef ref, {
  Map<String, dynamic>? existing,
}) {
  final isEdit = existing != null;
  return showMagicSheet<bool>(
    context,
    title: isEdit ? 'Редактировать абонемент' : 'Новый абонемент',
    subtitle: 'Каталог абонементов',
    icon: Icons.card_membership_rounded,
    builder: (ctx) => _PackageForm(ref: ref, existing: existing),
  );
}

class _PackageForm extends StatefulWidget {
  final WidgetRef ref;
  final Map<String, dynamic>? existing;
  const _PackageForm({required this.ref, this.existing});

  @override
  State<_PackageForm> createState() => _PackageFormState();
}

class _PackageFormState extends State<_PackageForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _lessons;
  late final TextEditingController _price;
  late final TextEditingController _validity;
  late final TextEditingController _branchId;
  late bool _isActive;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name']?.toString() ?? '');
    _lessons = TextEditingController(
      text: (e?['lessons_total'] ?? e?['lessonsTotal'])?.toString() ?? '',
    );
    _price = TextEditingController(text: e?['price']?.toString() ?? '');
    _validity = TextEditingController(
      text: (e?['validity_days'] ?? e?['validityDays'])?.toString() ?? '',
    );
    _branchId = TextEditingController(
      text: (e?['branch_id'] ?? e?['branchId'])?.toString() ?? '',
    );
    final active = e?['is_active'] ?? e?['isActive'];
    _isActive = active is bool ? active : true;
  }

  @override
  void dispose() {
    _name.dispose();
    _lessons.dispose();
    _price.dispose();
    _validity.dispose();
    _branchId.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, {String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: cs.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColor.goldLine),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _name.text.trim();
    final lessonsTotal = num.parse(_lessons.text.trim().replaceAll(',', '.'));
    final price = num.parse(_price.text.trim().replaceAll(',', '.'));
    final validityText = _validity.text.trim();
    final validityDays = validityText.isEmpty ? null : int.parse(validityText);
    final branchText = _branchId.text.trim();
    final branchId = branchText.isEmpty ? null : branchText;

    setState(() => _saving = true);
    final crm = widget.ref.read(magicCrmServiceProvider);
    try {
      if (_isEdit) {
        final id = widget.existing!['id'].toString();
        await crm.updateSubscriptionPackage(id, {
          'name': name,
          'lessonsTotal': lessonsTotal,
          'price': price,
          'validityDays': validityDays,
          'branchId': branchId,
          'isActive': _isActive,
        });
      } else {
        await crm.createSubscriptionPackage(
          name: name,
          lessonsTotal: lessonsTotal,
          price: price,
          validityDays: validityDays,
          branchId: branchId,
          isActive: _isActive,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      MagicToast.show(
        context,
        _isEdit ? 'Абонемент обновлён' : 'Абонемент создан',
        type: MagicToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      MagicToast.show(
        context,
        'Не удалось сохранить',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            decoration: _dec('Название', hint: 'Напр. «16 часов»'),
            textInputAction: TextInputAction.next,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Укажите название' : null,
          ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            controller: _lessons,
            decoration: _dec('Количество часов'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            validator: (v) {
              final n = num.tryParse((v ?? '').trim().replaceAll(',', '.'));
              if (n == null) return 'Введите число';
              if (n <= 0) return 'Должно быть больше 0';
              return null;
            },
          ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            controller: _price,
            decoration: _dec('Цена, ₽'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            validator: (v) {
              final n = num.tryParse((v ?? '').trim().replaceAll(',', '.'));
              if (n == null) return 'Введите число';
              if (n < 0) return 'Не может быть отрицательной';
              return null;
            },
          ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            controller: _validity,
            decoration: _dec('Срок действия, дней', hint: 'Необязательно'),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return null;
              final n = int.tryParse(t);
              if (n == null) return 'Введите целое число';
              if (n <= 0) return 'Должно быть больше 0';
              return null;
            },
          ),
          const SizedBox(height: AppSpace.md),
          TextFormField(
            controller: _branchId,
            decoration: _dec('ID филиала', hint: 'Необязательно'),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Активен',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: _isActive,
                  activeThumbColor: AppColor.gold,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _isActive = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    side: BorderSide(color: cs.outlineVariant),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                  ),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColor.gold,
                    foregroundColor: AppColor.onGold,
                    disabledBackgroundColor: AppColor.gold.withValues(
                      alpha: 0.5,
                    ),
                    disabledForegroundColor: AppColor.onGold,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColor.onGold,
                          ),
                        )
                      : Text(_isEdit ? 'Сохранить' : 'Создать'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
