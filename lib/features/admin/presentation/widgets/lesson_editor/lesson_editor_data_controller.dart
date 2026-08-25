import '../../../../../core/services/magic_crm_service.dart';
import '../lesson_decision/lesson_decision_models.dart';
import 'lesson_editor_models.dart';

typedef LessonEditorRowsById =
    Future<List<Map<String, dynamic>>> Function(String id);
typedef LessonEditorRows = Future<List<Map<String, dynamic>>> Function();
typedef LessonEditorCatalogLoader =
    Future<LessonDecisionCatalog> Function(String branchId);
typedef LessonEditorClientResolver =
    Future<Map<String, dynamic>?> Function({
      required String type,
      required String id,
    });

class LessonEditorLoadPatch {
  const LessonEditorLoadPatch({
    required this.branchId,
    required this.draft,
    required this.references,
  });

  final String? branchId;
  final LessonEditorDraft? draft;
  final LessonEditorReferenceState references;
}

abstract interface class LessonEditorDataLoader {
  Future<LessonEditorLoadPatch?> loadInitial(LessonEditorSession session);

  Future<LessonEditorLoadPatch?> selectClient(
    LessonClientRef? client, {
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  });

  Future<LessonEditorLoadPatch?> loadBranch(
    String branchId, {
    LessonEditorDraft? draft,
    LessonEditorReferenceState references =
        const LessonEditorReferenceState.empty(),
  });

  Future<LessonEditorLoadPatch?> loadSubscriptions(
    LessonClientRef? client, {
    LessonEditorDraft? draft,
    LessonEditorReferenceState references =
        const LessonEditorReferenceState.empty(),
  });

  void invalidateClientSelection();
}

class LessonEditorDataController implements LessonEditorDataLoader {
  LessonEditorDataController.forTesting({
    required LessonEditorRowsById listRooms,
    required LessonEditorCatalogLoader loadCatalog,
    required LessonEditorRowsById listSubscriptions,
    LessonEditorRows listTeachers = _emptyRows,
    LessonEditorRows listBranches = _emptyRows,
    LessonEditorRows searchClients = _emptyRows,
    LessonEditorClientResolver resolveClient = _emptyResolvedClient,
  }) : _listRooms = listRooms,
       _loadCatalog = loadCatalog,
       _listSubscriptions = listSubscriptions,
       _listTeachers = listTeachers,
       _listBranches = listBranches,
       _searchClients = searchClients,
       _resolveClient = resolveClient;

  LessonEditorDataController.fromCrm(MagicCrmService crm)
    : this.forTesting(
        listRooms: (branchId) => crm.listRooms(branchId: branchId, limit: 100),
        loadCatalog: (branchId) async => LessonDecisionCatalog.fromJson(
          await crm.getLessonDecisionCatalog(branchId: branchId),
          LessonDecisionOperation.settle,
        ),
        listSubscriptions: (studentId) =>
            crm.listSubscriptions(studentId: studentId, limit: 50),
        listTeachers: () => crm.listTeachers(limit: 100),
        listBranches: () => crm.listBranches(limit: 100),
        searchClients: () => crm.searchClientRefs(limit: 50),
        resolveClient: ({required type, required id}) =>
            crm.resolveClientRef(type: type, id: id),
      );

  final LessonEditorRowsById _listRooms;
  final LessonEditorCatalogLoader _loadCatalog;
  final LessonEditorRowsById _listSubscriptions;
  final LessonEditorRows _listTeachers;
  final LessonEditorRows _listBranches;
  final LessonEditorRows _searchClients;
  final LessonEditorClientResolver _resolveClient;

  int _branchRevision = 0;
  int _catalogRevision = 0;
  int _subscriptionRevision = 0;
  int _clientRevision = 0;
  String? _activeBranchId;
  String? _activeStudentId;
  String? _activeClientKey;

