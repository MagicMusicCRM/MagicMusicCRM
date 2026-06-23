import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/client_app_user_panel.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/leads_providers.dart';
import 'package:magic_music_crm/core/utils/status_color.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/models/types.dart';

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
  // Оплаты / Инвойсы / Документы / История / Прогресс).
  int _tabIndex = 0;
  bool get _isStudent => widget.entityType == 'student';
  String get _entityId => widget.lead['id'].toString();

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

  // ── Student state (entityType == 'student') ───────────────────────────────
  // Loaded from `getStudentCard` (+ a family fetch). Each section is isolated so
  // a single failed call never blanks the whole card.
  Map<String, dynamic>? _student;
  Map<String, dynamic>? _balance;
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

  @override
  void initState() {
    super.initState();
    _leadData = Map<String, dynamic>.from(widget.lead);
    _notesCtrl = TextEditingController(
      text: _leadData['notes']?.toString() ?? '',
    );
    _commentCtrl = TextEditingController();
    if (_isStudent) {
      // Student card: family is shared with the lead flow; the rest comes from
      // the student card endpoint. Lead-only fetches are skipped.
      _loadingFamily = true;
      _fetchFamily();
      _fetchStudentData();
      return;
    }
    _statuses = widget.allStatuses ?? const [];
    if (widget.allStatuses == null) _fetchStatuses();
    _fetchMetadata();
    _fetchCard();
    _fetchDuplicateCandidates();
    _fetchStatusHistory();
    _fetchFamily();
  }

  // Loads the student card in one round-trip (getStudentCard), mirroring
  // student_detail_screen._loadAllData. Per-section failures are isolated: the
  // bulk card load only fails the card if the student record itself is
  // unavailable; family loads independently via [_fetchFamily].
  Future<void> _fetchStudentData() async {
    if (mounted) {
      setState(() {
        _loadingStudent = true;
        _studentError = null;
      });
    }
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final card = await crm.getStudentCard(_entityId);
      if (!mounted) return;
      final student = card['student'] is Map<String, dynamic>
          ? card['student'] as Map<String, dynamic>
          : <String, dynamic>{};
      setState(() {
        _student = student;
        _balance = card['balance'] is Map<String, dynamic>
            ? card['balance'] as Map<String, dynamic>
            : null;
        _payments = _list(card['payments']);
        _lessons = _list(card['lessons']);
        _studentTasks = _list(card['tasks']);
        _studentComments = _list(card['comments']);
        _groups = _list(card['groups']);
        _expectedPayments = _list(card['expected_payments']);
        _studentTasks.sort(
          (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
        );
        _studentComments.sort(
          (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
        );
        _loadingStudent = false;
      });
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

  Future<void> _fetchCard() async {
    try {
      final card = await ref
          .read(magicCrmServiceProvider)
          .getLeadCard(widget.lead['id'].toString());
      if (!mounted) return;
      setState(() {
        _leadCard = card;
        if (card['lead'] is Map<String, dynamic>) {
          _leadData = {..._leadData, ...(card['lead'] as Map<String, dynamic>)};
        }
        _loadingCard = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCard = false);
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

  Future<void> _fetchStatusHistory() async {
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .getLeadStatusHistory(widget.lead['id'].toString());
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
    ]);

    if (mounted) {
      setState(() {
        _branches = List<Map<String, dynamic>>.from(results[0] as List);
        _customFieldSchema = results[1] as List<CrmCustomFieldDefinition>;
        _loadingMetadata = false;
      });
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
      final id = _leadData['id'];
      final customData = Map<String, dynamic>.from(
        _leadData['custom_data'] as Map? ?? {},
      );
      if (_leadData['branch_id'] != null) {
        customData['branchId'] = _leadData['branch_id'];
      }
      await ref
          .read(magicCrmServiceProvider)
          .updateLead(
            id.toString(),
            firstName: _leadData['name']?.toString(),
            lastName: _leadData['last_name']?.toString(),
            phone: _leadData['phone']?.toString(),
            email: _leadData['email']?.toString(),
            statusId: _leadData['status']?.toString(),
            notes: _notesCtrl.text,
            customDataPatch: customData,
          );
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

  void _updateCustomData(String key, dynamic value) {
    setState(() {
      final cd = Map<String, dynamic>.from(_leadData['custom_data'] ?? {});
      cd[key] = value;
      _leadData['custom_data'] = cd;
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
              _isStudent ? _buildStudentHeader(cs) : _buildHeader(cs, curStatus),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
              _buildTabBar(cs),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
              Expanded(
                child: IndexedStack(
                  index: _tabIndex,
                  children: _isStudent
                      ? [
                          _buildStudentInfoTab(cs),
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
                          _buildInfoTab(cs, curStatus),
                          _buildTasksTab(cs),
                          _buildCommentsTab(cs),
                          _buildFamilyTab(cs),
                          _buildHistoryTab(cs),
                        ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
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
                          'Лид · ${curStatus.$2} · ID ${_leadData['hollihop_id'] ?? '—'}',
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

  // ── Tab: Инфо ──────────────────────────────────────────────────────────────
  Widget _buildInfoTab(ColorScheme cs, StatusRecord curStatus) {
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
          _sectionTitle('Общая информация'),
          _buildStatusPicker(cs, curStatus),
          _buildTextField(cs, 'Имя', 'name'),
          _buildTextField(cs, 'Фамилия', 'last_name'),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: RuPhoneField(
              initialCanonical: _leadData['phone']?.toString(),
              onCanonicalChanged: (c) {
                setState(() {
                  _leadData['phone'] = c.isEmpty ? null : c;
                  _edited = true;
                });
              },
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          _buildTextField(
            cs,
            'Электронная почта',
            'email',
            keyboard: TextInputType.emailAddress,
          ),

          const SizedBox(height: AppSpace.lg),
          _sectionTitle('Дополнительные поля CRM'),
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
              'leads',
              excludedKeys: const {
                'branchId',
                'hollihopId',
                'hollihop_id',
                'sourceLeadId',
              },
            ),
            _buildBranchDropdown(cs, 'Основной филиал'),
          ],

          const SizedBox(height: AppSpace.lg),
          _sectionTitle('Заметки'),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: _inputDecoration(
              cs,
              hint: 'Общие примечания по лиду...',
            ),
          ),

          const SizedBox(height: AppSpace.lg),
          ClientAppUserPanel(
            entityType: 'lead',
            entityId: widget.lead['id'].toString(),
          ),

          const SizedBox(height: AppSpace.lg),
          _sectionTitle('Связи и активность'),
          _buildAggregateCard(cs, includeTasks: false),

          if (_loadingDuplicates || duplicateCandidates.isNotEmpty) ...[
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
    final tasks = card == null ? const <Map<String, dynamic>>[] : _list(card['tasks']);
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

    setState(() => _addingTask = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .createTask(
            entityType: widget.entityType,
            entityId: _entityId,
            title: title,
            dueAt: dueAt,
          );
      _dirty = true;
      if (_isStudent) {
        await _fetchStudentData();
      } else {
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
                  entityType: widget.entityType,
                  entityId: _entityId,
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

  // Parse the balance defensively (it can arrive as a string) and color it:
  // red < 0, green > 0, neutral at exactly 0. (Ported from student_detail.)
  num? get _studentBalanceNum {
    if (_balance == null) return null;
    final raw = _balance!['balance'];
    return raw is num ? raw : num.tryParse(raw?.toString() ?? '');
  }

  Color _studentBalanceColor(ColorScheme cs) {
    final b = _studentBalanceNum;
    if (b == null || b == 0) return cs.onSurfaceVariant;
    return b < 0 ? AppTheme.danger : AppTheme.success;
  }

  Widget _buildStudentHeader(ColorScheme cs) {
    final contact = _studentContact();
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
              Icons.school_outlined,
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColor.goldSoft,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: AppColor.goldLine),
                        ),
                        child: const Text(
                          'Ученик',
                          style: TextStyle(
                            color: AppColor.gold,
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
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

  // ── Student tab: Инфо ────────────────────────────────────────────────────
  Widget _buildStudentInfoTab(ColorScheme cs) {
    return _studentGuard(cs, () {
      final contact = _studentContact();
      final customData =
          _student!['custom_data'] as Map<String, dynamic>? ?? {};
      return ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          _buildInfoCard('Контактные данные', [
            _InfoRow(
              icon: Icons.phone_rounded,
              label: 'Телефон',
              value: contact.phone,
            ),
            _InfoRow(
              icon: Icons.email_rounded,
              label: 'Электронная почта',
              value: contact.email,
            ),
          ]),
          const SizedBox(height: AppSpace.lg),
          ClientAppUserPanel(
            entityType: 'student',
            entityId: _entityId,
          ),
          const SizedBox(height: AppSpace.lg),
          _buildInfoCard('Дополнительная информация', [
            _InfoRow(
              icon: Icons.cake_rounded,
              label: 'День рождения',
              value: _student!['birthday']?.toString() ?? '—',
            ),
            _InfoRow(
              icon: Icons.person_outline_rounded,
              label: 'Пол',
              value: _student!['gender'] == 'male'
                  ? 'Мужской'
                  : (_student!['gender'] == 'female' ? 'Женский' : '—'),
            ),
            if ((_student!['hollihop_id']?.toString().trim().isNotEmpty ??
                false))
              _InfoRow(
                icon: Icons.fingerprint_rounded,
                label: 'Идентификатор HolliHop',
                value: _student!['hollihop_id'].toString(),
              ),
            ...customData.entries
                .where(
                  (e) =>
                      !_isHiddenStudentCustomDataRow(e.key) &&
                      (e.value?.toString().trim().isNotEmpty ?? false),
                )
                .map(
                  (e) => _InfoRow(
                    icon: Icons.info_outline_rounded,
                    label: e.key,
                    value: e.value.toString(),
                  ),
                ),
          ]),
          const SizedBox(height: AppSpace.lg),
          _buildInfoCard('Финансовые настройки', [
            _InfoRow(
              icon: Icons.payments_outlined,
              label: 'Цена инд. занятия',
              value: _student!['individual_price'] != null
                  ? '${_student!['individual_price']} ₽'
                  : 'Не задана',
              onEdit: _editStudentPrice,
            ),
            if (_balance != null) ...[
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
            ],
          ]),
          const SizedBox(height: AppSpace.lg),
          _buildInfoCard('Группы', [
            if (_groups.isEmpty)
              const _InfoRow(
                icon: Icons.group_off_rounded,
                label: 'Группы',
                value: 'Нет активных групп',
              )
            else
              ..._groups.map((g) {
                final teacher = g['teachers'];
                String tName = '—';
                if (teacher != null) {
                  final tfName = teacher['first_name']?.toString() ?? '';
                  final tlName = teacher['last_name']?.toString() ?? '';
                  final p = teacher['profiles'] as Map<String, dynamic>?;
                  tName = '$tfName $tlName'.trim();
                  if (tName.isEmpty && p != null) {
                    tName = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'
                        .trim();
                  }
                }
                return _InfoRow(
                  icon: Icons.group_rounded,
                  label: g['name']?.toString() ?? 'Группа',
                  value: 'Преп.: $tName',
                );
              }),
          ]),
          const SizedBox(height: AppSpace.lg),
          _buildInfoCard('Семья', _buildStudentFamilyRows()),
        ],
      );
    });
  }

  bool _isHiddenStudentCustomDataRow(String key) {
    const hidden = {
      'hollihopid',
      'hollihop_id',
      'hollihopstudentid',
      'hollihop_student_id',
      'externalid',
      'external_id',
      'demoaccount',
      'demo_account',
      'isdemo',
      'is_demo',
      'sourceleadid',
      'source_lead_id',
      'leadid',
      'lead_id',
      'branchid',
      'branch_id',
      'disciplineid',
      'discipline_id',
      'disciplineinternal',
      'discipline_internal',
    };
    return hidden.contains(key.trim().toLowerCase());
  }

  List<Widget> _buildStudentFamilyRows() {
    final family = _family?['family'] as Map<String, dynamic>?;
    final members =
        (_family?['members'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const <Map<String, dynamic>>[];
    if (family == null || members.isEmpty) {
      return const [
        _InfoRow(
          icon: Icons.people_outline_rounded,
          label: 'Семья',
          value: 'Не указана',
        ),
      ];
    }
    final primaryId = family['primary_payer_member_id']?.toString();
    return members.map((m) {
      final role = _familyRoleLabel(m['role']);
      final isPayer = primaryId != null && m['id']?.toString() == primaryId;
      final label = [
        role,
        if (m['is_primary_contact'] == true) 'осн. контакт',
        if (isPayer) 'плательщик',
      ].join(' · ');
      return _InfoRow(
        icon: Icons.people_alt_rounded,
        label: label,
        value: (m['name']?.toString().trim().isNotEmpty ?? false)
            ? m['name'].toString()
            : 'Без имени',
      );
    }).toList();
  }

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
            if (_studentTasks.isEmpty)
              _emptyHint(cs, 'Открытых задач нет')
            else
              ..._studentTasks.map(
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
      return ListView.builder(
        padding: const EdgeInsets.all(AppSpace.xl),
        itemCount: _lessons.length,
        itemBuilder: (context, i) {
          final l = _lessons[i];
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
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(
                dateStr,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Преп.: $teacherName • ${l['groups']?['name'] ?? 'Инд.'}',
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
        },
      );
    });
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
                  color: (paid ? AppTheme.success : AppTheme.warning)
                      .withAlpha(30),
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

  // ── Student tab: История (merged tasks + comments) ───────────────────────
  Widget _buildStudentHistoryTab(ColorScheme cs) {
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
                  leading: Icon(
                    Icons.assignment_rounded,
                    color: AppColor.gold,
                  ),
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
                  leading: Icon(Icons.description_rounded, color: AppColor.gold),
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
            onPressed: _handleClose,
            style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
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
  Widget _goldButton(String label, VoidCallback? onPressed) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColor.gold,
        foregroundColor: AppColor.onGold,
        disabledBackgroundColor: AppColor.goldSoft,
        disabledForegroundColor: AppColor.text2,
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }

  Widget _ghostButton(String label, VoidCallback? onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColor.text,
        side: const BorderSide(color: AppColor.divider),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }

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

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime? dueAt;

    final created = await showMagicSheet<bool>(
      context,
      title: 'Задать ДЗ',
      subtitle: 'Новое домашнее задание',
      icon: Icons.assignment_rounded,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final dueLabel = dueAt == null
                ? 'Срок не задан'
                : DateFormat('d MMM yyyy, HH:mm', 'ru').format(dueAt!);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Заголовок *',
                    hintText: 'Что нужно выучить?',
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Описание',
                    hintText: 'Подробности (необязательно)',
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: () async {
                    final now = DateTime.now();
                    final date = await showDatePicker(
                      context: sheetContext,
                      initialDate: dueAt ?? now,
                      firstDate: now.subtract(const Duration(days: 1)),
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (date == null || !sheetContext.mounted) return;
                    final time = await showTimePicker(
                      context: sheetContext,
                      initialTime: TimeOfDay.fromDateTime(dueAt ?? now),
                    );
                    setSheetState(() {
                      dueAt = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time?.hour ?? 0,
                        time?.minute ?? 0,
                      );
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                      vertical: AppSpace.md,
                    ),
                    decoration: BoxDecoration(
                      color: AppColor.input,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: AppColor.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.event_rounded,
                          size: 18,
                          color: AppColor.gold,
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Text(
                            dueLabel,
                            style: TextStyle(
                              fontSize: 14,
                              color: dueAt == null
                                  ? AppColor.text2
                                  : AppColor.text,
                            ),
                          ),
                        ),
                        if (dueAt != null)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            color: AppColor.text2,
                            tooltip: 'Сбросить срок',
                            onPressed: () => setSheetState(() => dueAt = null),
                          ),
                      ],
                    ),
                  ),
                ),
                if (homeworks.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.lg),
                  const Divider(height: 1, color: AppColor.divider),
                  const SizedBox(height: AppSpace.md),
                  const Text(
                    'Последние ДЗ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColor.gold,
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  for (final hw in homeworks) _HomeworkTile(homework: hw),
                ],
              ],
            );
          },
        );
      },
      actions: [
        _ghostButton('Отмена', () => Navigator.pop(context, false)),
        _goldButton('Создать', () {
          if (titleCtrl.text.trim().isEmpty) {
            MagicToast.show(
              context,
              'Введите заголовок',
              type: MagicToastType.danger,
            );
            return;
          }
          Navigator.pop(context, true);
        }),
      ],
    );

    if (created != true || !mounted) return;

    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;

    try {
      await crm.createHomework(
        studentId: _entityId,
        title: title,
        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        dueAt: dueAt?.toIso8601String(),
      );
      if (!mounted) return;
      _dirty = true;
      MagicToast.show(
        context,
        'ДЗ создано',
        detail: title,
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
  }) {
    final r = BorderRadius.circular(AppRadius.control);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      isDense: isDense,
      suffixIcon: suffixIcon,
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      border: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: const BorderSide(color: AppColor.gold, width: 2),
      ),
    );
  }

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

  Widget _buildTextField(
    ColorScheme cs,
    String label,
    String key, {
    TextInputType? keyboard,
    bool isCustom = false,
  }) {
    String? initialVal;
    if (isCustom) {
      initialVal = (_leadData['custom_data'] as Map?)?[key]?.toString();
    } else {
      initialVal = _leadData[key]?.toString();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: TextFormField(
        initialValue: initialVal ?? '',
        decoration: _inputDecoration(cs, label: label, isDense: true),
        keyboardType: keyboard,
        onChanged: (v) {
          if (isCustom) {
            _updateCustomData(key, v);
          } else {
            setState(() {
              _leadData[key] = v;
              _edited = true;
            });
          }
        },
      ),
    );
  }

  List<Widget> _buildCustomFieldControls(
    ColorScheme cs,
    String entity, {
    Set<String> excludedKeys = const {},
  }) {
    final fields = _customFieldSchema
        .where(
          (field) =>
              field.entity == entity && !excludedKeys.contains(field.key),
        )
        .toList();
    if (fields.isEmpty) {
      return [
        Text(
          'Дополнительные поля не настроены',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ];
    }
    return fields.map((field) => _buildCustomFieldControl(cs, field)).toList();
  }

  Widget _buildCustomFieldControl(ColorScheme cs, CrmCustomFieldDefinition field) {
    final customData = _leadData['custom_data'] as Map? ?? {};
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
          onChanged: (value) => _updateCustomData(
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
        onChanged: (value) => _updateCustomData(field.key, value),
        title: Text(label),
        subtitle: field.hint == null ? null : Text(field.hint!),
        contentPadding: EdgeInsets.zero,
      );
    }

    if (field.type == 'date') {
      return _buildDateCustomField(cs, field, rawValue?.toString());
    }

    return _buildTextField(
      cs,
      label,
      field.key,
      keyboard: _keyboardForCustomField(field.type),
      isCustom: true,
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
            _updateCustomData(field.key, picked.toIso8601String());
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

  Widget _buildBranchDropdown(ColorScheme cs, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: DropdownButtonFormField<String>(
        initialValue: _leadData['branch_id'],
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
        onChanged: (v) => setState(() {
          _leadData['branch_id'] = v;
          _edited = true;
        }),
      ),
    );
  }

  Widget _buildCommentInput(ColorScheme cs) {
    return Row(
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
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
            ),
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
                  side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
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
                  onPressed: _familyBusy
                      ? null
                      : () => _removeFamilyMember(m),
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
  static const List<(String, String)> _familyRoleOptions = [
    ('parent', 'Родитель'),
    ('child', 'Ребёнок'),
    ('partner', 'Партнёр'),
    ('sibling', 'Брат/сестра'),
    ('guardian', 'Опекун'),
    ('payer', 'Плательщик'),
  ];

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
    final cs = Theme.of(context).colorScheme;
    final selfId = _leadData['id']?.toString() ?? widget.lead['id']?.toString();
    var role = _familyRoleOptions.first.$1;
    // Default the linked record to this card's own entity (lead or student).
    var entityType = widget.entityType;
    final entityIdCtrl = TextEditingController(text: selfId ?? '');
    var isPrimaryContact = false;

    final confirmed = await showMagicSheet<bool>(
      context,
      title: 'Добавить участника',
      subtitle: _isStudent
          ? 'Свяжите запись с семьёй ученика'
          : 'Свяжите запись с семьёй лида',
      icon: Icons.person_add_alt_1_rounded,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Роль',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  isExpanded: true,
                  decoration: _inputDecoration(cs, isDense: true),
                  items: _familyRoleOptions
                      .map(
                        (option) => DropdownMenuItem(
                          value: option.$1,
                          child: Text(option.$2),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setSheetState(() => role = value);
                  },
                ),
                const SizedBox(height: AppSpace.md),
                Text(
                  'Тип записи',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                DropdownButtonFormField<String>(
                  initialValue: entityType,
                  isExpanded: true,
                  decoration: _inputDecoration(cs, isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'lead', child: Text('Лид')),
                    DropdownMenuItem(value: 'student', child: Text('Ученик')),
                    DropdownMenuItem(value: 'profile', child: Text('Профиль')),
                  ],
                  onChanged: (value) {
                    if (value != null) setSheetState(() => entityType = value);
                  },
                ),
                const SizedBox(height: AppSpace.md),
                TextField(
                  controller: entityIdCtrl,
                  decoration: _inputDecoration(
                    cs,
                    label: 'ID записи',
                    hint: 'Идентификатор лида/ученика/профиля',
                    helperText: selfId == null
                        ? null
                        : (_isStudent
                              ? 'По умолчанию — текущий ученик'
                              : 'По умолчанию — текущий лид'),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                CheckboxListTile(
                  value: isPrimaryContact,
                  activeColor: AppColor.gold,
                  onChanged: (value) =>
                      setSheetState(() => isPrimaryContact = value ?? false),
                  title: const Text('Основной контакт'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
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
          child: const Text('Добавить'),
        ),
      ],
    );

    final entityId = entityIdCtrl.text.trim();
    entityIdCtrl.dispose();
    if (confirmed != true) return;
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
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 12,
        ),
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
            title: Text(transition, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            Text(
              empty,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
              ),
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
                    side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
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

    try {
      await ref
          .read(magicCrmServiceProvider)
          .createComment(
            entityType: widget.entityType,
            entityId: _entityId,
            body: text,
          );
      _commentCtrl.clear();
      if (mounted) {
        setState(() => _commentsRefreshKey++);
        if (_isStudent) {
          _fetchStudentData();
        } else {
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

class _CommentsList extends ConsumerStatefulWidget {
  final String entityType;
  final String entityId;
  final int refreshKey;
  const _CommentsList({
    required this.entityType,
    required this.entityId,
    required this.refreshKey,
  });

  @override
  ConsumerState<_CommentsList> createState() => _CommentsListState();
}

class _CommentsListState extends ConsumerState<_CommentsList> {
  // Bumped on «Повторить» to rebuild the FutureBuilder with a fresh request.
  int _retryKey = 0;

  // Maps a comment `kind` to a short Russian badge label. Unknown / generic
  // kinds (e.g. plain staff comments) get no badge.
  String? _kindLabel(Object? kind) {
    return switch (kind?.toString()) {
      'admin_comment' => 'Админ',
      'teacher_note' => 'Педагог',
      'progress' => 'Прогресс',
      _ => null,
    };
  }

  Widget _kindBadge(String label) {
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
          fontSize: 10,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('${widget.refreshKey}:$_retryKey'),
      future: ref
          .watch(magicCrmServiceProvider)
          .listComments(
            entityType: widget.entityType,
            entityId: widget.entityId,
          ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: LinearProgressIndicator(color: AppColor.gold),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Не удалось загрузить комментарии',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                TextButton.icon(
                  onPressed: () => setState(() => _retryKey++),
                  style: TextButton.styleFrom(foregroundColor: AppColor.gold),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) return const SizedBox.shrink();
        final comments = snapshot.data!;
        if (comments.isEmpty) {
          return Text(
            'Нет комментариев',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
            ),
          );
        }

        return Column(
          children: comments.map((c) {
            final dt = DateTime.tryParse(c['created_at'] ?? '')?.toLocal();
            final dateStr = dt != null
                ? DateFormat('d MMM HH:mm', 'ru').format(dt)
                : '';
            final kindLabel = _kindLabel(c['kind']);
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: AppSpace.sm),
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                (c['author_name']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ??
                                        false)
                                    ? c['author_name'].toString()
                                    : 'Сотрудник',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColor.gold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (kindLabel != null) ...[
                              const SizedBox(width: 6),
                              _kindBadge(kindLabel),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c['content'] ?? '',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// One labelled info row for the student Инфо / Документы tabs (ported from
/// student_detail_screen). When [onEdit] is set the row is tappable and shows a
/// trailing edit affordance.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onEdit;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (onEdit != null)
              const Icon(
                Icons.edit_outlined,
                size: 14,
                color: AppTheme.primaryGold,
              ),
          ],
        ),
      ),
    );
  }
}

/// Selectable subscription-package row inside the «Выдать абонемент» v7 sheet
/// (ported from student_detail_screen).
class _SubscriptionPackageTile extends StatelessWidget {
  final Map<String, dynamic> package;
  final VoidCallback onTap;
  const _SubscriptionPackageTile({required this.package, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = package['name']?.toString() ?? 'Абонемент';
    final lessons = package['lessons_total'] ?? package['lessonsTotal'];
    final price = package['price'];
    final validity = package['validity_days'] ?? package['validityDays'];
    final meta = [
      if (lessons != null) '$lessons зан.',
      if (price != null) '$price ₽',
      if (validity != null) '$validity дн.',
    ].join(' · ');

    return Material(
      color: AppColor.input,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: AppColor.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColor.goldSoft,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: AppColor.goldLine),
                ),
                child: const Icon(
                  Icons.card_membership_rounded,
                  size: 18,
                  color: AppColor.gold,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColor.text,
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          meta,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColor.text2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColor.text2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact read-only homework row for the «Последние ДЗ» section in the «Задать
/// ДЗ» v7 sheet (ported from student_detail_screen).
class _HomeworkTile extends StatelessWidget {
  final Map<String, dynamic> homework;
  const _HomeworkTile({required this.homework});

  @override
  Widget build(BuildContext context) {
    final title = homework['title']?.toString() ?? '—';
    final status = homework['status']?.toString();
    final dueRaw = homework['due_at'] ?? homework['dueAt'];
    final due = DateTime.tryParse(dueRaw?.toString() ?? '');
    final subtitle = [
      if (status != null && status.isNotEmpty) _statusLabel(status),
      if (due != null) DateFormat('d MMM yyyy', 'ru').format(due.toLocal()),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.assignment_outlined,
              size: 16,
              color: AppColor.text2,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColor.text),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColor.text2,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'assigned':
        return 'Назначено';
      case 'submitted':
        return 'Сдано';
      case 'done':
      case 'completed':
        return 'Завершено';
      default:
        return status;
    }
  }
}
