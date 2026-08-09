import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/user_roles_widget.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/v7/v7.dart';
import 'teacher_detail_dialog.dart';
import 'staff_detail_dialog.dart';
import 'group_detail_dialog.dart';
import 'create_employee_dialog.dart';
import 'create_group_dialog.dart';
import 'create_teacher_dialog.dart';
import 'branch_form_dialog.dart';
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Не удалось проверить доступ.')),
        data: (snapshot) =>
            snapshot.allows('system.settings.manage') ||
                snapshot.allows('config.crm.read')
            ? SystemSettingsWorkspace(
                role: snapshot.role,
                initialArea: initialArea,
              )
            : const Center(child: Text('Недостаточно прав для настроек.')),
      ),
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
      } else if (table == 'groups') {
        return crm.listGroups(limit: 100);
      } else if (table == 'rooms') {
        return crm.listRooms(limit: 100);
      } else if (table == 'employees') {
        return crm.listStaff(limit: 100);
      } else if (table == 'branches') {
        return crm.listBranches(limit: 100);
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
    ('schedule', 'Расписание', Icons.calendar_month_rounded),
    ('crm', 'CRM', Icons.view_kanban_rounded),
    ('sales', 'Продажи и оплаты', Icons.payments_rounded),
    ('users', 'Пользователи и доступы', Icons.manage_accounts_rounded),
    ('data', 'Данные и обслуживание', Icons.storage_rounded),
  ];

  late String _area;

  @override
  void initState() {
    super.initState();
    _area = _areas.any((area) => area.$1 == widget.initialArea)
        ? widget.initialArea!
        : 'organization';
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(capabilitySnapshotProvider).asData?.value;
    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final compact = MediaQuery.sizeOf(context).width < 900;
    final content = _content(snapshot);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Text(
              'Настройки системы',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: compact
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: DropdownButtonFormField<String>(
                          menuMaxHeight: 256,
                          initialValue: _area,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Раздел настроек',
                          ),
                          items: [
                            for (final area in _areas)
                              DropdownMenuItem(
                                value: area.$1,
                                child: Text(area.$2),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _area = value);
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
                        width: 248,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          children: [
                            for (final area in _areas)
                              ListTile(
                                selected: _area == area.$1,
                                leading: Icon(area.$3),
                                title: Text(area.$2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onTap: () => setState(() => _area = area.$1),
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
          ),
        ],
      ),
    );
  }

  Widget _content(CapabilitySnapshot snapshot) {
    final canEdit = snapshot.allows('config.crm.edit');
    return switch (_area) {
      'organization' => _OrganizationSettings(
        canEdit: canEdit,
        canCreateBranch:
            canEdit &&
            (snapshot.role == 'director' || snapshot.role == 'system_admin'),
      ),
      'schedule' => _ScheduleSettings(
        canEditReferences: canEdit,
        canManageGroups: snapshot.allows('schedule.lesson.write'),
      ),
      'crm' =>
        snapshot.allows('config.crm.read')
            ? const CrmConfigurationWorkspace()
            : const _SettingsDenied(
                text:
                    'Директор может открыть CRM-настройки после выдачи права.',
              ),
      'sales' => _SalesSettings(
        canEdit: snapshot.allows('commerce.package.manage'),
      ),
      'users' => _UsersSettings(
        currentRole: widget.role,
        initialSearch: widget.initialUserSearch,
        canCreatePeople: snapshot.allows('crm.client.write'),
      ),
      'data' => const _DataSettings(),
      _ => const SizedBox.shrink(),
    };
  }
}

class _ScheduleSettings extends StatefulWidget {
  const _ScheduleSettings({
    required this.canEditReferences,
    required this.canManageGroups,
  });

  final bool canEditReferences;
  final bool canManageGroups;

  @override
  State<_ScheduleSettings> createState() => _ScheduleSettingsState();
}

enum _ScheduleSettingsView { branchHours, teacherSchedules, groups }

class _ScheduleSettingsState extends State<_ScheduleSettings> {
  final _search = TextEditingController();
  _ScheduleSettingsView _view = _ScheduleSettingsView.branchHours;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final saved = await showCreateGroupSurface(context);
    if (saved == true && mounted) {
      ProviderScope.containerOf(context).invalidate(entitiesProvider('groups'));
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
            ),
            _ScheduleSettingsView.groups => _GroupsList(
              searchQuery: _search.text,
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
      saved = await showCreateEmployeeSurface(
        context,
        currentRole: widget.currentRole,
      );
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
  });

  final bool canEdit;
  final bool canCreateBranch;

  @override
  ConsumerState<_OrganizationSettings> createState() =>
      _OrganizationSettingsState();
}

class _OrganizationSettingsState extends ConsumerState<_OrganizationSettings> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const BranchFormDialog(),
    );
    if (saved == true) {
      ref.invalidate(entitiesProvider('branches'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SettingsToolbar(
          title: 'Организация',
          subtitle: widget.canEdit
              ? 'Филиалы; аудитории настраиваются внутри филиала'
              : 'Только просмотр назначенных филиалов',
          action: widget.canCreateBranch
              ? FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Новый филиал'),
                )
              : null,
        ),
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
            ],
          ),
        ),
        Expanded(
          child: _BranchesList(
            searchQuery: _search.text,
            canEdit: widget.canEdit,
          ),
        ),
      ],
    );
  }
}

class _SalesSettings extends ConsumerWidget {
  const _SalesSettings({required this.canEdit});

  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _SettingsToolbar(
          title: 'Продажи и оплаты',
          subtitle: 'Каталог абонементов',
          action: canEdit
              ? FilledButton.icon(
                  onPressed: () async {
                    if (await showPackageSheet(context, ref) == true) {
                      invalidateSubscriptionPackageCatalog(ref);
                    }
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Новый абонемент'),
                )
              : null,
        ),
        Expanded(
          child: _PackagesList(searchQuery: '', canEdit: canEdit),
        ),
      ],
    );
  }
}

class _DataSettings extends StatelessWidget {
  const _DataSettings();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: const [
          _SettingsToolbar(
            title: 'Данные и обслуживание',
            subtitle: 'Контроль качества и запросы на удаление',
          ),
          TabBar(
            tabs: [
              Tab(text: 'Качество данных'),
              Tab(text: 'Запросы на удаление'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [DataQualityWidget(), DeletionRequestsWidget()],
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
