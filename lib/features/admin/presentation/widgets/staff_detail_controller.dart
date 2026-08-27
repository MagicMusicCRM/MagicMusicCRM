import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/staff_detail_model.dart';

class StaffDetailValidationException implements Exception {
  const StaffDetailValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StaffDetailController extends ChangeNotifier {
  StaffDetailController({
    required MagicCrmService crm,
    required Map<String, dynamic> staff,
  }) : _crm = crm,
       _staff = Map<String, dynamic>.from(staff),
       draft = StaffDetailDraft.fromStaff(staff);

  final MagicCrmService _crm;
  Map<String, dynamic> _staff;

  final StaffDetailDraft draft;

  List<Map<String, dynamic>> _branches = const [];
  bool _loadingBranches = true;
  bool _saving = false;
  bool _disposed = false;
  String? _branchesError;
  int _branchLoadGeneration = 0;
  int _saveGeneration = 0;
  int _provisionGeneration = 0;

  Map<String, dynamic> get staff => _staff;
  List<Map<String, dynamic>> get branches => _branches;
  bool get loadingBranches => _loadingBranches;
  bool get saving => _saving;
  String? get branchesError => _branchesError;

  bool get isArchived => _staff['lifecycle_state'] == 'archived';
  bool get isAppAccount => _staff['is_app_account'] == true;
  String get appRole => _staff['app_role']?.toString() ?? '';
  String get profileUserId => _staff['profile_user_id']?.toString() ?? '';

  Future<void> loadBranches() async {
    final generation = ++_branchLoadGeneration;
    _loadingBranches = true;
    _branchesError = null;
    _notify();
    try {
      final branches = await _crm.listBranches();
      if (!_requestIsCurrent(generation, _branchLoadGeneration)) return;
      _branches = branches;
    } catch (error) {
      if (!_requestIsCurrent(generation, _branchLoadGeneration)) return;
      _branches = const [];
      _branchesError = userErrorMessage(
        error,
        fallback: 'Не удалось загрузить филиалы.',
      );
    } finally {
      if (_requestIsCurrent(generation, _branchLoadGeneration)) {
        _loadingBranches = false;
        _notify();
      }
    }
  }

  void setBranchSelected(String id, bool selected) {
    if (selected) {
      draft.branchIds.add(id);
    } else {
      draft.branchIds.remove(id);
    }
    _notify();
  }

  void setCanonicalPhone(String value) {
    draft.canonicalPhone = value;
    _notify();
  }

  void setStatus(String value) {
    draft.status = value;
    _notify();
  }

  Future<void> save() async {
    _validateSave();
    final id = _staffId();
    final generation = ++_saveGeneration;
    _saving = true;
    _notify();
    try {
      await _crm.updateStaff(
        id,
        firstName: draft.firstName,
        lastName: draft.lastName,
        phone: draft.canonicalPhone,
        position: draft.position,
        status: draft.status,
        branchIds: draft.branchIds.toList(),
        customDataPatch: draft.customDataPatch(),
      );
    } finally {
      if (_requestIsCurrent(generation, _saveGeneration)) {
        _saving = false;
        _notify();
      }
    }
  }

  Future<Map<String, dynamic>> loadCredentials() {
    return _crm.getStaffAccess(_staffId());
  }

  Future<Map<String, dynamic>> provisionAccess({
    String? email,
    String? password,
  }) async {
    final staffId = _staffId();
    final staffIdentity = _staff;
    final generation = ++_provisionGeneration;
    final updated = await _crm.provisionStaffAccess(
      staffId: staffId,
      email: email,
      password: password,
    );
    if (!_provisionIsCurrent(generation, staffId, staffIdentity)) {
      return updated;
    }
    _staff = Map<String, dynamic>.from(updated);
    draft.email = _staff['email']?.toString() ?? '';
    _notify();
    return updated;
  }

  void applyAccessRole(String role) {
    draft.role = role;
    _staff = {..._staff, 'role': role, 'app_role': role};
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _requestIsCurrent(int request, int current) =>
      !_disposed && request == current;

  bool _provisionIsCurrent(
    int generation,
    String staffId,
    Map<String, dynamic> staffIdentity,
  ) =>
      _requestIsCurrent(generation, _provisionGeneration) &&
      identical(_staff, staffIdentity) &&
      _staff['id']?.toString() == staffId;

  @override
  void dispose() {
    _disposed = true;
    _branchLoadGeneration++;
    _saveGeneration++;
    _provisionGeneration++;
    super.dispose();
  }

  String _staffId() {
    final id = _staff['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw const StaffDetailValidationException(
        'Не удалось определить сотрудника.',
      );
    }
    return id;
  }

  void _validateSave() {
    if (draft.firstName.trim().isEmpty ||
        draft.lastName.trim().isEmpty ||
        draft.status.trim().isEmpty) {
      throw const StaffDetailValidationException('Обязательное поле');
    }
    if (draft.branchIds.isEmpty) {
      throw const StaffDetailValidationException(
        'Выберите хотя бы один филиал.',
      );
    }
    if (isArchived) {
      throw const StaffDetailValidationException(
        'Архивную карточку нельзя изменить.',
      );
    }
  }
}
