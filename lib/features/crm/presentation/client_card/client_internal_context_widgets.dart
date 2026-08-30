import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/models/client_internal_context.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/navigation/context_transition_registry.dart';
import 'package:magic_music_crm/core/navigation/entity_link_navigator.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';
import 'package:magic_music_crm/core/widgets/magic_shimmer.dart';
import 'package:magic_music_crm/shared/widgets/audit_event_card.dart';

typedef ClientInternalNoteFlush = Future<bool> Function();

class ClientInternalNoteDraft {
  const ClientInternalNoteDraft({
    required this.body,
    required this.expectedVersion,
  });

  final String body;
  final int expectedVersion;

  Map<String, Object?> toJson() => {
    'body': body,
    'expectedVersion': expectedVersion,
  };

  static ClientInternalNoteDraft? fromJson(Object? value) {
    if (value is! Map) return null;
    final body = value['body'];
    final rawVersion = value['expectedVersion'];
    final version = rawVersion is num
        ? rawVersion.toInt()
        : int.tryParse(rawVersion?.toString() ?? '');
    if (body is! String || version == null || version < 0) return null;
    return ClientInternalNoteDraft(body: body, expectedVersion: version);
  }
}

class ClientInternalNoteCard extends StatefulWidget {
  const ClientInternalNoteCard({
    super.key,
    required this.loading,
    required this.note,
    required this.onSave,
    required this.onReload,
    required this.onRetry,
    required this.onPendingChanged,
    required this.onFlushChanged,
    required this.onDraftChanged,
    this.initialDraft,
    this.error,
  });

  final bool loading;
  final String? error;
  final ClientInternalNote? note;
  final Future<ClientInternalNote> Function(String body, int expectedVersion)
  onSave;
  final Future<ClientInternalNote> Function() onReload;
  final VoidCallback onRetry;
  final ValueChanged<bool> onPendingChanged;
  final ValueChanged<ClientInternalNoteFlush?> onFlushChanged;
  final ValueChanged<ClientInternalNoteDraft?> onDraftChanged;
  final ClientInternalNoteDraft? initialDraft;

  @override
  State<ClientInternalNoteCard> createState() => _ClientInternalNoteCardState();
}

class _ClientInternalNoteCardState extends State<ClientInternalNoteCard> {
  static const _autoSaveDelay = Duration(milliseconds: 800);

