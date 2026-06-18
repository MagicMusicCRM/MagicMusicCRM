import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/services/magic_settings_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
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

class _LeadDetailDialogState extends ConsumerState<LeadDetailDialog> {
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
  String? _duplicateDecisionId;

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
    final fallbackStatus = widget.allStatuses.isNotEmpty
        ? widget.allStatuses.first
        : ('new', 'Новый', AppTheme.primaryPurple);
    final curStatus = widget.allStatuses.firstWhere(
      (element) => element.$1 == _leadData['status'],
      orElse: () => fallbackStatus,
    );

    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_leadData['name'] ?? ''} ${_leadData['last_name'] ?? ''}'
                            .trim(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Лид (ID: ${_leadData['hollihop_id'] ?? '—'})',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, _dirty ? true : null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Общая информация'),
                    _buildStatusPicker(curStatus),
                    _buildTextField('Имя', 'name'),
                    _buildTextField('Фамилия', 'last_name'),
                    _buildTextField(
                      'Телефон',
                      'phone',
                      keyboard: TextInputType.phone,
                    ),
                    _buildTextField(
                      'Электронная почта',
                      'email',
                      keyboard: TextInputType.emailAddress,
                    ),

                    const SizedBox(height: 16),
                    _sectionTitle('Дополнительные поля CRM'),
                    if (_loadingMetadata)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else ...[
                      ..._buildCustomFieldControls(
                        'leads',
                        excludedKeys: const {
                          'branchId',
                          'hollihopId',
                          'hollihop_id',
                          'sourceLeadId',
                        },
                      ),
                      _buildBranchDropdown('Основной филиал'),
                    ],

                    const SizedBox(height: 16),
                    _sectionTitle('Заметки'),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Общие примечания по лиду...',
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 16),
                    _sectionTitle('Связи и активность'),
                    _buildAggregateCard(),

                    const SizedBox(height: 16),
                    _sectionTitle('Комментарии'),
                    _CommentsList(
                      leadId: _leadData['id'].toString(),
                      refreshKey: _commentsRefreshKey,
                    ),
                    const SizedBox(height: 8),
                    _buildCommentInput(),
                  ],
                ),
              ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving || _converting ? null : _convertToStudent,
                  icon: _converting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Создать ученика'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _saving || _converting
                      ? null
                      : () => Navigator.pop(context, _dirty ? true : null),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saving || _converting ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Сохранить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.primaryPurple,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStatusPicker(StatusRecord current) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _leadData['status'],
        decoration: const InputDecoration(labelText: 'Статус'),
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
          if (v != null) setState(() => _leadData['status'] = v);
        },
      ),
    );
  }

  Widget _buildTextField(
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
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: initialVal ?? '',
        decoration: InputDecoration(labelText: label),
        keyboardType: keyboard,
        onChanged: (v) {
          if (isCustom) {
            _updateCustomData(key, v);
          } else {
            setState(() => _leadData[key] = v);
          }
        },
      ),
    );
  }

  List<Widget> _buildCustomFieldControls(
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
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ];
    }
    return fields.map(_buildCustomFieldControl).toList();
  }

  Widget _buildCustomFieldControl(CrmCustomFieldDefinition field) {
    final customData = _leadData['custom_data'] as Map? ?? {};
    final rawValue = customData[field.key];
    final label = field.required ? '${field.label} *' : field.label;

    if (field.type == 'select') {
      final current = rawValue?.toString() ?? '';
      final initialValue = field.options.contains(current) ? current : '';
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: initialValue,
          decoration: InputDecoration(labelText: label, helperText: field.hint),
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
        onChanged: (value) => _updateCustomData(field.key, value),
        title: Text(label),
        subtitle: field.hint == null ? null : Text(field.hint!),
        contentPadding: EdgeInsets.zero,
      );
    }

    if (field.type == 'date') {
      return _buildDateCustomField(field, rawValue?.toString());
    }

    return _buildTextField(
      label,
      field.key,
      keyboard: _keyboardForCustomField(field.type),
      isCustom: true,
    );
  }

  Widget _buildDateCustomField(CrmCustomFieldDefinition field, String? value) {
    final dt = value == null ? null : DateTime.tryParse(value);
    final display = dt != null
        ? DateFormat('dd.MM.yyyy').format(dt)
        : 'Не выбрано';
    final label = field.required ? '${field.label} *' : field.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
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
          decoration: InputDecoration(labelText: label, helperText: field.hint),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(display),
              const Icon(Icons.calendar_today_rounded, size: 16),
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

  Widget _buildBranchDropdown(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _leadData['branch_id'],
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface.withAlpha(127),
        ),
        items: _branches
            .map(
              (b) => DropdownMenuItem(
                value: b['id'].toString(),
                child: Text(b['name']),
              ),
            )
            .toList(),
        onChanged: (v) => setState(() => _leadData['branch_id'] = v),
      ),
    );
  }

  Widget _buildCommentInput() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _commentCtrl,
            decoration: const InputDecoration(
              hintText: 'Написать комментарий...',
              isDense: true,
            ),
          ),
        ),
        IconButton(
          onPressed: _addComment,
          icon: const Icon(Icons.send_rounded, color: AppTheme.primaryPurple),
        ),
      ],
    );
  }

  Widget _buildAggregateCard() {
    if (_loadingCard) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    final card = _leadCard;
    if (card == null) {
      return Text(
        'Карточка активности временно недоступна',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
          spacing: 8,
          runSpacing: 8,
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
        const SizedBox(height: 12),
        if (_loadingDuplicates || duplicateCandidates.isNotEmpty) ...[
          _duplicateCandidatesSection(duplicateCandidates),
          const SizedBox(height: 8),
        ],
        _miniSection(
          title: 'Связанные ученики',
          empty: 'Связанных учеников нет',
          rows: linkedStudents,
          titleBuilder: (row) =>
              '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim(),
          subtitleBuilder: (row) => row['phone']?.toString(),
        ),
        _miniSection(
          title: 'Задачи',
          empty: 'Открытых задач нет',
          rows: tasks,
          titleBuilder: (row) => row['title']?.toString() ?? 'Задача',
          subtitleBuilder: (row) => _formatStatus(row['status']),
        ),
        _miniSection(
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
          title: 'Лента',
          empty: 'История пока пустая',
          rows: timeline.take(8).toList(),
          titleBuilder: (row) => row['title']?.toString() ?? 'Событие',
          subtitleBuilder: (row) => _formatDate(row['occurred_at']),
        ),
      ],
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
        color: AppTheme.primaryGold.withAlpha(28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryGold),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: const TextStyle(
              color: AppTheme.primaryGold,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _duplicateCandidatesSection(List<Map<String, dynamic>> candidates) {
    if (_loadingDuplicates) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
                  borderRadius: BorderRadius.circular(8),
                ),
                tileColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withAlpha(120),
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

  Widget _miniSection({
    required String title,
    required String empty,
    required List<Map<String, dynamic>> rows,
    required String Function(Map<String, dynamic>) titleBuilder,
    required String? Function(Map<String, dynamic>) subtitleBuilder,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  tileColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withAlpha(120),
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
    return DateFormat('dd.MM.yyyy HH:mm').format(dt);
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

class _CommentsList extends ConsumerWidget {
  final String leadId;
  final int refreshKey;
  const _CommentsList({required this.leadId, required this.refreshKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(refreshKey),
      future: ref
          .watch(magicCrmServiceProvider)
          .listComments(entityType: 'lead', entityId: leadId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final comments = snapshot.data!;
        if (comments.isEmpty) {
          return Text(
            'Нет комментариев',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          );
        }

        return Column(
          children: comments.map((c) {
            final dt = DateTime.tryParse(c['created_at'] ?? '')?.toLocal();
            final dateStr = dt != null
                ? DateFormat('d MMM HH:mm').format(dt)
                : '';
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
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
                          color: AppTheme.primaryPurple,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
