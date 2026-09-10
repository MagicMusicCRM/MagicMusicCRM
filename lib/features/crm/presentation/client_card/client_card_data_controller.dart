import 'client_card_aggregation.dart';
import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/commerce_projection.dart';
import 'package:magic_music_crm/core/models/lesson.dart';
import 'package:magic_music_crm/core/models/student_funnel.dart';
import 'package:magic_music_crm/core/navigation/crm_nav_rbac.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

/// Server read models only. Editable identity snapshots belong to the tab's draft.
class ClientCardStudentSnapshot {
  ClientCardStudentSnapshot({
    required this.student,
    required this.commerce,
    required this.commerceError,
    required this.funnel,
    required this.funnelError,
    required Map<String, dynamic> card,
  }) : lessons = List.unmodifiable(_rows(card['lessons']).map(Lesson.fromMap)),
       groups = List.unmodifiable(_rows(card['groups'])),
       indicators = Map.unmodifiable({
         for (final key in const [
           'paidMisses',
           'partiallyPaidMisses',
           'unpaidMisses',
         ])
           key: ((card['indicators'] as Map?)?[key] as num?)?.toInt() ?? 0,
       });
  final Map<String, dynamic> student;
  final CommerceStudent? commerce;
  final String? commerceError;
  final StudentFunnelConfiguration? funnel;
  final String? funnelError;
  final List<Lesson> lessons;
  final List<Map<String, dynamic>> groups;
  final Map<String, int> indicators;

  ClientCardStudentSnapshot._withCommerce(
    ClientCardStudentSnapshot source,
    this.commerce,
    this.commerceError,
  ) : student = source.student,
      funnel = source.funnel,
      funnelError = source.funnelError,
      lessons = source.lessons,
      groups = source.groups,
      indicators = source.indicators;
}

List<Map<String, dynamic>> _rows(Object? value) =>
    (value is List ? value : const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.unmodifiable(row))
        .toList();

/// One owner for card requests, role-scoped commerce and stale-response rejection.
/// This controller is created per workspace tab, never shared between identities.
class ClientCardDataController extends ChangeNotifier {
  ClientCardDataController({
    required MagicCrmService crm,
    required Future<String> Function() resolveRole,
  }) : _crm = crm,
       _resolveRole = resolveRole;
  final MagicCrmService _crm;
  final Future<String> Function() _resolveRole;
  bool _disposed = false;
  int _studentGeneration = 0, _leadGeneration = 0;
  int _commerceGeneration = 0;
  String? _studentId;
  ClientCardStudentSnapshot? _student;
  ClientCardStudentSnapshot? get student => _student;
  Map<String, dynamic>? _lead;
  Map<String, dynamic>? get lead => _lead;
  bool studentLoading = true, leadLoading = true;
  String? studentError, leadError;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<ClientCardStudentSnapshot?> loadStudent(
    String id, {
    bool preserveContent = false,
  }) async {
    if (_disposed || id.isEmpty) return null;
    final generation = ++_studentGeneration;
    final commerceGeneration = ++_commerceGeneration;
    if (_studentId != id) _student = null;
    _studentId = id;
    studentLoading = !preserveContent || _student == null;
    studentError = null;
    _notify();
    try {
      // Attach error handlers immediately to both independent requests.
      final results = await Future.wait<Object?>([
        _crm.getStudentCard(id),
        _loadCommerce(id),
      ]);
      if (_disposed || generation != _studentGeneration) return null;
      final card = results[0] as Map<String, dynamic>;
      final finance = results[1] as ({CommerceStudent? student, String? error});
      final identity = Map<String, dynamic>.from(card['student'] as Map? ?? {});
      identity['custom_data'] = {
        ...Map<String, dynamic>.from(identity['custom_data'] as Map? ?? {}),
        for (final entry in Map<String, dynamic>.from(
          card['custom_field_values'] as Map? ?? {},
        ).entries)
          if (entry.key != 'discipline' && entry.key != 'disciplines')
            entry.key: entry.value,
      };
      StudentFunnelConfiguration? funnel;
      String? funnelError;
      try {
        funnel = await _crm.getClientPipeline(
          clientType: 'student',
          branchId: identity['branch_id']?.toString(),
        );
      } catch (error) {
        funnelError = userErrorMessage(
          error,
          fallback: 'Не удалось загрузить воронку.',
        );
      }
      if (_disposed || generation != _studentGeneration) return null;
      _student = ClientCardStudentSnapshot(
        student: Map.unmodifiable(identity),
        commerce: commerceGeneration == _commerceGeneration
            ? finance.student
            : _student?.commerce,
        commerceError: commerceGeneration == _commerceGeneration
            ? finance.error
            : _student?.commerceError,
        funnel: funnel,
        funnelError: funnelError,
        card: card,
      );
      studentLoading = false;
      _notify();
      return _student;
    } catch (error) {
      if (_disposed || generation != _studentGeneration) return null;
      if (!preserveContent || _student == null) {
        studentError = userErrorMessage(
          error,
          fallback: 'Не удалось загрузить карточку ученика.',
        );
      }
      studentLoading = false;
      _notify();
      return null;
    }
  }

