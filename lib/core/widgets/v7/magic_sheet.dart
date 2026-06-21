import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// Opens a v7 bottom sheet (`.sheet` — grabber, head with icon-badge +
/// title/subtitle, scrollable body, optional footer actions) and resolves to
/// whatever the body pops via `Navigator.pop`.
///
/// Mirrors the prototype's booking / expense / card-menu sheets. Additive in
/// P0 — the canonical wrapper reskin phases use instead of bespoke
/// `showModalBottomSheet` chrome.
Future<T?> showMagicSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  String? subtitle,
  IconData? icon,
  List<Widget>? actions,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColor.scrim,
    builder: (context) => _MagicSheet(
      title: title,
      subtitle: subtitle,
      icon: icon,
      actions: actions,
      body: builder(context),
    ),
  );
}

class _MagicSheet extends StatelessWidget {
  const _MagicSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    required this.body,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget>? actions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.9;

    // v7 `.sheet{bottom:0}` — dock to the bottom, centered horizontally, and
    // lift above the soft keyboard so footer actions stay reachable on forms.
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 460, maxHeight: maxHeight),
          child: Container(
          decoration: BoxDecoration(
            color: AppColor.surface,
            border: const Border(
              top: BorderSide(color: AppColor.divider),
              left: BorderSide(color: AppColor.divider),
              right: BorderSide(color: AppColor.divider),
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.sheet),
            ),
            boxShadow: AppShadow.sh2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grabber.
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 2),
                decoration: BoxDecoration(
                  color: AppColor.sheetGrab,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              // Head.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon != null) ...[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColor.goldSoft,
                          borderRadius: BorderRadius.circular(AppRadius.icon),
                          border: Border.all(color: AppColor.goldLine),
                        ),
                        child: Icon(icon, size: 20, color: AppColor.gold),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColor.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColor.text2,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColor.divider),
              // Body (scrollable).
              Flexible(
                child: SingleChildScrollView(
                  padding: AppSpace.sheetBody,
                  child: body,
                ),
              ),
              // Footer actions.
              if (actions != null && actions!.isNotEmpty) ...[
                const Divider(height: 1, color: AppColor.divider),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 13, 20, 18),
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
      ),
    );
  }
}
