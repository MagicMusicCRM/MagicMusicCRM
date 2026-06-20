import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

/// Modal that converts a lead into a student, letting the user pick the
/// target branch + discipline. Returns the created student map, or null if
/// cancelled / failed.
class ConvertLeadDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> lead;
  const ConvertLeadDialog({super.key, required this.lead});

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Map<String, dynamic> lead,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ConvertLeadDialog(lead: lead),
    );
  }

  @override
  ConsumerState<ConvertLeadDialog> createState() => _ConvertLeadDialogState();
}

class _ConvertLeadDialogState extends ConsumerState<ConvertLeadDialog> {
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _disciplines = [];
  String? _branchId;
  String? _discipline; // discipline NAME (createStudent stores the name)
  bool _loadingBranches = true;
  bool _loadingDisciplines = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _branchId = widget.lead['branch_id']?.toString();
    final cd = widget.lead['custom_data'];
    if (cd is Map) _discipline = cd['discipline']?.toString();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final branches =
          await ref.read(magicCrmServiceProvider).listBranches(limit: 100);
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _loadingBranches = false;
        // Keep the inherited branch only if it is actually in the list.
        if (_branchId != null &&
            !_branches.any((b) => b['id'].toString() == _branchId)) {
          _branchId = null;
        }
      });
      if (_branchId != null) await _loadDisciplines(_branchId!);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingBranches = false;
          _error = 'Не удалось загрузить филиалы: $e';
        });
      }
    }
  }

  Future<void> _loadDisciplines(String branchId) async {
    setState(() {
      _loadingDisciplines = true;
      _disciplines = [];
    });
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .listBranchDisciplines(branchId);
      if (!mounted) return;
      setState(() {
        _disciplines = items;
        _loadingDisciplines = false;
        // Drop a stale inherited discipline that this branch doesn't offer.
        if (_discipline != null &&
            !_disciplines.any((d) => d['name']?.toString() == _discipline)) {
          _discipline = null;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDisciplines = false;
          _error = 'Не удалось загрузить направления: $e';
        });
      }
    }
  }

  Future<void> _convert() async {
    final firstNameRaw = (widget.lead['name'] ?? '').toString().trim();
    final lastName = (widget.lead['last_name'] ?? '').toString().trim();
    final phone = (widget.lead['phone'] ?? '').toString().trim();
    final email = (widget.lead['email'] ?? '').toString().trim();

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final patch = <String, dynamic>{};
      if (_branchId != null && _branchId!.isNotEmpty) {
        patch['branchId'] = _branchId;
      }
      if (_discipline != null && _discipline!.isNotEmpty) {
        patch['discipline'] = _discipline;
      }
      patch['sourceLeadId'] = widget.lead['id'].toString();

      final student = await ref.read(magicCrmServiceProvider).createStudent(
            firstName: firstNameRaw.isEmpty ? 'Без имени' : firstNameRaw,
            lastName: lastName.isEmpty ? null : lastName,
            phone: phone.isEmpty ? null : phone,
            email: email.isEmpty ? null : email,
            leadId: widget.lead['id'].toString(),
            customDataPatch: patch.isEmpty ? null : patch,
          );
      if (mounted) Navigator.pop(context, student);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Не удалось конвертировать: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = [
      widget.lead['name'],
      widget.lead['last_name'],
    ].where((v) => v != null && '$v'.trim().isNotEmpty).join(' ');

    return AlertDialog(
      title: const Text('Сделать учеником'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Лид «$name» будет конвертирован в ученика.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
            if (_loadingBranches)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _branchId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Филиал'),
                items: _branches
                    .map(
                      (b) => DropdownMenuItem(
                        value: b['id'].toString(),
                        child: Text(
                          b['name']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (v) {
                        setState(() => _branchId = v);
                        if (v != null) _loadDisciplines(v);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('disc:$_branchId'),
                initialValue: _discipline,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Направление',
                  suffixIcon: _loadingDisciplines
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  helperText: _branchId == null
                      ? 'Сначала выберите филиал'
                      : (_disciplines.isEmpty && !_loadingDisciplines
                          ? 'У филиала нет направлений'
                          : null),
                ),
                items: _disciplines
                    .map(
                      (d) => DropdownMenuItem(
                        value: d['name']?.toString(),
                        child: Text(
                          d['name']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving || _branchId == null
                    ? null
                    : (v) => setState(() => _discipline = v),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: AppTheme.danger,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
          onPressed: _saving || _loadingBranches || _loadingDisciplines || (_disciplines.isNotEmpty && _discipline == null) ? null : _convert,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.school_rounded, size: 18),
          label: const Text('Создать ученика'),
        ),
      ],
    );
  }
}
