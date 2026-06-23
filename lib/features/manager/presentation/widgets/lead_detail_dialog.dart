import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/models/types.dart';

class LeadDetailDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> lead;
  final List<StatusRecord> allStatuses;

  const LeadDetailDialog({
    super.key,
    required this.lead,
    required this.allStatuses,
  });

  @override
  ConsumerState<LeadDetailDialog> createState() => _LeadDetailDialogState();
}

class _LeadDetailDialogState extends ConsumerState<LeadDetailDialog>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _leadData;
  late TextEditingController _notesCtrl;
  late TextEditingController _commentCtrl;
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
  // True once the user has edited a field but not saved — used to warn before
  // discarding unsaved changes on close.
  bool _edited = false;
  String? _duplicateDecisionId;

  // v7 segmented tab bar: Инфо / Задачи / Комментарии / Семья / История.
  int _tabIndex = 0;
  static const List<(IconData, String)> _tabs = [
    (Icons.info_outline_rounded, 'Инфо'),
    (Icons.task_alt_rounded, 'Задачи'),
    (Icons.forum_outlined, 'Комментарии'),
    (Icons.people_alt_outlined, 'Семья'),
    (Icons.history_rounded, 'История'),
  ];

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
    _fetchMetadata();
    _fetchCard();
    _fetchDuplicateCandidates();
    _fetchStatusHistory();
    _fetchFamily();
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
            entityType: 'lead',
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
    final fallbackStatus = widget.allStatuses.isNotEmpty
        ? widget.allStatuses.first
        : ('new', 'Новый', AppTheme.primaryGold);
    final curStatus = widget.allStatuses.firstWhere(
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
          // Cap the width on wide desktop monitors instead of stretching the
          // form edge-to-edge.
          width: (MediaQuery.of(context).size.width * 0.9)
              .clamp(0.0, 900.0)
              .toDouble(),
          height: MediaQuery.of(context).size.height * 0.85,
          color: cs.surface,
          child: Column(
            children: [
              _buildHeader(cs, curStatus),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
              _buildTabBar(cs),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
              Expanded(
                child: IndexedStack(
                  index: _tabIndex,
                  children: [
                    _buildInfoTab(cs, curStatus),
                    _buildTasksTab(cs),
                    _buildCommentsTab(cs),
                    _buildFamilyTab(cs),
                    _buildHistoryTab(cs),
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
              _buildActionBar(cs),
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
          _sectionTitle('Задачи'),
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
                  leadId: _leadData['id'].toString(),
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
        items: widget.allStatuses.map((s) {
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
    final leadId = _leadData['id']?.toString() ?? widget.lead['id']?.toString();
    var role = _familyRoleOptions.first.$1;
    var entityType = 'lead';
    final entityIdCtrl = TextEditingController(text: leadId ?? '');
    var isPrimaryContact = false;

    final confirmed = await showMagicSheet<bool>(
      context,
      title: 'Добавить участника',
      subtitle: 'Свяжите запись с семьёй лида',
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
                    helperText: leadId == null
                        ? null
                        : 'По умолчанию — текущий лид',
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
            entityType: 'lead',
            entityId: _leadData['id'].toString(),
            body: text,
          );
      _commentCtrl.clear();
      if (mounted) {
        setState(() => _commentsRefreshKey++);
        _fetchCard();
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
  final String leadId;
  final int refreshKey;
  const _CommentsList({required this.leadId, required this.refreshKey});

  @override
  ConsumerState<_CommentsList> createState() => _CommentsListState();
}

class _CommentsListState extends ConsumerState<_CommentsList> {
  // Bumped on «Повторить» to rebuild the FutureBuilder with a fresh request.
  int _retryKey = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('${widget.refreshKey}:$_retryKey'),
      future: ref
          .watch(magicCrmServiceProvider)
          .listComments(entityType: 'lead', entityId: widget.leadId),
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
                      Text(
                        (c['author_name']?.toString().trim().isNotEmpty ??
                                false)
                            ? c['author_name'].toString()
                            : 'Сотрудник',
                        style: const TextStyle(
                          color: AppColor.gold,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
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