  @override
  Future<LessonEditorLoadPatch?> loadInitial(
    LessonEditorSession session,
  ) async {
    final clientRevision = _clientRevision;
    final resolved = await _resolveInitialClient(session);
    if (clientRevision != _clientRevision) return null;
    final selectedClient = resolved.client;
    _activeClientKey = selectedClient?.key;

    final results = await Future.wait<List<Map<String, dynamic>>>([
      _listTeachers(),
      _listBranches(),
      _searchClients(),
    ]);
    if (clientRevision != _clientRevision) return null;

    final teachers = _teacherItems(results[0]);
    final branches = _simpleItems(results[1]);
    final clients = _withSelectedClient(
      _clientItems(results[2]),
      selectedClient,
      resolved.row,
    );
    final branchId = _initialBranchId(
      branches,
      clientBranchId: selectedClient?.branchId,
      seededBranchId: session.draft.branchId,
    );
    _activeBranchId = branchId;
    final draft = _initialDraft(
      session.draft,
      selectedClient,
      branchId,
      teachers,
    );
    final references = LessonEditorReferenceState(
      teachers: teachers,
      clients: clients,
      branches: branches,
      rooms: const [],
      subscriptions: const [],
      catalog: null,
    );

    final branchPatch = branchId == null
        ? LessonEditorLoadPatch(
            branchId: null,
            draft: draft,
            references: references,
          )
        : await loadBranch(branchId, draft: draft, references: references);
    if (branchPatch == null ||
        !_ownsClient(clientRevision, selectedClient, branchId)) {
      return null;
    }

    final subscriptionPatch = await loadSubscriptions(
      selectedClient,
      draft: branchPatch.draft,
      references: branchPatch.references,
    );
    if (subscriptionPatch == null ||
        !_ownsClient(clientRevision, selectedClient, branchId)) {
      return null;
    }
    return subscriptionPatch;
  }

  @override
  Future<LessonEditorLoadPatch?> selectClient(
    LessonClientRef? client, {
    required LessonEditorDraft draft,
    required LessonEditorReferenceState references,
  }) async {
    final clientRevision = ++_clientRevision;
    _activeClientKey = client?.key;
    final transition = _clientSelectionTransition(client, draft, references);
    final selectedBranchId = transition.branchId;
    _activeBranchId = selectedBranchId;
    var nextDraft = transition.draft;
    var nextReferences = transition.references;

    if (transition.loadsBranch) {
      final branchPatch = await loadBranch(
        selectedBranchId!,
        draft: nextDraft,
        references: nextReferences,
      );
      if (branchPatch == null) return null;
      nextDraft = branchPatch.draft!;
      nextReferences = branchPatch.references;
    }
    if (!_ownsClient(clientRevision, client, selectedBranchId)) {
      return null;
    }

    final subscriptionPatch = await loadSubscriptions(
      client,
      draft: nextDraft,
      references: nextReferences,
    );
    if (subscriptionPatch == null ||
        !_ownsClient(clientRevision, client, selectedBranchId)) {
      return null;
    }
    return subscriptionPatch;
  }

  @override
  Future<LessonEditorLoadPatch?> loadBranch(
    String branchId, {
    LessonEditorDraft? draft,
    LessonEditorReferenceState references =
        const LessonEditorReferenceState.empty(),
  }) async {
    final branchRevision = ++_branchRevision;
    final catalogRevision = ++_catalogRevision;
    _activeBranchId = branchId;
    final results = await Future.wait<Object>([
      _listRooms(branchId),
      _loadCatalog(branchId),
    ]);
    if (branchRevision != _branchRevision ||
        catalogRevision != _catalogRevision ||
        _activeBranchId != branchId) {
      return null;
    }

    final rooms = _roomItems(
      results[0] as List<Map<String, dynamic>>,
      branchId,
    );
    var nextDraft = draft?.copyWith(branchId: branchId);
    if (nextDraft?.roomId case final roomId? when !_containsId(rooms, roomId)) {
      nextDraft = nextDraft!.copyWith(roomId: null);
    }
    return LessonEditorLoadPatch(
      branchId: branchId,
      draft: nextDraft,
      references: _copyReferences(
        references,
        rooms: rooms,
        catalog: results[1] as LessonDecisionCatalog,
      ),
    );
  }

