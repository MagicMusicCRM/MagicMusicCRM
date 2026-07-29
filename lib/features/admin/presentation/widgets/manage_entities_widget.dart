import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/widgets/lesson_state_badges.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/v7/v7.dart';
import 'create_student_dialog.dart';
import 'create_teacher_dialog.dart';
import 'create_group_dialog.dart';
import 'teacher_detail_dialog.dart';
import 'staff_detail_dialog.dart';
import 'group_detail_dialog.dart';
import 'create_room_dialog.dart';
import 'create_employee_dialog.dart';
import 'branch_form_dialog.dart';
import 'data_quality_widget.dart';
import 'deletion_requests_widget.dart';

part 'manage_entities_people.dart';
part 'manage_entities_scheduling.dart';
part 'manage_entities_facilities.dart';

final entitiesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      table,
    ) async {
      final crm = ref.watch(magicCrmServiceProvider);

      if (table == 'students') {
        final response = await crm.searchStudents(limit: 100);
        return _studentSearchItems(response);
      } else if (table == 'teachers') {
        return crm.listTeachers(limit: 100);
      } else if (table == 'lessons') {
        // Was 50 (the smallest cap on this screen); raised to 100 for parity
        // with the other tabs. A real fix — "load more" / server keyset
        // pagination — is tracked as debt: searchStudents/listLessons expose
        // only `limit`, no offset/cursor, and that query is perf-sensitive.
        return crm.listLessons(limit: 100);
      } else if (table == 'groups') {
        return crm.listGroups(limit: 100);
      } else if (table == 'rooms') {
        return crm.listRooms(limit: 100);
      } else if (table == 'employees') {
        return crm.listStaff(limit: 100);
      } else if (table == 'branches') {
        return crm.listBranches(limit: 100);
      } else if (table == 'subscription_packages') {
        return crm.listSubscriptionPackages(limit: 100);
      }

      return const <Map<String, dynamic>>[];
    });

final studentSearchProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      query,
    ) async {
      final response = await ref
          .watch(magicCrmServiceProvider)
          .searchStudents(q: query, limit: 100);
      return _studentSearchItems(response);
    });

List<Map<String, dynamic>> _studentSearchItems(Map<String, dynamic> response) {
  final items = response['items'];
  if (items is! List) return const <Map<String, dynamic>>[];
  return items.whereType<Map<String, dynamic>>().toList();
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

class ManageEntitiesWidget extends ConsumerStatefulWidget {
  const ManageEntitiesWidget({super.key});

  @override
  ConsumerState<ManageEntitiesWidget> createState() =>
      ManageEntitiesWidgetState();
}

class ManageEntitiesWidgetState extends ConsumerState<ManageEntitiesWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  // Debounces the server-backed search providers (students/teachers/staff)
  // so typing a name doesn't fire one API call per keystroke. Mirrors the
  // leads-board toolbar (leads_actions.dart).
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 10, vsync: this);
  }

  void setTab(int index) {
    if (index >= 0 && index < _tabController.length) {
      _tabController.animateTo(index);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Refresh the clear button instantly; commit the query (and thus the
    // provider refetch) only after the user pauses typing.
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _searchQuery = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(110),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Поиск...',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            _searchDebounce?.cancel();
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              indicatorColor: AppTheme.primaryGold,
              labelColor: AppTheme.primaryGold,
              unselectedLabelColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant,
              tabs: [
                Tab(text: 'Ученики'),
                Tab(text: 'Преподаватели'),
                Tab(text: 'Группы'),
                Tab(text: 'Занятия'),
                Tab(text: 'Аудитории'),
                Tab(text: 'Сотрудники'),
                Tab(text: 'Филиалы'),
                Tab(text: 'Каталог абонементов'),
                Tab(text: 'Качество данных'),
                Tab(text: 'Запросы на удаление'),
              ],
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _StudentsList(searchQuery: _searchQuery),
          _TeachersList(searchQuery: _searchQuery),
          _GroupsList(searchQuery: _searchQuery),
          const _LessonsList(),
          _RoomsList(searchQuery: _searchQuery),
          _EmployeesList(searchQuery: _searchQuery),
          _BranchesList(searchQuery: _searchQuery),
          _PackagesList(searchQuery: _searchQuery),
          const DataQualityWidget(),
          const DeletionRequestsWidget(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createNewEntity(context),
        backgroundColor: AppTheme.primaryGold,
        child: Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  void _createNewEntity(BuildContext context) async {
    // Subscription packages (Каталог) use a v7 sheet, not a Material dialog.
    if (_tabController.index == 7) {
      final saved = await showPackageSheet(context, ref);
      if (saved == true) {
        ref.invalidate(entitiesProvider('subscription_packages'));
      }
      return;
    }

    Widget? dialog;
    switch (_tabController.index) {
      case 0:
        dialog = const CreateStudentDialog();
        break;
      case 1:
        dialog = const CreateTeacherDialog();
        break;
      case 2:
        dialog = const CreateGroupDialog();
        break;
      case 3:
        // No longer creating lessons from here, redirecting to Schedule
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Для создания занятия используйте раздел "Расписание"',
            ),
          ),
        );
        return;
      case 4:
        dialog = const CreateRoomDialog();
        break;
      case 5:
        dialog = const CreateEmployeeDialog();
        break;
      case 6:
        dialog = const BranchFormDialog();
        break;
    }

    if (dialog != null) {
      final res = await showDialog(context: context, builder: (ctx) => dialog!);
      if (res == true) {
        // Invalidate appropriately based on tab index
        if (_tabController.index == 4) {
          ref.invalidate(entitiesProvider('rooms'));
        }
        if (_tabController.index == 2) {
          ref.invalidate(entitiesProvider('groups'));
        }
        if (_tabController.index == 1) {
          ref.invalidate(entitiesProvider('teachers'));
          ref.invalidate(teacherSearchProvider(_searchQuery.trim()));
        }
        if (_tabController.index == 0) {
          ref.invalidate(entitiesProvider('students'));
          ref.invalidate(studentSearchProvider(_searchQuery.trim()));
        }
        if (_tabController.index == 5) {
          ref.invalidate(entitiesProvider('employees'));
          ref.invalidate(staffSearchProvider(_searchQuery.trim()));
        }
        if (_tabController.index == 6) {
          ref.invalidate(entitiesProvider('branches'));
        }
      }
    }
  }
}
