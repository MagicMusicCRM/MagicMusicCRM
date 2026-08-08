import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/core/services/magic_profile_admin_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/show_client_card.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/access_editor_sheet.dart';

/// Карточка пользователя (профиль/админ).
///
/// Грузит профиль ([MagicProfileAdminService.getProfile]) и список привязанных
/// CRM-сущностей ([MagicProfileAdminService.getProfileLinks]). Сбои секций
/// изолированы: падение/пустота привязок не мешает показать шапку.
class ProfileDetailScreen extends ConsumerStatefulWidget {
  const ProfileDetailScreen({
    super.key,
    required this.profileId,
    this.embedded = false,
  });

  final String profileId;
  final bool embedded;

  @override
  ConsumerState<ProfileDetailScreen> createState() =>
      _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends ConsumerState<ProfileDetailScreen> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _links = const [];
  String? _linksError;
  bool _loading = true;
  bool _linking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _linksError = null;
    });

    final service = ref.read(magicProfileAdminServiceProvider);

    // Шапка — обязательная секция: её ошибка показывается как ошибка экрана.
    Map<String, dynamic> profile;
    try {
      profile = await service.getProfile(widget.profileId);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$err';
      });
      return;
    }

    // Привязки изолированы: их сбой/пустота не должны ронять шапку.
    List<Map<String, dynamic>> links;
    try {
      links = await service.getProfileLinks(widget.profileId);
    } catch (error) {
      links = const [];
      _linksError = '$error';
    }

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _links = links;
      _loading = false;
    });
  }

  String _fullName(Map<String, dynamic> p) {
    final first = (p['first_name'] ?? '').toString().trim();
    final last = (p['last_name'] ?? '').toString().trim();
    final name = '$last $first'.trim();
    if (name.isNotEmpty) return name;
    final email = (p['email'] ?? '').toString().trim();
    return email.isNotEmpty ? email : 'Без имени';
  }

  String _roleLabel(Object? role) {
    switch (role?.toString()) {
      case 'client':
        return 'Клиент';
      case 'teacher':
        return 'Преподаватель';
      case 'manager':
        return 'Управляющий';
      case 'director':
        return 'Директор';
      case 'admin':
        return 'Администратор';
      case 'system_admin':
        return 'Администратор системы';
      default:
        return (role?.toString().trim().isNotEmpty ?? false)
            ? role.toString()
            : 'Без роли';
    }
  }

  Future<void> _autoLink() async {
    if (_linking) return;
    setState(() => _linking = true);
    try {
      await ref
          .read(magicProfileAdminServiceProvider)
          .autoLinkByPhone(widget.profileId);
      await _load();
      if (mounted) MagicToast.show(context, 'Связи по телефону обновлены');
    } catch (error) {
      if (mounted) {
        MagicToast.show(
          context,
          'Не удалось обновить связи',
          detail: '$error',
          type: MagicToastType.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildBody(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Карточка пользователя')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColor.gold),
      );
    }

    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }

    final profile = _profile;
    if (profile == null) {
      return _ErrorState(message: 'Профиль не найден', onRetry: _load);
    }

    final snapshot = ref.watch(capabilitySnapshotProvider).asData?.value;
    final userId = profile['user_id']?.toString();
    return RefreshIndicator(
      color: AppColor.gold,
      backgroundColor: Theme.of(context).colorScheme.surface,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: [
          _Header(
            name: _fullName(profile),
            roleLabel: _roleLabel(profile['role']),
            email: (profile['email'] ?? '').toString(),
            phone: (profile['phone'] ?? '').toString(),
          ),
          if (snapshot?.allows('system.settings.manage') == true) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                if (userId?.isNotEmpty == true)
                  FilledButton.icon(
                    onPressed: () => AccessEditorSheet.show(
                      context,
                      actorRole: snapshot!.role,
                      userId: userId!,
                      userLabel: _fullName(profile),
                      onChanged: _load,
                    ),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Настроить доступ'),
                  ),
                OutlinedButton.icon(
                  onPressed: _linking ? null : _autoLink,
                  icon: _linking
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_rounded),
                  label: const Text('Связать по телефону'),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          _LinksSection(links: _links, error: _linksError, onRetry: _load),
        ],
      ),
    );
  }
}

/// Шапка карточки: ФИО, роль, email, телефон.
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.roleLabel,
    required this.email,
    required this.phone,
  });

  final String name;
  final String roleLabel;
  final String email;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColor.gold.withValues(alpha: 0.16),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColor.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _RolePill(label: roleLabel),
                  ],
                ),
              ),
            ],
          ),
          if (email.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpace.lg),
            _InfoRow(icon: Icons.email_outlined, value: email),
          ],
          if (phone.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            _InfoRow(icon: Icons.phone_outlined, value: phone),
          ],
        ],
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColor.goldSoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColor.goldLine),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColor.gold,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Секция «Привязанные клиенты».
class _LinksSection extends StatelessWidget {
  const _LinksSection({
    required this.links,
    required this.error,
    required this.onRetry,
  });

  final List<Map<String, dynamic>> links;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpace.xs,
            bottom: AppSpace.sm,
          ),
          child: Text(
            'Привязанные клиенты',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: error != null
              ? ListTile(
                  leading: Icon(
                    Icons.error_outline_rounded,
                    color: scheme.error,
                  ),
                  title: const Text('Не удалось загрузить привязки'),
                  subtitle: const Text(
                    'Профиль загружен. Повторите запрос привязанных клиентов.',
                  ),
                  trailing: TextButton(
                    onPressed: onRetry,
                    child: const Text('Повторить'),
                  ),
                )
              : links.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Text(
                    'Нет привязанных клиентов',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < links.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      _LinkTile(link: links[i]),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.link});

  final Map<String, dynamic> link;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entityType = link['entity_type']?.toString();
    final entityId = link['entity_id']?.toString();
    final name = (link['name'] ?? '').toString().trim();

    final isStudent = entityType == 'student';
    final typeLabel = isStudent ? 'Ученик' : 'Лид';
    final canOpen = entityId != null && entityId.isNotEmpty;

    return ListTile(
      leading: Icon(
        isStudent ? Icons.school_outlined : Icons.assignment_ind_outlined,
        color: AppColor.gold,
        size: 22,
      ),
      title: Text(
        name.isNotEmpty ? name : 'Без имени',
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        typeLabel,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
      trailing: canOpen
          ? Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurfaceVariant,
              size: 20,
            )
          : null,
      onTap: !canOpen
          ? null
          : () async {
              if (isStudent) {
                await showClientCard(
                  context,
                  entityType: 'student',
                  entityId: entityId,
                  presentationLabel: name,
                );
              } else {
                await showClientCard(
                  context,
                  entityType: 'lead',
                  entityId: entityId,
                  presentationLabel: name,
                );
              }
            },
    );
  }
}

/// Состояние ошибки шапки с действием «Повторить».
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AppColor.danger),
            const SizedBox(height: AppSpace.md),
            Text(
              'Ошибка: $message',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: AppSpace.lg),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: AppColor.gold),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