  @override
  Future<LessonEditorLoadPatch?> loadSubscriptions(
    LessonClientRef? client, {
    LessonEditorDraft? draft,
    LessonEditorReferenceState references =
        const LessonEditorReferenceState.empty(),
  }) async {
    final subscriptionRevision = ++_subscriptionRevision;
    final studentId = client?.type == 'student' ? client?.id : null;
    _activeStudentId = studentId;
    if (studentId == null) {
      return LessonEditorLoadPatch(
        branchId: draft?.branchId,
        draft: draft?.copyWith(subscriptionId: null),
        references: _copyReferences(references, subscriptions: const []),
      );
    }

    final rows = await _listSubscriptions(studentId);
    if (subscriptionRevision != _subscriptionRevision ||
        _activeStudentId != studentId) {
      return null;
    }
    final subscriptions = _subscriptionItems(rows);
    var nextDraft = draft;
    if (nextDraft?.subscriptionId case final subscriptionId?
        when !_containsId(subscriptions, subscriptionId)) {
      nextDraft = nextDraft!.copyWith(subscriptionId: null);
    }
    return LessonEditorLoadPatch(
      branchId: draft?.branchId,
      draft: nextDraft,
      references: _copyReferences(references, subscriptions: subscriptions),
    );
  }

  @override
  void invalidateClientSelection() {
    _clientRevision += 1;
    _branchRevision += 1;
    _catalogRevision += 1;
    _subscriptionRevision += 1;
    _activeClientKey = null;
    _activeBranchId = null;
    _activeStudentId = null;
  }

  Future<({LessonClientRef? client, Map<String, dynamic>? row})>
  _resolveInitialClient(LessonEditorSession session) async {
    final seededClient = session.seededClient ?? session.draft.client;
    if (session.isEdit ||
        seededClient == null ||
        seededClient.type == 'group') {
      return (client: seededClient, row: null);
    }
    final row = await _resolveClient(
      type: seededClient.type,
      id: seededClient.id,
    );
    return (
      client: row == null
          ? seededClient
          : _clientFromRow(row, fallback: seededClient),
      row: row,
    );
  }

  bool _ownsClient(int revision, LessonClientRef? client, String? branchId) =>
      revision == _clientRevision &&
      _activeClientKey == client?.key &&
      _activeBranchId == branchId;
}

Future<List<Map<String, dynamic>>> _emptyRows() async => const [];

// Kept as the symmetric no-op seam for ID-scoped loaders in this boundary.
// ignore: unused_element
Future<List<Map<String, dynamic>>> _emptyRowsById(String _) async => const [];

Future<Map<String, dynamic>?> _emptyResolvedClient({
  required String type,
  required String id,
}) async => null;

LessonEditorReferenceState _copyReferences(
  LessonEditorReferenceState source, {
  List<LessonEditorReferenceItem>? teachers,
  List<LessonEditorReferenceItem>? clients,
  List<LessonEditorReferenceItem>? branches,
  List<LessonEditorReferenceItem>? rooms,
  List<LessonEditorReferenceItem>? subscriptions,
  Object? catalog = _keepCatalog,
}) => LessonEditorReferenceState(
  teachers: teachers ?? source.teachers,
  clients: clients ?? source.clients,
  branches: branches ?? source.branches,
  rooms: rooms ?? source.rooms,
  subscriptions: subscriptions ?? source.subscriptions,
  catalog: identical(catalog, _keepCatalog)
      ? source.catalog
      : catalog as LessonDecisionCatalog?,
);

const _keepCatalog = Object();

