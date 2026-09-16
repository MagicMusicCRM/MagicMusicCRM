import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/teacher_detail_dialog.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_dialog.dart';

class PeopleSearchAction extends ConsumerWidget {
  const PeopleSearchAction({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(capabilitySnapshotProvider).asData?.value;
    if (access == null ||
        !access.allows('crm.client.read.basic') ||
        !const {
          'admin',
          'manager',
          'director',
          'system_admin',
        }.contains(access.role)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      key: const ValueKey('global-people-search'),
      tooltip: 'Найти человека',
      icon: const Icon(Icons.person_search_outlined),
      onPressed: () async {
        final person = await showMagicDialog<_Person>(
          context: context,
          builder: (_) => const _PeopleSearch(),
        );
        if (person == null || !context.mounted) return;
        final access = ref.read(capabilitySnapshotProvider).asData?.value;
        if (access == null || !access.allows('crm.client.read.basic')) return;
        try {
          if (person.type == 'teacher') {
            final fresh = await ref
                .read(magicCrmServiceProvider)
                .getTeacher(person.id);
            if (context.mounted) await TeacherDetailDialog.show(context, fresh);
          } else if (person.type == 'staff') {
            await StaffDetailDialog.show(
              context,
              person.row,
              currentRole: access.role,
            );
          } else {
            await openEntityLink(
              context,
              ref,
              EntityLink.fromJson({
                'entityType': person.type,
                'entityId': person.id,
              }),
            );
          }
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  userErrorMessage(
                    error,
                    fallback: 'Не удалось открыть карточку',
                  ),
                ),
              ),
            );
          }
        }
      },
    );
  }
}

class _PeopleSearch extends ConsumerStatefulWidget {
  const _PeopleSearch();
  @override
  ConsumerState<_PeopleSearch> createState() => _PeopleSearchState();
}

typedef _Person = ({
  String type,
  String id,
  String name,
  String context,
  Map<String, dynamic> row,
});

class _PeopleSearchState extends ConsumerState<_PeopleSearch> {
  final _query = TextEditingController();
  Timer? _debounce;
  int _sequence = 0;
  bool _loading = false;
  Object? _error;
  List<_Person> _items = [];
  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    final sequence = ++_sequence;
    setState(() {
      _items = [];
      _error = null;
      _loading = value.trim().length >= 2;
    });
    if (!_loading) return;
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(value.trim(), sequence),
    );
  }

  Future<void> _search(String query, int sequence) async {
    try {
      final access = ref.read(capabilitySnapshotProvider).asData?.value;
      if (access == null || !access.allows('crm.client.read.basic')) return;
      final crm = ref.read(magicCrmServiceProvider);
      // These existing endpoints retain their own role, branch and contact scopes.
      final sources = await Future.wait([
        crm.searchClientRefs(q: query, limit: 25),
        crm.listTeachers(q: query, limit: 25),
        crm.listStaff(q: query, limit: 25),
      ]);
      if (!mounted || sequence != _sequence) return;
      final result = <_Person>[];
      for (final row in sources[0]) {
        final links = row['links'];
        final converted = links is List
            ? links
                  .whereType<Map>()
                  .where((link) => link['rel'] == 'convertedStudent')
                  .firstOrNull
            : null;
        final clientRef = converted?['ref'] ?? row['ref'];
        if (clientRef is! Map) continue;
        final type = clientRef['type']?.toString(),
            id = clientRef['id']?.toString();
        if (id == null || (type != 'student' && type != 'lead')) continue;
        result.add((
          type: type!,
          id: id,
          name: (row['displayName'] ?? row['name'] ?? row['label'] ?? 'Клиент')
              .toString(),
          context: type == 'student' ? 'Ученик' : 'Лид',
          row: row,
        ));
      }
      for (var source = 1; source < 3; source++) {
        for (final row in sources[source]) {
          final id = row['id']?.toString();
          if (id == null) continue;
          final name = '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'
              .trim();
          result.add((
            type: source == 1 ? 'teacher' : 'staff',
            id: id,
            name: name.isEmpty ? 'Без имени' : name,
            context: source == 1
                ? 'Преподаватель'
                : switch (row['role']) {
                    'admin' => 'Администратор',
                    'manager' => 'Менеджер',
                    'director' => 'Директор',
                    _ => 'Сотрудник',
                  },
            row: row,
          ));
        }
      }
      final unique = <String, _Person>{
        for (final item in result) '${item.type}:${item.id}': item,
      };
      setState(() {
        _items = unique.values.toList();
        _loading = false;
      });
    } catch (error) {
      if (mounted && sequence == _sequence) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  void _open(_Person person) => Navigator.pop(context, person);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Найти человека'),
    content: SizedBox(
      width: 620,
      height: 480,
      child: Column(
        children: [
          TextField(
            controller: _query,
            autofocus: true,
            onChanged: _changed,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              if (_items.isNotEmpty) _open(_items.first);
            },
            decoration: const InputDecoration(
              labelText: 'Имя или фамилия',
              helperText: 'Ученики, лиды, преподаватели и сотрудники',
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          userErrorMessage(
                            _error,
                            fallback: 'Не удалось выполнить поиск',
                          ),
                        ),
                        TextButton(
                          onPressed: () => _changed(_query.text),
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  )
                : _items.isEmpty
                ? Center(
                    child: Text(
                      _query.text.trim().length < 2
                          ? 'Введите минимум 2 символа'
                          : 'Ничего не найдено',
                    ),
                  )
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final person = _items[index];
                      return ListTile(
                        title: Text(person.name),
                        subtitle: Text(person.context),
                        leading: Icon(
                          person.type == 'teacher'
                              ? Icons.school_outlined
                              : Icons.person_outline,
                        ),
                        onTap: () => _open(person),
                      );
                    },
                  ),
          ),
          if (_items.length >= 25)
            const Text(
              'Уточните запрос, если нужной записи нет в первых результатах',
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Закрыть'),
      ),
    ],
  );
}
