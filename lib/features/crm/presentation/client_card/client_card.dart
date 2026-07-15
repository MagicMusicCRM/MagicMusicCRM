import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/features/admin/presentation/providers/schedule_navigation_provider.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/top_up_dialog.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/client_app_user_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:magic_music_crm/core/utils/status_color.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'client_card_aggregation.dart';
import 'client_card_sheets.dart';
import 'client_card_ui.dart';
import 'student_schedule_section.dart';

part 'client_card_widgets.dart';

/// Unified «Карточка клиента». Phase 1 hosts the full lead experience (5 tabs:
/// Инфо / Задачи / Комментарии / Семья / История). Behaviour is equivalent to
/// the former `LeadDetailDialog`; the public surface gained an [entityType]
/// discriminator (default `'lead'`) so later phases can host students too.
///
/// [allStatuses] is optional — when omitted the card resolves the lead status
/// list itself via [leadStatusesProvider] so callers (e.g. deep links, the
/// launcher) don't have to pre-fetch it.
class ClientCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> lead;
  final List<StatusRecord>? allStatuses;
  final String entityType;

  const ClientCard({
    super.key,
    required this.lead,
    this.allStatuses,
    this.entityType = 'lead',
  });

  @override
  ConsumerState<ClientCard> createState() => _ClientCardState();
}

