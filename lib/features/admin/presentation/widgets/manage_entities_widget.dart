import 'package:magic_music_crm/core/forms/dirty_form_exit.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/app_dropdown.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/user_roles_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/notification_preferences_dialog.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/magic_page_state.dart';
import '../../../../core/widgets/magic_shimmer.dart';
import '../../../../core/widgets/magic_sheet.dart';
import '../../../../core/widgets/magic_toast.dart';
import 'teacher_detail_dialog.dart';
import 'staff_detail_dialog.dart';
import 'group_detail_dialog.dart';
import 'group_lifecycle_dialog.dart';
import 'create_employee_dialog.dart';
import 'create_group_dialog.dart';
import 'create_teacher_dialog.dart';
import 'branch_form_dialog.dart';
import 'branch_lifecycle_dialog.dart';
import 'reference_catalog_settings.dart';
import 'data_quality_widget.dart';
import 'deletion_requests_widget.dart';

part 'manage_entities_people.dart';
part 'manage_entities_scheduling.dart';
part 'manage_entities_facilities.dart';

class SystemSettingsRouteScreen extends ConsumerWidget {
  const SystemSettingsRouteScreen({super.key, this.initialArea});

  final String? initialArea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(capabilitySnapshotProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Настройки системы'),
      ),
      body: access.when(
        loading: () => const MagicPageState.loading(),
        error: (_, _) => MagicPageState(
          kind: MagicPageStateKind.error,
          title: 'Не удалось проверить доступ',
          message: 'Проверьте подключение и повторите попытку.',
          actionLabel: 'Повторить',
          onAction: () => ref.invalidate(capabilitySnapshotProvider),
        ),
        data: (snapshot) =>
            snapshot.allows('system.settings.manage') ||
                snapshot.allows('config.crm.read')
            ? SystemSettingsWorkspace(
                role: snapshot.role,
                initialArea: initialArea,
              )
            : const MagicPageState(
                kind: MagicPageStateKind.forbidden,
                title: 'Нет доступа к настройкам',
                message: 'Обратитесь к директору для проверки ваших прав.',
              ),
      ),
    );
  }
}

class _EntityLoadError extends StatelessWidget {
  const _EntityLoadError({required this.title, required this.onRetry});

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MagicPageState(
      kind: MagicPageStateKind.error,
      title: title,
      message: 'Проверьте подключение и повторите загрузку.',
      actionLabel: 'Повторить',
      onAction: onRetry,
    );
  }
}

final entitiesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      table,
    ) async {
      final crm = ref.watch(magicCrmServiceProvider);

      if (table == 'teachers') {
        return crm.listTeachers(limit: 100);
      } else if (table == 'groups' || table == 'groups:all') {
        return crm.listGroups(
          limit: 100,
          includeArchived: table.endsWith(':all'),
        );
      } else if (table == 'rooms') {
        return crm.listRooms(limit: 100);
      } else if (table == 'employees') {
        return crm.listStaff(limit: 100);
      } else if (table == 'branches') {
        return crm.listBranches(limit: 100);
      } else if (table == 'branches:all') {
        return crm.listBranches(limit: 100, includeArchived: true);
      } else if (table == 'subscription_packages' ||
          table == 'subscription_packages:all') {
        return crm.listSubscriptionPackages(
          limit: 100,
          includeArchived: table.endsWith(':all'),
        );
      }

      return const <Map<String, dynamic>>[];
    });

void invalidateSubscriptionPackageCatalog(WidgetRef ref) {
  ref.invalidate(entitiesProvider('subscription_packages'));
  ref.invalidate(entitiesProvider('subscription_packages:all'));
}

void invalidateBranchCatalog(WidgetRef ref) {
  ref.invalidate(entitiesProvider('branches'));
  ref.invalidate(entitiesProvider('branches:all'));
}

void invalidateGroupCatalog(WidgetRef ref) {
  ref.invalidate(entitiesProvider('groups'));
  ref.invalidate(entitiesProvider('groups:all'));
}

final teacherSearchProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      query,
    ) async {
      return ref
          .watch(magicCrmServiceProvider)
          .listTeachers(q: query, limit: 100);
    });

final staffSearchProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      query,
    ) async {
      return ref.watch(magicCrmServiceProvider).listStaff(q: query, limit: 100);
    });

final personnelDirectoryProvider =
    FutureProvider.family<
      List<Map<String, dynamic>>,
      ({bool teachers, String query, String? branchId, String? status})
    >((ref, filter) {
      final crm = ref.watch(magicCrmServiceProvider);
      return filter.teachers
          ? crm.listTeachers(
              q: filter.query,
              branchId: filter.branchId,
              status: filter.status,
              limit: 100,
            )
          : crm.listStaff(
              q: filter.query,
              branchId: filter.branchId,
              status: filter.status,
              limit: 100,
            );
    });

/// Operational personnel directory. It reuses the canonical teacher/staff
/// records and their existing access-controlled cards; settings remain the
/// place for account-wide configuration.
class PersonnelWorkspace extends ConsumerStatefulWidget {
  const PersonnelWorkspace({
    super.key,
    required this.snapshot,
    this.initialLink,
  });

  final CapabilitySnapshot snapshot;
  final EntityLink? initialLink;

  @override
  ConsumerState<PersonnelWorkspace> createState() => _PersonnelWorkspaceState();
}

class _PersonnelWorkspaceState extends ConsumerState<PersonnelWorkspace> {
  final _search = TextEditingController();
  final _exitGuardKey = GlobalKey<FormDiscardGuardState>();
  String _section = 'teachers';
  String? _directoryBranchId;
  String? _directoryStatus;
  String? _openedLinkKey;
  Map<String, dynamic>? _selectedPerson;
  bool _selectedIsTeacher = true;
  bool _showDirectory = true;
  bool _loadingSelected = false;
  String? _selectedError;
  int _selectionGeneration = 0;
  GlobalKey _detailKey = GlobalKey(debugLabel: 'personnel-detail');

  @override
  void initState() {
    super.initState();
    _queueLinkedCard(widget.initialLink);
  }

