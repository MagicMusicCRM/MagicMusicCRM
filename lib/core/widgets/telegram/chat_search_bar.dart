import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/theme/telegram_colors.dart';

/// Telegram-style search bar for chat list.
///
/// The widget owns its own result-state messaging: when the host passes the
/// current [query], whether a search is [isLoading], and the [resultCount],
/// the bar renders a status row underneath the field so the loading state is
/// always visually distinct from a genuine "no results" empty state.
class ChatSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final String hint;

  /// The active query text. When provided and non-empty, the status row is
  /// shown. Leave `null` to keep the bar in its plain input-only mode.
  final String? query;

  /// Whether results are currently being fetched/computed for [query].
  final bool isLoading;

  /// Number of results found for [query]. Used to distinguish a populated
  /// result set from the empty "Ничего не найдено" state.
  final int? resultCount;

  const ChatSearchBar({
    super.key,
    this.controller,
    this.onChanged,
    this.onTap,
    this.hint = 'Поиск',
    this.query,
    this.isLoading = false,
    this.resultCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onTap: onTap,
              keyboardType: TextInputType.text,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: isDark
                      ? TelegramColors.darkTextSecondary
                      : TelegramColors.lightTextSecondary,
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: isDark
                      ? TelegramColors.darkTextSecondary
                      : TelegramColors.lightTextSecondary,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 40),
                filled: true,
                fillColor: isDark
                    ? TelegramColors.darkInputBg
                    : TelegramColors.lightInputBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ),
        _buildStatusRow(isDark),
      ],
    );
  }

  /// Renders a status row beneath the field. Three explicit states keep the
  /// loading indicator and the empty "no results" message unambiguous:
  ///  * loading  -> spinner + "Поиск..."
  ///  * no hits  -> info icon + "Ничего не найдено"
  ///  * has hits -> nothing (the result list itself is the feedback)
  Widget _buildStatusRow(bool isDark) {
    final activeQuery = query?.trim() ?? '';
    if (activeQuery.isEmpty) {
      // No active query: input-only mode, nothing to announce.
      return const SizedBox.shrink();
    }

    final secondary = isDark
        ? TelegramColors.darkTextSecondary
        : TelegramColors.lightTextSecondary;

    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: secondary,
              ),
            ),
            const SizedBox(width: 8),
            Text('Поиск...', style: TextStyle(color: secondary, fontSize: 13)),
          ],
        ),
      );
    }

    if ((resultCount ?? -1) == 0) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            Icon(Icons.search_off_rounded, size: 16, color: secondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ничего не найдено',
                style: TextStyle(color: secondary, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    // Results present (or count unknown): the result list provides feedback.
    return const SizedBox.shrink();
  }
}
