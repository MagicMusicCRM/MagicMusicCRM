import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/lead_detail_dialog.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/core/services/hollihop_service.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'manage_statuses_dialog.dart';

class LeadsWidget extends ConsumerStatefulWidget {
  const LeadsWidget({super.key});

  @override
  ConsumerState<LeadsWidget> createState() => _LeadsWidgetState();
}

class _LeadsWidgetState extends ConsumerState<LeadsWidget> {
  final _searchCtrl = TextEditingController();
  List<StatusRecord> _activeStatuses = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _disciplines = [];
  List<Map<String, dynamic>> _levels = [];
  List<Map<String, dynamic>> _categories = [];
  List<LeadFilterPreset> _presets = [];
  LeadBoardFilters _filters = const LeadBoardFilters();
  Timer? _searchDebounce;
  final Map<String, String> _optimisticLeadStatuses = {};
  final Set<String> _hiddenLeadIds = {};
  final Set<String> _pendingLeadIds = {};
  final Map<String, List<Map<String, dynamic>>> _extraLeadsByStatus = {};
  final Set<String> _loadedExtraLeadIds = {};
  bool _presetsLoading = false;
  bool _hasLoadedMore = false;
  bool _loadingMore = false;
  String? _nextCursor;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
    _loadFilterMetadata();
    _loadPresets();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatuses() async {
    final res = await ref.read(leadStatusesProvider.future);
    final statuses = <StatusRecord>[];
    for (final r in res) {
      final key = r['key'].toString();
      final label = r['label'].toString();
      final rawColor = r['color']?.toString() ?? '8B5CF6';
      final hexColor = rawColor.replaceAll('#', '');
      final color = Color(int.parse('FF$hexColor', radix: 16));
      statuses.add((key, label, color));
    }

    if (!mounted) return;
    setState(() => _activeStatuses = statuses);
  }