  /// Refresh only the authorized financial projection, preserving identity,
  /// schedule and pipeline snapshots. Independent generations prevent an old
  /// full-card response from overwriting a newer finance response (and vice versa).
  Future<void> refreshCommerce(String id) async {
    if (_disposed || id.isEmpty || _studentId != id) return;
    if (_student == null) {
      await loadStudent(id, preserveContent: true);
      return;
    }
    final generation = ++_commerceGeneration;
    final finance = await _loadCommerce(id);
    if (_disposed || generation != _commerceGeneration || _studentId != id) {
      return;
    }
    final snapshot = _student;
    if (snapshot == null) return;
    _student = ClientCardStudentSnapshot._withCommerce(
      snapshot,
      finance.student,
      finance.error,
    );
    _notify();
  }

  Future<({CommerceStudent? student, String? error})> _loadCommerce(
    String id,
  ) async {
    try {
      final role = await _resolveRole();
      if (_disposed || !crmHasClientCardFinanceAccess(role)) {
        return (student: null, error: null);
      }
      return (
        student: (await _crm.getStudentCommerceProjection(id)).student,
        error: null,
      );
    } catch (error) {
      return (
        student: null,
        error: userErrorMessage(
          error,
          fallback: 'Проверьте подключение и повторите попытку.',
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> loadLead(
    String id, {
    bool applySnapshot = true,
  }) async {
    if (_disposed) return null;
    if (id.isEmpty) {
      leadLoading = false;
      _notify();
      return null;
    }
    leadLoading = _lead == null;
    leadError = null;
    _notify();
    final generation = ++_leadGeneration;
    try {
      final card = await _crm.getLeadCard(id);
      if (_disposed || generation != _leadGeneration) return null;
      if (applySnapshot) _lead = Map.unmodifiable(card);
      leadLoading = false;
      leadError = null;
      _notify();
      return card;
    } catch (error) {
      if (_disposed || generation != _leadGeneration) return null;
      leadLoading = false;
      leadError = userErrorMessage(error);
      _notify();
      return null;
    }
  }

  void acceptLeadSnapshot(Map<String, dynamic>? card) {
    if (_disposed) return;
    _leadGeneration++;
    _lead = card == null ? null : Map.unmodifiable(card);
  }

  void recordComment(String entityType, Map<String, dynamic> created) {
    if (_disposed) return;
    if (entityType == 'lead' && _lead != null) {
      _lead = Map.unmodifiable({
        ..._lead!,
        'comments': mergeByIdSorted([
          [created],
          _rows(_lead!['comments']),
        ], dateKey: 'created_at'),
      });
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _studentGeneration++;
    _commerceGeneration++;
    _leadGeneration++;
    super.dispose();
  }
}
