import 'dart:async';

import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/providers/crm_navigation_provider.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/homework_attachment_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/widgets/searchable_select.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';
import 'package:magic_music_crm/features/admin/presentation/providers/schedule_navigation_provider.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/schedule_widget.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/create_lesson_dialog.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/client_app_user_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/tasks/shared_tasks_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/students_board_providers.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:magic_music_crm/features/auth/providers/magic_auth_provider.dart';
import 'package:magic_music_crm/core/navigation/crm_nav_rbac.dart';
import 'package:magic_music_crm/features/crm/presentation/client_forms/client_forms_api.dart';
import 'package:magic_music_crm/core/utils/status_color.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/homework_attachment_widgets.dart';
import 'package:magic_music_crm/core/widgets/magic_desktop_scrollbar.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';
import 'package:magic_music_crm/core/widgets/magic_toast.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/models/types.dart';
import 'package:magic_music_crm/core/models/comment.dart';
import 'package:magic_music_crm/core/models/client_internal_context.dart';
import 'package:magic_music_crm/core/models/commerce_projection.dart';
import 'package:magic_music_crm/core/models/family_member.dart';
import 'package:magic_music_crm/core/models/student_balance.dart';
import 'package:magic_music_crm/core/models/payment.dart';
import 'package:magic_music_crm/core/models/subscription.dart';
import 'package:magic_music_crm/core/models/lesson.dart';
import 'package:magic_music_crm/core/models/student_funnel.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/navigation/entity_link_text.dart';
import 'package:magic_music_crm/core/workspace/workspace_navigation_scope.dart';
import 'package:magic_music_crm/core/workspace/workspace_state.dart';
import 'client_card_aggregation.dart';
import 'client_archive_button.dart';
import 'comment_share_button.dart';
import 'client_card_dialogs.dart';
import 'client_card_sheets.dart';
import 'client_card_ui.dart';
import 'subscription_cancel_sheet.dart';
import 'subscription_issue_sheet.dart';
import 'subscription_replace_sheet.dart';
import 'lead_lesson_date_tray.dart';
import 'recurring_schedule_plan_section.dart';
import 'client_payment_form.dart';
import 'client_payment_correction_sheet.dart';
import 'client_internal_context_widgets.dart';
import 'client_card_access_policy.dart';
import 'client_card_shell.dart';
import 'client_card_workspace_controller.dart';

