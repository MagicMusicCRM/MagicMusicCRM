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
import 'package:magic_music_crm/features/messenger/presentation/screens/crm_nav_rbac.dart';
import 'package:magic_music_crm/core/utils/status_color.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/core/theme/lesson_state_palette.dart';
import 'package:magic_music_crm/core/widgets/lesson_state_badges.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/core/models/comment.dart';
import 'package:magic_music_crm/core/models/commerce_projection.dart';
import 'package:magic_music_crm/core/models/family_member.dart';
import 'package:magic_music_crm/core/models/student_balance.dart';
import 'package:magic_music_crm/core/models/payment.dart';
import 'package:magic_music_crm/core/models/subscription.dart';
import 'package:magic_music_crm/core/models/lesson.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'client_card_aggregation.dart';
import 'client_card_staff_api.dart';
import 'client_archive_button.dart';
import 'comment_share_button.dart';
import 'client_card_dialogs.dart';
import 'client_card_sheets.dart';
import 'client_card_ui.dart';
import 'subscription_cancel_sheet.dart';
import 'subscription_issue_sheet.dart';
import 'subscription_replace_sheet.dart';
import 'student_schedule_section.dart';
import 'client_schedule_calendar.dart';

part 'client_card_widgets.dart';
part 'client_card_display.dart';
part 'client_card_sections.dart';
part 'client_card_student_tabs.dart';
part 'client_card_data.dart';
part 'client_card_tabs_a.dart';
part 'client_card_tabs_b.dart';
part 'client_card_student.dart';
part 'client_card_editors.dart';
part 'client_card_workspace_sections.dart';

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
    this.routed = false,
    this.initialSection = 'overview',
    this.onSectionChanged,
    this.onClose,
    this.capabilitySnapshot,
    this.initialViewState,
    this.onViewStateChanged,
  });

  final bool routed;
  final String initialSection;
  final ValueChanged<String>? onSectionChanged;
  final ValueChanged<bool?>? onClose;
  final CapabilitySnapshot? capabilitySnapshot;
  final ContextViewState? initialViewState;
  final ValueChanged<ContextViewState>? onViewStateChanged;

  @override
  ConsumerState<ClientCard> createState() => _ClientCardState();
}

