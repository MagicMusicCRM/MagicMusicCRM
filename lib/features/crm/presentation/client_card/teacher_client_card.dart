import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'client_card_v4_api.dart';

class TeacherClientCard extends ConsumerStatefulWidget {
  const TeacherClientCard({
    super.key,
    required this.entityType,
    required this.entityId,
    this.routed = false,
    this.onClose,
  });

  final String entityType;
  final String entityId;
  final bool routed;
  final VoidCallback? onClose;

  @override
  ConsumerState<TeacherClientCard> createState() => _TeacherClientCardState();
}

class _TeacherClientCardState extends ConsumerState<TeacherClientCard> {
  Map<String, dynamic>? _card;
  Object? _error;
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final card = await ref
          .read(clientCardV4ApiProvider)
          .loadCard(entityType: widget.entityType, entityId: widget.entityId);
      if (!mounted) return;
      setState(() {
        _card = card;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = SizedBox(
      key: const ValueKey('teacher-client-card'),
      width: widget.routed ? double.infinity : 600,
      height: widget.routed ? double.infinity : 720,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _TeacherCardError(error: _error!, onRetry: _load)
          : _body(cs),
    );
    if (widget.routed) return body;
    return Dialog(clipBehavior: Clip.antiAlias, child: body);
  }

  Widget _body(ColorScheme cs) {
    final card = _card ?? const <String, dynamic>{};
    final header =
        card['header'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final lifecycle =
        card['lifecycle'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final sections =
        card['sections'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    const tabs = [
      (Icons.event_note_outlined, 'Занятия', 'lessons'),
      (Icons.assignment_outlined, 'Домашние задания', 'homework'),
      (Icons.forum_outlined, 'Комментарии', 'comments'),
    ];
    final selected = tabs[_tab];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppColor.goldSoft,
                child: Icon(Icons.person_outline, color: AppColor.gold),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      header['displayName']?.toString() ?? 'Клиент',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${header['status'] ?? '—'}'
                      '${header['branchName'] == null ? '' : ' · ${header['branchName']}'}',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: widget.routed ? 'Назад' : 'Закрыть карточку',
                onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
                icon: Icon(
                  widget.routed
                      ? Icons.arrow_back_rounded
                      : Icons.close_rounded,
                ),
              ),
            ],
          ),
        ),
        if (lifecycle['tombstone'] == true)
          const MaterialBanner(
            key: ValueKey('client-tombstone'),
            content: Text(
              'Карточка находится в архиве. Учебная история доступна только для чтения.',
            ),
            actions: [SizedBox.shrink()],
          ),
        const Divider(height: 1),
        SingleChildScrollView(
          key: const ValueKey('teacher-client-card-tabs'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Row(
            children: [
              for (var index = 0; index < tabs.length; index++) ...[
                if (index > 0) const SizedBox(width: AppSpace.xs),
                ChoiceChip(
                  selected: _tab == index,
                  avatar: Icon(tabs[index].$1, size: 16),
                  label: Text(tabs[index].$2),
                  onSelected: (_) => setState(() => _tab = index),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _TeacherSection(
            key: ValueKey('teacher-section-${selected.$3}'),
            name: selected.$2,
            raw: sections[selected.$3],
          ),
        ),
      ],
    );
  }
}

class _TeacherSection extends StatelessWidget {
  const _TeacherSection({super.key, required this.name, required this.raw});

  final String name;
  final Object? raw;

  @override
  Widget build(BuildContext context) {
    final section = raw is Map<String, dynamic>
        ? raw! as Map<String, dynamic>
        : const <String, dynamic>{};
    final items = (section['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    if (items.isEmpty) {
      return Center(child: Text('$name: пока пусто'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpace.md),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (_, index) {
        final item = items[index];
        final title =
            item['title'] ??
            item['body'] ??
            item['scheduledAt'] ??
            item['createdAt'] ??
            'Запись';
        final subtitle =
            item['status'] ?? item['lifecycleState'] ?? item['dueAt'];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('$title'),
          subtitle: subtitle == null ? null : Text('$subtitle'),
        );
      },
    );
  }
}

class _TeacherCardError extends StatelessWidget {
  const _TeacherCardError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Карточка недоступна: $error', textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}
