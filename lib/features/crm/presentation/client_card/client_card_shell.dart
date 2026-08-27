import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

typedef ClientCardWorkspaceBuilder = Widget Function(BuildContext context);

class ClientCardShell extends StatelessWidget {
  const ClientCardShell({
    super.key,
    required this.routed,
    required this.edited,
    required this.dirty,
    required this.header,
    this.blacklistBanner,
    required this.desktopWorkspaceBuilder,
    required this.compactWorkspaceBuilder,
    required this.actionBar,
    required this.onCloseRequested,
  });

  final bool routed;
  final bool edited;
  final bool dirty;
  final Widget header;
  final Widget? blacklistBanner;
  final ClientCardWorkspaceBuilder desktopWorkspaceBuilder;
  final ClientCardWorkspaceBuilder compactWorkspaceBuilder;
  final Widget actionBar;
  final Future<void> Function() onCloseRequested;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final card = Container(
      key: const Key('client-card-shell-card'),
      width: routed
          ? double.infinity
          : (media.size.width * 0.92).clamp(0.0, 600.0).toDouble(),
      height: routed ? double.infinity : null,
      constraints: routed
          ? null
          : BoxConstraints(maxWidth: 600, maxHeight: media.size.height * 0.85),
      color: colors.surface,
      child: Column(
        children: [
          header,
          ?blacklistBanner,
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.6),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  routed && constraints.maxWidth >= 840
                  ? desktopWorkspaceBuilder(context)
                  : compactWorkspaceBuilder(context),
            ),
          ),
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.6),
          ),
          actionBar,
        ],
      ),
    );
    return PopScope(
      canPop: !edited && !dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await onCloseRequested();
      },
      child: routed
          ? card
          : MediaQuery.removeViewInsets(
              context: context,
              removeBottom: true,
              child: Dialog(
                backgroundColor: colors.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  side: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: card,
              ),
            ),
    );
  }
}
