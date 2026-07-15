import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/magic_profile_admin_service.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/widgets/v7/v7.dart';

part 'deletion_requests_cards.dart';

/// «Запросы на удаление» — account-deletion-request admin queue (P5-7 / KVA-198).
///
/// Closes the last backend orphan: a v7 review queue over
/// `magicProfileAdminServiceProvider.listDeletionRequests` with a status
/// filter and per-row actions to advance a request through its lifecycle
/// (pending → processing → completed/rejected) via `updateDeletionRequest`.
///
/// Surfaces come from [Theme.of]'s [ColorScheme] (light + dark aware); brand
/// accents come from the v7 [AppColor] tokens. Loading renders skeletons,
/// errors render a retry, and empty renders a friendly empty state. The backend
/// restricts updates to admins and returns 403 otherwise — that error is
/// surfaced verbatim through a [MagicToast].
class DeletionRequestsWidget extends ConsumerStatefulWidget {
  const DeletionRequestsWidget({super.key});

  @override
  ConsumerState<DeletionRequestsWidget> createState() =>
      _DeletionRequestsWidgetState();
}

class _DeletionRequestsWidgetState
    extends ConsumerState<DeletionRequestsWidget> {
  // `null` status = «Все» (no filter).
  String? _status;

  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _items = const [];

  // Row id currently being updated (disables that row's actions).
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref
          .read(magicProfileAdminServiceProvider)
          .listDeletionRequests(status: _status, limit: 100);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _selectStatus(String? status) {
    if (_status == status) return;
    setState(() => _status = status);
    _load();
  }

  Future<void> _advance(
    Map<String, dynamic> item,
    _DeletionAction action,
  ) async {
    final id = _readString(item, ['id']);
    if (id.isEmpty) {
      MagicToast.show(
        context,
        'Недостаточно данных для обновления',
        type: MagicToastType.danger,
      );
      return;
    }

    final identity = _identityLabel(item);
    final outcome = await _showConfirmSheet(action, identity);
    if (outcome == null || !mounted) return;

    setState(() => _busyId = id);
    try {
      await ref.read(magicProfileAdminServiceProvider).updateDeletionRequest(
            id,
            status: action.status,
            resolutionNote: outcome.note,
          );
      if (!mounted) return;
      setState(() => _busyId = null);
      await _load();
      if (!mounted) return;
      MagicToast.show(
        context,
        action.successMessage,
        detail: identity.isEmpty ? null : identity,
        type: MagicToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      MagicToast.show(
        context,
        'Не удалось обновить запрос',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  /// Opens the v7 confirm sheet. For reject/complete it also collects an
  /// optional resolution note. Resolves to an [_ConfirmOutcome] on confirm, or
  /// `null` if the operator cancels.
  Future<_ConfirmOutcome?> _showConfirmSheet(
    _DeletionAction action,
    String identity,
  ) {
    return showMagicSheet<_ConfirmOutcome>(
      context,
      title: action.confirmTitle,
      subtitle: identity.isEmpty ? 'Запрос на удаление' : identity,
      icon: action.icon,
      builder: (ctx) => _ConfirmSheetBody(action: action),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatusFilterBar(selected: _status, onSelect: _selectStatus),
        Expanded(
          child: RefreshIndicator(
            color: AppColor.gold,
            onRefresh: _load,
            child: _buildBody(),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: const [_CardListSkeleton()],
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: [_ErrorRetry(error: _error!, onRetry: _load)],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: const [
          _EmptyState(
            icon: Icons.inbox_outlined,
            message: 'Нет запросов на удаление',
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpace.md),
      itemCount: _items.length,
      itemBuilder: (ctx, i) {
        final item = _items[i];
        final id = _readString(item, ['id']);
        return _DeletionRequestCard(
          item: item,
          busy: _busyId == id,
          onAction: _advance,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status model.
// ─────────────────────────────────────────────────────────────────────────────

/// The lifecycle states of a deletion request, with Russian labels + accents.
enum _DeletionStatus {
  pending('pending', 'Ожидает', Icons.hourglass_empty_rounded),
  processing('processing', 'В работе', Icons.autorenew_rounded),
  completed('completed', 'Выполнен', Icons.check_circle_outline_rounded),
  rejected('rejected', 'Отклонён', Icons.cancel_outlined),
  cancelled('cancelled', 'Отменён', Icons.block_rounded);

  const _DeletionStatus(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;

  /// Terminal states cannot be advanced further.
  bool get isTerminal =>
      this == completed || this == rejected || this == cancelled;

  Color color(ColorScheme cs) {
    switch (this) {
      case _DeletionStatus.pending:
        return AppColor.gold;
      case _DeletionStatus.processing:
        return AppColor.gold2;
      case _DeletionStatus.completed:
        return AppColor.success;
      case _DeletionStatus.rejected:
        return AppColor.danger;
      case _DeletionStatus.cancelled:
        return cs.onSurfaceVariant;
    }
  }

  static _DeletionStatus fromValue(String raw) {
    final v = raw.trim().toLowerCase();
    for (final s in _DeletionStatus.values) {
      if (s.value == v) return s;
    }
    // Unknown / empty → treat as pending so it stays actionable.
    return _DeletionStatus.pending;
  }
}

/// An action that advances a request to a new status.
enum _DeletionAction {
  processing(
    status: 'processing',
    buttonLabel: 'В работу',
    confirmTitle: 'Взять в работу?',
    icon: Icons.play_arrow_rounded,
    successMessage: 'Запрос взят в работу',
    collectsNote: false,
    danger: false,
  ),
  completed(
    status: 'completed',
    buttonLabel: 'Выполнить',
    confirmTitle: 'Отметить выполненным?',
    icon: Icons.check_rounded,
    successMessage: 'Запрос выполнен',
    collectsNote: true,
    danger: false,
  ),
  rejected(
    status: 'rejected',
    buttonLabel: 'Отклонить',
    confirmTitle: 'Отклонить запрос?',
    icon: Icons.close_rounded,
    successMessage: 'Запрос отклонён',
    collectsNote: true,
    danger: true,
  );

  const _DeletionAction({
    required this.status,
    required this.buttonLabel,
    required this.confirmTitle,
    required this.icon,
    required this.successMessage,
    required this.collectsNote,
    required this.danger,
  });

  final String status;
  final String buttonLabel;
  final String confirmTitle;
  final IconData icon;
  final String successMessage;
  final bool collectsNote;
  final bool danger;
}

