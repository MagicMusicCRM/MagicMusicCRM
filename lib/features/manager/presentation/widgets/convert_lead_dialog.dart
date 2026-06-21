import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

/// v7 sheet that converts a lead into a student, letting the user pick the
/// target branch + discipline. Returns the created student map, or null if
/// cancelled / failed. Theme-aware (in-app screen, light+dark).
///
/// Contract LOCKED: the `createStudent` call + its `customDataPatch`
/// (`branchId`/`discipline`(name)/`sourceLeadId`) and the branch→discipline
/// cascade are unchanged — only the presentation is reskinned to v7.
class ConvertLeadDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> lead;
  const ConvertLeadDialog({super.key, required this.lead});

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Map<String, dynamic> lead,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColor.scrim,
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

  InputDecoration _decoration(
    ColorScheme cs, {
    required String label,
    Widget? suffixIcon,
    String? helperText,
  }) {
    final r = BorderRadius.circular(AppRadius.control);
    return InputDecoration(
      labelText: label,
      suffixIcon: suffixIcon,
      helperText: helperText,
      isDense: true,
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: const BorderSide(color: AppColor.gold, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final name = [
      widget.lead['name'],
      widget.lead['last_name'],
    ].where((v) => v != null && '$v'.trim().isNotEmpty).join(' ');
    final canConvert = !_saving &&
        !_loadingBranches &&
        !_loadingDisciplines &&
        !(_disciplines.isNotEmpty && _discipline == null);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: media.size.height * 0.85,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.sheet),
              ),
              border:
                  Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 2),
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColor.goldSoft,
                          borderRadius: BorderRadius.circular(AppRadius.icon),
                          border: Border.all(color: AppColor.goldLine),
                        ),
                        child: const Icon(
                          Icons.school_rounded,
                          size: 20,
                          color: AppColor.gold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Сделать учеником',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (name.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Лид «$name»',
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
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        iconSize: 20,
                        color: cs.onSurfaceVariant,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: _loadingBranches
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColor.gold,
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue: _branchId,
                                isExpanded: true,
                                decoration:
                                    _decoration(cs, label: 'Филиал'),
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
                              const SizedBox(height: 14),
                              DropdownButtonFormField<String>(
                                key: ValueKey('disc:$_branchId'),
                                initialValue: _discipline,
                                isExpanded: true,
                                decoration: _decoration(
                                  cs,
                                  label: 'Направление',
                                  suffixIcon: _loadingDisciplines
                                      ? const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : null,
                                  helperText: _branchId == null
                                      ? 'Сначала выберите филиал'
                                      : (_disciplines.isEmpty &&
                                              !_loadingDisciplines
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
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColor.dangerSoft,
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.control,
                                      ),
                                      border: Border.all(
                                        color: const Color(0x52E53935),
                                      ),
                                    ),
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        color: AppColor.danger,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColor.gold,
                            foregroundColor: AppColor.onGold,
                            disabledBackgroundColor:
                                AppColor.gold.withValues(alpha: 0.42),
                            disabledForegroundColor:
                                AppColor.onGold.withValues(alpha: 0.7),
                            elevation: 0,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.control),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          onPressed: canConvert ? _convert : null,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColor.onGold,
                                  ),
                                )
                              : const Text('Создать ученика'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