class _ClientCardState extends ConsumerState<ClientCard>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _leadData;
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
  bool _replacingSubscription = false;
  bool _cancellingSubscription = false;
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

  String _selectedSection = 'overview';

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

  static const List<(IconData, String, String)> _leadTabs = [
    (Icons.dashboard_outlined, 'Обзор', 'overview'),
    (Icons.event_note_rounded, 'Занятия', 'lessons'),
    (Icons.history_rounded, 'История и задачи', 'history_tasks'),
    (Icons.people_alt_outlined, 'Контакты', 'contacts'),
    (Icons.folder_outlined, 'Документы', 'documents'),
    (Icons.tune_rounded, 'Доп. поля', 'custom_fields'),
  ];

  static const List<(IconData, String, String)> _studentTabs = [
    (Icons.dashboard_outlined, 'Обзор', 'overview'),
    (Icons.event_note_rounded, 'Занятия', 'lessons'),
    (Icons.account_balance_wallet_rounded, 'Оплаты', 'payments'),
    (Icons.confirmation_number_outlined, 'Абонементы', 'subscriptions'),
    (Icons.history_rounded, 'История и задачи', 'history_tasks'),
    (Icons.people_alt_outlined, 'Контакты', 'contacts'),
    (Icons.folder_outlined, 'Документы', 'documents'),
    (Icons.tune_rounded, 'Доп. поля', 'custom_fields'),
  ];

  List<(IconData, String, String)> _tabsFor({
    required bool canReadClientFinance,
  }) {
    if (!_isStudent) return _leadTabs;
    if (canReadClientFinance) return _studentTabs;
    return _studentTabs
        .where((tab) => tab.$3 != 'payments' && tab.$3 != 'subscriptions')
        .toList(growable: false);
  }

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
  // Distinguish an untouched empty responsible from an explicit user clear.
  // The former lets the backend auto-claim on ordinary work; only the latter
  // sends clearAssignedTo/clearResponsible.
  bool _leadResponsibleChanged = false;
  bool _studentResponsibleChanged = false;

  /// Бан применяется своим запросом, а не «Сохранить» вместе с полями карточки
  /// — на время запроса тумблер заперт, чтобы двойной тап не отправил бан и
  /// разбан наперегонки.
  bool _blacklistBusy = false;

  Future<void> _handleClose() async {
    if (!_edited) {
      _closeCard(_dirty ? true : null);
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
      _closeCard(_dirty ? true : null);
    }
  }

  void _closeCard([bool? result]) {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose(result);
      return;
    }
    Navigator.pop(context, result);
  }

  List<Map<String, dynamic>> _branches = [];
  bool _loadingMetadata = true;
  List<CrmCustomFieldDefinition> _customFieldSchema = const [];
  // KVA-234: справочник дисциплин (GET /crm/disciplines) для мультивыбора.
  List<Map<String, dynamic>> _disciplineOptions = const [];

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
    // #8: «Источник заявки» ('source') удалён — на проде он пуст у всех, а
    // настоящие данные выгрузки лежат в 'adSource' («Рекламный источник»).
    'adSource',
    'requestType',
    'learningGoal',
    'discipline',
    'level',
    'category',
    'lessonType',
    'responsible',
    // #7: id выбранного ответственного едет рядом с именем и в converted-режиме
    // зеркалится между половинами так же, как само имя.
    'responsibleUserId',
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
    // #7: «Ответственный» — не свободный текст, а выбор сотрудника из
    // справочника (GET /api/admin/staff); своя строка-пикер.
    'responsible',
    'responsibleUserId',
    'preferredSchedule',
  };

  // `blacklisted` здесь больше нет: ✔ решение владельца 17.07 сделало чёрный
  // список баном — у него автор, причина и последствие (клиенту закрыты чаты),
  // ставится он своим эндпоинтом и живёт в колонке, а не в custom_data.
  static const Set<String> _studentOnlyCustomFieldKeys = {
    'contractStatus',
    'cabinetStatus',
    'noEmail',
  };

  static const List<String> _studentStatusOptions = [
    'Занимается',
    'Закончил обучение',
    'Саморегистрация',
  ];

  @override
  void initState() {
    super.initState();
    _selectedSection = widget.initialSection;
    _leadData = Map<String, dynamic>.from(widget.lead);
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

  @override
  void didUpdateWidget(covariant ClientCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _selectedSection = widget.initialSection;
    }
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
    final actorRole = ref.watch(releaseGateStatusProvider).asData?.value.role;
    final canReadClientFinance = crmHasClientCardFinanceAccess(actorRole ?? '');
    final canWriteSchedule =
        widget.capabilitySnapshot?.allows('schedule.lesson.write') ??
        crmHasManagerAccess(actorRole ?? '');
    final canReadSchedule = widget.capabilitySnapshot == null
        ? crmHasManagerAccess(actorRole ?? '')
        : widget.capabilitySnapshot!.allows('schedule.lesson.read.assigned') ||
              canWriteSchedule;
    final tabs = _tabsFor(canReadClientFinance: canReadClientFinance);
    final visibleTabIndex = tabs.indexWhere(
      (tab) => tab.$3 == _selectedSection,
    );
    final selectedIndex = visibleTabIndex < 0 ? 0 : visibleTabIndex;
    final fallbackStatus = _statuses.isNotEmpty
        ? _statuses.first
        : ('new', 'Новый', AppTheme.primaryGold);
    final curStatus = _statuses.firstWhere(
      (element) => element.$1 == _leadData['status'],
      orElse: () => fallbackStatus,
    );

    final card = Container(
      width: widget.routed
          ? double.infinity
          : (MediaQuery.of(context).size.width * 0.92)
                .clamp(0.0, 600.0)
                .toDouble(),
      height: widget.routed
          ? double.infinity
          : MediaQuery.of(context).size.height * 0.85,
      color: cs.surface,
      child: Column(
        children: [
          _isStudent
              ? _buildStudentHeader(cs, curStatus)
              : _buildHeader(cs, curStatus),
          if (_isBlacklisted) _buildBlacklistBanner(cs),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
          _buildTabBar(cs, tabs, selectedIndex: selectedIndex),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: [
                for (final tab in tabs)
                  _buildWorkspaceSection(
                    cs,
                    curStatus,
                    tab.$3,
                    canReadClientFinance: canReadClientFinance,
                    canReadSchedule: canReadSchedule,
                    canWriteSchedule: canWriteSchedule,
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
          _isStudent
              ? _buildStudentActionBar(
                  cs,
                  canReadClientFinance: canReadClientFinance,
                )
              : _buildActionBar(cs),
        ],
      ),
    );
    return PopScope(
      canPop: !_edited,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleClose();
      },
      child: widget.routed
          ? card
          : Dialog(
              backgroundColor: cs.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                side: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: card,
            ),
    );
  }
}