  Future<void> _loadFilterMetadata() async {
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final hollihop = ref.read(hollihopServiceProvider);
      final results = await Future.wait<dynamic>([
        crm.listBranches(limit: 100),
        hollihop.getDisciplines(),
        hollihop.getLevels(),
        hollihop.getCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = List<Map<String, dynamic>>.from(results[0] as List);
        _disciplines = _stringOptions(results[1] as List);
        _levels = _stringOptions(results[2] as List);
        _categories = _stringOptions(results[3] as List);
      });
    } catch (_) {
      // Filter metadata is progressive; the board remains usable without it.
    }
  }

  List<Map<String, dynamic>> _stringOptions(List values) {
    return values
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .map((value) => {'id': value, 'name': value})
        .toList();
  }

  Future<void> _loadPresets() async {
    setState(() => _presetsLoading = true);
    try {
      final presets = await ref.read(leadFilterPresetStoreProvider).load();
      if (!mounted) return;
      setState(() {
        _presets = presets;
        _presetsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _presetsLoading = false);
    }
  }

  void _setFilters(LeadBoardFilters filters) {
    setState(() {
      _filters = filters;
      _resetLoadedPages();
    });
  }

  void _refreshBoard() {
    _resetLoadedPages();
    ref.invalidate(leadBoardProvider(_filters));
    ref.invalidate(leadsStreamProvider);
  }

  void _resetLoadedPages() {
    _extraLeadsByStatus.clear();
    _loadedExtraLeadIds.clear();
    _hasLoadedMore = false;
    _nextCursor = null;
  }

  Future<void> _loadMoreLeads(String? cursor) async {
    final activeCursor = cursor?.trim();
    if (activeCursor == null || activeCursor.isEmpty || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _filters.fetchBoard(
        ref.read(magicCrmServiceProvider),
        cursor: activeCursor,
      );
      final columns = page['columns'] is List
          ? (page['columns'] as List).whereType<Map<String, dynamic>>()
          : const Iterable<Map<String, dynamic>>.empty();
      var appended = 0;
      for (final column in columns) {
        final statusId =
            column['key']?.toString() ?? column['id']?.toString() ?? '';
        if (statusId.isEmpty) continue;
        final items = column['items'] is List
            ? (column['items'] as List).whereType<Map<String, dynamic>>()
            : const Iterable<Map<String, dynamic>>.empty();
        final target = _extraLeadsByStatus.putIfAbsent(
          statusId,
          () => <Map<String, dynamic>>[],
        );
        for (final lead in items) {
          final leadId = lead['id']?.toString() ?? '';
          if (leadId.isEmpty || !_loadedExtraLeadIds.add(leadId)) continue;
          target.add(lead);
          appended++;
        }
      }
      if (!mounted) return;
      setState(() {
        _hasLoadedMore = true;
        _nextCursor = page['next_cursor']?.toString();
        _loadingMore = false;
      });
      if (appended == 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Новых лидов для догрузки нет')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _showError('Не удалось загрузить ещё лидов: $e');
    }
  }

  Future<void> _addLead() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _LeadDialog(),
    );
    if (result != null) {
      await ref
          .read(magicCrmServiceProvider)
          .createLead(
            firstName: result['name']!,
            phone: result['phone']!,
            source: result['source']!,
          );
      _refreshBoard();
    }
  }

  Future<void> _moveStatus(String id, String newStatus) async {
    if (id.isEmpty || _pendingLeadIds.contains(id)) return;
    final previous = _optimisticLeadStatuses[id];
    setState(() {
      _optimisticLeadStatuses[id] = newStatus;
      _pendingLeadIds.add(id);
    });
    try {
      await ref
          .read(magicCrmServiceProvider)
          .updateLead(id, statusId: newStatus);
      _refreshBoard();
      await ref.read(leadBoardProvider(_filters).future);
      if (!mounted) return;
      setState(() {
        _optimisticLeadStatuses.remove(id);
        _pendingLeadIds.remove(id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (previous == null) {
          _optimisticLeadStatuses.remove(id);
        } else {
          _optimisticLeadStatuses[id] = previous;
        }
        _pendingLeadIds.remove(id);
      });
      _showError('Не удалось изменить статус лида: $e');
    }
  }

  Future<void> _deleteLead(String id) async {
    if (id.isEmpty || _pendingLeadIds.contains(id)) return;
    setState(() {
      _hiddenLeadIds.add(id);
      _pendingLeadIds.add(id);
    });
    try {
      await ref.read(magicCrmServiceProvider).deleteLead(id);
      _refreshBoard();
      await ref.read(leadBoardProvider(_filters).future);
      if (!mounted) return;
      setState(() {
        _hiddenLeadIds.remove(id);
        _pendingLeadIds.remove(id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hiddenLeadIds.remove(id);
        _pendingLeadIds.remove(id);
      });
      _showError('Не удалось удалить лид: $e');
    }
  }

  void _openDetail(Map<String, dynamic> lead) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          LeadDetailDialog(lead: lead, allStatuses: _activeStatuses),
    );
    if (changed == true) {
      _refreshBoard();
    }
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppTheme.danger),
    );
  }

  Future<void> _saveCurrentPreset() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сохранить пресет'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Название пресета'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, controller.text),
            icon: const Icon(Icons.bookmark_add_rounded),
            label: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();

    final normalized = name?.trim();
    if (normalized == null || normalized.isEmpty) return;

    final currentFilters = _filters.copyWith(q: _searchCtrl.text.trim());
    final next =
        _presets
            .where(
              (preset) => preset.name.toLowerCase() != normalized.toLowerCase(),
            )
            .toList()
          ..add(LeadFilterPreset(name: normalized, filters: currentFilters));
    await ref.read(leadFilterPresetStoreProvider).save(next);
    if (!mounted) return;
    setState(() => _presets = next);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Пресет сохранён')));
  }

  Future<void> _deletePreset(int index) async {
    if (index < 0 || index >= _presets.length) return;
    final next = List<LeadFilterPreset>.from(_presets)..removeAt(index);
    await ref.read(leadFilterPresetStoreProvider).save(next);
    if (!mounted) return;
    setState(() => _presets = next);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Пресет удалён')));
  }

  void _applyPreset(int index) {
    if (index < 0 || index >= _presets.length) return;
    final preset = _presets[index];
    _searchDebounce?.cancel();
    _searchCtrl.text = preset.filters.q;
    _setFilters(preset.filters);
  }

  void _handlePresetMenu(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return;
    final index = int.tryParse(parts[1]);
    if (index == null) return;
    if (parts[0] == 'apply') {
      _applyPreset(index);
    } else if (parts[0] == 'delete') {
      _deletePreset(index);
    }
  }

  StatusRecord _statusFromColumn(Map<String, dynamic> column) {
    final rawColor = (column['color'] ?? '8B5CF6').toString();
    final hexColor = rawColor.replaceAll('#', '');
    final color = Color(int.tryParse('FF$hexColor', radix: 16) ?? 0xFF8B5CF6);
    return (
      column['key']?.toString() ?? column['id']?.toString() ?? 'new',
      column['label']?.toString() ??
          column['name']?.toString() ??
          'Без статуса',
      color,
    );
  }

  Widget _buildToolbar(Map<String, dynamic> board) {
    final total = board['total_count'] ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Воронка продаж · $total',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await ManageStatusesDialog.show(context);
                  await _loadStatuses();
                  _refreshBoard();
                },
                icon: const Icon(Icons.settings_rounded, size: 16),
                label: const Text('Колонки'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      hintText: 'Имя, телефон, источник',
                      suffixIcon: _filters.q.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _setFilters(_filters.copyWith(q: ''));
                              },
                            ),
                    ),
                    onChanged: (value) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 350),
                        () => _setFilters(_filters.copyWith(q: value.trim())),
                      );
                    },
                    onSubmitted: (value) =>
                        _setFilters(_filters.copyWith(q: value.trim())),
                  ),
                ),
                const SizedBox(width: 8),
                _quickFilter('all', 'Все'),
                _quickFilter('active', 'В работе'),
                _quickFilter('deferred', 'Отложенные'),
                _quickFilter('processed', 'Обработанные'),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Есть задачи'),
                  selected: _filters.openTasks,
                  onSelected: (selected) =>
                      _setFilters(_filters.copyWith(openTasks: selected)),
                ),
                const SizedBox(width: 8),
                _filterDropdown(
                  width: 190,
                  label: 'Филиал',
                  value: _filters.branchId,
                  options: _branches,
                  onChanged: (value) =>
                      _setFilters(_filters.copyWith(branchId: value ?? '')),
                ),
                _filterDropdown(
                  width: 180,
                  label: 'Статус',
                  value: _filters.statusId,
                  options: _activeStatuses
                      .map((s) => {'id': s.$1, 'name': s.$2})
                      .toList(),
                  onChanged: (value) =>
                      _setFilters(_filters.copyWith(statusId: value ?? '')),
                ),
                _filterDropdown(
                  width: 170,
                  label: 'Направление',
                  value: _filters.discipline,
                  options: _disciplines,
                  valueField: 'name',
                  onChanged: (value) =>
                      _setFilters(_filters.copyWith(discipline: value ?? '')),
                ),
                _filterDropdown(
                  width: 150,
                  label: 'Уровень',
                  value: _filters.level,
                  options: _levels,
                  valueField: 'name',
                  onChanged: (value) =>
                      _setFilters(_filters.copyWith(level: value ?? '')),
                ),
                _filterDropdown(
                  width: 160,
                  label: 'Категория',
                  value: _filters.category,
                  options: _categories,
                  valueField: 'name',
                  onChanged: (value) =>
                      _setFilters(_filters.copyWith(category: value ?? '')),
                ),
                OutlinedButton.icon(
                  onPressed: _saveCurrentPreset,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Сохранить пресет'),
                ),
                if (_presets.isNotEmpty || _presetsLoading)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: PopupMenuButton<String>(
                      tooltip: 'Пресеты',
                      enabled: !_presetsLoading,
                      icon: _presetsLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bookmarks_outlined),
                      onSelected: _handlePresetMenu,
                      itemBuilder: (_) => <PopupMenuEntry<String>>[
                        ...List.generate(
                          _presets.length,
                          (index) => PopupMenuItem<String>(
                            value: 'apply:$index',
                            child: SizedBox(
                              width: 220,
                              child: Text(
                                _presets[index].name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        const PopupMenuDivider(),
                        ...List.generate(
                          _presets.length,
                          (index) => PopupMenuItem<String>(
                            value: 'delete:$index',
                            child: SizedBox(
                              width: 220,
                              child: Text(
                                'Удалить: ${_presets[index].name}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppTheme.danger),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickFilter(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: _filters.quick == value,
        onSelected: (_) => _setFilters(_filters.copyWith(quick: value)),
      ),
    );
  }

  Widget _filterDropdown({
    required double width,
    required String label,
    required String value,
    required List<Map<String, dynamic>> options,
    required ValueChanged<String?> onChanged,
    String valueField = 'id',
  }) {
    final normalizedValue = value.isEmpty ? '' : value;
    final seen = <String>{};
    final optionItems = options
        .map((item) {
          final optionValue = item[valueField]?.toString() ?? '';
          final optionLabel =
              item['name']?.toString() ??
              item['label']?.toString() ??
              optionValue;
          return (optionValue, optionLabel);
        })
        .where((item) => item.$1.isNotEmpty && seen.add(item.$1))
        .toList();
    final hasSelected =
        normalizedValue.isEmpty ||
        optionItems.any((item) => item.$1 == normalizedValue);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: width,
        child: DropdownButtonFormField<String>(
          key: ValueKey('$label:$normalizedValue'),
          initialValue: normalizedValue,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [
            const DropdownMenuItem(value: '', child: Text('Все')),
            if (!hasSelected)
              DropdownMenuItem(
                value: normalizedValue,
                child: Text(normalizedValue, overflow: TextOverflow.ellipsis),
              ),
            ...optionItems.map(
              (item) => DropdownMenuItem(
                value: item.$1,
                child: Text(item.$2, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boardAsync = ref.watch(leadBoardProvider(_filters));

    return boardAsync.when(
      loading: () => const KanbanSkeleton(),
      error: (err, stack) => Center(child: Text('Ошибка: $err')),
      data: (board) {
        final columns = board['columns'] is List
            ? (board['columns'] as List).whereType<Map<String, dynamic>>()
            : const Iterable<Map<String, dynamic>>.empty();
        final active = columns.map(_statusFromColumn).toList();
        final pageCursor = _hasLoadedMore
            ? _nextCursor
            : board['next_cursor']?.toString();

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton(
            onPressed: _addLead,
            tooltip: 'Новый контакт',
            child: const Icon(Icons.person_add_rounded),
          ),
          body: Column(
            children: [
              _buildToolbar(board),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: columns.map((column) {
                      final status = _statusFromColumn(column);
                      final rawLeads = column['items'] is List
                          ? (column['items'] as List)
                                .whereType<Map<String, dynamic>>()
                                .toList()
                          : <Map<String, dynamic>>[];
                      final extraLeads =
                          _extraLeadsByStatus[status.$1] ??
                          const <Map<String, dynamic>>[];
                      final leads = rawLeads
                          .followedBy(extraLeads)
                          .where(
                            (lead) => !_hiddenLeadIds.contains(
                              lead['id']?.toString(),
                            ),
                          )
                          .map((lead) {
                            final id = lead['id']?.toString() ?? '';
                            final status = _optimisticLeadStatuses[id];
                            return status == null
                                ? lead
                                : {...lead, 'status': status};
                          })
                          .toList();
                      final totalCountRaw = column['total_count'];
                      final totalCount = totalCountRaw is num
                          ? totalCountRaw.toInt()
                          : int.tryParse(totalCountRaw?.toString() ?? '') ??
                                leads.length;
                      return _KanbanColumn(
                        status: status,
                        leads: leads,
                        totalCount: totalCount,
                        onMove: _moveStatus,
                        onDelete: _deleteLead,
                        onTap: _openDetail,
                        allStatuses: active,
                        onRefresh: _refreshBoard,
                        pendingLeadIds: _pendingLeadIds,
                        nextCursor: pageCursor,
                        loadingMore: _loadingMore,
                        onLoadMore: _loadMoreLeads,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KanbanColumn extends StatefulWidget {
  final StatusRecord status;
  final List<Map<String, dynamic>> leads;
  final int totalCount;
  final Function(String, String) onMove;
  final Function(String) onDelete;
  final Function(Map<String, dynamic>) onTap;
  final List<StatusRecord> allStatuses;
  final VoidCallback onRefresh;
  final Set<String> pendingLeadIds;
  final String? nextCursor;
  final bool loadingMore;
  final ValueChanged<String?> onLoadMore;

  const _KanbanColumn({
    required this.status,
    required this.leads,
    required this.totalCount,
    required this.onMove,
    required this.onDelete,
    required this.onTap,
    required this.allStatuses,
    required this.onRefresh,
    required this.pendingLeadIds,
    required this.nextCursor,
    required this.loadingMore,
    required this.onLoadMore,
  });

  @override
  State<_KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends State<_KanbanColumn> {
  @override
  Widget build(BuildContext context) {
    final hasMore =
        (widget.nextCursor?.trim().isNotEmpty ?? false) &&
        widget.totalCount > widget.leads.length;
    return Container(
      width: 300,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(127),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) => true,
        onAcceptWithDetails: (details) =>
            widget.onMove(details.data, widget.status.$1),
        builder: (context, candidateData, rejectedData) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: widget.status.$3,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.status.$2,
                      style: TextStyle(
                        color: widget.status.$3,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${widget.totalCount}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (candidateData.isNotEmpty)
                Container(
                  height: 100,
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: widget.status.$3),
                    borderRadius: BorderRadius.circular(10),
                    color: widget.status.$3.withAlpha(25),
                  ),
                  child: const Center(child: Icon(Icons.move_to_inbox_rounded)),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: widget.leads.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= widget.leads.length) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
                        child: OutlinedButton.icon(
                          onPressed: widget.loadingMore
                              ? null
                              : () => widget.onLoadMore(widget.nextCursor),
                          icon: widget.loadingMore
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.expand_more_rounded),
                          label: Text(
                            widget.loadingMore
                                ? 'Загрузка...'
                                : 'Загрузить ещё',
                          ),
                        ),
                      );
                    }
                    final lead = widget.leads[index];
                    final leadId = lead['id']?.toString() ?? '';
                    return _LeadCard(
                      lead: lead,
                      statusColor: widget.status.$3,
                      allStatuses: widget.allStatuses,
                      onMove: widget.onMove,
                      onDelete: widget.onDelete,
                      onTap: () => widget.onTap(lead),
                      onRefresh: widget.onRefresh,
                      isPending: widget.pendingLeadIds.contains(leadId),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Finalizing kanban column structure

class _LeadCard extends ConsumerWidget {
  final Map<String, dynamic> lead;
  final Color statusColor;
  final List<StatusRecord> allStatuses;
  final Function(String, String) onMove;
  final Function(String) onDelete;
  final VoidCallback onTap;
  final VoidCallback onRefresh;
  final bool isPending;

  const _LeadCard({
    required this.lead,
    required this.statusColor,
    required this.allStatuses,
    required this.onMove,
    required this.onDelete,
    required this.onTap,
    required this.onRefresh,
    required this.isPending,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = lead['id']?.toString() ?? '';
    final firstName = lead['name']?.toString() ?? '';
    final lName = lead['last_name']?.toString() ?? '';
    final name = '$firstName $lName'.trim();
    final displayName = name.isEmpty ? 'Без имени' : name;
    final phone = lead['phone']?.toString() ?? '';
    final source = lead['source']?.toString() ?? '';
    final branchName = lead['branch_name']?.toString() ?? '';
    final assignedName = lead['assigned_name']?.toString() ?? '';
    final linkedStudentId = lead['linked_student_id']?.toString() ?? '';
    final openTasks = _intValue(lead['open_tasks_count']);
    final comments = _intValue(lead['comments_count']);
    final trials = _intValue(lead['trial_lessons_count']);
    final currentStatus = lead['status']?.toString() ?? 'new';
    final dtStr = lead['created_at']?.toString();
    final dt = dtStr != null ? DateTime.tryParse(dtStr) : null;
    final dateStr = dt != null ? DateFormat('d MMM', 'ru').format(dt) : '';

    final customData = lead['custom_data'] as Map<String, dynamic>? ?? {};
    final discipline = customData['discipline']?.toString() ?? '';
    final level = customData['level']?.toString() ?? '';

    return LongPressDraggable<String>(
      data: id,
      maxSimultaneousDrags: isPending ? 0 : null,
      feedback: Transform.rotate(
        angle: 0.05,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryGold, width: 2),
            ),
            child: Text(
              displayName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
      child: Opacity(
        opacity: isPending ? 0.62 : 1,
        child: AbsorbPointer(
          absorbing: isPending,
          child: GestureDetector(
            onTap: onTap,
            child: Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: isPending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  Icons.more_horiz_rounded,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  size: 18,
                                ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 150),
                          onSelected: (v) {
                            if (v == 'delete') {
                              onDelete(id);
                            } else if (v == 'comment') {
                              _addComment(context, ref);
                            } else if (v == 'task') {
                              _addTask(context, ref);
                            } else if (v == 'trial') {
                              _scheduleTrial(context, ref);
                            } else {
                              onMove(id, v);
                            }
                          },
                          itemBuilder: (_) => [
                            ...allStatuses
                                .where((s) => s.$1 != currentStatus)
                                .map(
                                  (s) => PopupMenuItem(
                                    value: s.$1,
                                    child: Text('→ ${s.$2}'),
                                  ),
                                ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'comment',
                              child: Text('Добавить комментарий'),
                            ),
                            const PopupMenuItem(
                              value: 'task',
                              child: Text('Создать задачу'),
                            ),
                            const PopupMenuItem(
                              value: 'trial',
                              child: Text('Назначить пробный'),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Удалить',
                                style: TextStyle(color: AppTheme.danger),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (phone.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          phone,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (discipline.isNotEmpty)
                          _InfoBadge(
                            text: discipline,
                            color: AppTheme.primaryPurple.withAlpha(51),
                            textColor: AppTheme.primaryPurple,
                          ),
                        if (level.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _InfoBadge(
                              text: level,
                              color: AppTheme.warning.withAlpha(51),
                              textColor: AppTheme.warning,
                            ),
                          ),
                      ],
                    ),
                    if (branchName.isNotEmpty || assignedName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (branchName.isNotEmpty)
                              _IconBadge(
                                icon: Icons.location_on_outlined,
                                text: branchName,
                              ),
                            if (assignedName.isNotEmpty)
                              _IconBadge(
                                icon: Icons.person_pin_circle_outlined,
                                text: assignedName,
                              ),
                          ],
                        ),
                      ),
                    if (openTasks > 0 ||
                        comments > 0 ||
                        trials > 0 ||
                        linkedStudentId.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (openTasks > 0)
                              _MetricBadge(
                                icon: Icons.task_alt_rounded,
                                text: '$openTasks',
                              ),
                            if (comments > 0)
                              _MetricBadge(
                                icon: Icons.chat_bubble_outline_rounded,
                                text: '$comments',
                              ),
                            if (trials > 0)
                              _MetricBadge(
                                icon: Icons.event_available_rounded,
                                text: '$trials',
                              ),
                            if (linkedStudentId.isNotEmpty)
                              const _MetricBadge(
                                icon: Icons.link_rounded,
                                text: 'ученик',
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (source.isNotEmpty)
                          Text(
                            source,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        Text(
                          dateStr,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _addComment(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Комментарий к лиду'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Текст...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (content != null && content.trim().isNotEmpty) {
      await ref
          .read(magicCrmServiceProvider)
          .createComment(
            entityType: 'lead',
            entityId: lead['id'],
            body: content.trim(),
          );
      onRefresh();
    }
  }

  Future<void> _addTask(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Задача по лиду'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Что сделать?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (title != null && title.trim().isNotEmpty) {
      await ref
          .read(magicCrmServiceProvider)
          .createTask(
            entityType: 'lead',
            entityId: lead['id'],
            title: title.trim(),
          );
      onRefresh();
    }
  }

  Future<void> _scheduleTrial(BuildContext context, WidgetRef ref) async {
    final crm = ref.read(magicCrmServiceProvider);
    final [teachersRes, roomsRes] = await Future.wait([
      crm.listTeachers(limit: 100),
      crm.listRooms(limit: 100),
    ]);

    final teachers = List<Map<String, dynamic>>.from(teachersRes);
    final rooms = List<Map<String, dynamic>>.from(roomsRes);

    if (!context.mounted) return;
    if (teachers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет доступных преподавателей')),
      );
      return;
    }

    String? selectedTeacher = teachers.isNotEmpty ? teachers.first['id'] : null;
    String? selectedRoom = rooms.isNotEmpty ? rooms.first['id'] : null;
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Пробное занятие'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedTeacher,
                decoration: const InputDecoration(labelText: 'Учитель'),
                items: teachers
                    .map(
                      (t) => DropdownMenuItem(
                        value: t['id'].toString(),
                        child: Text('${t['first_name']} ${t['last_name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setLocalState(() => selectedTeacher = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRoom,
                decoration: const InputDecoration(labelText: 'Кабинет'),
                items: rooms
                    .map(
                      (r) => DropdownMenuItem(
                        value: r['id'].toString(),
                        child: Text(r['name']),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setLocalState(() => selectedRoom = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text(
                  'Дата: ${DateFormat('dd.MM.yyyy').format(selectedDate)}',
                ),
                trailing: const Icon(Icons.calendar_today_rounded),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (picked != null) {
                    setLocalState(() => selectedDate = picked);
                  }
                },
              ),
              ListTile(
                title: Text('Время: ${selectedTime.format(ctx)}'),
                trailing: const Icon(Icons.access_time_rounded),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: selectedTime,
                  );
                  if (picked != null) {
                    setLocalState(() => selectedTime = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Назначить'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && selectedTeacher != null) {
      final scheduledAt = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );

      await crm.createLesson(
        leadId: lead['id'],
        teacherId: selectedTeacher,
        roomId: selectedRoom,
        scheduledAt: scheduledAt.toIso8601String(),
        isTrial: true,
        status: 'scheduled',
        notes: 'Пробное занятие по лиду: ${lead['name'] ?? ''}',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пробное занятие назначено')),
        );
      }
      onRefresh();
    }
  }
}

class _InfoBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;

  const _InfoBadge({
    required this.text,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _IconBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetricBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withAlpha(36),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.primaryGold),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.primaryGold,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadDialog extends StatefulWidget {
  const _LeadDialog();

  @override
  State<_LeadDialog> createState() => _LeadDialogState();
}

class _LeadDialogState extends State<_LeadDialog> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('Новый лид'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(labelText: 'Телефон'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _sourceCtrl,
            decoration: const InputDecoration(
              labelText: 'Источник (ВКонтакте, сайт...)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (_nameCtrl.text.trim().isNotEmpty) {
              Navigator.pop(context, {
                'name': _nameCtrl.text.trim(),
                'phone': _phoneCtrl.text.trim(),
                'source': _sourceCtrl.text.trim(),
              });
            }
          },
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}
