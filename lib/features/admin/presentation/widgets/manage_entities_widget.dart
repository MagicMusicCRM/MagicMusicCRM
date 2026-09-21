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
import 'schedule_reference_settings.dart';

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
  String _section = 'teachers';
  String? _openedLinkKey;
  Map<String, dynamic>? _selectedPerson;
  bool _selectedIsTeacher = true;
  bool _loadingSelected = false;
  String? _selectedError;
  int _detailRevision = 0;

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

  Future<void> _openLinkedCard(EntityLink link) async {
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
      if (!mounted) return;
      setState(() {
        _selectedPerson = person;
        _loadingSelected = false;
        _detailRevision++;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingSelected = false;
        _selectedError = userErrorMessage(
          error,
          fallback: 'Не удалось открыть карточку.',
        );
      });
    }
  }

  void _selectPerson(Map<String, dynamic> person, bool isTeacher) {
    setState(() {
      _selectedPerson = Map<String, dynamic>.from(person);
      _selectedIsTeacher = isTeacher;
      _selectedError = null;
      _loadingSelected = false;
      _detailRevision++;
    });
  }

  Future<void> _refreshSelected() async {
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
        _detailRevision++;
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
          selectedId: _selectedIsTeacher
              ? (_selectedPerson?['id']?.toString())
              : null,
          onSelected: (person) => _selectPerson(person, true),
        )
      : _EmployeesList(
          searchQuery: _search.text,
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
    final id = person['id']?.toString() ?? '';
    return KeyedSubtree(
      key: ValueKey('personnel-detail:$id:$_detailRevision'),
      child: _selectedIsTeacher
          ? TeacherDetailDialog(
              teacher: person,
              embedded: true,
              onChanged: _refreshSelected,
              onClose: () => setState(() => _selectedPerson = null),
            )
          : StaffDetailDialog(
              staff: person,
              currentRole: widget.snapshot.role,
              embedded: true,
              onChanged: _refreshSelected,
              onClose: () => setState(() => _selectedPerson = null),
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
                      ButtonSegment(value: 'staff', label: Text('Сотрудники')),
                    ],
                    selected: {_section},
                    onSelectionChanged: (value) {
                      setState(() {
                        _section = value.first;
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
                      Align(alignment: Alignment.centerLeft, child: selector),
                      const SizedBox(height: 10),
                      search,
                    ],
                  );
                }
                return Row(
                  children: [
                    selector,
                    const SizedBox(width: 12),
                    Expanded(child: search),
                  ],
                );
              },
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
                    SizedBox(width: 360, child: _buildDirectory()),
                    VerticalDivider(
                      width: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
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
  }
}

class SystemSettingsWorkspace extends ConsumerStatefulWidget {
  const SystemSettingsWorkspace({
    super.key,
    required this.role,
    this.initialArea,
    this.initialUserSearch,
    this.initialTeacherId,
  });

  final String role;
  final String? initialArea;
  final String? initialUserSearch;
  final String? initialTeacherId;

  @override
  ConsumerState<SystemSettingsWorkspace> createState() =>
      _SystemSettingsWorkspaceState();
}