  @override
  void didUpdateWidget(covariant PersonnelWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLink?.toJson().toString() !=
        widget.initialLink?.toJson().toString()) {
      _queueLinkedCard(widget.initialLink);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _queueLinkedCard(EntityLink? link) {
    final type = link?.rawEntityType;
    if (link == null ||
        (type != 'staff' && type != 'personnel_teacher') ||
        link.entityId.isEmpty) {
      return;
    }
    final key = '$type:${link.entityId}';
    if (_openedLinkKey == key) return;
    _openedLinkKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openLinkedCard(link));
    });
  }

  Future<bool> _canLeaveCard() async =>
      await _exitGuardKey.currentState?.confirmLeave() ?? true;

  Future<void> _closeCard() async {
    if (!await _canLeaveCard() || !mounted) return;
    setState(() {
      ++_selectionGeneration;
      _selectedPerson = null;
      _loadingSelected = false;
    });
  }

  Future<void> _openLinkedCard(EntityLink link) async {
    if (!await _canLeaveCard() || !mounted) return;
    final generation = ++_selectionGeneration;
    final isTeacher = link.rawEntityType == 'personnel_teacher';
    setState(() {
      _section = isTeacher ? 'teachers' : 'staff';
      _selectedIsTeacher = isTeacher;
      _loadingSelected = true;
      _selectedError = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final person = isTeacher
          ? await crm.getTeacher(link.entityId)
          : await crm.getStaff(link.entityId);
      if (!mounted || generation != _selectionGeneration) return;
      setState(() {
        _selectedPerson = person;
        _loadingSelected = false;
        _detailKey = GlobalKey(debugLabel: 'personnel-detail');
      });
    } catch (error) {
      if (!mounted || generation != _selectionGeneration) return;
      setState(() {
        _loadingSelected = false;
        _selectedError = userErrorMessage(
          error,
          fallback: 'Не удалось открыть карточку.',
        );
      });
    }
  }

  Future<void> _selectPerson(
    Map<String, dynamic> person,
    bool isTeacher,
  ) async {
    if (_selectedPerson?['id'] == person['id'] &&
        _selectedIsTeacher == isTeacher) {
      return;
    }
    if (!await _canLeaveCard() || !mounted) return;
    final id = person['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final generation = ++_selectionGeneration;
    setState(() {
      _selectedIsTeacher = isTeacher;
      _selectedPerson = null;
      _selectedError = null;
      _loadingSelected = true;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final fresh = isTeacher
          ? await crm.getTeacher(id)
          : await crm.getStaff(id);
      if (!mounted || generation != _selectionGeneration) return;
      setState(() {
        _selectedPerson = fresh;
        _loadingSelected = false;
        _detailKey = GlobalKey(debugLabel: 'personnel-detail');
      });
    } catch (error) {
      if (!mounted || generation != _selectionGeneration) return;
      setState(() {
        _loadingSelected = false;
        _selectedError = userErrorMessage(
          error,
          fallback: 'Не удалось открыть карточку.',
        );
      });
    }
  }

  Future<void> _refreshSelected() async {
    ref.invalidate(personnelDirectoryProvider);
    final person = _selectedPerson;
    final id = person?['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final isTeacher = _selectedIsTeacher;
    if (isTeacher) {
      ref.invalidate(entitiesProvider('teachers'));
      ref.invalidate(teacherSearchProvider(_search.text.trim()));
    } else {
      ref.invalidate(entitiesProvider('employees'));
      ref.invalidate(staffSearchProvider(_search.text.trim()));
    }
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final updated = isTeacher
          ? await crm.getTeacher(id)
          : await crm.getStaff(id);
      if (!mounted || _selectedPerson?['id']?.toString() != id) return;
      setState(() {
        _selectedPerson = updated;
        _detailKey = GlobalKey(debugLabel: 'personnel-detail');
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(error, fallback: 'Не удалось обновить карточку.'),
          ),
        ),
      );
    }
  }

  Widget _buildDirectory() => _section == 'teachers'
      ? _TeachersList(
          searchQuery: _search.text,
          branchId: _directoryBranchId,
          status: _directoryStatus,
          selectedId: _selectedIsTeacher
              ? (_selectedPerson?['id']?.toString())
              : null,
          onSelected: (person) => _selectPerson(person, true),
        )
      : _EmployeesList(
          searchQuery: _search.text,
          branchId: _directoryBranchId,
          status: _directoryStatus,
          currentRole: widget.snapshot.role,
          selectedId: !_selectedIsTeacher
              ? (_selectedPerson?['id']?.toString())
              : null,
          onSelected: (person) => _selectPerson(person, false),
        );

  Widget _buildDetail() {
    if (_loadingSelected) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _selectedError;
    if (error != null) {
      return MagicPageState(
        kind: MagicPageStateKind.error,
        title: 'Не удалось открыть карточку',
        message: error,
      );
    }
    final person = _selectedPerson;
    if (person == null) {
      return const MagicPageState(
        kind: MagicPageStateKind.empty,
        title: 'Выберите человека',
        message: 'Карточка откроется рядом со списком без отдельного окна.',
      );
    }
    return KeyedSubtree(
      key: _detailKey,
      child: _selectedIsTeacher
          ? TeacherDetailDialog(
              teacher: person,
              embedded: true,
              onChanged: _refreshSelected,
              onClose: _closeCard,
              exitGuardKey: _exitGuardKey,
            )
          : StaffDetailDialog(
              staff: person,
              currentRole: widget.snapshot.role,
              embedded: true,
              onChanged: _refreshSelected,
              onClose: _closeCard,
              exitGuardKey: _exitGuardKey,
            ),
    );
  }

  Future<void> _create() async {
    bool? saved;
    if (_section == 'teachers') {
      saved = await showCreateTeacherSurface(context);
    } else {
      saved = await showCreateEmployeeSurface(context);
    }
    if (saved != true || !mounted) return;
    ref.invalidate(personnelDirectoryProvider);
    final query = _search.text.trim();
    if (_section == 'teachers') {
      ref.invalidate(entitiesProvider('teachers'));
      ref.invalidate(teacherSearchProvider(query));
    } else {
      ref.invalidate(entitiesProvider('employees'));
      ref.invalidate(staffSearchProvider(query));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = widget.snapshot.allows('crm.client.write');
    return LayoutBuilder(
      builder: (context, viewport) {
        if (viewport.maxWidth < 900 &&
            (_selectedPerson != null || _loadingSelected)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _closeCard,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('К списку персонала'),
                ),
              ),
              Expanded(
                child: KeyedSubtree(
                  key: const Key('personnel-detail-pane'),
                  child: _buildDetail(),
                ),
              ),
            ],
          );
        }
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: Column(
            children: [
              _SettingsToolbar(
                title: 'Персонал',
                subtitle: _section == 'teachers'
                    ? 'Преподаватели, филиалы, доступность и условия работы'
                    : 'Сотрудники, филиалы и доступ в приложение',
                action: canCreate
                    ? FilledButton.icon(
                        key: const Key('personnel-create'),
                        onPressed: _create,
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: Text(
                          _section == 'teachers'
                              ? 'Новый преподаватель'
                              : 'Новый сотрудник',
                        ),
                      )
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final selector = SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'teachers',
                            label: Text('Преподаватели'),
                          ),
                          ButtonSegment(
                            value: 'staff',
                            label: Text('Сотрудники'),
                          ),
                        ],
                        selected: {_section},
                        onSelectionChanged: (value) async {
                          if (!await _canLeaveCard() || !mounted) return;
                          setState(() {
                            _section = value.first;
                            ++_selectionGeneration;
                            _loadingSelected = false;
                            _directoryStatus = null;
                            _selectedPerson = null;
                            _selectedError = null;
                          });
                        },
                      ),
                    );
                    final search = TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search_rounded),
                        labelText: 'Поиск по персоналу',
                      ),
                    );
                    if (constraints.maxWidth < 700) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: selector,
                          ),
                          const SizedBox(height: 10),
                          search,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        selector,
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: _showDirectory
                              ? 'Скрыть список персонала'
                              : 'Показать список персонала',
                          onPressed: () =>
                              setState(() => _showDirectory = !_showDirectory),
                          icon: Icon(
                            _showDirectory
                                ? Icons.view_sidebar_outlined
                                : Icons.view_sidebar_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: search),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: 220,
                        child: AppDropdownButtonFormField<String>(
                          menuMaxHeight: 256,
                          key: ValueKey('personnel-branch-$_directoryBranchId'),
                          initialValue: _directoryBranchId ?? '',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Филиал',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Все филиалы'),
                            ),
                            for (final branch
                                in ref
                                        .watch(entitiesProvider('branches'))
                                        .asData
                                        ?.value ??
                                    <Map<String, dynamic>>[])
                              DropdownMenuItem(
                                value: branch['id'].toString(),
                                child: Text(
                                  branch['name']?.toString() ?? 'Филиал',
                                ),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () =>
                                _directoryBranchId = value == '' ? null : value,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: AppDropdownButtonFormField<String>(
                          menuMaxHeight: 256,
                          key: ValueKey(
                            'personnel-status-$_section-$_directoryStatus',
                          ),
                          initialValue: _directoryStatus ?? '',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Статус',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Все статусы'),
                            ),
                            if (_section == 'staff')
                              const DropdownMenuItem(
                                value: 'working',
                                child: Text('Работает'),
                              ),
                            const DropdownMenuItem(
                              value: 'active',
                              child: Text('Активен'),
                            ),
                            const DropdownMenuItem(
                              value: 'inactive',
                              child: Text('Неактивен'),
                            ),
                            const DropdownMenuItem(
                              value: 'archived',
                              child: Text('В архиве'),
                            ),
                          ],
                          onChanged: (value) => setState(
                            () => _directoryStatus = value == '' ? null : value,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 900) {
                      return _selectedPerson == null && !_loadingSelected
                          ? _buildDirectory()
                          : KeyedSubtree(
                              key: const Key('personnel-detail-pane'),
                              child: _buildDetail(),
                            );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_showDirectory || _selectedPerson == null) ...[
                          SizedBox(width: 300, child: _buildDirectory()),
                          VerticalDivider(
                            width: 1,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ],
                        Expanded(
                          child: KeyedSubtree(
                            key: const Key('personnel-detail-pane'),
                            child: _buildDetail(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SystemSettingsWorkspace extends ConsumerStatefulWidget {
  const SystemSettingsWorkspace({
    super.key,
    required this.role,
    this.initialArea,
    this.initialUserSearch,
  });

  final String role;
  final String? initialArea;
  final String? initialUserSearch;

  @override
  ConsumerState<SystemSettingsWorkspace> createState() =>
      _SystemSettingsWorkspaceState();
}

class _SystemSettingsWorkspaceState
    extends ConsumerState<SystemSettingsWorkspace> {
  static const _areas = <(String, String, IconData)>[
    ('organization', 'Организация', Icons.apartment_rounded),
    ('users', 'Пользователи', Icons.manage_accounts_rounded),
    ('notifications', 'Уведомления', Icons.notifications_outlined),
    ('crm', 'CRM и воронки', Icons.view_kanban_rounded),
    ('subscriptions', 'Абонементы', Icons.confirmation_number_outlined),
    ('system', 'Интеграции и система', Icons.hub_rounded),
  ];

  static const _searchTerms = <String, String>{
    'organization': 'филиалы аудитории справочники дисциплины причины',
    'crm': 'клиенты лиды поля воронки источники бизнес параметры система',
    'subscriptions': 'продажи оплаты абонементы каталог пакеты тарифы',
    'users': 'пользователи аккаунты сотрудники роли права доступ связи',
    'notifications': 'уведомления получатели события каналы доставка',
    'system': 'интеграции данные обслуживание удаление качество система',
  };

  late String _area;
  final _search = TextEditingController();
  final Set<String> _visitedAreas = {};
  final _contentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _area = _normalizeArea(widget.initialArea);
    _visitedAreas.add(_area);
  }

  @override
  void didUpdateWidget(covariant SystemSettingsWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialArea != widget.initialArea) {
      _area = _normalizeArea(widget.initialArea);
      _visitedAreas.add(_area);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _normalizeArea(String? area) => switch (area) {
    'schedule' || 'learning' => 'organization',
    'sales' => 'subscriptions',
    'access' => 'users',
    'data' => 'system',
    final value when _areas.any((candidate) => candidate.$1 == value) => value!,
    _ => 'organization',
  };

  List<(String, String, IconData)> _allowedAreas(CapabilitySnapshot snapshot) {
    if (snapshot.allows('system.settings.manage')) return _areas;
    if (snapshot.allows('config.crm.read')) {
      return _areas
          .where((area) => area.$1 == 'crm' || area.$1 == 'subscriptions')
          .toList();
    }
    return const [];
  }

  void _selectArea(String area) {
    setState(() {
      _area = area;
      _visitedAreas.add(area);
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(capabilitySnapshotProvider).asData?.value;
    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final areas = _allowedAreas(snapshot);
    if (areas.isEmpty) {
      return const _SettingsDenied(
        text: 'Директор сможет открыть настройки после выдачи права.',
      );
    }
    if (!areas.any((candidate) => candidate.$1 == _area)) {
      _area = areas.first.$1;
      _visitedAreas.add(_area);
    }
    final compact = MediaQuery.sizeOf(context).width < 900;
    final query = _search.text.trim().toLowerCase();
    final visibleAreas = query.isEmpty
        ? areas
        : areas.where((area) {
            final haystack = '${area.$2} ${_searchTerms[area.$1] ?? ''}'
                .toLowerCase();
            return haystack.contains(query);
          }).toList();
    final selectedIndex = areas.indexWhere((area) => area.$1 == _area);
    final content = IndexedStack(
      key: _contentKey,
      index: selectedIndex,
      children: [
        for (final area in areas)
          KeyedSubtree(
            key: ValueKey('settings-area-${area.$1}'),
            child: _visitedAreas.contains(area.$1)
                ? _content(snapshot, area.$1)
                : const SizedBox.shrink(),
          ),
      ],
    );
    final search = TextField(
      key: const Key('settings-search'),
      controller: _search,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.search_rounded),
        labelText: 'Поиск по настройкам',
      ),
    );
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: compact
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: search,
                ),
                if (visibleAreas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Подходящих настроек не найдено'),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AppDropdownButtonFormField<String>(
                      menuMaxHeight: 256,
                      key: ValueKey('settings-area-$_area-$query'),
                      initialValue:
                          visibleAreas.any((candidate) => candidate.$1 == _area)
                          ? _area
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Раздел настроек',
                      ),
                      items: [
                        for (final area in visibleAreas)
                          DropdownMenuItem(
                            value: area.$1,
                            child: Text(area.$2),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) _selectArea(value);
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                Expanded(child: content),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 272,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                        child: search,
                      ),
                      Expanded(
                        child: visibleAreas.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Text('Подходящих настроек не найдено'),
                                ),
                              )
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  16,
                                ),
                                children: [
                                  for (final area in visibleAreas)
                                    ListTile(
                                      selected: _area == area.$1,
                                      leading: Icon(area.$3),
                                      title: Text(area.$2),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      onTap: () => _selectArea(area.$1),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                Expanded(child: content),
              ],
            ),
    );
  }

  Widget _content(CapabilitySnapshot snapshot, String area) {
    final canEdit = snapshot.allows('config.crm.edit');
    return switch (area) {
      'organization' => _OrganizationSettings(
        canEdit: canEdit,
        canCreateBranch:
            canEdit &&
            (snapshot.role == 'director' || snapshot.role == 'system_admin'),
        canManageLifecycle:
            canEdit &&
            (snapshot.role == 'director' || snapshot.role == 'system_admin'),
      ),
      'crm' when snapshot.allows('config.crm.read') => const Column(
        children: [
          _SettingsToolbar(
            title: 'CRM и воронки',
            subtitle: 'Поля карточек, справочники, правила и воронки клиентов',
          ),
          Expanded(child: CrmConfigurationWorkspace()),
        ],
      ),
      'crm' => const _SettingsDenied(text: 'Нет доступа к настройкам CRM.'),
      'subscriptions' => _SalesSettings(
        canEdit: snapshot.allows('commerce.package.manage'),
      ),
      'notifications' => const NotificationPreferencesDialog(embedded: true),
      'users' => UserRolesWidget(
        currentRole: widget.role,
        initialSearch: widget.initialUserSearch,
      ),
      'system' => _DataSettings(
        canManageDeletion:
            snapshot.role == 'admin' ||
            snapshot.role == 'director' ||
            snapshot.role == 'system_admin',
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class GroupsWorkspace extends ConsumerStatefulWidget {
  const GroupsWorkspace({super.key, required this.snapshot, this.initialLink});
  final CapabilitySnapshot snapshot;
  final EntityLink? initialLink;
  @override
  ConsumerState<GroupsWorkspace> createState() => _GroupsWorkspaceState();
}

class _GroupsWorkspaceState extends ConsumerState<GroupsWorkspace> {
  final _search = TextEditingController();
  bool _showArchived = false;
  String? _openedId;
  @override
  void initState() {
    super.initState();
    _queueLinkedGroup();
  }

  @override
  void didUpdateWidget(covariant GroupsWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    _queueLinkedGroup();
  }

  void _queueLinkedGroup() {
    final link = widget.initialLink;
    if (link?.entityId == '__section__') {
      _openedId = null;
      return;
    }
    if (link?.entityType != EntityLinkType.group ||
        link!.entityId == '__section__' ||
        link.entityId.isEmpty ||
        _openedId == link.entityId ||
        (!widget.snapshot.allows('schedule.lesson.read.assigned') &&
            !widget.snapshot.allows('schedule.lesson.write'))) {
      return;
    }
    _openedId = link.entityId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final group = await ref
            .read(magicCrmServiceProvider)
            .getGroup(link.entityId);
        if (!mounted || widget.initialLink?.entityId != link.entityId) return;
        if (await GroupDetailDialog.show(
                  context,
                  group,
                  canWrite:
                      widget.snapshot.allows('schedule.lesson.write') &&
                      group['lifecycle_state'] != 'archived',
                ) ==
                true &&
            mounted) {
          invalidateGroupCatalog(ref);
        }
      } catch (error) {
        if (mounted) {
          MagicToast.show(
            context,
            userErrorMessage(error, fallback: 'Не удалось открыть группу.'),
            type: MagicToastType.danger,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (await showCreateGroupSurface(context) == true && mounted) {
      invalidateGroupCatalog(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.snapshot.allows('schedule.lesson.read.assigned') &&
        !widget.snapshot.allows('schedule.lesson.write')) {
      return const _SettingsDenied(text: 'Нет доступа к группам.');
    }
    final canWrite = widget.snapshot.allows('schedule.lesson.write');
    return Column(
      children: [
        _SettingsToolbar(
          title: 'Группы',
          subtitle: 'Состав, преподаватели и параметры учебных групп',
          action: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => invalidateGroupCatalog(ref),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Обновить'),
              ),
              if (canWrite)
                FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Новая группа'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Поиск группы',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                selected: _showArchived,
                onSelected: (value) => setState(() => _showArchived = value),
                avatar: const Icon(Icons.archive_outlined, size: 18),
                label: const Text('Завершённые'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _GroupsList(
            searchQuery: _search.text,
            includeArchived: _showArchived,
            canManageLifecycle: canWrite,
          ),
        ),
      ],
    );
  }
}

class _OrganizationSettings extends ConsumerStatefulWidget {
  const _OrganizationSettings({
    required this.canEdit,
    required this.canCreateBranch,
    required this.canManageLifecycle,
  });

  final bool canEdit;
  final bool canCreateBranch;
  final bool canManageLifecycle;

  @override
  ConsumerState<_OrganizationSettings> createState() =>
      _OrganizationSettingsState();
}

class _OrganizationSettingsState extends ConsumerState<_OrganizationSettings> {
  final _search = TextEditingController();
  final _exitGuardKey = GlobalKey<FormDiscardGuardState>();
  Map<String, dynamic>? _selectedBranch;
  bool _creating = false;
  String _section = 'branches';
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    // This catalog may have been loaded before an external administrative
    // operation (for example, a controlled prelaunch reset). Always reconcile
    // the first frame with the authoritative API instead of showing an old
    // Riverpod family value until the whole application is restarted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) invalidateBranchCatalog(ref);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _creating = true);
  }

  void _closeCard() => setState(() {
    _selectedBranch = null;
    _creating = false;
  });

  Future<void> _back() async {
    if (await _exitGuardKey.currentState?.confirmLeave() == false || !mounted) {
      return;
    }
    _closeCard();
  }

  void _refreshBranches() => invalidateBranchCatalog(ref);

  @override
  Widget build(BuildContext context) {
    if (_creating || _selectedBranch != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _back,
              icon: const Icon(Icons.arrow_back),
              label: const Text('К списку филиалов'),
            ),
          ),
          Expanded(
            child: BranchFormDialog(
              key: const Key('branch-detail-pane'),
              branch: _selectedBranch,
              embedded: true,
              canEdit:
                  widget.canEdit &&
                  _selectedBranch?['lifecycle_state'] != 'archived',
              canManageLifecycle:
                  widget.canManageLifecycle &&
                  _selectedBranch?['lifecycle_state'] != 'archived',
              exitGuardKey: _exitGuardKey,
              onClose: _closeCard,
              onSaved: () {
                invalidateBranchCatalog(ref);
                _closeCard();
              },
            ),
          ),
        ],
      );
    }
    final branches = _section == 'branches';
    return Column(
      children: [
        _SettingsToolbar(
          title: branches ? 'Организация' : 'Организационные справочники',
          subtitle: branches
              ? widget.canEdit
                    ? 'Филиалы, рабочие часы, аудитории и дисциплины'
                    : 'Только просмотр назначенных филиалов'
              : 'Дисциплины школы и причины отказа',
          action: branches
              ? Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('refresh-branch-catalog'),
                      onPressed: _refreshBranches,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Обновить'),
                    ),
                    if (widget.canCreateBranch)
                      FilledButton.icon(
                        onPressed: _create,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Новый филиал'),
                      ),
                  ],
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'branches',
                  label: Text('Филиалы'),
                  icon: Icon(Icons.apartment_rounded),
                ),
                ButtonSegment(
                  value: 'references',
                  label: Text('Справочники'),
                  icon: Icon(Icons.library_books_outlined),
                ),
              ],
              selected: {_section},
              onSelectionChanged: (value) {
                setState(() => _section = value.first);
              },
            ),
          ),
        ),
        if (branches)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded),
                      labelText: 'Поиск по названию',
                    ),
                  ),
                ),
                if (widget.canManageLifecycle) ...[
                  const SizedBox(width: 12),
                  FilterChip(
                    selected: _showArchived,
                    onSelected: (value) =>
                        setState(() => _showArchived = value),
                    avatar: const Icon(Icons.archive_outlined, size: 18),
                    label: const Text('Показать архив'),
                  ),
                ],
              ],
            ),
          ),
        Expanded(
          child: branches
              ? _BranchesList(
                  searchQuery: _search.text,
                  canEdit: widget.canEdit,
                  canManageLifecycle: widget.canManageLifecycle,
                  includeArchived: _showArchived,
                  onSelected: (branch) =>
                      setState(() => _selectedBranch = branch),
                )
              : ReferenceCatalogSettings(canEdit: widget.canManageLifecycle),
        ),
      ],
    );
  }
}

