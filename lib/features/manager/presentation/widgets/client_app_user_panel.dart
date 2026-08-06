import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/providers/chat_providers.dart';
import 'package:magic_music_crm/core/navigation/entity_route_registry.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

/// Shared «Пользователь приложения» panel embedded in both the lead card and
/// the student card. Shows the app user(s) linked to the CRM entity, lets staff
/// jump straight into a chat with each one, and — when nothing is linked yet —
/// offers a phone-based link flow over `/crm/clients/{entityType}/{entityId}/*`.
///
/// [entityType] is exactly `'lead'` or `'student'`; [entityId] is that record's
/// id. Flat Magic styling (design tokens, no glow), Russian copy.
class ClientAppUserPanel extends ConsumerStatefulWidget {
  final String entityType;
  final String entityId;

  const ClientAppUserPanel({
    super.key,
    required this.entityType,
    required this.entityId,
  });

  @override
  ConsumerState<ClientAppUserPanel> createState() => _ClientAppUserPanelState();
}

class _ClientAppUserPanelState extends ConsumerState<ClientAppUserPanel> {
  List<Map<String, dynamic>> _linkedUsers = const [];
  bool _loading = true;
  String? _error;
  // True while a phone-based link lookup / write is in flight, so the
  // «Привязать по телефону» button can't fire twice.
  bool _linking = false;

  @override
  void initState() {
    super.initState();
    _loadLinkedUsers();
  }

  Future<void> _loadLinkedUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .getClientLinkedUsers(widget.entityType, widget.entityId);
      if (!mounted) return;
      setState(() {
        _linkedUsers = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// Opens the in-app chat with [userId] by reusing the messenger navigation
  /// mechanism from the student card: set the navigation target, then return to
  /// the dashboard where the messenger screen is hosted.
  void _openChat(String? userId) {
    if (userId == null || userId.isEmpty) return;
    ref
        .read(messengerNavigationProvider.notifier)
        .navigateTo(MessengerNavigationState(partnerId: userId));
  }

  Future<void> _startLinkByPhone() async {
    setState(() => _linking = true);
    List<Map<String, dynamic>> candidates;
    try {
      candidates = await ref
          .read(magicCrmServiceProvider)
          .listClientUserCandidates(widget.entityType, widget.entityId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _linking = false);
      MagicToast.show(
        context,
        'Не удалось загрузить пользователей',
        detail: '$e',
        type: MagicToastType.danger,
      );
      return;
    }
    if (!mounted) return;
    setState(() => _linking = false);

    if (candidates.isEmpty) {
      MagicToast.show(
        context,
        'Нет пользователей с таким номером',
        type: MagicToastType.info,
      );
      return;
    }

    final selected = await showMagicAdaptiveSurface<Map<String, dynamic>>(
      context,
      kind: AppSurfaceKind.selection,
      title: 'Привязать пользователя',
      subtitle: 'Выберите аккаунт приложения по номеру телефона',
      icon: Icons.link_rounded,
      builder: (sheetContext) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in candidates) ...[
              _CandidateTile(
                candidate: c,
                onTap: () => Navigator.pop(sheetContext, c),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          ],
        );
      },
    );

    if (selected == null || !mounted) return;
    final userId = selected['userId']?.toString();
    if (userId == null || userId.isEmpty) return;
    await _linkUser(userId);
  }