({
  LessonEditorDraft draft,
  LessonEditorReferenceState references,
  String? branchId,
  bool loadsBranch,
})
_clientSelectionTransition(
  LessonClientRef? client,
  LessonEditorDraft draft,
  LessonEditorReferenceState references,
) {
  final clientBranchId = client?.branchId;
  final switchesBranch =
      _containsId(references.branches, clientBranchId) &&
      clientBranchId != draft.branchId;
  if (!switchesBranch) {
    return (
      draft: draft.copyWith(client: client),
      references: references,
      branchId: draft.branchId,
      loadsBranch: false,
    );
  }
  return (
    draft: draft.copyWith(
      client: client,
      branchId: clientBranchId,
      teacherId: null,
      roomId: null,
      settlementTypeKey: null,
      compensationRuleKey: null,
    ),
    references: _copyReferences(references, rooms: const [], catalog: null),
    branchId: clientBranchId,
    loadsBranch: true,
  );
}

List<LessonEditorReferenceItem> _withSelectedClient(
  List<LessonEditorReferenceItem> clients,
  LessonClientRef? selectedClient,
  Map<String, dynamic>? resolvedRow,
) {
  if (selectedClient == null ||
      clients.any((item) => item.id == selectedClient.key)) {
    return clients;
  }
  final row = resolvedRow ?? _clientRow(selectedClient)!;
  return List.unmodifiable([
    _clientItem(row, fallback: selectedClient),
    ...clients,
  ]);
}

String? _initialBranchId(
  List<LessonEditorReferenceItem> branches, {
  required String? clientBranchId,
  required String? seededBranchId,
}) {
  if (_containsId(branches, clientBranchId)) return clientBranchId;
  if (_containsId(branches, seededBranchId)) return seededBranchId;
  return branches.firstOrNull?.id;
}

LessonEditorDraft _initialDraft(
  LessonEditorDraft source,
  LessonClientRef? client,
  String? branchId,
  List<LessonEditorReferenceItem> teachers,
) {
  final draft = source.copyWith(client: client, branchId: branchId);
  return _isTeacherEligible(teachers, draft.teacherId, branchId)
      ? draft
      : draft.copyWith(teacherId: null);
}

List<LessonEditorReferenceItem> _teacherItems(
  List<Map<String, dynamic>> rows,
) => List.unmodifiable([
  for (final row in rows)
    if (_text(row['id']) case final id?)
      LessonEditorReferenceItem(
        id: id,
        label: _teacherLabel(row),
        raw: _immutableRow(row),
        status: _text(row['status']),
        assignedBranchIds: Set.unmodifiable(_assignedBranchIds(row)),
      ),
]);

List<LessonEditorReferenceItem> _simpleItems(List<Map<String, dynamic>> rows) =>
    List.unmodifiable([
      for (final row in rows)
        if (_text(row['id']) case final id?)
          LessonEditorReferenceItem(
            id: id,
            label: _text(row['name']) ?? 'Без названия',
            raw: _immutableRow(row),
            status: _text(row['status'] ?? row['lifecycle_state']),
          ),
    ]);

List<LessonEditorReferenceItem> _clientItems(List<Map<String, dynamic>> rows) =>
    List.unmodifiable([for (final row in rows) ?_clientItemOrNull(row)]);

LessonEditorReferenceItem? _clientItemOrNull(Map<String, dynamic> row) {
  final client = _clientFromRow(row);
  return client == null ? null : _clientItem(row, fallback: client);
}

LessonEditorReferenceItem _clientItem(
  Map<String, dynamic> row, {
  required LessonClientRef fallback,
}) {
  final client = _clientFromRow(row, fallback: fallback)!;
  return LessonEditorReferenceItem(
    id: client.key,
    label: client.label,
    raw: _immutableRow(row),
    branchId: client.branchId,
    status: _text(row['lifecycleState'] ?? row['lifecycle_state']),
  );
}

