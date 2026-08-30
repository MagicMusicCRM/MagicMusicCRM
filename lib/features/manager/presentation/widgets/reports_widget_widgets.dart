part of 'reports_widget.dart';

class _ReportsError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _ReportsError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColor.danger,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              'Не удалось загрузить отчеты',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              userErrorMessage(error, fallback: 'Не удалось загрузить отчёт.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

class _ActivityLogTab extends ConsumerStatefulWidget {
  const _ActivityLogTab({required this.filter, required this.accessSnapshot});

  final DashboardFilter filter;
  final CapabilitySnapshot? accessSnapshot;

  @override
  ConsumerState<_ActivityLogTab> createState() => _ActivityLogTabState();
}

class _ActivityLogTabState extends ConsumerState<_ActivityLogTab> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _loading = true;
  bool _refreshing = false;
  int _loadSequence = 0;
  Object? _loadError;
  String _entityType = 'all';
  List<AuditPresentationEvent> _items = [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _loadActivity();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ActivityLogTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter) {
      _loadActivity(preserveContent: true);
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _loadActivity(preserveContent: true);
    });
  }

  Future<void> _loadActivity({bool preserveContent = false}) async {
    final sequence = ++_loadSequence;
    setState(() {
      if (preserveContent && _items.isNotEmpty) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _loadError = null;
    });
    try {
      final filter = widget.filter.apiFilter;
      final items = await ref
          .read(magicCrmServiceProvider)
          .listActivityLog(
            q: _searchCtrl.text,
            entityType: _entityType == 'all' ? null : _entityType,
            branchId: filter['branchId']?.toString(),
            from: filter['from']?.toString(),
            to: filter['to']?.toString(),
            limit: 100,
          );
      if (!mounted || sequence != _loadSequence) return;
      setState(() {
        _items = items;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (mounted && sequence == _loadSequence) {
        setState(() {
          if (!preserveContent || _items.isEmpty) _loadError = e;
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _setFilter(void Function() update) {
    setState(update);
    _loadActivity(preserveContent: true);
  }

  Future<void> _openActivityEntity(ContextTransition transition) async {
    final snapshot = widget.accessSnapshot;
    if (snapshot == null ||
        !EntityRouteRegistry().resolve(transition.target, snapshot).canOpen) {
      return;
    }
    try {
      await openEntityLink(
        context,
        ref,
        transition.target,
        sourceViewState: transition.sourceState,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(e, fallback: 'Не удалось открыть запись.'),
          ),
        ),
      );
    }
  }

  ContextTransition? _activityTransition(AuditPresentationEvent event) {
    final id = event.target.id?.trim();
    final routeType = event.target.routeType?.trim();
    if (id == null || id.isEmpty || routeType == null || routeType.isEmpty) {
      return null;
    }
    try {
      return const ContextTransitionRegistry().create(
        source: ContextSourceType.audit,
        target: ContextTargetType.changedEntity,
        entityId: id,
        sourceState: ContextViewState(
          filters: {
            ...widget.filter.toContextViewState().filters,
            'entityType': _entityType,
            'query': _searchCtrl.text,
          },
        ),
        rawEntityType: routeType,
      );
    } on FormatException {
      return null;
    } on StateError {
      return null;
    }
  }

  Widget _activityCard(AuditPresentationEvent event) {
    final transition = _activityTransition(event);
    final snapshot = widget.accessSnapshot;
    final canOpen =
        transition != null &&
        snapshot != null &&
        EntityRouteRegistry().resolve(transition.target, snapshot).canOpen;
    return AuditEventCard(
      key: ValueKey(event.id),
      event: event,
      onOpenTarget: !canOpen
          ? null
          : () => unawaited(_openActivityEntity(transition)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340, minWidth: 240),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Поиск действий',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              _ReportFilterDropdown(
                label: 'Объект',
                value: _entityType,
                icon: Icons.link_rounded,
                options: const [
                  ('all', 'Все объекты'),
                  ('student', 'Ученики'),
                  ('lead', 'Лиды'),
                  ('teacher', 'Учителя'),
                  ('staff', 'Сотрудники'),
                  ('lesson', 'Занятия'),
                  ('task', 'Задачи'),
                ],
                onChanged: (value) => _setFilter(() => _entityType = value),
              ),
              if (_searchCtrl.text.isNotEmpty || _entityType != 'all')
                TextButton.icon(
                  onPressed: () {
                    _searchDebounce?.cancel();
                    setState(() {
                      _searchCtrl.clear();
                      _searchDebounce?.cancel();
                      _entityType = 'all';
                    });
                    _loadActivity(preserveContent: true);
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Сбросить'),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 2,
          child: _refreshing
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColor.gold),
                )
              : _loadError != null
              ? _ReportsError(error: _loadError, onRetry: () => _loadActivity())
              : _items.isEmpty
              ? Center(
                  child: Text(
                    'Нет действий за период',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppColor.gold,
                  onRefresh: () => _loadActivity(preserveContent: true),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _activityCard(_items[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ReportFilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  const _ReportFilterDropdown({
    required this.label,
    required this.value,
    required this.icon,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = options.any((option) => option.$1 == value)
        ? value
        : options.first.$1;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220, minWidth: 170),
      child: DropdownButtonFormField<String>(
        menuMaxHeight: 256,
        key: ValueKey('$label-$normalized'),
        initialValue: normalized,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        items: options
            .map(
              (option) => DropdownMenuItem<String>(
                value: option.$1,
                child: Text(option.$2, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}