  Future<void> _linkUser(String userId) async {
    setState(() => _linking = true);
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .linkUserToClient(widget.entityType, widget.entityId, userId);
      if (!mounted) return;
      setState(() {
        _linkedUsers = items;
        _linking = false;
      });
      MagicToast.show(
        context,
        'Пользователь привязан',
        type: MagicToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _linking = false);
      MagicToast.show(
        context,
        'Не удалось привязать пользователя',
        detail: '$e',
        type: MagicToastType.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColor.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColor.goldSoft,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: AppColor.goldLine),
                ),
                child: const Icon(
                  Icons.smartphone_rounded,
                  size: 17,
                  color: AppColor.gold,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              const Expanded(
                child: Text(
                  'Пользователь приложения',
                  style: TextStyle(
                    color: AppColor.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: LinearProgressIndicator(color: AppColor.gold),
      );
    }

    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Не удалось загрузить данные',
            style: TextStyle(color: AppColor.text2, fontSize: 13),
          ),
          const SizedBox(height: AppSpace.xs),
          TextButton.icon(
            onPressed: _loadLinkedUsers,
            style: TextButton.styleFrom(foregroundColor: AppColor.gold),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Повторить'),
          ),
        ],
      );
    }

    if (_linkedUsers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Нет привязанного пользователя',
            style: TextStyle(color: AppColor.text2, fontSize: 13),
          ),
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _linking ? null : _startLinkByPhone,
              style: FilledButton.styleFrom(
                backgroundColor: AppColor.goldSoft,
                foregroundColor: AppColor.gold,
                disabledBackgroundColor: AppColor.goldSoft,
                disabledForegroundColor: AppColor.text2,
                elevation: 0,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                  vertical: AppSpace.sm,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  side: const BorderSide(color: AppColor.goldLine),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: _linking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColor.gold,
                      ),
                    )
                  : const Icon(Icons.link_rounded, size: 16),
              label: const Text('Привязать по телефону'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _linkedUsers.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpace.sm),
          _LinkedUserRow(
            user: _linkedUsers[i],
            onChat: () => _openChat(_linkedUsers[i]['userId']?.toString()),
          ),
        ],
      ],
    );
  }
}

/// One linked app user: name + phone, an optional link-source chip, and a
/// «Написать» chat action that opens the in-app chat with that user.
class _LinkedUserRow extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onChat;

  const _LinkedUserRow({required this.user, required this.onChat});

  @override
  Widget build(BuildContext context) {
    final name = (user['name']?.toString().trim().isNotEmpty ?? false)
        ? user['name'].toString()
        : 'Без имени';
    final phone = user['phone']?.toString().trim() ?? '';
    final sourceLabel = _sourceLabel(user['linkSource']?.toString());

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColor.input,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColor.divider),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.person_outline_rounded,
            size: 18,
            color: AppColor.gold,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColor.text,
                        ),
                      ),
                    ),
                    if (sourceLabel != null) ...[
                      const SizedBox(width: AppSpace.sm),
                      _SourceChip(label: sourceLabel),
                    ],
                  ],
                ),
                if (phone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColor.text2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          IconButton(
            tooltip: 'Написать',
            visualDensity: VisualDensity.compact,
            onPressed: onChat,
            icon: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 18,
              color: AppColor.gold,
            ),
          ),
        ],
      ),
    );
  }

  String? _sourceLabel(String? source) {
    switch (source) {
      case 'self':
      case 'own':
        return 'свой аккаунт';
      case null:
      case '':
        return null;
      default:
        return 'привязан';
    }
  }
}

/// Small flat chip indicating how the user was linked (own account / linked).
class _SourceChip extends StatelessWidget {
  final String label;
  const _SourceChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColor.goldSoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColor.goldLine),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColor.gold,
        ),
      ),
    );
  }
}

/// Selectable user-candidate row inside the «Привязать по телефону» sheet.
class _CandidateTile extends StatelessWidget {
  final Map<String, dynamic> candidate;
  final VoidCallback onTap;

  const _CandidateTile({required this.candidate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = (candidate['name']?.toString().trim().isNotEmpty ?? false)
        ? candidate['name'].toString()
        : 'Без имени';
    final meta = [
      candidate['phone']?.toString().trim(),
      candidate['email']?.toString().trim(),
    ].where((v) => v != null && v.isNotEmpty).join(' · ');

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
                  Icons.person_outline_rounded,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColor.text2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.goldSoft,
                  foregroundColor: AppColor.gold,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.sm,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    side: const BorderSide(color: AppColor.goldLine),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Привязать'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
