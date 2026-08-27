import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import 'reference_catalog_lifecycle_state.dart';

export 'reference_catalog_lifecycle_state.dart';

class ReferenceCatalogLifecycleController extends ChangeNotifier {
  ReferenceCatalogLifecycleController({
    required MagicCrmService service,
    required this.entityType,
    required Map<String, dynamic> initialItem,
  }) : _service = service,
       _initialItem = Map<String, dynamic>.from(initialItem),
       _id = initialItem['id']?.toString() ?? '',
       _state = ReferenceCatalogLifecycleState.initial(
         entityType: entityType,
         item: initialItem,
       );

  final MagicCrmService _service;
  final String entityType;
  final Map<String, dynamic> _initialItem;
  final String _id;
  ReferenceCatalogLifecycleState _state;
  int _loadGeneration = 0;
  int _mutationGeneration = 0;
  bool _disposed = false;

  ReferenceCatalogLifecycleState get state => _state;

  Future<void> load({String? errorAfterLoad}) async {
    if (_disposed || _id.isEmpty) return;
    final generation = ++_loadGeneration;
    _emit(state.copyWith(loading: true, error: null));
    try {
      final values = await Future.wait<Object>([
        _service.previewReferenceCatalogLifecycle(
          entityType: entityType,
          id: _id,
        ),
        _service.listReferenceCatalogHistory(entityType: entityType, id: _id),
      ]);
      if (!_loadActive(generation)) return;
      final preview = Map<String, dynamic>.from(values[0] as Map);
      _emit(
        state.copyWith(
          entity: _entityFrom(preview),
          preview: preview,
          history: (values[1] as List).cast<Map<String, dynamic>>(),
          loading: false,
          entitySyncRevision: state.entitySyncRevision + 1,
          error: errorAfterLoad,
        ),
      );
    } catch (error) {
      if (!_loadActive(generation)) return;
      _emit(
        state.copyWith(
          loading: false,
          error:
              errorAfterLoad ??
              userErrorMessage(error, fallback: 'Не удалось проверить запись.'),
        ),
      );
    }
  }

  Future<bool> rename({
    required String name,
    required String reasonText,
  }) async {
    if (_disposed) return false;
    final reason = _validatedReason(reasonText);
    if (reason == null || state.saving) return false;
    if (!state.canRename) {
      _emit(state.copyWith(error: 'Изменение названия недоступно.'));
      return false;
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty ||
        normalizedName == state.entity['name']?.toString()) {
      _emit(state.copyWith(error: 'Укажите новое название.'));
      return false;
    }
    final generation = _beginSaving();
    try {
      await _service.renameReferenceCatalogItem(
        entityType: entityType,
        id: _id,
        name: normalizedName,
        expectedVersion: state.version,
        reasonText: reason,
      );
      if (!_mutationActive(generation)) return false;
      _emit(state.copyWith(saving: false));
      await load();
      return !_disposed;
    } catch (error) {
      return _reconcileMutationError(error, generation);
    }
  }

  Future<bool> commitLifecycle({required String reasonText}) async {
    if (_disposed) return false;
    final reason = _validatedReason(reasonText);
    if (reason == null || state.saving || !state.canCommit) return false;
    final generation = _beginSaving();
    try {
      if (state.archived) {
        await _service.restoreReferenceCatalogItem(
          entityType: entityType,
          id: _id,
          expectedVersion: state.version,
          reasonText: reason,
        );
      } else {
        await _service.archiveReferenceCatalogItem(
          entityType: entityType,
          id: _id,
          expectedVersion: state.version,
          reasonText: reason,
        );
      }
      if (!_mutationActive(generation)) return false;
      _emit(state.copyWith(saving: false));
      return true;
    } catch (error) {
      return _reconcileMutationError(error, generation);
    }
  }

  String? _validatedReason(String raw) {
    final reason = raw.trim();
    if (reason.length >= 3) return reason;
    _emit(
      state.copyWith(error: 'Укажите понятную причину (минимум 3 символа).'),
    );
    return null;
  }

  int _beginSaving() {
    final generation = ++_mutationGeneration;
    _emit(state.copyWith(saving: true, error: null));
    return generation;
  }

  Future<bool> _reconcileMutationError(Object error, int generation) async {
    if (!_mutationActive(generation)) return false;
    final message = userErrorMessage(
      error,
      fallback: 'Не удалось изменить запись.',
    );
    _emit(state.copyWith(saving: false, error: message));
    await load(errorAfterLoad: message);
    return false;
  }

  Map<String, dynamic> _entityFrom(Map<String, dynamic> preview) {
    final raw = preview['entity'];
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : Map<String, dynamic>.from(_initialItem);
  }

  bool _loadActive(int generation) =>
      !_disposed && generation == _loadGeneration;

  bool _mutationActive(int generation) =>
      !_disposed && generation == _mutationGeneration;

  void _emit(ReferenceCatalogLifecycleState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loadGeneration += 1;
    _mutationGeneration += 1;
    super.dispose();
  }
}
