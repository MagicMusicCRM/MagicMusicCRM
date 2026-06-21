import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// Opens a v7 end-side slide-out panel (`.drawer` — 380px, surface, head with
/// title + close, scrollable body, optional footer) and resolves to whatever
/// the body pops.
///
/// This is the card-detail / column-editor drawer pattern from the prototype.
/// Additive in P0 — the canonical wrapper the Clients (P3) and Settings (P5)
/// reskins mount their detail panels in.
Future<T?> showMagicDrawer<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  List<Widget>? actions,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: AppColor.scrim,
    transitionDuration: AppMotion.slow,
    pageBuilder: (context, _, _) {
      return Align(
        alignment: Alignment.centerRight,
        child: _MagicDrawer(
          title: title,
          actions: actions,
          body: builder(context),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: AppMotion.ease)),
        child: child,
      );
    },
  );
}

class _MagicDrawer extends StatelessWidget {
  const _MagicDrawer({
    required this.title,
    required this.actions,
    required this.body,
  });

  final String title;
  final List<Widget>? actions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 380,
        constraints: BoxConstraints(maxWidth: width * 0.92),
        height: double.infinity,
        decoration: const BoxDecoration(
          color: AppColor.surface,
          border: Border(left: BorderSide(color: AppColor.divider)),
          boxShadow: AppShadow.sh2,
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Head.
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColor.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.16,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: AppColor.text2,
                      iconSize: 20,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColor.divider),
              // Body.
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpace.drawerBody),
                  child: body,
                ),
              ),
              // Footer.
              if (actions != null && actions!.isNotEmpty) ...[
                const Divider(height: 1, color: AppColor.divider),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                  child: Row(
                    children: [
                      for (var i = 0; i < actions!.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: actions![i]),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