class _ClientCardState extends ConsumerState<ClientCard>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _leadData;
  late TextEditingController _notesCtrl;
  late TextEditingController _commentCtrl;
  // Тип нового комментария (0037): admin_comment | teacher_note. Переключатель
  // виден staff-ролям и только когда комментарий уйдёт на ученик-половину.
  String _commentKind = 'admin_comment';
  // Личный счёт (KVA-235): 0 = Приход, 1 = Расход; ключ перегружает FutureBuilder.
  int _ledgerTab = 0;
  int _ledgerRefreshKey = 0;
  // Resolved status list: either the one passed in or self-fetched.
  List<StatusRecord> _statuses = const [];
  bool _saving = false;
  bool _converting = false;
  bool _loadingCard = true;
  int _commentsRefreshKey = 0;
  Map<String, dynamic>? _leadCard;
  List<Map<String, dynamic>> _duplicateCandidates = [];
  bool _loadingDuplicates = true;
  bool _dirty = false;
  List<Map<String, dynamic>> _statusHistory = [];
  bool _loadingHistory = true;
  Map<String, dynamic>? _family;
  bool _loadingFamily = true;
  // True while a family add/remove write is in flight — disables the family
  // action controls so a double-tap can't fire two mutations.
  bool _familyBusy = false;
  // True while a task create is in flight — disables the add-task control.
  bool _addingTask = false;
  // True once the user has edited a field but not saved — used to warn before
  // discarding unsaved changes on close.
  bool _edited = false;
  String? _duplicateDecisionId;

  // Adaptive segmented tab bar. Leads keep the original 5 tabs; students get the
  // ported student tab set (Инфо / Задачи / Комментарии / Семья / Занятия /
  // Оплаты / Инвойсы / Документы / История / Прогресс). A converted client
  // (lead → student) reuses the student tab set — its body folds in the lead
  // Инфо/source section and the merged comments / tasks / history.
  int _tabIndex = 0;

  // ── Aggregation (Phase 4) ─────────────────────────────────────────────────
  // The card opens for one entity (widget.entityType / widget.lead['id']) but a
  // converted client owns BOTH a lead and a student record. We resolve the
  // counterpart on load and surface them in one card.
  //
  // `_mode` starts from the open entity and is upgraded to `converted` only once
  // a counterpart is actually resolved. `_resolvedLeadId` / `_resolvedStudentId`
  // are the ids the lead-side / student-side fetches run against (which may
  // differ from the open entity id when the counterpart is loaded).
  ClientMode _mode = ClientMode.leadOnly;
  String? _resolvedLeadId;
  String? _resolvedStudentId;

  // True while the card renders the student layout (plain student OR converted).
  // Drives the header, tab set and action bar.
  bool get _isStudent => _mode.hasStudentHalf;
  bool get _isConverted => _mode.isConverted;

  // The id of the entity the card was opened for (unchanged from Phase 1/2).
  String get _entityId => widget.lead['id'].toString();

  // Effective ids for each half once resolution settles. Fall back to the open
  // entity id so the single-side modes behave exactly as before.
  String get _studentId =>
      _resolvedStudentId ?? (widget.entityType == 'student' ? _entityId : '');
  String get _leadId =>
      _resolvedLeadId ?? (widget.entityType == 'lead' ? _entityId : '');

  static const List<(IconData, String)> _leadTabs = [
    (Icons.info_outline_rounded, 'Инфо'),
    (Icons.task_alt_rounded, 'Задачи'),
    (Icons.forum_outlined, 'Комментарии'),
    (Icons.people_alt_outlined, 'Семья'),
    (Icons.history_rounded, 'История'),
  ];

  static const List<(IconData, String)> _studentTabs = [
    (Icons.info_outline_rounded, 'Инфо'),
    (Icons.task_alt_rounded, 'Задачи'),
    (Icons.forum_outlined, 'Комментарии'),
    (Icons.people_alt_outlined, 'Семья'),
    (Icons.event_note_rounded, 'Занятия'),
    (Icons.account_balance_wallet_rounded, 'Оплаты'),
    (Icons.receipt_long_rounded, 'Инвойсы'),
    (Icons.description_rounded, 'Документы'),
    (Icons.history_rounded, 'История'),
    (Icons.auto_graph_rounded, 'Прогресс'),
  ];

  List<(IconData, String)> get _tabs => _isStudent ? _studentTabs : _leadTabs;

  // The (entityType, entityId) pairs whose comment / task / history streams the
  // card aggregates. A single-side card returns one pair; a converted client
  // returns both halves so merged lists de-dup and origin-badge correctly.
  List<ClientHalfRef> get _halfRefs => [
    if (_mode.hasLeadHalf && _leadId.isNotEmpty)
      (entityType: 'lead', entityId: _leadId),
    if (_mode.hasStudentHalf && _studentId.isNotEmpty)
      (entityType: 'student', entityId: _studentId),
  ];

  // ── Student state (entityType == 'student') ───────────────────────────────
  // Loaded from `getStudentCard` (+ a family fetch). Each section is isolated so
  // a single failed call never blanks the whole card.
  Map<String, dynamic>? _student;
  Map<String, dynamic>? _balance;
  List<Map<String, dynamic>> _subscriptions = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _lessons = [];
  List<Map<String, dynamic>> _studentTasks = [];
  // Unified comment stream for the Прогресс tab ([PROGRESS]-prefixed notes) and
  // the «История» merge — the «Комментарии» tab reads live via [_CommentsList].
  List<Map<String, dynamic>> _studentComments = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _expectedPayments = [];
  bool _loadingStudent = true;
  String? _studentError;
  bool _realtimeRefreshQueued = false;

  Future<void> _handleClose() async {
    if (!_edited) {
      Navigator.pop(context, _dirty ? true : null);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Несохранённые изменения'),
        content: const Text(
          'Изменения не сохранены. Закрыть карточку без сохранения?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Остаться'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Закрыть без сохранения'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      Navigator.pop(context, _dirty ? true : null);
    }
  }

  List<Map<String, dynamic>> _branches = [];
  bool _loadingMetadata = true;
  List<CrmCustomFieldDefinition> _customFieldSchema = const [];
  // KVA-234: справочник дисциплин (GET /crm/disciplines) для мультивыбора.
  List<Map<String, dynamic>> _disciplineOptions = const [];
  // KVA-234: заявки лида (app.lead_applications) — секция «Заявки».
  List<Map<String, dynamic>> _leadApplications = const [];

  static const Set<String> _systemOnlyCustomFieldKeys = {
    'hollihopid',
    'hollihop_id',
    'hollihopstudentid',
    'hollihop_student_id',
    'externalid',
    'external_id',
    'sourceleadid',
    'source_lead_id',
    'leadid',
    'lead_id',
  };

  static const Set<String> _commonClientCustomFieldKeys = {
    'middleName',
    'gender',
    'birthday',
    'source',
    'adSource',
    'requestType',
    'learningGoal',
    'discipline',
    'level',
    'category',
    'lessonType',
    'responsible',
    'preferredSchedule',
    'contactPersonName',
    'contactPersonRelation',
    'contactPersonPhone',
    'contactPersonEmail',
    // KVA-234: массивы contactPersons/disciplines живут в custom_data и в
    // converted-режиме зеркалятся между лид- и ученик-половинами как общие.
    'contactPersons',
    'disciplines',
    'address',
    'applicationData',
  };

  // KVA-234: одиночные contactPerson*-поля заменены редактором списка
  // «Контактные лица», discipline — мультивыбором чипами; из общей формы
  // custom-полей они исключаются.
  static const Set<String> _customKeysWithDedicatedEditor = {
    'contactPersonName',
    'contactPersonRelation',
    'contactPersonPhone',
    'contactPersonEmail',
    'discipline',
  };

  static const Set<String> _studentOnlyCustomFieldKeys = {
    'workplace',
    'position',
    'contractStatus',
    'cabinetStatus',
    'blacklisted',
    'noEmail',
    'individualPrice',
  };

  static const List<String> _studentStatusOptions = [
    'Занимается',
    'Закончил обучение',
    'Саморегистрация',
  ];

  @override
  void initState() {
    super.initState();
    _leadData = Map<String, dynamic>.from(widget.lead);
    _notesCtrl = TextEditingController(
      text: _leadData['notes']?.toString() ?? '',
    );
    _commentCtrl = TextEditingController();
    if (widget.entityType == 'student') {
      // Opened as a student. Start in studentOnly; once the student loads we
      // read its `lead_id` and, if present, resolve the lead half (converted).
      _mode = ClientMode.studentOnly;
      _resolvedStudentId = _entityId;
      _loadingFamily = true;
      if (widget.allStatuses == null) _fetchStatuses();
      _fetchMetadata();
      _fetchFamily();
      _fetchStudentData(then: _resolveLeadCounterpart);
      return;
    }
    // Opened as a lead. Start in leadOnly; once the lead card loads we inspect
    // `linked_students` and, if non-empty, resolve the student half (converted).
    _mode = ClientMode.leadOnly;
    _resolvedLeadId = _entityId;
    _statuses = widget.allStatuses ?? const [];
    if (widget.allStatuses == null) _fetchStatuses();
    _fetchMetadata();
    _fetchCard(then: _resolveStudentCounterpart);
    _fetchDuplicateCandidates();
    _fetchStatusHistory();
    _fetchFamily();
  }

  // ── Counterpart resolution (Phase 4) ──────────────────────────────────────
  // Each resolver runs AFTER its own half has loaded and isolates failures: a
  // failed counterpart fetch leaves the card in its single-side mode rather than
  // blanking it. The two halves still load in parallel — the counterpart's
  // fetches are fired without awaiting and update their own sections.

  /// Student-opened path: if the loaded student carries a `lead_id`, fetch the
  /// lead half (lead card, status history, statuses, metadata) and flip to
  /// `converted`. Failures degrade silently back to studentOnly.
  void _resolveLeadCounterpart() {
    if (!mounted) return;
    final leadId = _student?['lead_id']?.toString();
    if (leadId == null || leadId.isEmpty) return;
    setState(() {
      _mode = ClientMode.converted;
      _resolvedLeadId = leadId;
      // Lead-side sections start loading now.
      _loadingCard = true;
      _loadingHistory = true;
    });
    // Parallel, isolated lead-half fetches against the resolved lead id. Lead
    // statuses are needed for the header label and the originating-lead card;
    // the editable lead form / branch metadata isn't shown in converted mode,
    // so we skip _fetchMetadata here.
    _statuses = widget.allStatuses ?? _statuses;
    if (_statuses.isEmpty) _fetchStatuses();
    _fetchCard(leadId: leadId);
    _fetchStatusHistory(leadId: leadId);
  }

  /// Lead-opened path: if the lead card lists linked students, pick the primary
  /// (first / most recent) one, fetch the student half and flip to `converted`.
  /// Additional linked students stay visible via the existing linked-students
  /// UI. Failures degrade silently back to leadOnly.
  void _resolveStudentCounterpart() {
    if (!mounted) return;
    final linked = _list(_leadCard?['linked_students']);
    if (linked.isEmpty) return;
    final primary = _primaryLinkedStudent(linked);
    final studentId = primary?['id']?.toString();
    if (studentId == null || studentId.isEmpty) return;
    setState(() {
      _mode = ClientMode.converted;
      _resolvedStudentId = studentId;
      _loadingStudent = true;
      _studentError = null;
    });
    // Parallel, isolated student-half fetch against the resolved student id.
    _fetchStudentData(studentId: studentId);
  }

  /// Picks the primary linked student: most recently created, falling back to
  /// the first row when no timestamps are present.
  Map<String, dynamic>? _primaryLinkedStudent(
    List<Map<String, dynamic>> linked,
  ) {
    if (linked.isEmpty) return null;
    final sorted = [...linked]
      ..sort(
        (a, b) => (b['created_at']?.toString() ?? '').compareTo(
          a['created_at']?.toString() ?? '',
        ),
      );
    return sorted.first;
  }

  // ── Merged section data (Phase 4) ─────────────────────────────────────────
  // Each merge tags rows with `_origin` (entityType) so converted views can show
  // an origin chip, then de-dups by `id` and sorts desc by date. Single-side
  // modes return just their own half (no behavioural change vs Phase 1/2).

  List<Map<String, dynamic>> _origin(
    List<Map<String, dynamic>> rows,
    String entityType,
  ) => rows.map((r) => {...r, '_origin': entityType}).toList();

  /// Lead tasks (from the lead card) + student tasks, de-duped by id.
  List<Map<String, dynamic>> get _mergedTasks {
    final leadTasks = _mode.hasLeadHalf
        ? _origin(_list(_leadCard?['tasks']), 'lead')
        : const <Map<String, dynamic>>[];
    final studentTasks = _mode.hasStudentHalf
        ? _origin(_studentTasks, 'student')
        : const <Map<String, dynamic>>[];
    return mergeByIdSorted([studentTasks, leadTasks], dateKey: 'created_at');
  }

  /// Lead status history + student timeline, normalised onto a shared shape and
  /// merged/sorted desc. Returns rows with: `_kind` ('status'|'event'),
  /// `_origin`, `_date`, `_title`, `_subtitle`.
  List<Map<String, dynamic>> get _mergedHistory {
    final out = <List<Map<String, dynamic>>>[];
    if (_mode.hasLeadHalf) {
      out.add(
        _statusHistory.map((h) {
          final from = h['old_status']?.toString();
          final to = h['new_status']?.toString();
          final transition = [
            if (from != null && from.isNotEmpty) from else '—',
            '→',
            if (to != null && to.isNotEmpty) to else '—',
          ].join(' ');
          final comment = h['comment']?.toString().trim() ?? '';
          return {
            'id': h['id'],
            '_origin': 'lead',
            '_kind': 'status',
            '_date': h['changed_at'],
            '_title': transition,
            '_subtitle': comment,
          };
        }).toList(),
      );
    }
    if (_mode.hasStudentHalf) {
      out.add(
        _list(_studentCardTimeline).map((t) {
          return {
            'id': t['id'],
            '_origin': 'student',
            '_kind': 'event',
            '_date': t['occurred_at'],
            '_title': t['title']?.toString() ?? 'Событие',
            '_subtitle': t['body']?.toString() ?? '',
          };
        }).toList(),
      );
    }
    return mergeByIdSorted(out, dateKey: '_date');
  }

  // The student timeline is part of the student card payload; kept separately so
  // the merged history can fold it in alongside the lead status history.
  List<Map<String, dynamic>> _studentCardTimeline = const [];

  // True when the lead card lists at least one linked student — used to hide the
  // «Создать ученика» button even before resolution flips the mode.
  bool get _hasLinkedStudent => _list(_leadCard?['linked_students']).isNotEmpty;

  // Loads the student card in one round-trip (getStudentCard), mirroring
  // student_detail_screen._loadAllData. Per-section failures are isolated: the
  // bulk card load only fails the card if the student record itself is
  // unavailable; family loads independently via [_fetchFamily].
  Future<void> _fetchStudentData({
    String? studentId,
    VoidCallback? then,
  }) async {
    final id = studentId ?? _studentId;
    if (id.isEmpty) return;
    if (mounted) {
      setState(() {
        _loadingStudent = true;
        _studentError = null;
      });
    }
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final card = await crm.getStudentCard(id);
      if (!mounted) return;
      final student = card['student'] is Map<String, dynamic>
          ? card['student'] as Map<String, dynamic>
          : <String, dynamic>{};
      setState(() {
        _student = student;
        _balance = card['balance'] is Map<String, dynamic>
            ? card['balance'] as Map<String, dynamic>
            : null;
        _subscriptions = _list(card['subscriptions']);
        _payments = _list(card['payments']);
        _lessons = _list(card['lessons']);
        _studentTasks = _list(card['tasks']);
        _studentComments = _list(card['comments']);
        _groups = _list(card['groups']);
        _expectedPayments = _list(card['expected_payments']);
        _studentCardTimeline = _list(card['timeline']);
        _studentTasks.sort(
          (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
        );
        _studentComments.sort(
          (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
        );
        _loadingStudent = false;
      });
      then?.call();
    } catch (e) {
      debugPrint('Error loading student card: $e');
      if (mounted) {
        setState(() {
          _studentError = '$e';
          _loadingStudent = false;
        });
      }
    }
  }

  Future<void> _fetchStatuses() async {
    try {
      final raw = await ref.read(leadStatusesProvider.future);
      if (!mounted) return;
      setState(() {
        _statuses = raw
            .map<StatusRecord>(
              (r) => (
                r['key'].toString(),
                r['label'].toString(),
                statusColorFromValue(r['color']),
              ),
            )
            .toList();
      });
    } catch (_) {
      // Card still renders with a fallback status.
    }
  }

  Future<void> _fetchCard({String? leadId, VoidCallback? then}) async {
    final id = leadId ?? _leadId;
    if (id.isEmpty) {
      if (mounted) setState(() => _loadingCard = false);
      return;
    }
    // Заявки грузятся параллельно и изолированно: их сбой не роняет карточку.
    _fetchLeadApplications(id);
    try {
      final card = await ref.read(magicCrmServiceProvider).getLeadCard(id);
      if (!mounted) return;
      setState(() {
        _leadCard = card;
        if (card['lead'] is Map<String, dynamic>) {
          _leadData = {..._leadData, ...(card['lead'] as Map<String, dynamic>)};
          // After merging the lead record, `_leadData['id']` is the lead id —
          // keep `_resolvedLeadId` in sync so lead-side ops target it.
          _resolvedLeadId = _leadData['id']?.toString() ?? id;
        }
        _loadingCard = false;
      });
      then?.call();
    } catch (_) {
      if (mounted) setState(() => _loadingCard = false);
    }
  }

  // KVA-234: заявки лида из app.lead_applications — секция «Заявки».
  Future<void> _fetchLeadApplications(String leadId) async {
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .listLeadApplications(leadId);
      if (!mounted) return;
      setState(() => _leadApplications = items);
    } catch (_) {
      // Секция останется с пустым состоянием «Заявок нет».
    }
  }

  Future<void> _fetchDuplicateCandidates() async {
    final leadId = _leadData['id']?.toString() ?? widget.lead['id']?.toString();
    if (leadId == null || leadId.isEmpty) {
      if (mounted) setState(() => _loadingDuplicates = false);
      return;
    }
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .listDuplicateCandidates(leadId: leadId, limit: 20);
      if (!mounted) return;
      setState(() {
        _duplicateCandidates = items
            .where(_isCurrentLeadDuplicateCandidate)
            .toList();
        _loadingDuplicates = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDuplicates = false);
    }
  }

  Future<void> _fetchStatusHistory({String? leadId}) async {
    final id = leadId ?? _leadId;
    if (id.isEmpty) {
      if (mounted) setState(() => _loadingHistory = false);
      return;
    }
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .getLeadStatusHistory(id);
      if (!mounted) return;
      setState(() {
        _statusHistory = items;
        _loadingHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _fetchFamily() async {
    try {
      final result = await ref
          .read(magicCrmServiceProvider)
          .getFamilyForEntity(
            entityType: widget.entityType,
            entityId: widget.lead['id'].toString(),
          );
      if (!mounted) return;
      setState(() {
        _family = result;
        _loadingFamily = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingFamily = false);
    }
  }

  Future<void> _fetchMetadata() async {
    final crm = ref.read(magicCrmServiceProvider);
    final settings = ref.read(magicSettingsServiceProvider);
    final results = await Future.wait<dynamic>([
      crm.listBranches(limit: 100),
      settings.getCrmCustomFields(),
      // KVA-234: справочник дисциплин для мультивыбора; сбой не роняет форму.
      crm.listDisciplines().catchError(
        (_) => const <Map<String, dynamic>>[],
      ),
    ]);

    if (mounted) {
      setState(() {
        _branches = List<Map<String, dynamic>>.from(results[0] as List);
        _customFieldSchema = results[1] as List<CrmCustomFieldDefinition>;
        _disciplineOptions = List<Map<String, dynamic>>.from(results[2] as List);
        _loadingMetadata = false;
      });
    }
  }

  void _scheduleRealtimeRefresh(String entity) {
    if (!mounted || _realtimeRefreshQueued) return;
    if (_edited && (entity == 'lead' || entity == 'student')) return;
    _realtimeRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _realtimeRefreshQueued = false;
      _refreshFromRealtime(entity);
    });
  }

  void _refreshFromRealtime(String entity) {
    switch (entity) {
      case 'lead':
      case 'student':
      case 'task':
      case 'comment':
      case 'lesson':
      case 'payment':
      case 'subscription':
      case 'group':
      case 'chat_work':
        if (_mode.hasLeadHalf && _leadId.isNotEmpty) {
          _fetchCard();
          _fetchStatusHistory();
        }
        if (_mode.hasStudentHalf && _studentId.isNotEmpty) {
          _fetchStudentData();
        }
        _fetchFamily();
        break;
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final service = ref.read(magicCrmServiceProvider);
      if (_mode.hasLeadHalf && _leadId.isNotEmpty) {
        final customData = Map<String, dynamic>.from(
          _leadData['custom_data'] as Map? ?? {},
        );
        if (_leadData['branch_id'] != null) {
          customData['branchId'] = _leadData['branch_id'];
        }
        await service.updateLead(
          _leadId,
          firstName: _clientFirstName,
          lastName: _clientLastName,
          phone: _clientPhone,
          email: _clientEmail,
          statusId: _leadData['status']?.toString(),
          notes: _notesCtrl.text,
          customDataPatch: customData,
        );
      }

      if (_mode.hasStudentHalf && _studentId.isNotEmpty) {
        final customData = Map<String, dynamic>.from(
          _student?['custom_data'] as Map? ?? {},
        );
        final branchId = _clientBranchId;
        if (branchId != null && branchId.isNotEmpty) {
          customData['branchId'] = branchId;
        }
        await service.updateStudent(
          _studentId,
          firstName: _clientFirstName,
          lastName: _clientLastName,
          phone: _clientPhone,
          email: _clientEmail,
          status: _student?['status']?.toString(),
          customDataPatch: customData,
        );
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _convertToStudent() async {
    final firstName = (_leadData['name'] ?? '').toString().trim();
    if (firstName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('У лида должно быть имя.')));
      return;
    }

    setState(() => _converting = true);
    try {
      final customData = Map<String, dynamic>.from(
        _leadData['custom_data'] as Map? ?? {},
      );
      if (_leadData['branch_id'] != null) {
        customData['branchId'] = _leadData['branch_id'];
      }
      customData['sourceLeadId'] = _leadData['id'].toString();

      await ref
          .read(magicCrmServiceProvider)
          .createStudent(
            firstName: firstName,
            lastName: _leadData['last_name']?.toString(),
            phone: _leadData['phone']?.toString(),
            email: _leadData['email']?.toString(),
            leadId: _leadData['id'].toString(),
            customDataPatch: customData,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Лид конвертирован в ученика.')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка конвертации: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _converting = false);
      }
    }
  }

  void _updateCustomDataForEntity(String entity, String key, dynamic value) {
    setState(() {
      void put(Map<String, dynamic> target) {
        final cd = Map<String, dynamic>.from(target['custom_data'] ?? {});
        if (value == null || value == '') {
          cd.remove(key);
        } else {
          cd[key] = value;
        }
        target['custom_data'] = cd;
      }

      if (entity == 'students' && _student != null) {
        put(_student!);
        if (_isConverted && _commonClientCustomFieldKeys.contains(key)) {
          put(_leadData);
        }
      } else {
        put(_leadData);
        if (_isConverted &&
            _student != null &&
            _commonClientCustomFieldKeys.contains(key)) {
          put(_student!);
        }
      }
      _edited = true;
    });
  }

  Future<void> _attachDuplicateCandidate(Map<String, dynamic> candidate) async {
    final candidateId = candidate['id']?.toString();
    if (candidateId == null || candidateId.isEmpty) return;
    final student = _candidateEntity(candidate, 'student');
    final studentName = student['name']?.toString().trim();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Связать с учеником?'),
        content: Text(
          studentName == null || studentName.isEmpty
              ? 'Лид будет прикреплен к существующей карточке ученика.'
              : 'Лид будет прикреплен к ученику "$studentName".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Связать'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _duplicateDecisionId = candidateId);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .decideDuplicateCandidate(
            candidateId,
            status: 'attached',
            notes: 'Связано из карточки лида',
          );
      _dirty = true;
      await Future.wait([_fetchCard(), _fetchDuplicateCandidates()]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лид связан с существующим учеником')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка связи: $e')));
    } finally {
      if (mounted) setState(() => _duplicateDecisionId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(crmRealtimeProvider, (previous, next) {
      final event = next.value;
      if (event == null) return;
      // Skip the 30s fallback poll (10 entities) — it was refetching the whole
      // card every 30s, flashing spinners and jittering fields. Real socket
      // events still refresh.
      if (event.isFallbackPoll) return;
      _scheduleRealtimeRefresh(event.entity);
    });

    final cs = Theme.of(context).colorScheme;
    final fallbackStatus = _statuses.isNotEmpty
        ? _statuses.first
        : ('new', 'Новый', AppTheme.primaryGold);
    final curStatus = _statuses.firstWhere(
      (element) => element.$1 == _leadData['status'],
      orElse: () => fallbackStatus,
    );

    return PopScope(
      canPop: !_edited,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleClose();
      },
      child: Dialog(
        backgroundColor: cs.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Container(
          // Narrow card width so the form reads as a focused client card
          // instead of stretching edge-to-edge on wide desktop monitors.
          width: (MediaQuery.of(context).size.width * 0.92)
              .clamp(0.0, 600.0)
              .toDouble(),
          height: MediaQuery.of(context).size.height * 0.85,
          color: cs.surface,
          child: Column(
            children: [
              _isStudent
                  ? _buildStudentHeader(cs, curStatus)
                  : _buildHeader(cs, curStatus),
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.6),
              ),
              _buildTabBar(cs),
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.6),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tabIndex,
                  children: _isStudent
                      ? [
                          _buildClientInfoTab(cs, curStatus),
                          _buildStudentTasksTab(cs),
                          _buildCommentsTab(cs),
                          _buildFamilyTab(cs),
                          _buildLessonsTab(cs),
                          _buildPaymentsTab(cs),
                          _buildInvoicesTab(cs),
                          _buildDocumentsTab(cs),
                          _buildStudentHistoryTab(cs),
                          _buildProgressTab(cs),
                        ]
                      : [
                          _buildClientInfoTab(cs, curStatus),
                          _buildTasksTab(cs),
                          _buildCommentsTab(cs),
                          _buildFamilyTab(cs),
                          _buildHistoryTab(cs),
                        ],
                ),
              ),
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.6),
              ),
              _isStudent ? _buildStudentActionBar(cs) : _buildActionBar(cs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, StatusRecord curStatus) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.md,
        AppSpace.md,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColor.goldSoft,
              borderRadius: BorderRadius.circular(AppRadius.icon),
              border: Border.all(color: AppColor.goldLine),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              size: 22,
              color: AppColor.gold,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_leadData['name'] ?? ''} ${_leadData['last_name'] ?? ''}'
                      .trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: curStatus.$3,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          [
                            'Клиент · Лид · ${curStatus.$2}',
                            ?_ageLabel(),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _handleClose,
            icon: const Icon(Icons.close_rounded),
            iconSize: 20,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.sm,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpace.sm),
              _buildTabChip(cs, i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTabChip(ColorScheme cs, int index) {
    final selected = _tabIndex == index;
    final (icon, label) = _tabs[index];
    return Material(
      color: selected ? AppColor.goldSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(
              color: selected ? AppColor.goldLine : cs.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColor.gold : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColor.gold : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        AppSpace.lg,
      ),
      // Wrap so the action buttons reflow onto a second line on narrow
      // (mobile) dialog widths instead of overflowing on the right.
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Hide «Создать ученика» once a linked student exists (the card is
            // — or is about to become — converted): the conversion already
            // happened. `_isConverted` covers the resolved case; the
            // linked_students check covers the brief window before resolution
            // flips the mode.
            if (!_isConverted && !_hasLinkedStudent)
              OutlinedButton.icon(
                onPressed: _saving || _converting ? null : _convertToStudent,
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
                icon: _converting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Создать ученика'),
              ),
            TextButton(
              onPressed: _saving || _converting ? null : _handleClose,
              style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: _saving || _converting ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColor.gold,
                foregroundColor: AppColor.onGold,
                disabledBackgroundColor: AppColor.gold.withValues(alpha: 0.42),
                disabledForegroundColor: AppColor.onGold.withValues(alpha: 0.7),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColor.onGold,
                      ),
                    )
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab: Клиент ───────────────────────────────────────────────────────────
  Widget _buildClientInfoTab(ColorScheme cs, StatusRecord curStatus) {
    if (_isStudent) {
      return _studentGuard(cs, () => _buildClientInfoContent(cs, curStatus));
    }
    return _buildClientInfoContent(cs, curStatus);
  }

  Widget _buildClientInfoContent(ColorScheme cs, StatusRecord curStatus) {
    final duplicateCandidates = _duplicateCandidates
        .where(_isCurrentLeadDuplicateCandidate)
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Клиент'),
          if (_mode.hasLeadHalf) _buildStatusPicker(cs, curStatus),
          if (_mode.hasStudentHalf) _buildStudentStatusPicker(cs),
          _buildClientTextField(
            cs,
            'Имя',
            _clientFirstName,
            (value) => _updateClientCore('firstName', value),
          ),
          _buildClientTextField(
            cs,
            'Фамилия',
            _clientLastName,
            (value) => _updateClientCore('lastName', value),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: RuPhoneField(
              key: ValueKey('client-phone-${_clientPhone ?? ''}'),
              initialCanonical: _clientPhone,
              onCanonicalChanged: (c) {
                _updateClientCore('phone', c.isEmpty ? null : c);
              },
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          _buildClientTextField(
            cs,
            'Электронная почта',
            _clientEmail,
            (value) => _updateClientCore('email', value),
            keyboard: TextInputType.emailAddress,
          ),
          if (!_loadingMetadata) _buildBranchDropdown(cs, 'Основной филиал'),

          const SizedBox(height: AppSpace.lg),
          _sectionTitle('Параметры клиента'),
          if (_loadingMetadata)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(color: AppColor.gold),
              ),
            )
          else ...[
            ..._buildCustomFieldControls(
              cs,
              _isStudent ? 'students' : 'leads',
              includeKeys: _commonClientCustomFieldKeys,
              excludedKeys: _customKeysWithDedicatedEditor,
            ),
            // KVA-234: мультидисциплины чипами + список контактных лиц.
            _buildDisciplinesChips(cs, _isStudent ? 'students' : 'leads'),
            _buildContactPersonsEditor(cs, _isStudent ? 'students' : 'leads'),
          ],

          if (_mode.hasStudentHalf) ...[
            const SizedBox(height: AppSpace.lg),
            _sectionTitle('Поля ученика'),
            if (_loadingMetadata)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(color: AppColor.gold),
                ),
              )
            else
              ..._buildCustomFieldControls(
                cs,
                'students',
                includeKeys: _studentOnlyCustomFieldKeys,
              ),
            if (_balance != null) ...[
              const SizedBox(height: AppSpace.lg),
              _buildInfoCard('Финансы', [
                _InfoRow(
                  icon: Icons.summarize_outlined,
                  label: 'Всего оплачено',
                  value: '${_balance!['total_paid']} ₽',
                ),
                _InfoRow(
                  icon: Icons.history_edu_outlined,
                  label: 'Списано за уроки',
                  value: '${_balance!['total_cost']} ₽',
                ),
                _InfoRow(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Баланс',
                  value: '${_balance!['balance']} ₽',
                ),
              ]),
            ],
            if (_subscriptions.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              _buildInfoCard('Абонементы', [
                for (final s in _subscriptions.take(5))
                  _InfoRow(
                    icon: s['status'] == 'active'
                        ? Icons.confirmation_number_outlined
                        : Icons.history_toggle_off_rounded,
                    label: (s['package_name']?.toString().trim().isNotEmpty ??
                            false)
                        ? s['package_name'].toString()
                        : 'Абонемент',
                    value: _subscriptionRemainder(s),
                  ),
              ]),
            ],
            if (_studentId.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              StudentScheduleSection(
                studentId: _studentId,
                lessons: _lessons,
                onChanged: _fetchStudentData,
              ),
            ],
            if (_balance != null) ...[
              const SizedBox(height: AppSpace.lg),
              _buildLedgerSection(cs),
            ],
            const SizedBox(height: AppSpace.lg),
            _buildStudentGroupsInfoCard(cs),
          ],

          if (_mode.hasLeadHalf) ...[
            if (_leadCreatedAtLabel() != null) ...[
              const SizedBox(height: AppSpace.lg),
              _buildInfoCard('Обращение', [
                _InfoRow(
                  icon: Icons.event_outlined,
                  label: 'Дата обращения',
                  value: _leadCreatedAtLabel()!,
                ),
              ]),
            ],
            const SizedBox(height: AppSpace.lg),
            _sectionTitle('Заметки'),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: _inputDecoration(
                cs,
                hint: 'Общие примечания по клиенту...',
              ),
            ),
          ],

          const SizedBox(height: AppSpace.lg),
          ClientAppUserPanel(
            entityType: _mode.hasStudentHalf ? 'student' : 'lead',
            entityId: _mode.hasStudentHalf ? _studentId : _leadId,
          ),

          const SizedBox(height: AppSpace.lg),
          _sectionTitle('Связи и активность'),
          _buildAggregateCard(cs, includeTasks: false),

          if (_mode.hasLeadHalf &&
              (_loadingDuplicates || duplicateCandidates.isNotEmpty)) ...[
            const SizedBox(height: AppSpace.md),
            _sectionTitle('Кандидаты на связь'),
            _duplicateCandidatesSection(cs, duplicateCandidates),
          ],
        ],
      ),
    );
  }

  // ── Tab: Задачи ──────────────────────────────────────────────────────────
  Widget _buildTasksTab(ColorScheme cs) {
    if (_loadingCard) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
        child: Center(child: CircularProgressIndicator(color: AppColor.gold)),
      );
    }
    final card = _leadCard;
    final tasks = card == null
        ? const <Map<String, dynamic>>[]
        : _list(card['tasks']);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('Задачи')),
              _buildAddTaskButton(cs),
            ],
          ),
          if (card == null)
            _emptyHint(cs, 'Карточка активности временно недоступна')
          else if (tasks.isEmpty)
            _emptyHint(cs, 'Открытых задач нет')
          else
            ...tasks.map(
              (row) => _entityTile(
                cs,
                title: row['title']?.toString() ?? 'Задача',
                subtitle: _formatStatus(row['status']),
                leading: Icons.task_alt_rounded,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddTaskButton(ColorScheme cs) {
    return TextButton.icon(
      onPressed: _addingTask ? null : _openAddTaskSheet,
      style: TextButton.styleFrom(
        foregroundColor: AppColor.gold,
        backgroundColor: AppColor.goldSoft,
        disabledForegroundColor: AppColor.gold.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          side: const BorderSide(color: AppColor.goldLine),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      icon: _addingTask
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_rounded, size: 16),
      label: const Text('Добавить'),
    );
  }

  Future<void> _openAddTaskSheet() async {
    final cs = Theme.of(context).colorScheme;
    final titleCtrl = TextEditingController();
    DateTime? due;
    String? assignedTo;
    // Сотрудники для поля «Исполнитель»; сбой загрузки не блокирует задачу.
    var staff = const <Map<String, dynamic>>[];
    try {
      staff = List<Map<String, dynamic>>.from(
        await ref.read(magicCrmServiceProvider).listStaff(limit: 100),
      );
    } catch (_) {}
    if (!mounted) return;

    final confirmed = await showMagicSheet<bool>(
      context,
      title: 'Новая задача',
      subtitle: _isStudent
          ? 'Поставьте задачу по этому ученику'
          : 'Поставьте задачу по этому лиду',
      icon: Icons.task_alt_rounded,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final dueLabel = due == null
                ? 'Без срока'
                : DateFormat('dd.MM.yyyy', 'ru').format(due!);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: _inputDecoration(
                    cs,
                    label: 'Название',
                    hint: 'Например: Перезвонить клиенту',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                Text(
                  'Срок',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: due ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setSheetState(() => due = picked);
                  },
                  child: InputDecorator(
                    decoration: _inputDecoration(cs, isDense: true),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(dueLabel),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (due != null)
                              InkWell(
                                onTap: () => setSheetState(() => due = null),
                                child: Icon(
                                  Icons.clear_rounded,
                                  size: 16,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 16,
                              color: AppColor.gold,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (staff.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.md),
                  DropdownButtonFormField<String?>(
                    initialValue: assignedTo,
                    isExpanded: true,
                    decoration: _inputDecoration(
                      cs,
                      label: 'Исполнитель',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Не назначен'),
                      ),
                      for (final s in staff)
                        if (s['profile_user_id'] != null)
                          DropdownMenuItem<String?>(
                            value: s['profile_user_id'].toString(),
                            child: Text(
                              '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'
                                  .trim(),
                            ),
                          ),
                    ],
                    onChanged: (v) => setSheetState(() => assignedTo = v),
                  ),
                ],
              ],
            );
          },
        );
      },
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColor.gold,
            foregroundColor: AppColor.onGold,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          child: const Text('Создать'),
        ),
      ],
    );

    final title = titleCtrl.text.trim();
    final dueAt = due?.toUtc().toIso8601String();
    titleCtrl.dispose();
    if (confirmed != true) return;
    if (title.isEmpty) {
      if (mounted) {
        MagicToast.show(
          context,
          'Укажите название задачи',
          type: MagicToastType.danger,
        );
      }
      return;
    }

    // New tasks target the primary half: the student side for a converted
    // client, otherwise the open entity.
    final targetType = _isConverted ? 'student' : widget.entityType;
    final targetId = _isConverted ? _studentId : _entityId;
    if (targetId.isEmpty) return;
    setState(() => _addingTask = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createTask(
            entityType: targetType,
            entityId: targetId,
            title: title,
            dueAt: dueAt,
            assignedTo: assignedTo,
          );
      _dirty = true;
      if (_mode.hasStudentHalf) {
        await _fetchStudentData();
      }
      if (_mode.hasLeadHalf) {
        await _fetchCard();
      }
      if (mounted) {
        MagicToast.show(
          context,
          'Задача добавлена',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка добавления',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _addingTask = false);
    }
  }

  /// «Записать на пробный урок» прямо из карточки лида — тот же диалог, что в
  /// меню канбан-доски (leads_widget._scheduleTrial).
  Future<void> _scheduleTrialFromCard() async {
    final crm = ref.read(magicCrmServiceProvider);
    List<Map<String, dynamic>> teachers;
    List<Map<String, dynamic>> rooms;
    try {
      final [teachersRes, roomsRes] = await Future.wait([
        crm.listTeachers(limit: 100),
        crm.listRooms(limit: 100),
      ]);
      teachers = List<Map<String, dynamic>>.from(teachersRes);
      rooms = List<Map<String, dynamic>>.from(roomsRes);
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось загрузить данные',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
      return;
    }
    if (!mounted) return;
    if (teachers.isEmpty) {
      MagicToast.show(
        context,
        'Нет доступных преподавателей',
        type: MagicToastType.danger,
      );
      return;
    }

    String? selectedTeacher = teachers.first['id']?.toString();
    String? selectedRoom = rooms.isNotEmpty ? rooms.first['id']?.toString() : null;
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

    if (confirmed != true || selectedTeacher == null) return;
    final scheduledAt = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    try {
      await crm.createLesson(
        leadId: _leadId,
        teacherId: selectedTeacher,
        roomId: selectedRoom,
        scheduledAt: scheduledAt.toIso8601String(),
        isTrial: true,
        status: 'scheduled',
        notes: 'Пробное занятие по лиду: ${_leadData['name'] ?? ''}',
      );
      _dirty = true;
      await _fetchCard();
      if (mounted) {
        MagicToast.show(
          context,
          'Пробное занятие назначено',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка назначения',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    }
  }

  // ── Tab: Комментарии ─────────────────────────────────────────────────────
  Widget _buildCommentsTab(ColorScheme cs) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.xl,
              AppSpace.lg,
              AppSpace.xl,
              AppSpace.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Комментарии'),
                _CommentsList(
                  // For a converted client both halves are loaded, merged,
                  // de-duped by id and origin-badged; single-side cards pass one
                  // ref and render exactly as before (no origin chip).
                  refs: _halfRefs,
                  showOrigin: _isConverted,
                  refreshKey: _commentsRefreshKey,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            AppSpace.sm,
            AppSpace.xl,
            AppSpace.lg,
          ),
          child: _buildCommentInput(cs),
        ),
      ],
    );
  }

  // ── Tab: Семья ───────────────────────────────────────────────────────────
  Widget _buildFamilyTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('Семья')),
              _buildFamilyAddButton(cs),
            ],
          ),
          _buildFamilySection(cs),
        ],
      ),
    );
  }

  Widget _buildFamilyAddButton(ColorScheme cs) {
    return TextButton.icon(
      onPressed: _familyBusy ? null : _openAddFamilyMemberSheet,
      style: TextButton.styleFrom(
        foregroundColor: AppColor.gold,
        backgroundColor: AppColor.goldSoft,
        disabledForegroundColor: AppColor.gold.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          side: const BorderSide(color: AppColor.goldLine),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      icon: const Icon(Icons.add_rounded, size: 16),
      label: const Text('Добавить'),
    );
  }

  // ── Tab: История ─────────────────────────────────────────────────────────
  Widget _buildHistoryTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('История статусов'),
          _buildStatusHistorySection(cs),
        ],
      ),
    );
  }

  Widget _emptyHint(ColorScheme cs, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Text(
        text,
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
      ),
    );
  }

  // ══ STUDENT (entityType == 'student') ════════════════════════════════════
  // Ported from student_detail_screen.dart, adapted to the compact dialog and
  // the unified comments tab. Lead methods above are untouched.

  /// Resolves the student display name with a fallback to the linked profile,
  /// matching student_detail_screen.
  ({String name, String phone, String email}) _studentContact() {
    final s = _student ?? const <String, dynamic>{};
    final profile = s['profiles'] as Map<String, dynamic>?;
    final sfName = s['first_name']?.toString() ?? '';
    final slName = s['last_name']?.toString() ?? '';
    var name = '$sfName $slName'.trim();
    if (name.isEmpty && profile != null) {
      name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
          .trim();
    }
    final phone =
        (s['phone']?.toString().trim().isNotEmpty == true
                ? s['phone']
                : profile?['phone'])
            ?.toString() ??
        '—';
    final email =
        (s['email']?.toString().trim().isNotEmpty == true
                ? s['email']
                : profile?['email'])
            ?.toString() ??
        '—';
    return (
      name: name.isEmpty ? 'Без имени' : name,
      phone: phone,
      email: email,
    );
  }

  String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == '—' ? null : text;
  }

  String? get _clientFirstName => _isStudent
      ? _nonEmpty(_student?['first_name'])
      : _nonEmpty(_leadData['name'] ?? _leadData['first_name']);

  String? get _clientLastName => _isStudent
      ? _nonEmpty(_student?['last_name'])
      : _nonEmpty(_leadData['last_name']);

  String? get _clientPhone => _isStudent
      ? _nonEmpty(_student?['phone'])
      : _nonEmpty(_leadData['phone']);

  String? get _clientEmail => _isStudent
      ? _nonEmpty(_student?['email'])
      : _nonEmpty(_leadData['email']);

  String? get _clientBranchId {
    final studentCustom = _student?['custom_data'];
    if (_isStudent && studentCustom is Map) {
      return _nonEmpty(studentCustom['branchId'] ?? studentCustom['branch_id']);
    }
    return _nonEmpty(_leadData['branch_id']);
  }

  void _updateClientCore(String key, dynamic value) {
    setState(() {
      if (_mode.hasLeadHalf) {
        switch (key) {
          case 'firstName':
            _leadData['name'] = value;
            _leadData['first_name'] = value;
          case 'lastName':
            _leadData['last_name'] = value;
          case 'phone':
            _leadData['phone'] = value;
          case 'email':
            _leadData['email'] = value;
          case 'branchId':
            _leadData['branch_id'] = value;
        }
      }
      if (_mode.hasStudentHalf && _student != null) {
        switch (key) {
          case 'firstName':
            _student!['first_name'] = value;
          case 'lastName':
            _student!['last_name'] = value;
          case 'phone':
            _student!['phone'] = value;
          case 'email':
            _student!['email'] = value;
          case 'branchId':
            final cd = Map<String, dynamic>.from(
              _student!['custom_data'] ?? {},
            );
            if (value == null || value == '') {
              cd.remove('branchId');
            } else {
              cd['branchId'] = value;
            }
            _student!['custom_data'] = cd;
        }
      }
      _edited = true;
    });
  }

  // Parse the balance defensively (it can arrive as a string) and color it:
  // red < 0, green > 0, neutral at exactly 0. (Ported from student_detail.)
  num? get _studentBalanceNum {
    if (_balance == null) return null;
    final raw = _balance!['balance'];
    return raw is num ? raw : num.tryParse(raw?.toString() ?? '');
  }

  /// «Остаток: 7 астр.ч. / 14 000 ₽» — денежная часть считается по цене пакета
  /// пропорционально оставшимся часам; без пакета показываем только часы.
  String _subscriptionRemainder(Map<String, dynamic> s) {
    num toNum(Object? v) =>
        v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
    String hours(num v) =>
        v == v.truncate() ? v.toInt().toString() : v.toStringAsFixed(1);
    final total = toNum(s['lessons_total']);
    final left = total - toNum(s['lessons_used']);
    final price = s['package_price'];
    final money = (price is num && total > 0)
        ? ' / ${(price / total * left).round()} ₽'
        : '';
    final status = s['status']?.toString();
    final suffix = status == 'active' ? '' : ' · ${_formatStatus(status)}';
    return 'Остаток: ${hours(left)} из ${hours(total)} астр.ч.$money$suffix';
  }

  // ── Личный счёт (KVA-235, формат HolliHop: вкладки Приход/Расход) ────────
  Widget _buildLedgerSection(ColorScheme cs) {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('ledger-$_ledgerRefreshKey'),
      future: ref.read(magicCrmServiceProvider).getStudentLedger(_studentId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: LinearProgressIndicator(color: AppColor.gold),
          );
        }
        if (snap.hasError) {
          return Text(
            'Личный счёт недоступен',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          );
        }
        final data = snap.data ?? const {};
        num toNum(Object? v) =>
            v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
        final income = toNum(data['income_total']);
        final outcome = toNum(data['outcome_total']);
        final items = _list(data['items']);
        final visible = items
            .where(
              (r) => _ledgerTab == 0
                  ? toNum(r['amount']) > 0
                  : toNum(r['amount']) < 0,
            )
            .take(8)
            .toList();
        String rub(num v) => '${v.round()} ₽';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Личный счёт: ${rub(income)} − ${rub(outcome)} = '
                    '${rub(income - outcome)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _openTopUpDialog,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColor.gold,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  child: const Text('Добавить'),
                ),
                TextButton(
                  onPressed: _openRefundDialog,
                  style: TextButton.styleFrom(
                    foregroundColor: cs.error,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  child: const Text('Возврат'),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              children: [
                for (final (index, label) in const [
                  (0, 'Приход'),
                  (1, 'Расход'),
                ])
                  ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: _ledgerTab == index,
                    selectedColor: AppColor.goldSoft,
                    onSelected: (_) => setState(() => _ledgerTab = index),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            if (visible.isEmpty)
              Text(
                'Операций нет',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              )
            else
              ...visible.map((r) {
                final amount = toNum(r['amount']);
                final dt = DateTime.tryParse(
                  r['occurred_at']?.toString() ?? '',
                )?.toLocal();
                final meta = [
                  if (dt != null) DateFormat('dd.MM.yy', 'ru').format(dt),
                  r['method'],
                  r['author_name'],
                ].where((v) => v != null && '$v'.isNotEmpty).join(' · ');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 78,
                        child: Text(
                          '${amount > 0 ? '+' : ''}${amount.round()} ₽',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: amount > 0 ? AppTheme.success : cs.error,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r['description']?.toString().trim().isNotEmpty ==
                                      true
                                  ? r['description'].toString()
                                  : _ledgerKindLabel(r['kind']),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            if (meta.isNotEmpty)
                              Text(
                                meta,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  String _ledgerKindLabel(Object? kind) {
    return switch (kind?.toString()) {
      'payment' => 'Платёж',
      'lesson_charge' => 'Списание за занятие',
      'refund' => 'Возврат',
      'adjustment' => 'Корректировка',
      'transfer_in' => 'Перенос (зачисление)',
      'transfer_out' => 'Перенос (списание)',
      _ => 'Операция',
    };
  }

  void _refreshLedger() {
    setState(() => _ledgerRefreshKey++);
    _fetchStudentData();
  }

  Future<void> _openTopUpDialog() async {
    if (_student == null) return;
    final added = await TopUpDialog.show(context, _student!);
    if (added == true) _refreshLedger();
  }

  Future<void> _openRefundDialog() async {
    final cs = Theme.of(context).colorScheme;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final confirmed = await showMagicSheet<bool>(
      context,
      title: 'Возврат средств',
      subtitle: 'Сумма спишется с личного счёта клиента',
      icon: Icons.undo_rounded,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: amountCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecoration(cs, label: 'Сумма (₽)', isDense: true),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: descCtrl,
            decoration: _inputDecoration(
              cs,
              label: 'Комментарий',
              hint: 'Например: возврат за отменённые занятия',
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: cs.error,
            foregroundColor: cs.onError,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          child: const Text('Вернуть'),
        ),
      ],
    );
    final amount = num.tryParse(amountCtrl.text.trim().replaceAll(',', '.'));
    final description = descCtrl.text.trim();
    amountCtrl.dispose();
    descCtrl.dispose();
    if (confirmed != true) return;
    if (amount == null || amount <= 0) {
      if (mounted) {
        MagicToast.show(
          context,
          'Введите корректную сумму',
          type: MagicToastType.danger,
        );
      }
      return;
    }
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createAdjustment(
            studentId: _studentId,
            kind: 'refund',
            amount: amount,
            description: description.isEmpty ? null : description,
          );
      _dirty = true;
      _refreshLedger();
      if (mounted) {
        MagicToast.show(
          context,
          'Возврат оформлен',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка возврата',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    }
  }

  /// Возраст «N лет» из custom-поля birthday (ISO или дд.мм.гггг).
  String? _ageLabel() {
    Object? raw;
    if (_mode.hasStudentHalf && _student != null) {
      raw = _customDataForEntity('students')['birthday'];
    }
    raw ??= _customDataForEntity('leads')['birthday'];
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    var birth = DateTime.tryParse(s);
    if (birth == null) {
      final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})').firstMatch(s);
      if (m == null) return null;
      birth = DateTime(
        int.parse(m.group(3)!),
        int.parse(m.group(2)!),
        int.parse(m.group(1)!),
      );
    }
    final now = DateTime.now();
    var years = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      years--;
    }
    if (years < 0 || years > 120) return null;
    final mod100 = years % 100;
    final mod10 = years % 10;
    final word = (mod100 >= 11 && mod100 <= 14)
        ? 'лет'
        : mod10 == 1
        ? 'год'
        : (mod10 >= 2 && mod10 <= 4)
        ? 'года'
        : 'лет';
    return '$years $word';
  }

  String? _leadCreatedAtLabel() {
    final dt = DateTime.tryParse(
      _leadData['created_at']?.toString() ?? '',
    )?.toLocal();
    if (dt == null) return null;
    return DateFormat('dd.MM.yyyy HH:mm', 'ru').format(dt);
  }

  Color _studentBalanceColor(ColorScheme cs) {
    final b = _studentBalanceNum;
    if (b == null || b == 0) return cs.onSurfaceVariant;
    return b < 0 ? AppTheme.danger : AppTheme.success;
  }

  // Pill badge for the header («Ученик» / «Лид→Ученик»).
  Widget _headerBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColor.goldSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColor.goldLine),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColor.gold,
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
        ),
      ),
    );
  }

  Widget _buildStudentHeader(ColorScheme cs, StatusRecord curStatus) {
    final contact = _studentContact();
    final converted = _isConverted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.md,
        AppSpace.md,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColor.goldSoft,
              borderRadius: BorderRadius.circular(AppRadius.icon),
              border: Border.all(color: AppColor.goldLine),
            ),
            child: Icon(
              converted ? Icons.swap_horiz_rounded : Icons.school_outlined,
              size: 22,
              color: AppColor.gold,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      _headerBadge(converted ? 'Лид→Ученик' : 'Ученик'),
                      // For a converted client surface BOTH halves: the lead
                      // status (origin) and the student balance.
                      if (converted) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: curStatus.$3,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            curStatus.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      if (_balance != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Баланс: ${_balance!['balance']} ₽',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _studentBalanceColor(cs),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _handleClose,
            icon: const Icon(Icons.close_rounded),
            iconSize: 20,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  // Wraps any student tab body with the shared loading / error / not-found
  // states so per-tab isolation reuses one place.
  Widget _studentGuard(ColorScheme cs, Widget Function() child) {
    if (_loadingStudent) {
      return const Center(
        child: CircularProgressIndicator(color: AppColor.gold),
      );
    }
    if (_studentError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: AppColor.danger,
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'Ошибка: $_studentError',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: AppSpace.md),
              TextButton(
                onPressed: _fetchStudentData,
                style: TextButton.styleFrom(foregroundColor: AppColor.gold),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }
    if (_student == null) {
      return Center(
        child: Text(
          'Ученик не найден',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return child();
  }

  // Read-only «Исходный лид» card for the converted Инфо tab: source, request
  // ── Student tab: Задачи ──────────────────────────────────────────────────
  Widget _buildStudentTasksTab(ColorScheme cs) {
    return _studentGuard(cs, () {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          AppSpace.lg,
          AppSpace.xl,
          AppSpace.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _sectionTitle('Задачи')),
                _buildAddTaskButton(cs),
              ],
            ),
            if (_mergedTasks.isEmpty)
              _emptyHint(cs, 'Открытых задач нет')
            else
              ..._mergedTasks.map(
                (row) => _entityTile(
                  cs,
                  title: row['title']?.toString() ?? 'Задача',
                  subtitle: _formatStatus(row['status']),
                  leading: Icons.task_alt_rounded,
                  origin: _isConverted ? row['_origin']?.toString() : null,
                ),
              ),
          ],
        ),
      );
    });
  }

  // ── Student tab: Занятия (flat list; Phase 5 adds past/upcoming) ──────────
  Widget _buildLessonsTab(ColorScheme cs) {
    return _studentGuard(cs, () {
      if (_lessons.isEmpty) {
        return Center(
          child: Text(
            'Занятий не найдено',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        );
      }

      // Split into «Предстоящие» (scheduled_at >= now, ascending) and
      // «Прошедшие» (scheduled_at < now, descending). Lessons without a parsable
      // time fold into «Прошедшие» so they are never silently dropped.
      final now = DateTime.now();
      final upcoming = <Map<String, dynamic>>[];
      final past = <Map<String, dynamic>>[];
      for (final l in _lessons) {
        final dt = DateTime.tryParse(l['scheduled_at']?.toString() ?? '');
        if (dt != null && !dt.isBefore(now)) {
          upcoming.add(l);
        } else {
          past.add(l);
        }
      }
      int byTime(Map<String, dynamic> a, Map<String, dynamic> b) {
        final ad = DateTime.tryParse(a['scheduled_at']?.toString() ?? '');
        final bd = DateTime.tryParse(b['scheduled_at']?.toString() ?? '');
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      }

      upcoming.sort(byTime); // ascending (soonest first)
      past.sort((a, b) => byTime(b, a)); // descending (most recent first)

      return ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          if (upcoming.isNotEmpty) ...[
            _sectionTitle('Предстоящие'),
            ...upcoming.map((l) => _buildLessonRow(cs, l)),
          ],
          if (upcoming.isNotEmpty && past.isNotEmpty)
            const SizedBox(height: AppSpace.md),
          if (past.isNotEmpty) ...[
            _sectionTitle('Прошедшие'),
            ...past.map((l) => _buildLessonRow(cs, l)),
          ],
        ],
      );
    });
  }

  /// One tappable lesson row. Tapping focuses the dashboard schedule on the
  /// lesson's day with the lesson highlighted, then closes the card.
  Widget _buildLessonRow(ColorScheme cs, Map<String, dynamic> l) {
    final dt = DateTime.tryParse(l['scheduled_at']?.toString() ?? '');
    final dateStr = dt != null
        ? DateFormat('d MMM, HH:mm', 'ru').format(dt)
        : '—';
    final teacherData = l['teachers'] as Map<String, dynamic>?;
    String teacherName = '—';
    if (teacherData != null) {
      final tfName = teacherData['first_name']?.toString() ?? '';
      final tlName = teacherData['last_name']?.toString() ?? '';
      final p = teacherData['profiles'] as Map<String, dynamic>?;
      var tName = '$tfName $tlName'.trim();
      if (tName.isEmpty && p != null) {
        tName = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
      }
      teacherName = tName.isEmpty ? '—' : tName;
    }
    final completed = l['status'] == 'completed';
    final lessonId = l['id']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: (lessonId != null && lessonId.isNotEmpty && dt != null)
            ? () => _openScheduleForLesson(dt, lessonId)
            : null,
        title: Text(
          dateStr,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            'Преп.: $teacherName',
            '${l['groups']?['name'] ?? 'Инд.'}',
            if ((l['rooms']?['name']?.toString() ?? '').isNotEmpty)
              'Ауд.: ${l['rooms']['name']}',
          ].join(' • '),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (completed ? AppTheme.success : AppTheme.primaryGold)
                .withAlpha(30),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            completed ? 'Завершено' : 'Запланировано',
            style: TextStyle(
              fontSize: 11,
              color: completed ? AppTheme.success : AppTheme.primaryGold,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  /// Focus the dashboard schedule on [scheduledAt] with [lessonId] highlighted,
  /// then close this card and route to the admin dashboard schedule tab.
  ///
  /// Mirrors [ClientAppUserPanel._openChat]: set the cross-screen navigation
  /// target, pop this card (the dialog / sheet), then navigate to the host
  /// screen. The schedule lives on canonical CRM tab 2 (Расписание) inside the
  /// admin dashboard, so we also request that tab via [crmNavigationRequestProvider].
  void _openScheduleForLesson(DateTime scheduledAt, String lessonId) {
    ref.read(scheduleNavigationProvider.notifier).focus(scheduledAt, lessonId);
    // Select the schedule destination (tab 2) once the dashboard renders.
    ref
        .read(crmNavigationRequestProvider.notifier)
        .navigateTo(const CrmNavigationRequest(tabIndex: 2));
    // Close the card (dialog on desktop / bottom sheet on mobile).
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(_dirty ? true : null);
    }
    // Route to the admin dashboard which hosts the schedule.
    context.go('/admin');
  }

  // ── Student tab: Оплаты ──────────────────────────────────────────────────
  Widget _buildPaymentsTab(ColorScheme cs) {
    return _studentGuard(cs, () {
      if (_payments.isEmpty) {
        return Center(
          child: Text(
            'Оплат не найдено',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(AppSpace.xl),
        itemCount: _payments.length,
        itemBuilder: (context, i) {
          final p = _payments[i];
          final dt = DateTime.tryParse(p['payment_date']?.toString() ?? '');
          final dateStr = dt != null
              ? DateFormat('d MMM yyyy', 'ru').format(dt)
              : '—';
          final paymentNote = (p['notes'] ?? p['description'] ?? '')
              .toString()
              .trim();
          final method = (p['method'] ?? p['type'] ?? '').toString().trim();
          final subtitle = [
            dateStr,
            if (paymentNote.isNotEmpty) paymentNote,
          ].join(' • ');
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(
                Icons.account_balance_wallet_rounded,
                color: AppTheme.success,
              ),
              title: Text(
                '${p['amount']} ₽',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(subtitle),
              trailing: method.isEmpty
                  ? null
                  : Text(
                      method,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
            ),
          );
        },
      );
    });
  }

  // ── Student tab: Инвойсы ─────────────────────────────────────────────────
  Widget _buildInvoicesTab(ColorScheme cs) {
    return _studentGuard(cs, () {
      if (_expectedPayments.isEmpty) {
        return Center(
          child: Text(
            'Инвойсов не найдено',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(AppSpace.xl),
        itemCount: _expectedPayments.length,
        itemBuilder: (context, i) {
          final p = _expectedPayments[i];
          final dt = DateTime.tryParse(p['due_date']?.toString() ?? '');
          final dateStr = dt != null
              ? DateFormat('d MMM yyyy', 'ru').format(dt)
              : '—';
          final status = p['status']?.toString() ?? 'pending';
          final description = (p['description'] ?? '').toString().trim();
          final paid = status == 'paid';
          final subtitle = [
            'Срок: $dateStr',
            if (description.isNotEmpty) description,
          ].join(' • ');
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                paid
                    ? Icons.check_circle_rounded
                    : Icons.pending_actions_rounded,
                color: paid ? AppTheme.success : AppTheme.warning,
              ),
              title: Text(
                '${p['amount']} ₽',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(subtitle),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (paid ? AppTheme.success : AppTheme.warning).withAlpha(
                    30,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  paid ? 'Оплачено' : 'Ожидает',
                  style: TextStyle(
                    fontSize: 11,
                    color: paid ? AppTheme.success : AppTheme.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  // ── Student tab: Документы ───────────────────────────────────────────────
  Widget _buildDocumentsTab(ColorScheme cs) {
    return _studentGuard(cs, () {
      final contractUrl = _student!['contract_url'] as String?;
      return ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          _buildInfoCard('Договоры и документы', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.description_rounded,
                color: AppTheme.primaryGold,
              ),
              title: const Text('Основной договор'),
              subtitle: Text(contractUrl ?? 'Не прикреплен'),
              trailing: IconButton(
                icon: Icon(
                  contractUrl != null
                      ? Icons.edit_rounded
                      : Icons.add_link_rounded,
                ),
                onPressed: _editStudentContractUrl,
              ),
              onTap: contractUrl != null
                  ? () => _openStudentContractUrl(contractUrl)
                  : null,
            ),
          ]),
        ],
      );
    });
  }

  // Merged-history list (converted): lead status history + student timeline,
  // sorted desc, each row carrying an origin chip.
  Widget _buildMergedHistoryView(ColorScheme cs) {
    // Lead status history loads independently; show a spinner until it settles
    // so converted history isn't briefly missing its lead half.
    if (_loadingHistory) {
      return const Center(
        child: CircularProgressIndicator(color: AppColor.gold),
      );
    }
    final items = _mergedHistory;
    if (items.isEmpty) {
      return Center(
        child: Text(
          'История пуста',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpace.xl),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        final isStatus = item['_kind'] == 'status';
        final dt = DateTime.tryParse(item['_date']?.toString() ?? '');
        final dateStr = dt != null
            ? DateFormat('d MMM HH:mm', 'ru').format(dt.toLocal())
            : '—';
        final subtitle = item['_subtitle']?.toString() ?? '';
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isStatus
                              ? Icons.flag_rounded
                              : Icons.timeline_rounded,
                          size: 16,
                          color: isStatus
                              ? AppTheme.warning
                              : AppTheme.primaryGold,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isStatus ? 'Статус' : 'Событие',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isStatus
                                ? AppTheme.warning
                                : AppTheme.primaryGold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        ClientOriginChip(
                          entityType: item['_origin']?.toString() ?? 'student',
                        ),
                      ],
                    ),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item['_title']?.toString() ?? '',
                  style: const TextStyle(fontSize: 14),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Student tab: История ─────────────────────────────────────────────────
  // For a converted client this folds lead status history into the student
  // timeline (merged, de-duped by id, origin-badged). A plain student keeps the
  // Phase 2 view (its own tasks + comments).
  Widget _buildStudentHistoryTab(ColorScheme cs) {
    if (_isConverted) {
      return _studentGuard(cs, () => _buildMergedHistoryView(cs));
    }
    return _studentGuard(cs, () {
      if (_studentTasks.isEmpty && _studentComments.isEmpty) {
        return Center(
          child: Text(
            'История пуста',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        );
      }
      final items = [
        ..._studentTasks.map(
          (t) => {'type': 'task', 'data': t, 'date': t['created_at']},
        ),
        ..._studentComments
            .where(
              (c) =>
                  !(c['content']?.toString().startsWith('[PROGRESS]') ?? false),
            )
            .map(
              (c) => {'type': 'comment', 'data': c, 'date': c['created_at']},
            ),
      ];
      items.sort(
        (a, b) => ((b['date'] as String?) ?? '').compareTo(
          (a['date'] as String?) ?? '',
        ),
      );
      return ListView.builder(
        padding: const EdgeInsets.all(AppSpace.xl),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final item = items[i];
          final isTask = item['type'] == 'task';
          final data = item['data'] as Map<String, dynamic>;
          final dt = DateTime.tryParse(item['date'] as String? ?? '');
          final dateStr = dt != null
              ? DateFormat('d MMM HH:mm', 'ru').format(dt.toLocal())
              : '—';
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isTask
                                ? Icons.task_alt_rounded
                                : Icons.comment_rounded,
                            size: 16,
                            color: isTask
                                ? AppTheme.warning
                                : AppTheme.primaryGold,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isTask ? 'Задача' : 'Комментарий',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isTask
                                  ? AppTheme.warning
                                  : AppTheme.primaryGold,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isTask
                        ? (data['title']?.toString() ?? '')
                        : (data['content']?.toString() ?? ''),
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (isTask && data['description'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      data['description'].toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    });
  }

  // ── Student tab: Прогресс ([PROGRESS]-prefixed comments) ──────────────────
  Widget _buildProgressTab(ColorScheme cs) {
    return _studentGuard(cs, () {
      final progressNotes = _studentComments
          .where(
            (c) => c['content']?.toString().startsWith('[PROGRESS]') ?? false,
          )
          .toList();
      if (progressNotes.isEmpty) {
        return Center(
          child: Text(
            'Заметок об успехах ещё нет',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(AppSpace.xl),
        itemCount: progressNotes.length,
        itemBuilder: (ctx, i) {
          final note = progressNotes[i];
          final content = (note['content']?.toString() ?? '').replaceFirst(
            '[PROGRESS] ',
            '',
          );
          final dt = DateTime.tryParse(note['created_at']?.toString() ?? '');
          final dateStr = dt != null
              ? DateFormat('d MMM yyyy, HH:mm', 'ru').format(dt.toLocal())
              : '—';
          final author = note['profiles'];
          final authorName = author != null
              ? '${author['first_name'] ?? ''} ${author['last_name'] ?? ''}'
                    .trim()
              : 'Система';
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.stars_rounded,
                        color: AppTheme.success,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        authorName.isEmpty ? 'Система' : authorName,
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    content,
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  // ── Student action bar (overflow menu hosts the v7 student actions) ───────
  Widget _buildStudentActionBar(ColorScheme cs) {
    final busy = _loadingStudent || _student == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        AppSpace.lg,
      ),
      child: Row(
        children: [
          PopupMenuButton<String>(
            enabled: !busy,
            tooltip: 'Действия',
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            onSelected: (value) {
              switch (value) {
                case 'subscription':
                  _showIssueSubscriptionSheet();
                case 'homework':
                  _showAssignHomeworkSheet();
                case 'price':
                  _editStudentPrice();
                case 'contract':
                  _editStudentContractUrl();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'subscription',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.card_membership_rounded,
                    color: AppColor.gold,
                  ),
                  title: Text('Выдать абонемент'),
                ),
              ),
              PopupMenuItem(
                value: 'homework',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.assignment_rounded, color: AppColor.gold),
                  title: Text('Задать ДЗ'),
                ),
              ),
              PopupMenuItem(
                value: 'price',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.payments_outlined, color: AppColor.gold),
                  title: Text('Изменить цену'),
                ),
              ),
              PopupMenuItem(
                value: 'contract',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.description_rounded,
                    color: AppColor.gold,
                  ),
                  title: Text('Редактировать договор'),
                ),
              ),
            ],
            child: OutlinedButton.icon(
              onPressed: null,
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface,
                disabledForegroundColor: cs.onSurface,
                side: BorderSide(color: cs.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: const Text('Действия'),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _saving || _converting ? null : _handleClose,
            style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
            child: const Text('Отмена'),
          ),
          const SizedBox(width: AppSpace.sm),
          FilledButton(
            onPressed: busy || _saving || _converting ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.gold,
              foregroundColor: AppColor.onGold,
              disabledBackgroundColor: AppColor.gold.withValues(alpha: 0.42),
              disabledForegroundColor: AppColor.onGold.withValues(alpha: 0.7),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColor.onGold,
                    ),
                  )
                : const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentGroupsInfoCard(ColorScheme cs) {
    return _buildInfoCard('Группы', [
      if (_groups.isEmpty)
        const _InfoRow(
          icon: Icons.group_off_rounded,
          label: 'Группы',
          value: 'Нет активных групп',
        )
      else
        ..._groups.map((g) {
          final teacher = g['teachers'];
          var teacherName = '—';
          if (teacher is Map<String, dynamic>) {
            final firstName = teacher['first_name']?.toString() ?? '';
            final lastName = teacher['last_name']?.toString() ?? '';
            teacherName = '$firstName $lastName'.trim();
          }
          return _InfoRow(
            icon: Icons.groups_rounded,
            label: g['name']?.toString() ?? 'Группа',
            value: teacherName.isEmpty || teacherName == '—'
                ? 'Без преподавателя'
                : 'Преподаватель: $teacherName',
          );
        }),
    ]);
  }

  // ── Student actions (ported from student_detail_screen) ──────────────────
  Future<void> _editStudentPrice() async {
    final controller = TextEditingController(
      text: _student?['individual_price']?.toString(),
    );
    final newPrice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Цена занятия'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Сумма (₽)'),
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

    if (newPrice != null && double.tryParse(newPrice) != null) {
      try {
        final price = double.parse(newPrice);
        await ref
            .read(magicCrmServiceProvider)
            .updateStudent(
              _entityId,
              customDataPatch: {
                'individualPrice': price,
                'individual_price': price,
              },
            );
        _dirty = true;
        await _fetchStudentData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
        }
      }
    }
  }

  Future<void> _openStudentContractUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Некорректная ссылка на договор')),
      );
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть договор')),
      );
    }
  }

  Future<void> _editStudentContractUrl() async {
    final controller = TextEditingController(
      text: _student?['contract_url']?.toString(),
    );
    final newUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ссылка на договор'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://...',
            labelText: 'Ссылка на документ',
          ),
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

    if (newUrl != null) {
      try {
        await ref
            .read(magicCrmServiceProvider)
            .updateStudent(
              _entityId,
              customDataPatch: {
                'legacyContractUrl': newUrl.trim(),
                'contract_url': newUrl.trim(),
              },
            );
        _dirty = true;
        await _fetchStudentData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
        }
      }
    }
  }

  /// Flat gold button used inside the v7 «Задать ДЗ» sheet (ported helper).
  Future<void> _showIssueSubscriptionSheet() async {
    final crm = ref.read(magicCrmServiceProvider);
    List<Map<String, dynamic>> packages;
    try {
      packages = await crm.listSubscriptionPackages(limit: 100);
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось загрузить абонементы',
        detail: '$e',
        type: MagicToastType.danger,
      );
      return;
    }
    if (!mounted) return;

    if (packages.isEmpty) {
      MagicToast.show(
        context,
        'Нет доступных абонементов',
        type: MagicToastType.info,
      );
      return;
    }

    final selected = await showMagicSheet<Map<String, dynamic>>(
      context,
      title: 'Выдать абонемент',
      subtitle: 'Выберите пакет занятий',
      icon: Icons.card_membership_rounded,
      builder: (sheetContext) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final pkg in packages) ...[
              _SubscriptionPackageTile(
                package: pkg,
                onTap: () => Navigator.pop(sheetContext, pkg),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          ],
        );
      },
    );

    if (selected == null || !mounted) return;

    final packageId = selected['id']?.toString();
    if (packageId == null || packageId.isEmpty) return;

    try {
      await crm.issueSubscription(_entityId, packageId);
      if (!mounted) return;
      _dirty = true;
      MagicToast.show(
        context,
        'Абонемент выдан',
        detail: selected['name']?.toString(),
        type: MagicToastType.success,
      );
      _fetchStudentData();
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось выдать абонемент',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  Future<void> _showAssignHomeworkSheet() async {
    final crm = ref.read(magicCrmServiceProvider);

    List<Map<String, dynamic>> homeworks = const [];
    try {
      homeworks = await crm.listHomeworks(studentId: _entityId, limit: 5);
    } catch (_) {
      // Listing is best-effort; the assign form still works without it.
    }
    if (!mounted) return;

    final input = await showAssignHomeworkSheet(
      context,
      recentHomeworks: homeworks,
    );
    if (input == null || !mounted) return;

    try {
      await crm.createHomework(
        studentId: _entityId,
        title: input.title,
        description: input.description,
        dueAt: input.dueAt?.toIso8601String(),
      );
      if (!mounted) return;
      _dirty = true;
      MagicToast.show(
        context,
        'ДЗ создано',
        detail: input.title,
        type: MagicToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось создать ДЗ',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  /// Shared card container used by the student Инфо/Документы tabs (ported from
  /// student_detail_screen._buildInfoCard).
  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppTheme.primaryGold,
              ),
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    ColorScheme cs, {
    String? label,
    String? hint,
    String? helperText,
    bool isDense = false,
    Widget? suffixIcon,
  }) => clientCardInputDecoration(
    cs,
    label: label,
    hint: hint,
    helperText: helperText,
    isDense: isDense,
    suffixIcon: suffixIcon,
  );

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md, top: AppSpace.xs),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColor.gold,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Text(
            title,
            style: const TextStyle(
              color: AppColor.gold,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPicker(ColorScheme cs, StatusRecord current) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: DropdownButtonFormField<String>(
        initialValue: _leadData['status'],
        isExpanded: true,
        decoration: _inputDecoration(cs, label: 'Статус', isDense: true),
        items: _statuses.map((s) {
          return DropdownMenuItem(
            value: s.$1,
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: s.$3,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(s.$2),
              ],
            ),
          );
        }).toList(),
        onChanged: (v) {
          if (v != null) {
            setState(() {
              _leadData['status'] = v;
              _edited = true;
            });
          }
        },
      ),
    );
  }

  Widget _buildStudentStatusPicker(ColorScheme cs) {
    final current = _student?['status']?.toString() ?? '';
    final options = [
      if (current.isNotEmpty && !_studentStatusOptions.contains(current))
        current,
      ..._studentStatusOptions,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: DropdownButtonFormField<String>(
        initialValue: current.isEmpty ? null : current,
        isExpanded: true,
        decoration: _inputDecoration(
          cs,
          label: 'Статус ученика',
          isDense: true,
        ),
        items: options
            .map(
              (status) => DropdownMenuItem(value: status, child: Text(status)),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            _student?['status'] = value;
            _edited = true;
          });
        },
      ),
    );
  }

  Widget _buildClientTextField(
    ColorScheme cs,
    String label,
    String? value,
    ValueChanged<String?> onChanged, {
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: TextFormField(
        key: ValueKey('$label-${value ?? ''}'),
        initialValue: value ?? '',
        decoration: _inputDecoration(cs, label: label, isDense: true),
        keyboardType: keyboard,
        onChanged: (v) => onChanged(v.trim().isEmpty ? null : v),
      ),
    );
  }

  List<Widget> _buildCustomFieldControls(
    ColorScheme cs,
    String entity, {
    Set<String>? includeKeys,
    Set<String> excludedKeys = const {},
  }) {
    final fields = _customFieldSchema
        .where(
          (field) =>
              field.entity == entity &&
              !_isSystemOnlyCustomField(field.key) &&
              (includeKeys == null || includeKeys.contains(field.key)) &&
              !excludedKeys.contains(field.key),
        )
        .toList();
    if (fields.isEmpty) {
      return [
        Text(
          'Дополнительные поля не настроены',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      ];
    }
    return fields.map((field) => _buildCustomFieldControl(cs, field)).toList();
  }

  Widget _buildCustomFieldControl(
    ColorScheme cs,
    CrmCustomFieldDefinition field,
  ) {
    final customData = _customDataForEntity(field.entity);
    final rawValue = customData[field.key];
    final label = field.required ? '${field.label} *' : field.label;

    if (field.type == 'select') {
      final current = rawValue?.toString() ?? '';
      final initialValue = field.options.contains(current) ? current : '';
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: DropdownButtonFormField<String>(
          initialValue: initialValue,
          isExpanded: true,
          decoration: _inputDecoration(
            cs,
            label: label,
            helperText: field.hint,
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Не выбрано')),
            ...field.options.map(
              (option) => DropdownMenuItem(value: option, child: Text(option)),
            ),
          ],
          onChanged: (value) => _updateCustomDataForEntity(
            field.entity,
            field.key,
            value == null || value.isEmpty ? null : value,
          ),
        ),
      );
    }

    if (field.type == 'boolean') {
      return SwitchListTile(
        value: rawValue == true || rawValue?.toString() == 'true',
        activeThumbColor: AppColor.gold,
        onChanged: (value) =>
            _updateCustomDataForEntity(field.entity, field.key, value),
        title: Text(label),
        subtitle: field.hint == null ? null : Text(field.hint!),
        contentPadding: EdgeInsets.zero,
      );
    }

    if (field.type == 'date') {
      return _buildDateCustomField(cs, field, rawValue?.toString());
    }

    return _buildCustomTextField(
      cs,
      label,
      field,
      rawValue?.toString(),
      keyboard: _keyboardForCustomField(field.type),
    );
  }

  bool _isSystemOnlyCustomField(String key) =>
      _systemOnlyCustomFieldKeys.contains(_normalizedCustomKey(key));

  String _normalizedCustomKey(String key) =>
      key.trim().replaceAll('-', '_').toLowerCase();

  Map<String, dynamic> _customDataForEntity(String entity) {
    if (entity == 'students' && _student != null) {
      return Map<String, dynamic>.from(_student!['custom_data'] as Map? ?? {});
    }
    return Map<String, dynamic>.from(_leadData['custom_data'] as Map? ?? {});
  }

  Widget _buildCustomTextField(
    ColorScheme cs,
    String label,
    CrmCustomFieldDefinition field,
    String? value, {
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: TextFormField(
        key: ValueKey('${field.entity}-${field.key}-${value ?? ''}'),
        initialValue: value ?? '',
        decoration: _inputDecoration(
          cs,
          label: label,
          helperText: field.hint,
          isDense: true,
        ),
        keyboardType: keyboard,
        onChanged: (v) => _updateCustomDataForEntity(
          field.entity,
          field.key,
          v.trim().isEmpty ? null : v,
        ),
      ),
    );
  }

  Widget _buildDateCustomField(
    ColorScheme cs,
    CrmCustomFieldDefinition field,
    String? value,
  ) {
    final dt = value == null ? null : DateTime.tryParse(value);
    final display = dt != null
        ? DateFormat('dd.MM.yyyy', 'ru').format(dt)
        : 'Не выбрано';
    final label = field.required ? '${field.label} *' : field.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: dt ?? DateTime.now(),
            firstDate: DateTime(1950),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            _updateCustomDataForEntity(
              field.entity,
              field.key,
              picked.toIso8601String(),
            );
          }
        },
        child: InputDecorator(
          decoration: _inputDecoration(
            cs,
            label: label,
            helperText: field.hint,
            isDense: true,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(display),
              const Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: AppColor.gold,
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextInputType? _keyboardForCustomField(String type) {
    return switch (type) {
      'number' => TextInputType.number,
      'phone' => TextInputType.phone,
      'email' => TextInputType.emailAddress,
      'url' => TextInputType.url,
      _ => null,
    };
  }

  // ── KVA-234: мультидисциплины ─────────────────────────────────────────────
  // Массив custom_data['disciplines']; одиночное discipline остаётся для
  // совместимости и пишется первым элементом массива.
  List<String> _disciplinesForEntity(String entity) {
    final customData = _customDataForEntity(entity);
    final raw = customData['disciplines'];
    if (raw is List) {
      return raw
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList();
    }
    final single = customData['discipline']?.toString();
    return single == null || single.isEmpty ? const [] : [single];
  }

  void _toggleDiscipline(String entity, String name) {
    final current = _disciplinesForEntity(entity);
    final next = current.contains(name)
        ? current.where((value) => value != name).toList()
        : [...current, name];
    _updateCustomDataForEntity(entity, 'disciplines', next);
    _updateCustomDataForEntity(
      entity,
      'discipline',
      next.isEmpty ? null : next.first,
    );
  }

  Widget _buildDisciplinesChips(ColorScheme cs, String entity) {
    final selected = _disciplinesForEntity(entity);
    // Справочник — GET /crm/disciplines; при пустом ответе fallback на опции
    // custom-поля discipline из схемы. Выбранные значения всегда видимы.
    final schemaOptions = _customFieldSchema
        .where((field) => field.entity == entity && field.key == 'discipline')
        .expand((field) => field.options);
    final options = <String>{
      for (final row in _disciplineOptions)
        if ((row['name']?.toString() ?? '').isNotEmpty) row['name'].toString(),
      if (_disciplineOptions.isEmpty) ...schemaOptions,
      ...selected,
    }.toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: InputDecorator(
        decoration: _inputDecoration(cs, label: 'Направления', isDense: true),
        child: options.isEmpty
            ? Text(
                'Справочник направлений пуст',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              )
            : Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: options.map((name) {
                  return FilterChip(
                    label: Text(name),
                    selected: selected.contains(name),
                    visualDensity: VisualDensity.compact,
                    selectedColor: AppColor.gold.withValues(alpha: 0.22),
                    checkmarkColor: AppColor.gold,
                    onSelected: (_) => _toggleDiscipline(entity, name),
                  );
                }).toList(),
              ),
      ),
    );
  }

  // ── KVA-234: контактные лица ──────────────────────────────────────────────
  // Массив custom_data['contactPersons'] [{name, relation, phone, email}].
  // Миграция на лету: пока массива нет, старые одиночные contactPerson*-поля
  // показываются первым элементом; любое изменение пишет уже массив.
  List<Map<String, dynamic>> _contactPersonsForEntity(String entity) {
    final customData = _customDataForEntity(entity);
    final raw = customData['contactPersons'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    final legacy = <String, dynamic>{
      'name': customData['contactPersonName']?.toString() ?? '',
      'relation': customData['contactPersonRelation']?.toString() ?? '',
      'phone': customData['contactPersonPhone']?.toString() ?? '',
      'email': customData['contactPersonEmail']?.toString() ?? '',
    }..removeWhere((_, value) => (value as String).isEmpty);
    return legacy.isEmpty ? const [] : [legacy];
  }

  void _writeContactPersons(
    String entity,
    List<Map<String, dynamic>> persons,
  ) {
    _updateCustomDataForEntity(entity, 'contactPersons', persons);
    // Первый элемент зеркалится в старые одиночные поля для совместимости.
    final first = persons.isNotEmpty
        ? persons.first
        : const <String, dynamic>{};
    _updateCustomDataForEntity(entity, 'contactPersonName', first['name']);
    _updateCustomDataForEntity(
      entity,
      'contactPersonRelation',
      first['relation'],
    );
    _updateCustomDataForEntity(entity, 'contactPersonPhone', first['phone']);
    _updateCustomDataForEntity(entity, 'contactPersonEmail', first['email']);
  }

  Future<void> _editContactPerson(String entity, {int? index}) async {
    final persons = _contactPersonsForEntity(entity);
    final existing = index == null
        ? const <String, dynamic>{}
        : persons[index];
    final nameCtrl = TextEditingController(
      text: existing['name']?.toString() ?? '',
    );
    final phoneCtrl = TextEditingController(
      text: existing['phone']?.toString() ?? '',
    );
    final emailCtrl = TextEditingController(
      text: existing['email']?.toString() ?? '',
    );
    String relation = existing['relation']?.toString() ?? '';
    final relationOptions = _customFieldSchema
        .where(
          (field) =>
              field.entity == entity && field.key == 'contactPersonRelation',
        )
        .expand((field) => field.options)
        .toList();
    if (relation.isNotEmpty && !relationOptions.contains(relation)) {
      relationOptions.add(relation);
    }
    final cs = Theme.of(context).colorScheme;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          index == null ? 'Новое контактное лицо' : 'Контактное лицо',
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: _inputDecoration(cs, label: 'Имя', isDense: true),
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<String>(
                initialValue: relationOptions.contains(relation)
                    ? relation
                    : '',
                isExpanded: true,
                decoration: _inputDecoration(
                  cs,
                  label: 'Кем приходится',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Не выбрано')),
                  ...relationOptions.map(
                    (option) =>
                        DropdownMenuItem(value: option, child: Text(option)),
                  ),
                ],
                onChanged: (value) => relation = value ?? '',
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration(
                  cs,
                  label: 'Телефон',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration(cs, label: 'Email', isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.gold,
              foregroundColor: AppColor.onGold,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final person = <String, dynamic>{
        'name': nameCtrl.text.trim(),
        'relation': relation,
        'phone': phoneCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
      }..removeWhere((_, value) => (value as String).isEmpty);
      final next = [...persons];
      if (index == null) {
        next.add(person);
      } else {
        next[index] = person;
      }
      _writeContactPersons(entity, next);
    }
    nameCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
  }

  Widget _buildContactPersonsEditor(ColorScheme cs, String entity) {
    final persons = _contactPersonsForEntity(entity);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Контактные лица',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () => _editContactPerson(entity),
                style: TextButton.styleFrom(
                  foregroundColor: AppColor.gold,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 15),
                label: const Text('Добавить контактное лицо'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (persons.isEmpty)
            Text(
              'Контактные лица не указаны',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            )
          else
            ...List.generate(persons.length, (i) {
              final person = persons[i];
              final name = person['name']?.toString().trim() ?? '';
              final subtitle = [
                person['relation'],
                person['phone'],
                person['email'],
              ].where((v) => v != null && '$v'.isNotEmpty).join(' · ');
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    side: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  title: Text(
                    name.isEmpty ? 'Без имени' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: subtitle.isEmpty
                      ? null
                      : Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        tooltip: 'Изменить',
                        onPressed: () => _editContactPerson(entity, index: i),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: AppTheme.danger,
                        ),
                        tooltip: 'Удалить',
                        onPressed: () => _writeContactPersons(entity, [
                          ...persons,
                        ]..removeAt(i)),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildBranchDropdown(ColorScheme cs, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: DropdownButtonFormField<String>(
        initialValue: _clientBranchId,
        isExpanded: true,
        decoration: _inputDecoration(cs, label: label, isDense: true),
        items: _branches
            .map(
              (b) => DropdownMenuItem(
                value: b['id'].toString(),
                child: Text(b['name']),
              ),
            )
            .toList(),
        onChanged: (v) => _updateClientCore('branchId', v),
      ),
    );
  }

  /// Staff может выбрать поток комментария; педагог всегда пишет teacher_note.
  bool get _canPickCommentKind {
    final role = ref.read(releaseGateStatusProvider).asData?.value.role;
    final isStaff = role == 'admin' ||
        role == 'manager' ||
        role == 'director' ||
        role == 'system_admin';
    final targetIsStudent = _isConverted || widget.entityType == 'student';
    return isStaff && targetIsStudent;
  }

  Widget _buildCommentInput(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_canPickCommentKind) ...[
          Wrap(
            spacing: AppSpace.sm,
            children: [
              for (final (kind, label) in const [
                ('admin_comment', 'Комментарий админа'),
                ('teacher_note', 'Для педагога'),
              ])
                ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: _commentKind == kind,
                  selectedColor: AppColor.goldSoft,
                  onSelected: (_) => setState(() => _commentKind = kind),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                decoration: _inputDecoration(
                  cs,
                  hint: 'Написать комментарий...',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Material(
              color: AppColor.gold,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: _addComment,
                child: const Padding(
                  padding: EdgeInsets.all(AppSpace.md),
                  child: Icon(
                    Icons.send_rounded,
                    color: AppColor.onGold,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAggregateCard(ColorScheme cs, {bool includeTasks = true}) {
    if (_loadingCard) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: LinearProgressIndicator(color: AppColor.gold),
      );
    }
    final card = _leadCard;
    if (card == null) {
      return Text(
        'Карточка активности временно недоступна',
        style: TextStyle(color: cs.onSurfaceVariant),
      );
    }

    final linkedStudents = _list(card['linked_students']);
    final tasks = _list(card['tasks']);
    final trials = _list(card['trials']);
    final otherLeads = _list(card['other_leads']);
    final timeline = _list(card['timeline']);
    final duplicateCandidates = _duplicateCandidates
        .where(_isCurrentLeadDuplicateCandidate)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            _summaryChip(
              Icons.school_outlined,
              'Ученики',
              linkedStudents.length,
            ),
            _summaryChip(Icons.task_alt_rounded, 'Задачи', tasks.length),
            _summaryChip(
              Icons.event_available_rounded,
              'Пробные',
              trials.length,
            ),
            _summaryChip(Icons.link_rounded, 'Похожие лиды', otherLeads.length),
            if (_loadingDuplicates || duplicateCandidates.isNotEmpty)
              _summaryChip(
                Icons.merge_type_rounded,
                'Кандидаты',
                duplicateCandidates.length,
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        _miniSection(
          cs,
          title: 'Связанные ученики',
          empty: 'Связанных учеников нет',
          rows: linkedStudents,
          titleBuilder: (row) =>
              '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim(),
          subtitleBuilder: (row) => row['phone']?.toString(),
        ),
        if (includeTasks)
          _miniSection(
            cs,
            title: 'Задачи',
            empty: 'Открытых задач нет',
            rows: tasks,
            titleBuilder: (row) => row['title']?.toString() ?? 'Задача',
            subtitleBuilder: (row) => _formatStatus(row['status']),
          ),
        _miniSection(
          cs,
          title: 'Пробные занятия',
          empty: 'Пробные занятия не назначены',
          rows: trials,
          titleBuilder: (row) => _formatDate(row['scheduled_at']),
          subtitleBuilder: (row) => [
            row['teacher_name'],
            row['room_name'],
          ].where((value) => value != null && '$value'.isNotEmpty).join(' · '),
          action: _mode.hasLeadHalf
              ? TextButton.icon(
                  onPressed: _scheduleTrialFromCard,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColor.gold,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 15),
                  label: const Text('На пробный'),
                )
              : null,
        ),
        // KVA-234: заявки лида (HolliHop GetStudyRequests) — порядок секций по
        // HolliHop: Связанные ученики → Пробные занятия → Заявки → Лента.
        _miniSection(
          cs,
          title: 'Заявки',
          empty: 'Заявок нет',
          rows: _leadApplications,
          titleBuilder: (row) => _formatDate(row['applied_at']),
          subtitleBuilder: (row) {
            final utm = row['utm'];
            final utmSource = utm is Map ? utm['Source']?.toString() : null;
            return [row['channel'], row['discipline'], utmSource]
                .where((value) => value != null && '$value'.isNotEmpty)
                .join(' · ');
          },
        ),
        _miniSection(
          cs,
          title: 'Лента',
          empty: 'История пока пустая',
          rows: timeline.take(8).toList(),
          titleBuilder: (row) => row['title']?.toString() ?? 'Событие',
          subtitleBuilder: (row) => _formatDate(row['occurred_at']),
        ),
      ],
    );
  }

  String _familyRoleLabel(Object? role) {
    return switch (role?.toString()) {
      'parent' => 'Родитель',
      'child' => 'Ребёнок',
      'guardian' => 'Опекун',
      'payer' => 'Плательщик',
      'sibling' => 'Брат/сестра',
      final value when value != null && value.isNotEmpty => value,
      _ => 'Член семьи',
    };
  }

  Widget _buildFamilySection(ColorScheme cs) {
    if (_loadingFamily) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: LinearProgressIndicator(color: AppColor.gold),
      );
    }
    final family = _family?['family'] as Map<String, dynamic>?;
    final members = _list(_family?['members']);
    if (family == null) {
      return Text(
        'Семья не указана',
        style: TextStyle(color: cs.onSurfaceVariant),
      );
    }
    final primaryId = family['primary_payer_member_id']?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((family['name']?.toString().trim().isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              family['name'].toString(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        if (members.isEmpty)
          Text(
            'Участники не добавлены',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          )
        else
          ...members.map((m) {
            final isPayer =
                primaryId != null && m['id']?.toString() == primaryId;
            final subtitle = [
              _familyRoleLabel(m['role']),
              if (m['is_primary_contact'] == true) 'Осн. контакт',
              if (isPayer) 'Плательщик',
            ].where((value) => value.isNotEmpty).join(' · ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  side: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                leading: const Icon(
                  Icons.people_alt_rounded,
                  size: 18,
                  color: AppColor.gold,
                ),
                title: Text(
                  (m['name']?.toString().trim().isNotEmpty ?? false)
                      ? m['name'].toString()
                      : 'Без имени',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: subtitle.isEmpty ? null : Text(subtitle),
                trailing: IconButton(
                  tooltip: 'Удалить участника',
                  visualDensity: VisualDensity.compact,
                  onPressed: _familyBusy ? null : () => _removeFamilyMember(m),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: AppTheme.danger,
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  // Role keys understood by the family API, paired with Russian labels for the
  // add-member sheet picker.
  // Reads the family id out of either the existing `_family` payload or the
  // raw `createFamily` response (which nests the record under `family`).
  String? _familyIdFrom(Map<String, dynamic>? source) {
    if (source == null) return null;
    final direct = source['id']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = source['family'];
    if (nested is Map) {
      final id = nested['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  Future<void> _openAddFamilyMemberSheet() async {
    final selfId = _leadData['id']?.toString() ?? widget.lead['id']?.toString();
    final input = await showAddFamilyMemberSheet(
      context,
      isStudent: _isStudent,
      // Default the linked record to this card's own entity (lead or student).
      defaultEntityType: widget.entityType,
      defaultEntityId: selfId,
    );
    if (input == null) return;
    final role = input.role;
    final entityType = input.entityType;
    final entityId = input.entityId;
    final isPrimaryContact = input.isPrimaryContact;
    if (entityId.isEmpty) {
      if (mounted) {
        MagicToast.show(
          context,
          'Укажите ID записи',
          type: MagicToastType.danger,
        );
      }
      return;
    }

    setState(() => _familyBusy = true);
    try {
      final crm = ref.read(magicCrmServiceProvider);
      var familyId = _familyIdFrom(_family?['family'] as Map<String, dynamic>?);
      if (familyId == null) {
        final branchId = _leadData['branch_id']?.toString();
        final created = await crm.createFamily({
          if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
        });
        familyId = _familyIdFrom(created);
        if (familyId == null) {
          throw StateError('Не удалось получить идентификатор семьи');
        }
      }
      await crm.addFamilyMember(
        familyId,
        entityType: entityType,
        entityId: entityId,
        role: role,
        isPrimaryContact: isPrimaryContact ? true : null,
      );
      await _fetchFamily();
      if (mounted) {
        MagicToast.show(
          context,
          'Участник добавлен',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка добавления',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _familyBusy = false);
    }
  }

  Future<void> _removeFamilyMember(Map<String, dynamic> member) async {
    final memberId = member['id']?.toString();
    if (memberId == null || memberId.isEmpty) return;
    final name = (member['name']?.toString().trim().isNotEmpty ?? false)
        ? member['name'].toString()
        : 'участника';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: Text('Связь "$name" с семьёй будет удалена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _familyBusy = true);
    try {
      await ref.read(magicCrmServiceProvider).removeFamilyMember(memberId);
      await _fetchFamily();
      if (mounted) {
        MagicToast.show(
          context,
          'Участник удалён',
          type: MagicToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        MagicToast.show(
          context,
          'Ошибка удаления',
          detail: '$e',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _familyBusy = false);
    }
  }

  Widget _buildStatusHistorySection(ColorScheme cs) {
    if (_loadingHistory) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: LinearProgressIndicator(color: AppColor.gold),
      );
    }
    if (_statusHistory.isEmpty) {
      return Text(
        'Изменений статуса пока нет',
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _statusHistory.take(12).map((h) {
        final from = h['old_status']?.toString();
        final to = h['new_status']?.toString();
        final transition = [
          if (from != null && from.isNotEmpty) from else '—',
          '→',
          if (to != null && to.isNotEmpty) to else '—',
        ].join(' ');
        final comment = h['comment']?.toString().trim() ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            leading: const Icon(
              Icons.history_rounded,
              size: 18,
              color: AppColor.gold,
            ),
            title: Text(
              transition,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                _formatDate(h['changed_at']),
                if (comment.isNotEmpty) comment,
              ].where((value) => value.isNotEmpty).join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(),
    );
  }

  List<Map<String, dynamic>> _list(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map<String, dynamic>>().toList();
  }

  Widget _summaryChip(IconData icon, String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColor.goldSoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColor.goldLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColor.gold),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: const TextStyle(
              color: AppColor.gold,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _duplicateCandidatesSection(
    ColorScheme cs,
    List<Map<String, dynamic>> candidates,
  ) {
    if (_loadingDuplicates) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: LinearProgressIndicator(color: AppColor.gold),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Кандидаты на связь с учеником',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          ...candidates.take(4).map((candidate) {
            final student = _candidateEntity(candidate, 'student');
            final title = student['name']?.toString().trim();
            final subtitle =
                [
                      student['phone'],
                      student['email'],
                      _duplicateMatchText(candidate),
                    ]
                    .where((value) => value != null && '$value'.isNotEmpty)
                    .join(' · ');
            final candidateId = candidate['id']?.toString();
            final pending =
                candidateId != null && candidateId == _duplicateDecisionId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  side: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                title: Text(
                  title == null || title.isEmpty
                      ? 'Существующий ученик'
                      : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: subtitle.isEmpty
                    ? null
                    : Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColor.goldSoft,
                    foregroundColor: AppColor.gold,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                  ),
                  onPressed: pending
                      ? null
                      : () => _attachDuplicateCandidate(candidate),
                  icon: pending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_rounded, size: 16),
                  label: const Text('Связать'),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  bool _isCurrentLeadDuplicateCandidate(Map<String, dynamic> candidate) {
    final leadId = _leadData['id']?.toString() ?? widget.lead['id']?.toString();
    if (leadId == null || leadId.isEmpty) return false;
    return (candidate['entity_type_a'] == 'lead' &&
            candidate['entity_id_a'] == leadId &&
            candidate['entity_type_b'] == 'student') ||
        (candidate['entity_type_b'] == 'lead' &&
            candidate['entity_id_b'] == leadId &&
            candidate['entity_type_a'] == 'student');
  }

  Map<String, dynamic> _candidateEntity(
    Map<String, dynamic> candidate,
    String entityType,
  ) {
    if (candidate['entity_type_a'] == entityType) {
      final value = candidate['entity_a'];
      return value is Map<String, dynamic> ? value : const <String, dynamic>{};
    }
    if (candidate['entity_type_b'] == entityType) {
      final value = candidate['entity_b'];
      return value is Map<String, dynamic> ? value : const <String, dynamic>{};
    }
    return const <String, dynamic>{};
  }

  String _duplicateMatchText(Map<String, dynamic> candidate) {
    final matchValue = candidate['match_value']?.toString().trim() ?? '';
    final confidence = _asNum(candidate['confidence']);
    final confidenceText = confidence > 0
        ? '${(confidence * 100).round()}% совпадение'
        : '';
    return [
      if (matchValue.isNotEmpty) matchValue,
      if (confidenceText.isNotEmpty) confidenceText,
    ].join(' · ');
  }

  num _asNum(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  Widget _entityTile(
    ColorScheme cs, {
    required String title,
    String? subtitle,
    required IconData leading,
    String? origin,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        leading: Icon(leading, size: 18, color: AppColor.gold),
        title: Text(
          title.isEmpty ? 'Без названия' : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: subtitle == null || subtitle.isEmpty
            ? null
            : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: origin == null ? null : ClientOriginChip(entityType: origin),
      ),
    );
  }

  Widget _miniSection(
    ColorScheme cs, {
    required String title,
    required String empty,
    required List<Map<String, dynamic>> rows,
    required String Function(Map<String, dynamic>) titleBuilder,
    required String? Function(Map<String, dynamic>) subtitleBuilder,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            Text(
              empty,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            )
          else
            ...rows.take(4).map((row) {
              final subtitle = subtitleBuilder(row);
              final titleText = titleBuilder(row);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    side: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  tileColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  title: Text(
                    titleText.isEmpty ? 'Без названия' : titleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: subtitle == null || subtitle.isEmpty
                      ? null
                      : Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              );
            }),
        ],
      ),
    );
  }

  String _formatStatus(Object? status) {
    return switch (status?.toString()) {
      'open' => 'Открыта',
      'in_progress' => 'В работе',
      'done' => 'Выполнена',
      'cancelled' => 'Отменена',
      final value when value != null && value.isNotEmpty => value,
      _ => '',
    };
  }

  String _formatDate(Object? raw) {
    final dt = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (dt == null) return '';
    return DateFormat('dd.MM.yyyy HH:mm', 'ru').format(dt);
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    // New comments target the card's primary half: the student side for a
    // converted client (where most activity lives), otherwise the open entity.
    final targetType = _isConverted ? 'student' : widget.entityType;
    final targetId = _isConverted ? _studentId : _entityId;
    if (targetId.isEmpty) return;
    // kind существует только у entity_comments (ученик): staff выбирает поток,
    // педагог всегда пишет teacher_note (admin_comment ему запрещён RBAC'ом).
    final role = ref.read(releaseGateStatusProvider).asData?.value.role;
    final kind = targetType != 'student'
        ? null
        : _canPickCommentKind
        ? _commentKind
        : role == 'teacher'
        ? 'teacher_note'
        : null;
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createComment(
            entityType: targetType,
            entityId: targetId,
            body: text,
            kind: kind,
          );
      _commentCtrl.clear();
      if (mounted) {
        setState(() => _commentsRefreshKey++);
        if (_mode.hasStudentHalf) {
          _fetchStudentData();
        }
        if (_mode.hasLeadHalf) {
          _fetchCard();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }
}

