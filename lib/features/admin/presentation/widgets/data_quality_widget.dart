import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../core/widgets/v7/v7.dart';

part 'data_quality_cards.dart';

/// «Качество данных» (data quality) admin panel — P5-7 / KVA-198.
///
/// Closes the phone-review + lead-dedup orphan with two v7 sections:
///   1. «Очередь телефонов» — read-only phone review queue (flagged for manual
///      review) with a live count badge.
///   2. «Дубликаты лидов» — lead merge candidates with a confirm-then-merge
///      flow (winner picker + undo affordance via the returned merge-log id).
///
/// Surfaces come from [Theme.of]'s [ColorScheme] (light + dark aware); brand
/// accents come from the v7 [AppColor] tokens. Loading renders skeletons,
/// errors render a retry, and empty renders a friendly empty state.
class DataQualityWidget extends ConsumerStatefulWidget {
  const DataQualityWidget({super.key});

  @override
  ConsumerState<DataQualityWidget> createState() => _DataQualityWidgetState();
}

class _DataQualityWidgetState extends ConsumerState<DataQualityWidget> {
  // Phone review queue state.
  bool _phoneLoading = true;
  Object? _phoneError;
  List<Map<String, dynamic>> _phoneItems = const [];
  int _phoneCount = 0;

  // Merge candidates state.
  bool _mergeLoading = true;
  Object? _mergeError;
  List<Map<String, dynamic>> _mergeItems = const [];

  // Tracks the busy merge candidate (by row key) to disable its button.
  String? _mergingKey;

  @override
  void initState() {
    super.initState();
    _loadPhones();
    _loadMerges();
  }

  Future<void> _loadPhones() async {
    setState(() {
      _phoneLoading = true;
      _phoneError = null;
    });
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final items = await crm.listPhoneReviewQueue(limit: 100);
      final count = await crm.countPhoneReviewQueue();
      if (!mounted) return;
      setState(() {
        _phoneItems = items;
        _phoneCount = count;
        _phoneLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phoneError = e;
        _phoneLoading = false;
      });
    }
  }

  Future<void> _loadMerges() async {
    setState(() {
      _mergeLoading = true;
      _mergeError = null;
    });
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .listMergeCandidates(limit: 100);
      if (!mounted) return;
      setState(() {
        _mergeItems = items;
        _mergeLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mergeError = e;
        _mergeLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColor.gold,
      onRefresh: () async {
        await Future.wait([_loadPhones(), _loadMerges()]);
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: [
          _SectionHeader(
            icon: Icons.phone_in_talk_rounded,
            title: 'Очередь телефонов',
            subtitle: 'Номера, помеченные для ручной проверки',
            badge: _phoneLoading ? null : _phoneCount,
          ),
          const SizedBox(height: AppSpace.sm),
          _buildPhoneSection(),
          const SizedBox(height: AppSpace.xl),
          _SectionHeader(
            icon: Icons.merge_type_rounded,
            title: 'Дубликаты лидов',
            subtitle: 'Кандидаты на объединение по телефону и имени',
            badge: _mergeLoading ? null : _mergeItems.length,
          ),
          const SizedBox(height: AppSpace.sm),
          _buildMergeSection(),
        ],
      ),
    );
  }

  // ── Phone review queue ─────────────────────────────────────────────────────
  Widget _buildPhoneSection() {
    if (_phoneLoading) return const _CardListSkeleton();
    if (_phoneError != null) {
      return _ErrorRetry(error: _phoneError!, onRetry: _loadPhones);
    }
    if (_phoneItems.isEmpty) {
      return const _EmptyState(
        icon: Icons.check_circle_outline_rounded,
        message: 'Очередь пуста — все номера в порядке',
      );
    }
    return Column(
      children: [for (final item in _phoneItems) _PhoneReviewCard(item: item)],
    );
  }

  // ── Merge candidates ───────────────────────────────────────────────────────
  Widget _buildMergeSection() {
    if (_mergeLoading) return const _CardListSkeleton();
    if (_mergeError != null) {
      return _ErrorRetry(error: _mergeError!, onRetry: _loadMerges);
    }
    if (_mergeItems.isEmpty) {
      return const _EmptyState(
        icon: Icons.verified_outlined,
        message: 'Дубликаты не найдены',
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _mergeItems.length; i++)
          _MergeCandidateCard(
            item: _mergeItems[i],
            rowKey: _mergeKey(_mergeItems[i], i),
            busy: _mergingKey == _mergeKey(_mergeItems[i], i),
            onMerge: _confirmMerge,
          ),
      ],
    );
  }

  String _mergeKey(Map<String, dynamic> item, int index) {
    final winner = _readString(item, ['winnerId', 'winner_id']);
    final loser = _readString(item, ['loserId', 'loser_id']);
    if (winner.isNotEmpty || loser.isNotEmpty) return '$winner|$loser';
    return 'idx-$index';
  }

  Future<void> _confirmMerge(Map<String, dynamic> item, String rowKey) async {
    final firstId = _readString(item, ['loserId', 'loser_id']);
    final secondId = _readString(item, ['winnerId', 'winner_id']);
    if (firstId.isEmpty || secondId.isEmpty) {
      MagicToast.show(
        context,
        'Недостаточно данных для объединения',
        type: MagicToastType.danger,
      );
      return;
    }

    final name = _readString(item, ['name']);
    final phone = _readString(item, [
      'phone',
      'phoneNormalized',
      'phone_normalized',
    ]);

    final winnerId = await showDialog<String>(
      context: context,
      builder: (ctx) => _MergeConfirmDialog(
        name: name,
        phone: phone,
        firstId: firstId,
        secondId: secondId,
        first: _readMap(item, 'first'),
        second: _readMap(item, 'second'),
      ),
    );
    if (winnerId == null || !mounted) return;

    final loserId = winnerId == firstId ? secondId : firstId;

    setState(() => _mergingKey = rowKey);
    try {
      final res = await ref
          .read(magicCrmServiceProvider)
          .mergeLeads(winnerId: winnerId, loserId: loserId);
      if (!mounted) return;
      setState(() => _mergingKey = null);

      final mergeLogId = _readString(res, ['mergeLogId', 'merge_log_id']);
      await _loadMerges();
      if (!mounted) return;

      MagicToast.show(
        context,
        'Лиды объединены',
        detail: name.isEmpty ? null : name,
        type: MagicToastType.success,
        actionLabel: mergeLogId.isEmpty ? null : 'Отменить',
        onAction: mergeLogId.isEmpty ? null : () => _undoMerge(mergeLogId),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _mergingKey = null);
      MagicToast.show(
        context,
        'Не удалось объединить',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  Future<void> _undoMerge(String mergeLogId) async {
    try {
      await ref.read(magicCrmServiceProvider).undoMerge(mergeLogId);
      await _loadMerges();
      if (!mounted) return;
      MagicToast.show(
        context,
        'Объединение отменено',
        type: MagicToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      MagicToast.show(
        context,
        'Не удалось отменить объединение',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Defensive readers (snake_case AND camelCase).
// ─────────────────────────────────────────────────────────────────────────────
String _readString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null) {
      final str = value.toString().trim();
      if (str.isNotEmpty) return str;
    }
  }
  return '';
}

Map<String, dynamic> _readMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is Map ? Map<String, dynamic>.from(value) : const {};
}
