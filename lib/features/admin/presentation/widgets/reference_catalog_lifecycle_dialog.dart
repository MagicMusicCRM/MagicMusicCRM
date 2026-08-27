import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

import 'reference_catalog_lifecycle_content.dart';
import 'reference_catalog_lifecycle_controller.dart';

class ReferenceCatalogLifecycleDialog extends ConsumerStatefulWidget {
  const ReferenceCatalogLifecycleDialog({
    super.key,
    required this.entityType,
    required this.item,
  });

  final String entityType;
  final Map<String, dynamic> item;

  @override
  ConsumerState<ReferenceCatalogLifecycleDialog> createState() =>
      _ReferenceCatalogLifecycleDialogState();
}

class _ReferenceCatalogLifecycleDialogState
    extends ConsumerState<ReferenceCatalogLifecycleDialog> {
  final _name = TextEditingController();
  final _reason = TextEditingController();
  late final ReferenceCatalogLifecycleController _controller;
  String? _serverName;
  int _entitySyncRevision = 0;

  @override
  void initState() {
    super.initState();
    _serverName = widget.item['name']?.toString();
    _name.text = _serverName ?? '';
    _controller = ReferenceCatalogLifecycleController(
      service: ref.read(magicCrmServiceProvider),
      entityType: widget.entityType,
      initialItem: widget.item,
    )..addListener(_onControllerChanged);
    _controller.load();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final state = _controller.state;
    final serverName = state.entity['name']?.toString();
    if (serverName != null && state.entitySyncRevision != _entitySyncRevision) {
      _entitySyncRevision = state.entitySyncRevision;
      _serverName = serverName;
      _name.text = serverName;
    }
    setState(() {});
  }

  Future<void> _rename() async {
    final renamed = await _controller.rename(
      name: _name.text,
      reasonText: _reason.text,
    );
    if (renamed && mounted) _reason.clear();
  }

  Future<void> _commitLifecycle() async {
    final committed = await _controller.commitLifecycle(
      reasonText: _reason.text,
    );
    if (committed && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => ReferenceCatalogLifecycleContent(
    state: _controller.state,
    nameController: _name,
    reasonController: _reason,
    onRename: _rename,
    onCommit: _commitLifecycle,
    onClose: () => Navigator.pop(context),
  );
}
