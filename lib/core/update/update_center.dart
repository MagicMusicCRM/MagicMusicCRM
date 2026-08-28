import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/env.dart';
import '../theme/design_tokens.dart';
import 'release_history.dart';
import 'update_provider.dart';
import 'windows_update_service.dart';

Future<void> showUpdatesCenter(
  BuildContext context, {
  WindowsUpdateService? service,
  ReleaseHistoryRepository? historyRepository,
  Future<void> Function(UpdateManifest manifest)? onInstall,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => UpdatesCenterDialog(
      service: service,
      historyRepository: historyRepository,
      onInstall: onInstall,
    ),
  );
}

class AppVersionButton extends StatefulWidget {
  const AppVersionButton({
    super.key,
    required this.onPressed,
    this.hasUpdate = false,
    this.versionLoader,
  });

  final VoidCallback onPressed;
  final bool hasUpdate;
  final Future<InstalledAppVersion> Function()? versionLoader;

  @override
  State<AppVersionButton> createState() => _AppVersionButtonState();
}

class _AppVersionButtonState extends State<AppVersionButton> {
  late final Future<InstalledAppVersion> _version;

  @override
  void initState() {
    super.initState();
    _version = (widget.versionLoader ?? loadInstalledAppVersion)();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InstalledAppVersion>(
      future: _version,
      builder: (context, snapshot) {
        final version = snapshot.data;
        final label = version?.shortVersion ?? 'Версия';
        final versionDescription = version == null
            ? 'Открыть раздел обновлений'
            : 'Версия ${version.version}. Открыть раздел обновлений';
        final description = widget.hasUpdate
            ? 'Доступно обновление. $versionDescription'
            : versionDescription;
        return Semantics(
          button: true,
          label: description,
          child: SizedBox(
            width: 68,
            height: 48,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.control),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('app-version-button'),
                borderRadius: BorderRadius.circular(AppRadius.control),
                hoverColor: AppColor.goldSoft,
                highlightColor: AppColor.goldSoft,
                onTap: widget.onPressed,
                child: Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: AppColor.text2,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColor.text2,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.hasUpdate)
                      Positioned(
                        key: const ValueKey('app-version-update-dot'),
                        top: 6,
                        right: 15,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: AppColor.gold2,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColor.sidebar,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class UpdatesCenterDialog extends ConsumerStatefulWidget {
  const UpdatesCenterDialog({
    super.key,
    this.service,
    this.historyRepository,
    this.onInstall,
    this.versionLoader,
  });

  final WindowsUpdateService? service;
  final ReleaseHistoryRepository? historyRepository;
  final Future<void> Function(UpdateManifest manifest)? onInstall;
  final Future<InstalledAppVersion> Function()? versionLoader;

  @override
  ConsumerState<UpdatesCenterDialog> createState() =>
      _UpdatesCenterDialogState();
}

class _UpdatesCenterDialogState extends ConsumerState<UpdatesCenterDialog> {
  late final WindowsUpdateService _service;
  late final ReleaseHistoryRepository _historyRepository;
  late final Future<List<AppReleaseNote>> _history;
  late final Future<InstalledAppVersion> _installedVersion;

  bool _checking = false;
  String? _checkMessage;

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ??
        WindowsUpdateService(
          manifestUrl: windowsUpdateManifestUrlForApi(Env.magicApiBaseUrl),
        );
    _historyRepository =
        widget.historyRepository ??
        ReleaseHistoryRepository(
          remoteUrl: releaseHistoryUrlForApi(Env.magicApiBaseUrl),
        );
    _history = _historyRepository.load();
    _installedVersion = (widget.versionLoader ?? loadInstalledAppVersion)();
  }

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _checkMessage = null;
    });

    final result = await _service.checkDetailed();
    if (!mounted) return;

    switch (result.status) {
      case WindowsUpdateCheckStatus.available:
        ref.read(availableUpdateProvider.notifier).set(result.manifest);
        _checkMessage = 'Новая версия найдена.';
        break;
      case WindowsUpdateCheckStatus.upToDate:
        ref.read(availableUpdateProvider.notifier).set(null);
        _checkMessage = 'Установлена актуальная версия.';
        break;
      case WindowsUpdateCheckStatus.unavailable:
        _checkMessage =
            'Не удалось проверить обновления. Проверьте интернет и повторите.';
        break;
      case WindowsUpdateCheckStatus.invalidResponse:
        _checkMessage =
            'Сервер обновлений вернул некорректные данные. Попробуйте позже.';
        break;
      case WindowsUpdateCheckStatus.invalidConfiguration:
        _checkMessage = 'Проверка обновлений недоступна в этой сборке.';
        break;
      case WindowsUpdateCheckStatus.unsupported:
        _checkMessage =
            'Для этой платформы обновления устанавливаются отдельно.';
        break;
    }

    setState(() => _checking = false);
  }

  Future<void> _install(UpdateManifest manifest) async {
    final install = widget.onInstall;
    if (install == null) return;
    Navigator.of(context).pop();
    await Future<void>.delayed(Duration.zero);
    await install(manifest);
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(availableUpdateProvider);
    final media = MediaQuery.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpace.lg),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: media.size.height * 0.88,
        ),
        child: Column(
          children: [
            _Header(onClose: () => Navigator.of(context).pop()),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: _UpdateStatusCard(
                installedVersion: _installedVersion,
                available: available,
                checking: _checking,
                checkMessage: _checkMessage,
                onCheck: _checkForUpdates,
                onInstall: available == null || widget.onInstall == null
                    ? null
                    : () => unawaited(_install(available)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpace.lg,
                0,
                AppSpace.lg,
                AppSpace.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'История версий',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<AppReleaseNote>>(
                future: _history,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final releases = snapshot.data;
                  if (releases == null || releases.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpace.xl),
                        child: Text(
                          'История версий временно недоступна.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg,
                      0,
                      AppSpace.lg,
                      AppSpace.lg,
                    ),
                    itemCount: releases.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpace.sm),
                    itemBuilder: (context, index) => _ReleaseCard(
                      release: releases[index],
                      initiallyExpanded: index == 0,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.sm,
        AppSpace.md,
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_alt_rounded, color: AppColor.gold),
          const SizedBox(width: AppSpace.sm),
          const Expanded(
            child: Text(
              'Обновления',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Закрыть',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _UpdateStatusCard extends StatelessWidget {
  const _UpdateStatusCard({
    required this.installedVersion,
    required this.available,
    required this.checking,
    required this.checkMessage,
    required this.onCheck,
    required this.onInstall,
  });

  final Future<InstalledAppVersion> installedVersion;
  final UpdateManifest? available;
  final bool checking;
  final String? checkMessage;
  final VoidCallback onCheck;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: available == null ? AppColor.surface : AppColor.goldSoft,
        border: Border.all(
          color: available == null ? AppColor.divider : AppColor.goldLine,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpace.md,
        runSpacing: AppSpace.md,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  available == null
                      ? 'Текущая версия'
                      : 'Доступна версия ${available!.version}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                FutureBuilder<InstalledAppVersion>(
                  future: installedVersion,
                  builder: (context, snapshot) => Text(
                    snapshot.data == null
                        ? 'Определяем установленную версию'
                        : 'Установлено: ${snapshot.data!.version}',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                if ((available?.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    available!.notes!.trim(),
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                if (checkMessage != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(checkMessage!, style: const TextStyle(fontSize: 12.5)),
                ],
              ],
            ),
          ),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              OutlinedButton.icon(
                onPressed: checking ? null : onCheck,
                icon: checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(checking ? 'Проверяем' : 'Проверить'),
              ),
              if (onInstall != null)
                FilledButton.icon(
                  onPressed: onInstall,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Установить'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release, required this.initiallyExpanded});

  final AppReleaseNote release;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColor.surface,
        border: Border.all(color: AppColor.divider),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.xs,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpace.md,
          0,
          AppSpace.md,
          AppSpace.md,
        ),
        title: Text(
          '${release.version}  ${release.title}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Text(
            '${release.date}\n${release.summary}',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
          ),
        ),
        children: [
          for (final change in release.changes)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(Icons.circle, size: 5, color: AppColor.gold),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(change, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
