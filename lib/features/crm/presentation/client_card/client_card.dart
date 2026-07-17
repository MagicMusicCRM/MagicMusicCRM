import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
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
import 'package:magic_music_crm/core/models/comment.dart';
import 'package:magic_music_crm/core/models/family_member.dart';
import 'package:magic_music_crm/core/models/student_balance.dart';
import 'package:magic_music_crm/core/models/payment.dart';
import 'package:magic_music_crm/core/models/subscription.dart';
import 'package:magic_music_crm/core/models/lesson.dart';
import '../trial_lesson_booking.dart';
import 'client_card_aggregation.dart';
import 'client_card_dialogs.dart';
import 'client_card_sheets.dart';
import 'client_card_ui.dart';
import 'student_schedule_section.dart';

part 'client_card_widgets.dart';
part 'client_card_display.dart';
part 'client_card_sections.dart';
part 'client_card_student_tabs.dart';
part 'client_card_data.dart';
part 'client_card_tabs_a.dart';
part 'client_card_tabs_b.dart';
part 'client_card_student.dart';
part 'client_card_editors.dart';

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
  // Cached so card rebuilds (keystrokes, tab switches, Приход/Расход toggle)
  // don't re-fetch the ledger — an inline future restarts a FutureBuilder on
  // every build. Reset to null by _refreshLedger.
  Future<Map<String, dynamic>>? _ledgerFuture;
  // Resolved status list: either the one passed in or self-fetched.
  List<StatusRecord> _statuses = const [];
  bool _saving = false;
  bool _converting = false;
  bool _loadingCard = true;
  int _commentsRefreshKey = 0;
  // Bumped after a homework is assigned so the «Прогресс» tab refetches.
  int _homeworkRefreshKey = 0;
  Map<String, dynamic>? _leadCard;
  List<Map<String, dynamic>> _duplicateCandidates = [];
  bool _loadingDuplicates = true;
  bool _dirty = false;
  List<Map<String, dynamic>> _statusHistory = [];
  List<Map<String, dynamic>> _studentCardTimeline = const [];
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
  // student tab set (Инфо / Задачи / Комментарии / Семья / Занятия / Оплаты /
  // История). A converted client (lead → student) reuses the student tab set —
  // its body folds in the lead Инфо/source section and the merged comments /
  // tasks / history.
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
  StudentBalance? _balance;
  List<Subscription> _subscriptions = [];
  List<Payment> _payments = [];
  List<Lesson> _lessons = [];
  List<Map<String, dynamic>> _studentTasks = [];
  // Unified comment stream folded into the «История» merge — the «Комментарии»
  // tab reads live via [_CommentsList].
  List<Map<String, dynamic>> _studentComments = [];
  List<Map<String, dynamic>> _groups = [];
  bool _loadingStudent = true;
  String? _studentError;
  bool _realtimeRefreshQueued = false;
  // Bumped ONLY when field values are replaced from the server (fetch/merge).
  // Text editors key on this instead of their live value, so local keystrokes
  // never recreate the field (which would drop cursor/focus/IME state), while
  // a server refresh still re-seeds initialValue.
  int _editorEpoch = 0;

  /// Бан применяется своим запросом, а не «Сохранить» вместе с полями карточки
  /// — на время запроса тумблер заперт, чтобы двойной тап не отправил бан и
  /// разбан наперегонки.
  bool _blacklistBusy = false;

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
    'age',
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
  //
  // `age` — свой редактор по другой причине: при заполненной дате рождения
  // возраст считается из неё, и вписанное руками число не читается. Обычное
  // поле ввода в этом случае врало бы, что его слушают.
  static const Set<String> _customKeysWithDedicatedEditor = {
    'age',
    'contactPersonName',
    'contactPersonRelation',
    'contactPersonPhone',
    'contactPersonEmail',
    'discipline',
  };

  // `blacklisted` здесь больше нет: ✔ решение владельца 17.07 сделало чёрный
  // список баном — у него автор, причина и последствие (клиенту закрыты чаты),
  // ставится он своим эндпоинтом и живёт в колонке, а не в custom_data.
  static const Set<String> _studentOnlyCustomFieldKeys = {
    'workplace',
    'position',
    'contractStatus',
    'cabinetStatus',
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

  // setState guarded by mounted, so logic/builder methods can live in
  // extension part files (extensions cannot call the @protected setState).
  void _emitState(void Function() fn) {
    if (mounted) setState(fn);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
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
              // ✔ Владелец 17.07: карточка забаненного помечается красным.
              // Над вкладками, а не внутри одной из них: бан касается всей
              // карточки, и он не должен зависеть от того, куда сотрудник
              // успел переключиться.
              if (_isBlacklisted) _buildBlacklistBanner(cs),
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
}
