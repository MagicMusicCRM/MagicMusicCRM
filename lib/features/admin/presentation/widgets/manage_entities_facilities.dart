part of 'manage_entities_widget.dart';

// ─────────────────────────────────────────────────
class _BranchesList extends ConsumerWidget {
  final String searchQuery;
  final bool canEdit;
  final bool canManageLifecycle;
  final bool includeArchived;
  const _BranchesList({
    required this.searchQuery,
    required this.canEdit,
    required this.canManageLifecycle,
    required this.includeArchived,
  });

  String _offsetLabel(int minutes) {
    final sign = minutes >= 0 ? '+' : '-';
    final abs = minutes.abs();
    final h = abs ~/ 60;
    final m = abs % 60;
    final offset = m == 0 ? '$sign$h ч' : '$sign$h ч $m мин';
    return switch (minutes) {
      180 => 'Москва ($offset)',
      120 => 'Калининград ($offset)',
      60 => 'Центральная Европа ($offset)',
      0 => 'Всемирное время',
      _ => 'Смещение $offset',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      entitiesProvider(includeArchived ? 'branches:all' : 'branches'),
    );
    return async.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(12), child: ListSkeleton()),
      error: (_, _) => _EntityLoadError(
        title: 'Не удалось загрузить филиалы',
        onRetry: () => invalidateBranchCatalog(ref),
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
              final archived = item['lifecycle_state'] == 'archived';

              Future<void> openLifecycle() async {
                final changed = await showDialog<bool>(
                  context: context,
                  builder: (_) => BranchLifecycleDialog(branch: item),
                );
                if (changed == true) invalidateBranchCatalog(ref);
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: archived
                      ? (canManageLifecycle ? openLifecycle : null)
                      : !canEdit
                      ? null
                      : () async {
                          final res = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => BranchFormDialog(branch: item),
                          );
                          if (res == true) {
                            invalidateBranchCatalog(ref);
                          }
                        },
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryGold.withAlpha(30),
                    child: Icon(
                      Icons.location_city_rounded,
                      color: AppTheme.primaryGold,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(name)),
                      if (archived)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('Архив'),
                          ),
                        ),
                    ],
                  ),
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canManageLifecycle)
                        IconButton(
                          tooltip: archived
                              ? 'Восстановить филиал'
                              : 'Проверить закрытие',
                          onPressed: openLifecycle,
                          icon: Icon(
                            archived
                                ? Icons.restore_rounded
                                : Icons.archive_outlined,
                          ),
                        ),
                      Icon(
                        archived
                            ? Icons.lock_outline_rounded
                            : canEdit
                            ? Icons.edit_rounded
                            : Icons.lock_outline_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 18,
                      ),
                    ],
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
  final bool canEdit;
  final bool includeArchived;
  const _PackagesList({
    required this.searchQuery,
    required this.canEdit,
    required this.includeArchived,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = entitiesProvider(
      includeArchived ? 'subscription_packages:all' : 'subscription_packages',
    );
    final async = ref.watch(provider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: _PackagesSkeleton(),
      ),
      error: (_, _) => _EntityLoadError(
        title: 'Не удалось загрузить абонементы',
        onRetry: () => invalidateSubscriptionPackageCatalog(ref),
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
          onRefresh: () async => ref.invalidate(provider),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              return _PackageCard(item: item, canEdit: canEdit);
            },
          ),
        );
      },
    );
  }
}

