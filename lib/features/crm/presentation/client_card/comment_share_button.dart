import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

class CommentShareButton extends ConsumerStatefulWidget {
  const CommentShareButton({
    super.key,
    required this.commentId,
    required this.version,
    required this.sharedWithTeacher,
    required this.allowed,
    required this.onChanged,
  });

  final String commentId;
  final int version;
  final bool sharedWithTeacher;
  final bool allowed;
  final VoidCallback onChanged;

  @override
  ConsumerState<CommentShareButton> createState() => _CommentShareButtonState();
}

class _CommentShareButtonState extends ConsumerState<CommentShareButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .setCommentVisibility(
            commentId: widget.commentId,
            visibleToTeacher: !widget.sharedWithTeacher,
            expectedVersion: widget.version,
          );
      if (mounted) widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить видимость: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.allowed) return const SizedBox.shrink();
    final visible = widget.sharedWithTeacher;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: ValueKey('comment-share-${widget.commentId}'),
        onPressed: _busy ? null : _toggle,
        style: TextButton.styleFrom(
          foregroundColor: visible
              ? AppColor.gold
              : Theme.of(context).colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: _busy
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                visible
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                size: 14,
              ),
        label: Text(
          visible ? 'Виден преподавателю' : 'Показать преподавателю',
          style: const TextStyle(fontSize: 10),
        ),
      ),
    );
  }
}
