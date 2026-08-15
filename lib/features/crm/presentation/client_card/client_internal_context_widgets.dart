import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/client_internal_context.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/v7/v7.dart';

class ClientInternalNoteCard extends StatefulWidget {
  const ClientInternalNoteCard({
    super.key,
    required this.loading,
    required this.note,
    required this.onSave,
    required this.onRetry,
    this.error,
  });

  final bool loading;
  final String? error;
  final ClientInternalNote? note;
  final Future<ClientInternalNote> Function(String body, int expectedVersion)
  onSave;
  final VoidCallback onRetry;

  @override
  State<ClientInternalNoteCard> createState() => _ClientInternalNoteCardState();
}

class _ClientInternalNoteCardState extends State<ClientInternalNoteCard> {
  late final TextEditingController _controller;
  bool _dirty = false;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note?.body ?? '');
  }

  @override
  void didUpdateWidget(covariant ClientInternalNoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && oldWidget.note?.version != widget.note?.version) {
      _controller.text = widget.note?.body ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final note = await widget.onSave(
        _controller.text,
        widget.note?.version ?? 0,
      );
      if (!mounted) return;
      _controller.text = note.body;
      setState(() => _dirty = false);
    } catch (error) {
      if (mounted) {
        setState(
          () => _saveError = userErrorMessage(
            error,
            fallback: 'Не удалось сохранить заметку.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.loading && widget.note == null) {
      return const SkeletonBox(height: 120);
    }
    if (widget.error != null && widget.note == null) {
      return MagicPageState(
        kind: MagicPageStateKind.error,
        title: 'Не удалось загрузить заметку',
        message: widget.error!,
        actionLabel: 'Повторить',
        onAction: widget.onRetry,
      );
    }
    final note = widget.note;
    return Container(
      key: const Key('client-internal-note'),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.sticky_note_2_outlined, color: AppColor.gold),
              SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  'Заметка о клиенте',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          TextField(
            key: const Key('client-internal-note-input'),
            controller: _controller,
            minLines: 2,
            maxLines: 5,
            maxLength: 20000,
            enabled: !_saving,
            decoration: const InputDecoration(
              hintText: 'Общий контекст для администраторов и руководителей',
              alignLabelWithHint: true,
            ),
            onChanged: (_) {
              if (!_dirty) setState(() => _dirty = true);
            },
          ),
          if (_saveError != null) ...[
            Text(
              'Не удалось сохранить: $_saveError',
              style: TextStyle(color: cs.error, fontSize: 12),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              if (note?.updatedAt != null)
                Text(
                  '${note?.updatedByName?.trim().isNotEmpty == true ? note!.updatedByName : 'Вы'} · '
                  '${DateFormat('dd.MM.yyyy HH:mm').format(note!.updatedAt!.toLocal())}',
                  style: const TextStyle(color: AppColor.text2, fontSize: 12),
                )
              else
                const Text(
                  'Заметка пока не заполнена',
                  style: TextStyle(color: AppColor.text2, fontSize: 12),
                ),
              FilledButton.icon(
                key: const Key('client-internal-note-save'),
                onPressed: _dirty && !_saving ? _save : null,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Сохранить заметку'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ClientOperationalHistoryView extends StatelessWidget {
  const ClientOperationalHistoryView({
    super.key,
    required this.loading,
    required this.loadingMore,
    required this.items,
    required this.hasMore,
    required this.onRetry,
    required this.onLoadMore,
    this.error,
  });

  final bool loading;
  final bool loadingMore;
  final String? error;
  final List<ClientOperationalHistoryItem> items;
  final bool hasMore;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) return const SkeletonBox(height: 160);
    if (error != null && items.isEmpty) {
      return MagicPageState(
        kind: MagicPageStateKind.error,
        title: 'Не удалось загрузить историю действий',
        message: error!,
        actionLabel: 'Повторить',
        onAction: onRetry,
      );
    }
    return Column(
      key: const Key('client-operational-history'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'История действий сотрудников',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: AppSpace.sm),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
            child: Text(
              'Зафиксированных действий пока нет',
              style: TextStyle(color: AppColor.text2),
            ),
          )
        else
          for (final item in items) _OperationalHistoryRow(item: item),
        if (hasMore)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('client-operational-history-more'),
              onPressed: loadingMore ? null : onLoadMore,
              icon: loadingMore
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: const Text('Показать ещё'),
            ),
          ),
      ],
    );
  }
}

class _OperationalHistoryRow extends StatelessWidget {
  const _OperationalHistoryRow({required this.item});

  final ClientOperationalHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.history_rounded, size: 18, color: AppColor.gold),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.action,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpace.xs),
                Text('Причина: ${item.reason}'),
                if (item.summary?.trim().isNotEmpty == true)
                  Text(
                    item.summary!,
                    style: const TextStyle(color: AppColor.text2),
                  ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '${item.actorName} · '
                  '${DateFormat('dd.MM.yyyy HH:mm').format(item.occurredAt.toLocal())}',
                  style: const TextStyle(color: AppColor.text2, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