List<LessonEditorReferenceItem> _roomItems(
  List<Map<String, dynamic>> rows,
  String branchId,
) => List.unmodifiable([
  for (final row in rows)
    if (_text(row['id']) case final id?
        when _text(row['branch_id'] ?? row['branchId']) == branchId &&
            _text(row['lifecycle_state'] ?? row['lifecycleState']) !=
                'archived')
      LessonEditorReferenceItem(
        id: id,
        label: _text(row['name']) ?? 'Без названия',
        raw: _immutableRow(row),
        branchId: branchId,
        status: _text(row['lifecycle_state'] ?? row['lifecycleState']),
      ),
]);

List<LessonEditorReferenceItem> _subscriptionItems(
  List<Map<String, dynamic>> rows,
) => List.unmodifiable([
  for (final row in rows)
    if (_text(row['id']) case final id? when _text(row['status']) == 'active')
      LessonEditorReferenceItem(
        id: id,
        label: _subscriptionLabel(row),
        raw: _immutableRow(row),
        status: 'active',
      ),
]);

LessonClientRef? _clientFromRow(
  Map<String, dynamic> row, {
  LessonClientRef? fallback,
}) {
  final ref = row['ref'];
  final type = ref is Map ? _text(ref['type']) : null;
  final id = ref is Map ? _text(ref['id']) : null;
  if ((type == null || id == null) && fallback == null) return null;
  return LessonClientRef(
    type: type ?? fallback!.type,
    id: id ?? fallback!.id,
    label: _text(row['label']) ?? fallback?.label ?? 'Клиент без имени',
    branchId: _text(row['branchId'] ?? row['branch_id']) ?? fallback?.branchId,
  );
}

Map<String, dynamic>? _clientRow(LessonClientRef? client) => client == null
    ? null
    : {
        'ref': {'type': client.type, 'id': client.id},
        'label': client.label,
        if (client.branchId != null) 'branchId': client.branchId,
      };

bool _containsId(List<LessonEditorReferenceItem> rows, String? id) =>
    id != null && rows.any((row) => row.id == id);

bool _isTeacherEligible(
  List<LessonEditorReferenceItem> teachers,
  String? teacherId,
  String? branchId,
) {
  if (teacherId == null) return true;
  if (branchId == null) return false;
  return teachers.any(
    (teacher) =>
        teacher.id == teacherId &&
        teacher.status == 'active' &&
        teacher.assignedBranchIds.contains(branchId),
  );
}

Iterable<String> _assignedBranchIds(Map<String, dynamic> teacher) sync* {
  final assignments = teacher['assigned_branches'];
  if (assignments is! List) return;
  for (final assignment in assignments.whereType<Map>()) {
    final id = _text(assignment['id']);
    if (id != null) yield id;
  }
}

String _teacherLabel(Map<String, dynamic> teacher) {
  final profile = teacher['profiles'];
  var label = [
    _text(teacher['first_name']),
    _text(teacher['last_name']),
  ].whereType<String>().join(' ');
  if (label.isEmpty && profile is Map) {
    label = [
      _text(profile['first_name']),
      _text(profile['last_name']),
    ].whereType<String>().join(' ');
  }
  return label.isEmpty ? 'Без имени' : label;
}

String _subscriptionLabel(Map<String, dynamic> subscription) {
  final name = _text(subscription['package_name']) ?? 'Абонемент';
  final total = subscription['lessons_total'];
  final used = subscription['lessons_used'];
  final balance = total is num && used is num ? total - used : null;
  return balance == null ? name : '$name · остаток $balance';
}

Map<String, dynamic> _immutableRow(Map<String, dynamic> row) =>
    Map.unmodifiable({
      for (final entry in row.entries) entry.key: _immutableValue(entry.value),
    });

Object? _immutableValue(Object? value) {
  if (value is Map) {
    return Map.unmodifiable({
      for (final entry in value.entries)
        entry.key: _immutableValue(entry.value),
    });
  }
  if (value is List) {
    return List.unmodifiable([for (final item in value) _immutableValue(item)]);
  }
  if (value is Set) {
    return Set.unmodifiable({for (final item in value) _immutableValue(item)});
  }
  return value;
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