class _PackageCard extends ConsumerWidget {
  final Map<String, dynamic> item;
  final bool canEdit;
  const _PackageCard({required this.item, required this.canEdit});

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
        (item['branches']?['name'] ?? item['branchName'] ?? item['branch_name'])
            ?.toString() ??
        '';
    final isArchived =
        item['archivedAt'] != null ||
        item['archived_at'] != null ||
        item['deleted_at'] != null ||
        item['active'] == false ||
        item['isActive'] == false ||
        item['is_active'] == false;
    final isActive = !isArchived;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: !canEdit || isArchived
            ? null
            : () async {
                final saved = await showPackageSheet(
                  context,
                  ref,
                  existing: item,
                );
                if (saved == true) {
                  invalidateSubscriptionPackageCatalog(ref);
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
                label: isActive ? 'Активен' : 'В архиве',
                color: isActive ? AppTheme.success : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
        trailing: canEdit
            ? IconButton(
                key: ValueKey(
                  isArchived
                      ? 'restore-subscription-package-${item['id']}'
                      : 'archive-subscription-package-${item['id']}',
                ),
                icon: Icon(
                  isArchived
                      ? Icons.restore_from_trash_outlined
                      : Icons.archive_outlined,
                  color: isArchived ? AppTheme.success : AppColor.danger,
                ),
                tooltip: isArchived ? 'Восстановить' : 'Архивировать',
                onPressed: () => isArchived
                    ? _confirmRestorePackage(context, ref, item)
                    : _confirmArchivePackage(context, ref, item),
              )
            : const Icon(Icons.lock_outline_rounded),
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

Future<void> _confirmArchivePackage(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> item,
) async {
  final id = item['id']?.toString();
  if (id == null || id.isEmpty) return;
  final version = _asInt(item['version']);
  final name = item['name'] as String? ?? 'абонемент';

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Архивировать абонемент?'),
      content: Text(
        '«$name» исчезнет из новой выдачи. Исторические абонементы '
        'сохранятся, а пакет можно будет восстановить.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Архивировать', style: TextStyle(color: AppColor.danger)),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  try {
    await ref
        .read(magicCrmServiceProvider)
        .archiveSubscriptionPackage(id, expectedVersion: version);
    invalidateSubscriptionPackageCatalog(ref);
    if (context.mounted) {
      MagicToast.show(
        context,
        'Абонемент перемещён в архив',
        type: MagicToastType.success,
      );
    }
  } catch (e) {
    if (context.mounted) {
      MagicToast.show(
        context,
        'Не удалось архивировать',
        detail: userErrorMessage(e),
        type: MagicToastType.danger,
      );
    }
  }
}

Future<void> _confirmRestorePackage(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> item,
) async {
  final id = item['id']?.toString();
  if (id == null || id.isEmpty) return;
  final version = _asInt(item['version']);
  final name = item['name'] as String? ?? 'абонемент';

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Восстановить абонемент?'),
      content: Text(
        '«$name» снова станет доступен для оформления новых абонементов.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Восстановить'),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  try {
    await ref
        .read(magicCrmServiceProvider)
        .restoreSubscriptionPackage(id, expectedVersion: version);
    invalidateSubscriptionPackageCatalog(ref);
    if (context.mounted) {
      MagicToast.show(
        context,
        'Абонемент восстановлен',
        type: MagicToastType.success,
      );
    }
  } catch (e) {
    if (context.mounted) {
      MagicToast.show(
        context,
        'Не удалось восстановить',
        detail: userErrorMessage(e),
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
  String? _branchId;
  List<Map<String, dynamic>> _branches = const [];
  bool _loadingBranches = true;
  late int _expectedVersion;
  bool _saving = false;
  bool _stale = false;
  bool _loadingLatest = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name']?.toString() ?? '');
    _lessons = TextEditingController(
      text:
          (e?['unitCount'] ?? e?['lessons_total'] ?? e?['lessonsTotal'])
              ?.toString() ??
          '',
    );
    _price = TextEditingController(text: _packagePriceText(e));
    _validity = TextEditingController(
      text: (e?['validity_days'] ?? e?['validityDays'])?.toString() ?? '',
    );
    _branchId = (e?['branch_id'] ?? e?['branchId'])?.toString();
    _expectedVersion = _asInt(e?['version']);
    _loadBranches();
  }

  @override
  void dispose() {
    _name.dispose();
    _lessons.dispose();
    _price.dispose();
    _validity.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await widget.ref
          .read(magicCrmServiceProvider)
          .listBranches(limit: 100);
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _loadingBranches = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingBranches = false);
    }
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
    final branchId = _branchId;

    setState(() => _saving = true);
    final crm = widget.ref.read(magicCrmServiceProvider);
    try {
      if (_isEdit) {
        final id = widget.existing!['id'].toString();
        await crm.updateSubscriptionPackage(id, {
          'name': name,
          'unitCount': lessonsTotal,
          'basePriceMinor': subscriptionPriceMinor(price),
          'currencyCode': 'RUB',
          'validityDays': validityDays,
          'branchId': branchId,
        }, expectedVersion: _expectedVersion);
      } else {
        await crm.createSubscriptionPackage(
          name: name,
          lessonsTotal: lessonsTotal,
          price: price,
          validityDays: validityDays,
          branchId: branchId,
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
      final stale = _isEdit && e is MagicApiException && e.statusCode == 409;
      if (stale) {
        invalidateSubscriptionPackageCatalog(widget.ref);
        setState(() => _stale = true);
      }
      MagicToast.show(
        context,
        stale ? 'Каталог уже изменён' : 'Не удалось сохранить',
        detail: stale
            ? 'Сохранение остановлено. Загрузите актуальную версию и '
                  'проверьте поля.'
            : userErrorMessage(e),
        type: MagicToastType.danger,
      );
    }
  }

  Future<void> _reloadLatest() async {
    if (!_isEdit || _loadingLatest) return;
    setState(() => _loadingLatest = true);
    try {
      final id = widget.existing!['id'].toString();
      final items = await widget.ref
          .read(magicCrmServiceProvider)
          .listSubscriptionPackages(limit: 200, includeArchived: true);
      final latest = items.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['id']?.toString() == id,
        orElse: () => null,
      );
      if (!mounted) return;
      if (latest == null) {
        throw StateError('Пакет больше не доступен.');
      }
      final archivedAt = latest['archivedAt'] ?? latest['archived_at'];
      final active =
          latest['active'] ?? latest['isActive'] ?? latest['is_active'] ?? true;
      if (archivedAt != null || active != true) {
        Navigator.pop(context, false);
        MagicToast.show(
          context,
          'Пакет уже архивирован',
          detail: 'Редактор закрыт, каталог обновлён.',
          type: MagicToastType.info,
        );
        return;
      }

      _name.text = latest['name']?.toString() ?? '';
      _lessons.text =
          (latest['unitCount'] ??
                  latest['lessons_total'] ??
                  latest['lessonsTotal'])
              ?.toString() ??
          '';
      _price.text = _packagePriceText(latest);
      _validity.text =
          (latest['validity_days'] ?? latest['validityDays'])?.toString() ?? '';
      _branchId = (latest['branch_id'] ?? latest['branchId'])?.toString();
      setState(() {
        _expectedVersion = _asInt(latest['version']);
        _stale = false;
        _loadingLatest = false;
      });
      invalidateSubscriptionPackageCatalog(widget.ref);
      MagicToast.show(
        context,
        'Загружена актуальная версия',
        detail: 'Черновик сброшен. Проверьте поля перед сохранением.',
        type: MagicToastType.info,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingLatest = false);
      MagicToast.show(
        context,
        'Не удалось обновить редактор',
        detail: userErrorMessage(error),
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
          LayoutBuilder(
            builder: (context, constraints) => DropdownMenu<String>(
              key: ValueKey('package-branch-${_branchId ?? 'school'}'),
              width: constraints.maxWidth,
              enableFilter: true,
              requestFocusOnTap: true,
              initialSelection: _branchId,
              label: Text(_loadingBranches ? 'Загрузка филиалов…' : 'Филиал'),
              helperText: 'Необязательно: пусто означает всю школу',
              dropdownMenuEntries: [
                const DropdownMenuEntry(value: '', label: 'Вся школа'),
                for (final branch in _branches)
                  DropdownMenuEntry(
                    value: branch['id'].toString(),
                    label: branch['name']?.toString() ?? 'Филиал',
                  ),
              ],
              onSelected: _loadingBranches
                  ? null
                  : (value) => setState(
                      () => _branchId = value == null || value.isEmpty
                          ? null
                          : value,
                    ),
            ),
          ),
          if (_stale) ...[
            const SizedBox(height: AppSpace.md),
            Container(
              key: const Key('subscription-package-stale-banner'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColor.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Эта версия устарела. Ваш черновик не отправлен.',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Загрузите актуальные данные: текущие поля формы будут '
                    'заменены данными сервера.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const Key('subscription-package-reload-latest'),
                    onPressed: _loadingLatest ? null : _reloadLatest,
                    icon: _loadingLatest
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: const Text('Загрузить актуальную версию'),
                  ),
                ],
              ),
            ),
          ],
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
                  onPressed: _saving || _stale ? null : _save,
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

String _packagePriceText(Map<String, dynamic>? package) {
  if (package == null) return '';
  final legacy = package['price'];
  if (legacy != null) return legacy.toString();
  final minor = BigInt.tryParse(
    (package['basePriceMinor'] ?? package['base_price_minor'])?.toString() ??
        '',
  );
  if (minor == null) return '';
  final whole = minor ~/ BigInt.from(100);
  final fraction = (minor % BigInt.from(100)).toInt();
  return fraction == 0
      ? whole.toString()
      : '$whole.${fraction.toString().padLeft(2, '0')}';
}