class _SalesSettings extends ConsumerStatefulWidget {
  const _SalesSettings({required this.canEdit});

  final bool canEdit;

  @override
  ConsumerState<_SalesSettings> createState() => _SalesSettingsState();
}

class _SalesSettingsState extends ConsumerState<_SalesSettings> {
  bool _showArchived = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SettingsToolbar(
          title: 'Абонементы',
          subtitle: 'Пакеты занятий, стоимость и срок действия',
          action: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.canEdit)
                FilterChip(
                  key: const ValueKey('subscription-packages-archive-filter'),
                  selected: _showArchived,
                  onSelected: (value) => setState(() => _showArchived = value),
                  avatar: const Icon(Icons.archive_outlined, size: 18),
                  label: const Text('Показать архив'),
                ),
              if (widget.canEdit)
                FilledButton.icon(
                  onPressed: () async {
                    if (await showPackageSheet(context, ref) == true) {
                      invalidateSubscriptionPackageCatalog(ref);
                    }
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Новый абонемент'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TextField(
            key: const Key('subscription-package-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Поиск абонемента',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        Expanded(
          child: _PackagesList(
            searchQuery: _search.text,
            canEdit: widget.canEdit,
            includeArchived: _showArchived,
          ),
        ),
      ],
    );
  }
}

class _DataSettings extends StatelessWidget {
  const _DataSettings({required this.canManageDeletion});

  final bool canManageDeletion;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const _SettingsToolbar(
            title: 'Данные и обслуживание',
            subtitle: 'Контроль качества и запросы на удаление',
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Качество данных'),
              Tab(text: 'Запросы на удаление'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const DataQualityWidget(),
                DeletionRequestsWidget(canManage: canManageDeletion),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsToolbar extends StatelessWidget {
  const _SettingsToolbar({
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 640
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  if (action != null) ...[
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: action!),
                  ],
                ],
              )
            : Row(
                children: [
                  Expanded(child: heading),
                  ?action,
                ],
              ),
      ),
    );
  }
}

class _SettingsDenied extends StatelessWidget {
  const _SettingsDenied({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 42),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