  late final TextEditingController _controller;
  Timer? _autoSaveTimer;
  Future<bool>? _saveInFlight;
  bool _dirty = false;
  bool _saving = false;
  bool _saveQueued = false;
  int _editRevision = 0;
  late int _version;
  String? _saveError;
  bool _conflict = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _controller = TextEditingController(
      text: draft?.body ?? widget.note?.body ?? '',
    );
    _version = draft?.expectedVersion ?? widget.note?.version ?? 0;
    _dirty = draft != null;
    widget.onFlushChanged(_flush);
    if (_dirty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleSave();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ClientInternalNoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incomingDraft = widget.initialDraft;
    if (!_dirty &&
        incomingDraft != null &&
        incomingDraft != oldWidget.initialDraft) {
      _version = incomingDraft.expectedVersion;
      _controller.text = incomingDraft.body;
      _dirty = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleSave();
      });
      return;
    }
    if (!_dirty && oldWidget.note?.version != widget.note?.version) {
      _version = widget.note?.version ?? _version;
      _controller.text = widget.note?.body ?? '';
    }
  }

  @override
  void dispose() {
    widget.onFlushChanged(null);
    _autoSaveTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, () {
      _autoSaveTimer = null;
      unawaited(_save());
    });
    _notifyPending();
  }

  void _notifyPending() {
    widget.onPendingChanged(
      _dirty || _saving || _autoSaveTimer != null || _saveInFlight != null,
    );
  }

  Future<bool> _save() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    if (!_dirty) {
      _notifyPending();
      return Future<bool>.value(true);
    }
    if (_conflict) {
      _notifyPending();
      return Future<bool>.value(false);
    }
    final active = _saveInFlight;
    if (active != null) {
      _saveQueued = true;
      _notifyPending();
      return active;
    }
    late final Future<bool> save;
    save = _performSave();
    _saveInFlight = save;
    unawaited(
      save.then((saved) {
        if (!mounted) return;
        if (identical(_saveInFlight, save)) _saveInFlight = null;
        final queued = _saveQueued;
        _saveQueued = false;
        _notifyPending();
        if (saved && queued && _dirty) unawaited(_save());
      }),
    );
    return save;
  }

  Future<bool> _performSave() async {
    final revision = _editRevision;
    final body = _controller.text;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    _notifyPending();
    try {
      final note = await widget.onSave(body, _version);
      if (!mounted) return false;
      _version = note.version;
      setState(() {
        _conflict = false;
        if (revision == _editRevision) {
          _controller.text = note.body;
          _dirty = false;
          widget.onDraftChanged(null);
        } else {
          _saveQueued = true;
        }
      });
      return true;
    } catch (error) {
      if (mounted) {
        if (error is MagicApiException && error.statusCode == 409) {
          try {
            final latest = await widget.onReload();
            if (mounted) _version = latest.version;
          } catch (_) {
            // Keep the local draft and stale version. A later retry will either
            // refresh successfully or receive another safe 409.
          }
          if (mounted) {
            setState(() {
              _conflict = true;
              _saveError =
                  'Заметку изменил другой сотрудник. Ваш текст сохранён здесь; нажмите «Повторить», чтобы применить его явно.';
            });
          }
        } else {
          setState(
            () => _saveError = userErrorMessage(
              error,
              fallback: 'Не удалось сохранить заметку.',
            ),
          );
        }
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _notifyPending();
      }
    }
  }

  Future<bool> _flush() async {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    if (_conflict) return false;
    while (mounted && _dirty) {
      final save = _saveInFlight ?? _save();
      if (!await save) return false;
      if (identical(_saveInFlight, save)) _saveInFlight = null;
    }
    _notifyPending();
    return mounted && !_dirty;
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
            decoration: const InputDecoration(
              hintText: 'Общий контекст для администраторов и руководителей',
              alignLabelWithHint: true,
            ),
            onChanged: (_) {
              setState(() {
                _dirty = true;
                _editRevision++;
                if (!_conflict) _saveError = null;
              });
              widget.onDraftChanged(
                ClientInternalNoteDraft(
                  body: _controller.text,
                  expectedVersion: _version,
                ),
              );
              if (_conflict) {
                _notifyPending();
              } else {
                _scheduleSave();
              }
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
              if (_saveError != null)
                FilledButton.icon(
                  key: const Key('client-internal-note-retry'),
                  onPressed: _saving
                      ? null
                      : () {
                          setState(() => _conflict = false);
                          unawaited(_save());
                        },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Повторить'),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _dirty || _saving
                          ? Icons.sync_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 17,
                      color: _dirty || _saving
                          ? cs.onSurfaceVariant
                          : AppColor.success,
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Text(
                      _dirty || _saving ? 'Сохраняем…' : 'Сохранено',
                      style: TextStyle(
                        color: _dirty || _saving
                            ? cs.onSurfaceVariant
                            : AppColor.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ClientOperationalHistoryView extends ConsumerWidget {
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
  final List<AuditPresentationEvent> items;
  final bool hasMore;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          for (final item in items) ...[
            _clientAuditCard(context, ref, item),
            const SizedBox(height: AppSpace.sm),
          ],
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

Widget _clientAuditCard(
  BuildContext context,
  WidgetRef ref,
  AuditPresentationEvent event,
) {
  final transition = _clientAuditTransition(event);
  return AuditEventCard(
    key: ValueKey(event.id),
    event: event,
    onOpenTarget: transition == null
        ? null
        : () => unawaited(_openClientAuditTarget(context, ref, transition)),
  );
}

ContextTransition? _clientAuditTransition(AuditPresentationEvent event) {
  final id = event.target.id?.trim();
  final routeType = event.target.routeType?.trim();
  if (id == null || id.isEmpty || routeType == null || routeType.isEmpty) {
    return null;
  }
  try {
    return const ContextTransitionRegistry().create(
      source: ContextSourceType.audit,
      target: ContextTargetType.changedEntity,
      entityId: id,
      sourceState: ContextViewState(filters: const {'section': 'history'}),
      rawEntityType: routeType,
    );
  } on FormatException {
    return null;
  } on StateError {
    return null;
  }
}

Future<void> _openClientAuditTarget(
  BuildContext context,
  WidgetRef ref,
  ContextTransition transition,
) async {
  try {
    await openEntityLink(
      context,
      ref,
      transition.target,
      sourceViewState: transition.sourceState,
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userErrorMessage(error, fallback: 'Не удалось открыть запись.'),
        ),
      ),
    );
  }
}