class _SystemSettingsWorkspaceState
    extends ConsumerState<SystemSettingsWorkspace> {
  static const _areas = <(String, String, IconData)>[
    ('organization', 'Организация', Icons.apartment_rounded),
    ('learning', 'Обучение', Icons.school_rounded),
    ('crm', 'Клиенты', Icons.view_kanban_rounded),
    ('access', 'Доступ и уведомления', Icons.manage_accounts_rounded),
    ('system', 'Интеграции и система', Icons.hub_rounded),
  ];

  static const _searchTerms = <String, String>{
    'organization': 'филиалы аудитории справочники дисциплины причины',
    'learning': 'расписание графики преподавателей группы часы работы',
    'crm': 'клиенты лиды поля воронки источники продажи оплаты абонементы',
    'access': 'пользователи сотрудники роли права уведомления доступ',
    'system': 'интеграции данные обслуживание удаление качество система',
  };

  late String _area;
  late final String _initialClientArea;
  final _search = TextEditingController();
  final Set<String> _visitedAreas = {};

  @override
  void initState() {
    super.initState();
    _area = _normalizeArea(widget.initialArea);
    _initialClientArea = widget.initialArea == 'sales' ? 'sales' : 'crm';
    _visitedAreas.add(_area);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _normalizeArea(String? area) => switch (area) {
    'schedule' => 'learning',
    'sales' => 'crm',
    'users' => 'access',
    'data' => 'system',
    final value when _areas.any((candidate) => candidate.$1 == value) => value!,
    _ => 'organization',
  };

  List<(String, String, IconData)> _allowedAreas(CapabilitySnapshot snapshot) {
    if (snapshot.allows('system.settings.manage')) return _areas;
    if (snapshot.allows('config.crm.read')) {
      return _areas.where((area) => area.$1 == 'crm').toList();
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
      'learning' => _ScheduleSettings(
        canEditReferences: canEdit,
        canManageGroups: snapshot.allows('schedule.lesson.write'),
        initialTeacherId: widget.initialTeacherId,
      ),
      'crm' => _ClientSettingsGroup(
        snapshot: snapshot,
        initialArea: _initialClientArea,
      ),
      'access' => _UsersSettings(
        currentRole: widget.role,
        initialSearch: widget.initialUserSearch,
        canCreatePeople: snapshot.allows('crm.client.write'),
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

class _ClientSettingsGroup extends StatefulWidget {
  const _ClientSettingsGroup({
    required this.snapshot,
    required this.initialArea,
  });

  final CapabilitySnapshot snapshot;
  final String initialArea;

  @override
  State<_ClientSettingsGroup> createState() => _ClientSettingsGroupState();
}

class _ClientSettingsGroupState extends State<_ClientSettingsGroup> {
  late String _area;
  final _visited = <String>{};

  @override
  void initState() {
    super.initState();
    _area = widget.initialArea == 'sales' ? 'sales' : 'crm';
    _visited.add(_area);
  }

  @override
  Widget build(BuildContext context) {
    final canReadCrm = widget.snapshot.allows('config.crm.read');
    final areas = <(String, String)>[
      if (canReadCrm) ('crm', 'CRM и воронки'),
      ('sales', 'Продажи и оплаты'),
    ];
    if (!areas.any((candidate) => candidate.$1 == _area)) {
      _area = areas.first.$1;
      _visited.add(_area);
    }
    return Column(
      children: [
        _SettingsToolbar(
          title: 'Клиенты',
          subtitle: 'Воронки, поля, источники, абонементы и правила продаж',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<String>(
              segments: [
                for (final area in areas)
                  ButtonSegment(value: area.$1, label: Text(area.$2)),
              ],
              selected: {_area},
              onSelectionChanged: (value) {
                setState(() {
                  _area = value.first;
                  _visited.add(_area);
                });
              },
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: areas.indexWhere((area) => area.$1 == _area),
            children: [
              for (final area in areas)
                KeyedSubtree(
                  key: ValueKey('client-settings-${area.$1}'),
                  child: !_visited.contains(area.$1)
                      ? const SizedBox.shrink()
                      : area.$1 == 'crm'
                      ? const CrmConfigurationWorkspace()
                      : _SalesSettings(
                          canEdit: widget.snapshot.allows(
                            'commerce.package.manage',
                          ),
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScheduleSettings extends StatefulWidget {
  const _ScheduleSettings({
    required this.canEditReferences,
    required this.canManageGroups,
    this.initialTeacherId,
  });

  final bool canEditReferences;
  final bool canManageGroups;
  final String? initialTeacherId;

  @override
  State<_ScheduleSettings> createState() => _ScheduleSettingsState();
}

enum _ScheduleSettingsView { branchHours, teacherSchedules, groups }

class _ScheduleSettingsState extends State<_ScheduleSettings> {
  final _search = TextEditingController();
  late _ScheduleSettingsView _view;
  bool _showArchivedGroups = false;

  @override
  void initState() {
    super.initState();
    _view = widget.initialTeacherId == null
        ? _ScheduleSettingsView.branchHours
        : _ScheduleSettingsView.teacherSchedules;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final saved = await showCreateGroupSurface(context);
    if (saved == true && mounted) {
      final container = ProviderScope.containerOf(context);
      container.invalidate(entitiesProvider('groups'));
      container.invalidate(entitiesProvider('groups:all'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _view == _ScheduleSettingsView.groups;
    final title = switch (_view) {
      _ScheduleSettingsView.branchHours => 'Часы работы филиалов',
      _ScheduleSettingsView.teacherSchedules => 'Графики преподавателей',
      _ScheduleSettingsView.groups => 'Учебные группы',
    };
    final subtitle = switch (_view) {
      _ScheduleSettingsView.branchHours =>
        'Рабочие дни, время открытия и исключения',
      _ScheduleSettingsView.teacherSchedules =>
        'Назначения по филиалам, рабочие часы и недоступность',
      _ScheduleSettingsView.groups => 'Состав и параметры учебных групп',
    };
    return Column(
      children: [
        _SettingsToolbar(
          title: title,
          subtitle: subtitle,
          action: groups && widget.canManageGroups
              ? FilledButton.icon(
                  onPressed: _createGroup,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Новая группа'),
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<_ScheduleSettingsView>(
                  segments: const [
                    ButtonSegment(
                      value: _ScheduleSettingsView.branchHours,
                      label: Text('Часы филиалов'),
                    ),
                    ButtonSegment(
                      value: _ScheduleSettingsView.teacherSchedules,
                      label: Text('Графики преподавателей'),
                    ),
                    ButtonSegment(
                      value: _ScheduleSettingsView.groups,
                      label: Text('Группы'),
                    ),
                  ],
                  selected: {_view},
                  onSelectionChanged: (value) {
                    setState(() => _view = value.first);
                  },
                ),
              ),
              if (groups) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 420,
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
                    FilterChip(
                      selected: _showArchivedGroups,
                      onSelected: (value) {
                        setState(() => _showArchivedGroups = value);
                      },
                      avatar: const Icon(Icons.archive_outlined, size: 18),
                      label: const Text('Показывать завершённые'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: switch (_view) {
            _ScheduleSettingsView.branchHours => ScheduleReferenceSettings(
              key: const ValueKey('branch-hours-settings'),
              canEdit: widget.canEditReferences,
              section: ScheduleReferenceSection.branchHours,
            ),
            _ScheduleSettingsView.teacherSchedules => ScheduleReferenceSettings(
              key: const ValueKey('teacher-schedule-settings'),
              canEdit: widget.canEditReferences,
              section: ScheduleReferenceSection.teacherSchedule,
              initialTeacherId: widget.initialTeacherId,
            ),
            _ScheduleSettingsView.groups => _GroupsList(
              searchQuery: _search.text,
              includeArchived: _showArchivedGroups,
              canManageLifecycle: widget.canManageGroups,
            ),
          },
        ),
      ],
    );
  }
}

class _UsersSettings extends StatefulWidget {
  const _UsersSettings({
    required this.currentRole,
    required this.initialSearch,
    required this.canCreatePeople,
  });

  final String currentRole;
  final String? initialSearch;
  final bool canCreatePeople;

  @override
  State<_UsersSettings> createState() => _UsersSettingsState();
}

class _UsersSettingsState extends State<_UsersSettings> {
  final _search = TextEditingController();
  String _section = 'access';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    bool? saved;
    if (_section == 'staff') {
      saved = await showCreateEmployeeSurface(context);
    } else if (_section == 'teachers') {
      saved = await showCreateTeacherSurface(context);
    }
    if (saved != true || !mounted) return;
    final container = ProviderScope.containerOf(context);
    final query = _search.text.trim();
    if (_section == 'staff') {
      container.invalidate(entitiesProvider('employees'));
      container.invalidate(staffSearchProvider(query));
    } else {
      container.invalidate(entitiesProvider('teachers'));
      container.invalidate(teacherSearchProvider(query));
    }
  }

  @override
  Widget build(BuildContext context) {
    final listSection = _section != 'access';
    return Column(
      children: [
        _SettingsToolbar(
          title: 'Пользователи и доступы',
          subtitle: switch (_section) {
            'staff' => 'Сотрудники школы',
            'teachers' => 'Преподаватели и специализации',
            _ => 'Аккаунты, роли и персональные права',
          },
          action: listSection && widget.canCreatePeople
              ? FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(
                    _section == 'staff'
                        ? 'Новый сотрудник'
                        : 'Новый преподаватель',
                  ),
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'access', label: Text('Доступы')),
                      ButtonSegment(value: 'staff', label: Text('Сотрудники')),
                      ButtonSegment(
                        value: 'teachers',
                        label: Text('Преподаватели'),
                      ),
                    ],
                    selected: {_section},
                    onSelectionChanged: (value) {
                      setState(() => _section = value.first);
                    },
                  ),
                ),
              ),
              if (listSection) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded),
                      labelText: 'Поиск',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: switch (_section) {
            'staff' => _EmployeesList(
              searchQuery: _search.text,
              currentRole: widget.currentRole,
            ),
            'teachers' => _TeachersList(searchQuery: _search.text),
            _ => UserRolesWidget(
              currentRole: widget.currentRole,
              initialSearch: widget.initialSearch,
            ),
          },
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
    final saved = await showMagicDialog<bool>(
      context: context,
      builder: (_) => const BranchFormDialog(),
    );
    if (saved == true) {
      invalidateBranchCatalog(ref);
    }
  }

  void _refreshBranches() => invalidateBranchCatalog(ref);

  @override
  Widget build(BuildContext context) {
    final branches = _section == 'branches';
    return Column(
      children: [
        _SettingsToolbar(
          title: branches ? 'Организация' : 'Организационные справочники',
          subtitle: branches
              ? widget.canEdit
                    ? 'Филиалы; аудитории и дисциплины настраиваются внутри филиала'
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SettingsToolbar(
          title: 'Продажи и оплаты',
          subtitle: 'Каталог абонементов',
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
        Expanded(
          child: _PackagesList(
            searchQuery: '',
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
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
            ),
          ),
          ?action,
        ],
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