part 'client_card_widgets.dart';
part 'client_card_display.dart';
part 'client_card_sections.dart';
part 'client_card_student_tabs.dart';
part 'client_card_internal_context.dart';
part 'client_card_counterpart_resolution.dart';
part 'client_card_loaders.dart';
part 'client_card_realtime.dart';
part 'client_card_persistence.dart';
part 'client_card_workspace_draft.dart';
part 'client_card_header.dart';
part 'client_card_overview_tab.dart';
part 'client_card_tasks_tab.dart';
part 'client_card_collaboration_tabs.dart';
part 'client_card_presentation.dart';
part 'client_card_student.dart';
part 'client_card_custom_fields.dart';
part 'client_card_custom_field_inputs.dart';
part 'client_card_moderation.dart';
part 'client_card_contact_editors.dart';
part 'client_card_assignment_editors.dart';
part 'client_card_comment_editor.dart';
part 'client_card_family_access.dart';
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
    this.workspaceTabId,
  });

  final bool routed;
  final String initialSection;
  final ValueChanged<String>? onSectionChanged;
  final ValueChanged<bool?>? onClose;
  final CapabilitySnapshot? capabilitySnapshot;
  final ContextViewState? initialViewState;
  final ValueChanged<ContextViewState>? onViewStateChanged;
  final String? workspaceTabId;

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
  // Resolved status list: either the one passed in or self-fetched.
  List<StatusRecord> _statuses = const [];
  bool _saving = false;
  Timer? _autoSaveTimer;
  Future<bool>? _autoSaveInFlight;
  int _editRevision = 0;
  bool _autoSavePending = false;
  bool _autoSaveQueued = false;
  bool _autoSaveFailed = false;
  bool _autoSaveConflict = false;
  final Map<String, int> _leadCoreEditRevisions = {};
  final Map<String, int> _studentCoreEditRevisions = {};
  final Map<String, int> _leadCustomEditRevisions = {};
  final Map<String, int> _studentCustomEditRevisions = {};
  int? _leadStatusEditRevision;
  int? _studentStatusEditRevision;
  int? _leadResponsibleEditRevision;
  int? _studentResponsibleEditRevision;
  bool _converting = false;
  bool _replacingSubscription = false;
  bool _cancellingSubscription = false;
  bool _creatingPayment = false;
  CommerceMovement? _adjustingPayment;
  bool _loadingCard = true;
  int _commentsRefreshKey = 0;
  // Bumped after a homework is assigned so the «Прогресс» tab refetches.
  int _homeworkRefreshKey = 0;
  Map<String, dynamic>? _leadCard;
  List<Map<String, dynamic>> _duplicateCandidates = [];
  bool _loadingDuplicates = true;
  Map<String, dynamic>? _family;
  bool _loadingFamily = true;
  // True while a family add/remove write is in flight — disables the family
  // action controls so a double-tap can't fire two mutations.
  bool _familyBusy = false;
  bool _clientAccessAllowed = false;
  bool _loadingClientAccess = false;
  bool _clientAccessBusy = false;
  String? _clientAccessError;
  List<Map<String, dynamic>> _linkedUsers = const [];
  List<Map<String, dynamic>> _clientUserCandidates = const [];
  String? _duplicateDecisionId;

  late final ClientCardWorkspaceController _workspaceController;
  WorkspaceNavigationScope? _registeredWorkspaceScope;
  String? _registeredWorkspaceTabId;
  String? _registeredWorkspaceFormKey;
  int _workspaceRegistrationGeneration = 0;
  bool _workspaceDraftSyncScheduled = false;
  WorkspaceFormState? _restoredWorkspaceForm;
  bool _restoredWorkspaceDraftApplied = false;
  int? _restoredLeadExpectedVersion;
  int? _restoredStudentExpectedVersion;
  ClientInternalNoteDraft? _workspaceInternalNoteDraft;
  bool get _dirty => _workspaceController.dirty;
  bool get _edited => _workspaceController.edited;
  set _edited(bool value) {
    _workspaceController.edited = value;
    if (value) {
      _editRevision++;
      if (_autoSaveConflict) {
        _autoSaveFailed = true;
      } else {
        _autoSaveFailed = false;
        _scheduleAutoSave();
      }
    }
    _syncWorkspaceFormDirty();
    if (value) _scheduleWorkspaceDraftSync();
  }

  String get _selectedSection => _workspaceController.selectedSection;
  ScrollController get _taskScrollController =>
      _workspaceController.taskScrollController;
  ScrollController get _paymentScrollController =>
      _workspaceController.paymentScrollController;
  ScrollController get _subscriptionScrollController =>
      _workspaceController.subscriptionScrollController;
  ScrollController get _desktopScrollController =>
      _workspaceController.desktopScrollController;
  bool get _desktopCalendarExpanded =>
      _workspaceController.desktopCalendarExpanded;
  set _desktopCalendarExpanded(bool value) =>
      _workspaceController.desktopCalendarExpanded = value;
  bool get _customFieldsExpanded => _workspaceController.customFieldsExpanded;
  set _customFieldsExpanded(bool value) =>
      _workspaceController.customFieldsExpanded = value;
  bool _internalContextAllowed = false;
  bool _internalContextLoading = false;
  bool _operationalHistoryLoadingMore = false;
  String? _internalContextError;
  ClientInternalNote? _internalNote;
  bool _internalNoteIsPending = false;
  bool get _internalNotePending => _internalNoteIsPending;
  set _internalNotePending(bool value) {
    _internalNoteIsPending = value;
    _syncWorkspaceFormDirty();
  }

  ClientInternalNoteFlush? _flushInternalNote;
  List<AuditPresentationEvent> _operationalHistory = const [];
  String? _operationalHistoryCursor;
  final Map<String, GlobalKey> _desktopSectionKeys = {
    for (final section in [
      'overview',
      'lessons',
      'payments',
      'subscriptions',
      'progress',
      'history_tasks',
      'contacts',
      'documents',
    ])
      section: GlobalKey(),
  };

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

  String? get _snapshotActorRole {
    final role = widget.capabilitySnapshot?.role.trim();
    return role == null || role.isEmpty ? null : role;
  }

  String? _currentActorRole([String? releaseGateRole]) =>
      _snapshotActorRole ??
      releaseGateRole ??
      ref.read(releaseGateStatusProvider).asData?.value.role;

  Future<String> _resolveActorRole() async =>
      _snapshotActorRole ??
      (await ref.read(releaseGateStatusProvider.future)).role;

  // Effective ids for each half once resolution settles. Fall back to the open
  // entity id so the single-side modes behave exactly as before.
  String get _studentId =>
      _resolvedStudentId ?? (widget.entityType == 'student' ? _entityId : '');
  String get _leadId =>
      _resolvedLeadId ?? (widget.entityType == 'lead' ? _entityId : '');

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
  StudentFunnelConfiguration? _studentFunnel;
  String? _studentFunnelError;
  StudentBalance? _balance;
  List<Subscription> _subscriptions = [];
  List<Payment> _payments = [];
  CommerceStudent? _commerceStudent;
  List<Lesson> _lessons = [];
  Map<String, int> _studentIndicators = const {};
  List<Map<String, dynamic>> _studentTasks = [];
  // Unified comment stream folded into the «История» merge — the «Комментарии»
  // tab reads live via [_CommentsList].
  List<Map<String, dynamic>> _studentComments = [];
  List<Map<String, dynamic>> _groups = [];
  bool _loadingStudent = true;
  String? _studentError;
  bool _realtimeRefreshQueued = false;
  final List<CrmChangedEvent> _realtimeRefreshQueue = [];
  final List<CrmChangedEvent> _realtimeRefreshDeferred = [];
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
    if (!await _flushPendingClientEdits() || !mounted) return;
    _closeCard(_workspaceController.terminalCloseResult);
  }

  Future<bool> _flushPendingClientEdits() async {
    final flushInternalNote = _flushInternalNote;
    if (_internalNotePending) {
      if (flushInternalNote == null) return false;
      if (!await flushInternalNote()) return false;
    }
    return _flushAutoSave();
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
  List<Map<String, dynamic>> _sources = [];
  bool _loadingMetadata = true;
  List<CrmCustomFieldDefinition> _customFieldSchema = const [];
  bool _typedCustomFieldSchemaLoaded = false;
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
    'adsource',
    'advertisingsource',
    'advertising_source',
    'source',
    'sourceid',
    // Direction is edited through the canonical /crm/disciplines catalog.
    // The old typed definition can remain non-system in upgraded databases,
    // but it must never create a second, stale validation path.
    'discipline',
    'disciplines',
  };

  static const Set<String> _commonClientCustomFieldKeys = {
    'middleName',
    'gender',
    'birthday',
    'age',
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

  static const Set<String> _primaryBusinessCustomFieldKeys = {
    'requestType',
    'learningGoal',
    'level',
    'category',
    'lessonType',
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
  @override
  void initState() {
    super.initState();
    final restoredOffset = widget.initialViewState?.scrollOffset ?? 0;
    _workspaceController = ClientCardWorkspaceController(
      initialSection: widget.initialSection,
      restoredOffset: restoredOffset,
    );
    if (_selectedSection != 'overview') {
      _workspaceController.schedulePostFrameIntent(
        () => unawaited(
          _ensureDesktopSectionVisible(
            _selectedSection,
            animated: false,
            additionalOffset: restoredOffset,
          ),
        ),
      );
    }
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
      _fetchClientAccess();
      _fetchInternalContext();
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
    _fetchFamily();
    _fetchClientAccess();
    _fetchInternalContext();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleWorkspaceFormRegistration();
  }

  @override
  void didUpdateWidget(covariant ClientCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleWorkspaceFormRegistration();
    if (oldWidget.initialSection != widget.initialSection) {
      _workspaceController.restoreSection(widget.initialSection);
      _workspaceController.schedulePostFrameIntent(
        () => unawaited(_ensureDesktopSectionVisible(_selectedSection)),
      );
    }
  }

  void _scheduleWorkspaceFormRegistration() {
    final scope = WorkspaceNavigationScope.maybeOf(context);
    final workspaceScope = scope?.isDesktop == true ? scope : null;
    final tabId = widget.workspaceTabId;
    final formKey = 'client-card:${widget.entityType}:$_entityId';
    if (_registeredWorkspaceScope?.controller == workspaceScope?.controller &&
        _registeredWorkspaceTabId == tabId &&
        _registeredWorkspaceFormKey == formKey) {
      final controller = workspaceScope?.controller;
      final formStillMounted =
          controller != null &&
          tabId != null &&
          controller.state.tabs.any(
            (tab) => tab.tabId == tabId && tab.forms.containsKey(formKey),
          );
      if (formStillMounted) {
        controller.registerForm(
          tabId,
          formKey,
          onSave: _flushPendingClientEdits,
        );
        _restoreWorkspaceFormIfNeeded(
          controller.state.tabs
              .firstWhere((tab) => tab.tabId == tabId)
              .forms[formKey],
        );
        return;
      }
    }
    final generation = ++_workspaceRegistrationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _workspaceRegistrationGeneration) return;
      _unregisterWorkspaceForm(preserveDirtyDraft: true);
      if (workspaceScope == null || tabId == null) return;
      final controller = workspaceScope.controller;
      if (!controller.state.tabs.any((tab) => tab.tabId == tabId)) return;
      controller.registerForm(tabId, formKey, onSave: _flushPendingClientEdits);
      final registeredForm = controller.state.tabs
          .firstWhere((tab) => tab.tabId == tabId)
          .forms[formKey];
      _registeredWorkspaceScope = workspaceScope;
      _registeredWorkspaceTabId = tabId;
      _registeredWorkspaceFormKey = formKey;
      final restoringDraft = _restoreWorkspaceFormIfNeeded(registeredForm);
      if (!restoringDraft) {
        // This is a newly mounted live form, not a persisted recovery draft.
        // Later parent rebuilds must not replay its own current draft.
        _restoredWorkspaceDraftApplied = true;
        _syncWorkspaceFormDirty();
      }
    });
  }

  void _syncWorkspaceFormDirty() {
    final workspaceScope = _registeredWorkspaceScope;
    final tabId = _registeredWorkspaceTabId;
    final formKey = _registeredWorkspaceFormKey;
    if (workspaceScope == null || tabId == null || formKey == null) return;
    final dirty = _edited || _internalNotePending;
    final controller = workspaceScope.controller;
    if (!controller.state.tabs.any((tab) => tab.tabId == tabId)) return;
    controller.updateForm(
      tabId,
      formKey,
      dirty: dirty,
      expectedVersion: _workspaceExpectedVersion,
      draft: dirty ? _buildWorkspaceDraft() : const {},
    );
  }

  void _unregisterWorkspaceForm({bool preserveDirtyDraft = false}) {
    final workspaceScope = _registeredWorkspaceScope;
    final tabId = _registeredWorkspaceTabId;
    final formKey = _registeredWorkspaceFormKey;
    _registeredWorkspaceScope = null;
    _registeredWorkspaceTabId = null;
    _registeredWorkspaceFormKey = null;
    if (workspaceScope == null || tabId == null || formKey == null) return;
    final controller = workspaceScope.controller;
    if (!controller.state.tabs.any((tab) => tab.tabId == tabId)) return;
    controller.unregisterForm(
      tabId,
      formKey,
      preserveDirtyDraft: preserveDirtyDraft,
    );
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

  void _markDirty([VoidCallback? update]) {
    _emitState(() {
      update?.call();
      _workspaceController.dirty = true;
    });
  }

  void _recordCoreEdit(String key) {
    if (_mode.hasLeadHalf) _leadCoreEditRevisions[key] = _editRevision;
    if (_mode.hasStudentHalf) _studentCoreEditRevisions[key] = _editRevision;
  }

  bool get _hasPendingCardEdits =>
      _leadCoreEditRevisions.isNotEmpty ||
      _studentCoreEditRevisions.isNotEmpty ||
      _leadCustomEditRevisions.isNotEmpty ||
      _studentCustomEditRevisions.isNotEmpty ||
      _leadStatusEditRevision != null ||
      _studentStatusEditRevision != null ||
      _leadResponsibleEditRevision != null ||
      _studentResponsibleEditRevision != null;

  void _selectSection(String section) {
    unawaited(_selectSectionAfterPendingNote(section));
  }

  Future<void> _selectSectionAfterPendingNote(String section) async {
    if (section != _selectedSection && _internalNotePending) {
      final flush = _flushInternalNote;
      if (flush != null && !await flush()) return;
    }
    if (!mounted) return;
    _emitState(() => _workspaceController.selectSection(section));
    widget.onSectionChanged?.call(section);
    _workspaceController.schedulePostFrameIntent(
      () => unawaited(_ensureDesktopSectionVisible(section)),
    );
  }

  Future<void> _ensureDesktopSectionVisible(
    String section, {
    bool animated = true,
    double additionalOffset = 0,
  }) async {
    if (!mounted || !widget.routed || MediaQuery.sizeOf(context).width < 840) {
      return;
    }
    final target = _desktopSectionKeys[section]?.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      alignment: 0.02,
      duration: animated
          ? AppMotion.effective(context, AppMotion.medium)
          : Duration.zero,
      curve: Curves.easeOutCubic,
    );
    if (!mounted ||
        additionalOffset <= 0 ||
        !_workspaceController.desktopScrollController.hasClients) {
      return;
    }
    final position = _workspaceController.desktopScrollController.position;
    _workspaceController.desktopScrollController.jumpTo(
      (position.pixels + additionalOffset).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void _openLinkedRecord(
    BuildContext sourceContext,
    EntityLink link,
    EntityOpenTarget target,
  ) {
    final previous = widget.initialViewState;
    final scrollable = Scrollable.maybeOf(sourceContext);
    unawaited(
      openEntityLink(
        context,
        ref,
        link,
        target: target,
        sourceViewState: ContextViewState(
          filters: {...?previous?.filters, 'section': _selectedSection},
          date: previous?.date,
          scrollOffset:
              scrollable?.position.pixels ?? previous?.scrollOffset ?? 0,
          selectedColumn: previous?.selectedColumn,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _workspaceRegistrationGeneration++;
    _syncWorkspaceFormDirty();
    _unregisterWorkspaceForm(preserveDirtyDraft: true);
    _autoSaveTimer?.cancel();
    _commentCtrl.dispose();
    _workspaceController.dispose();
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
      _scheduleRealtimeRefresh(event);
    });

    final cs = Theme.of(context).colorScheme;
    final releaseGateRole = ref
        .watch(releaseGateStatusProvider)
        .asData
        ?.value
        .role;
    final actorRole = _currentActorRole(releaseGateRole);
    final access = ClientCardAccessPolicy.project(
      actorRole: actorRole ?? '',
      capabilitySnapshot: widget.capabilitySnapshot,
      hasStudentHalf: _isStudent,
    );
    final tabs = access.sections;
    final selectedIndex = access.selectedIndexFor(_selectedSection);
    final fallbackStatus = _statuses.isNotEmpty
        ? _statuses.first
        : ('new', 'Новый', AppTheme.primaryGold);
    final curStatus = _statuses.firstWhere(
      (element) => element.$1 == _leadData['status'],
      orElse: () => fallbackStatus,
    );

    return ClientCardShell(
      routed: widget.routed,
      edited: _edited || _internalNotePending,
      dirty: _dirty,
      header: _isStudent
          ? _buildStudentHeader(cs, curStatus)
          : _buildHeader(cs, curStatus),
      blacklistBanner: _isBlacklisted ? _buildBlacklistBanner(cs) : null,
      desktopWorkspaceBuilder: (_) => _buildDesktopWorkspaceCanvas(
        cs,
        curStatus,
        tabs,
        canReadClientFinance: access.canReadClientFinance,
        canReadSchedule: access.canReadSchedule,
        canWriteSchedule: access.canWriteSchedule,
        canReadTasks: access.canReadTasks,
      ),
      compactWorkspaceBuilder: (_) => Column(
        children: [
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
                    canReadClientFinance: access.canReadClientFinance,
                    canReadSchedule: access.canReadSchedule,
                    canWriteSchedule: access.canWriteSchedule,
                    canReadTasks: access.canReadTasks,
                  ),
              ],
            ),
          ),
        ],
      ),
      actionBar: _isStudent ? _buildStudentActionBar(cs) : _buildActionBar(cs),
      onCloseRequested: _handleClose,
    );
  }
}
