part of 'crm_configuration_workspace.dart';

class _CrmConfigurationShell extends StatelessWidget {
  const _CrmConfigurationShell({
    required this.exitController,
    required this.loading,
    required this.busy,
    required this.error,
    required this.branches,
    required this.branchId,
    required this.isManager,
    required this.areas,
    required this.area,
    required this.selectedKey,
    required this.baseVersion,
    required this.dirty,
    required this.initialSchoolSetup,
    required this.canEdit,
    required this.canPublish,
    required this.listPane,
    required this.editorPane,
    required this.onRetry,
    required this.onScopeChanged,
    required this.onAreaChanged,
    required this.onSaveDraft,
    required this.onPublish,
  });

  final DirtyFormExitController exitController;
  final bool loading;
  final bool busy;
  final String? error;
  final List<Map<String, dynamic>> branches;
  final String? branchId;
  final bool isManager;
  final List<(String, String, IconData)> areas;
  final String area;
  final String? selectedKey;
  final int baseVersion;
  final bool dirty;
  final bool initialSchoolSetup;
  final bool canEdit;
  final bool canPublish;
  final Widget listPane;
  final Widget editorPane;
  final VoidCallback onRetry;
  final ValueChanged<String?> onScopeChanged;
  final ValueChanged<String> onAreaChanged;
  final Future<bool> Function() onSaveDraft;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return _CrmConfigurationError(error: error!, onRetry: onRetry);
    }
    return DirtyFormExitScope(
      controller: exitController,
      child: Column(
        children: [
          _CrmConfigurationToolbar(
            scopeSelector: _CrmConfigurationScopeSelector(
              branches: branches,
              branchId: branchId,
              isManager: isManager,
              busy: busy,
              onChanged: onScopeChanged,
            ),
            status: _CrmConfigurationDraftStatus(
              initialSchoolSetup: initialSchoolSetup,
              dirty: dirty,
              baseVersion: baseVersion,
            ),
            busy: busy,
            dirty: dirty,
            initialSchoolSetup: initialSchoolSetup,
            canEdit: canEdit,
            canPublish: canPublish,
            onSaveDraft: onSaveDraft,
            onPublish: onPublish,
          ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth >= 900 ? _desktop() : _compact(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktop() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 230, child: _areaList()),
        const VerticalDivider(width: 1),
        SizedBox(width: 360, child: listPane),
        const VerticalDivider(width: 1),
        Expanded(child: editorPane),
      ],
    );
  }

  Widget _compact() {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            children: [
              for (final item in areas)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.xs),
                  child: ChoiceChip(
                    label: Text(item.$2),
                    selected: area == item.$1,
                    onSelected: (_) => onAreaChanged(item.$1),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: selectedKey == null ? listPane : editorPane),
      ],
    );
  }

  Widget _areaList() {
    return ListView(
      padding: const EdgeInsets.all(AppSpace.sm),
      children: [
        for (final item in areas)
          ListTile(
            selected: area == item.$1,
            leading: Icon(item.$3),
            title: Text(item.$2),
            onTap: () => onAreaChanged(item.$1),
          ),
      ],
    );
  }
}

class _CrmConfigurationError extends StatelessWidget {
  const _CrmConfigurationError({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error, textAlign: TextAlign.center),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}

class _CrmConfigurationToolbar extends StatelessWidget {
  const _CrmConfigurationToolbar({
    required this.scopeSelector,
    required this.status,
    required this.busy,
    required this.dirty,
    required this.initialSchoolSetup,
    required this.canEdit,
    required this.canPublish,
    required this.onSaveDraft,
    required this.onPublish,
  });

  final Widget scopeSelector;
  final Widget status;
  final bool busy;
  final bool dirty;
  final bool initialSchoolSetup;
  final bool canEdit;
  final bool canPublish;
  final Future<bool> Function() onSaveDraft;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            scopeSelector,
            status,
            if (canEdit)
              OutlinedButton.icon(
                onPressed: busy || !dirty ? null : onSaveDraft,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Сохранить черновик'),
              ),
            if (canPublish)
              FilledButton.icon(
                key: const ValueKey('configuration-publish'),
                onPressed: busy || (!dirty && !initialSchoolSetup)
                    ? null
                    : onPublish,
                icon: const Icon(Icons.publish_rounded),
                label: const Text('Проверить и опубликовать'),
              ),
          ],
        ),
      ),
    );
  }
}

class _CrmConfigurationScopeSelector extends StatelessWidget {
  const _CrmConfigurationScopeSelector({
    required this.branches,
    required this.branchId,
    required this.isManager,
    required this.busy,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> branches;
  final String? branchId;
  final bool isManager;
  final bool busy;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 270,
      child: DropdownButtonFormField<String?>(
        menuMaxHeight: 256,
        key: const ValueKey('configuration-scope'),
        initialValue: branchId,
        decoration: const InputDecoration(labelText: 'Область действия'),
        items: [
          if (!isManager)
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Вся школа'),
            ),
          ...branches.map(
            (branch) => DropdownMenuItem<String?>(
              value: branch['id']?.toString(),
              child: Text(branch['name']?.toString() ?? 'Филиал'),
            ),
          ),
        ],
        onChanged: busy ? null : onChanged,
      ),
    );
  }
}

class _CrmConfigurationDraftStatus extends StatelessWidget {
  const _CrmConfigurationDraftStatus({
    required this.initialSchoolSetup,
    required this.dirty,
    required this.baseVersion,
  });

  final bool initialSchoolSetup;
  final bool dirty;
  final int baseVersion;

  (IconData, String) get _status {
    if (initialSchoolSetup) {
      return (Icons.rocket_launch_outlined, 'Начальная настройка');
    }
    if (dirty) return (Icons.edit_note_rounded, 'Черновик');
    return (Icons.verified_outlined, 'Опубликовано');
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Chip(
      avatar: Icon(status.$1, size: 18),
      label: Text('${status.$2} · версия $baseVersion'),
    );
  }
}

class _CrmConfigurationListPane extends StatelessWidget {
  const _CrmConfigurationListPane({
    required this.title,
    this.addLabel,
    this.onAdd,
    required this.children,
  });

  final String title;
  final String? addLabel;
  final VoidCallback? onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (addLabel != null)
                IconButton(
                  tooltip: addLabel,
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                ),
            ],
          ),
        ),
        Expanded(
          child: children.isEmpty
              ? const Center(child: Text('Пока нет элементов'))
              : ListView(children: children),
        ),
      ],
    );
  }
}

class _CrmConfigurationProperty extends StatelessWidget {
  const _CrmConfigurationProperty({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(color: AppColor.text2)),
          ),
          Expanded(child: Text(value?.toString() ?? 'Не указано')),
        ],
      ),
    );
  }
}

class _CrmConfigurationHistoryList extends StatelessWidget {
  const _CrmConfigurationHistoryList({
    required this.revisions,
    required this.canPublish,
    required this.onRollback,
  });

  final List<Map<String, dynamic>> revisions;
  final bool canPublish;
  final ValueChanged<Map<String, dynamic>> onRollback;

  @override
  Widget build(BuildContext context) {
    final currentVersion = revisions.firstOrNull?['version'];
    return _CrmConfigurationListPane(
      title: 'Неизменяемые версии',
      children: revisions
          .map(
            (revision) => ListTile(
              title: Text('Версия ${revision['version']}'),
              subtitle: Text(revision['reason']?.toString() ?? ''),
              trailing: canPublish && revision['version'] != currentVersion
                  ? IconButton(
                      tooltip: 'Опубликовать откат к этой версии',
                      onPressed: () => onRollback(revision),
                      icon: const Icon(Icons.restore_rounded),
                    )
                  : null,
            ),
          )
          .toList(),
    );
  }
}

class _CrmFunnelEntry extends StatelessWidget {
  const _CrmFunnelEntry({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.view_kanban_outlined),
          label: const Text('Настроить воронки лидов и учеников'),
        ),
      ),
    );
  }
}

class _CrmConfigurationImpactContent extends StatelessWidget {
  const _CrmConfigurationImpactContent({
    required this.impact,
    required this.valid,
    required this.changes,
    required this.screens,
    required this.onReasonChanged,
  });

  final Map<String, dynamic> impact;
  final bool valid;
  final Map<dynamic, dynamic> changes;
  final String screens;
  final ValueChanged<String> onReasonChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Новых полей: ${changes['fieldsCreated'] ?? 0} · '
              'изменено: ${changes['fieldsUpdated'] ?? 0} · '
              'архивировано: ${changes['fieldsArchived'] ?? 0}',
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Типов списания изменено: '
              '${changes['settlementTypesChanged'] ?? 0} · '
              'типов оплаты преподавателю: '
              '${changes['compensationRulesChanged'] ?? 0}',
            ),
            const SizedBox(height: AppSpace.sm),
            Text('Затронутые экраны: ${screens.isEmpty ? 'нет' : screens}'),
            for (final warning in (impact['warnings'] as List? ?? const []))
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Text('• $warning'),
              ),
            for (final issue in (impact['blockingIssues'] as List? ?? const []))
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Text(
                  '• ${(issue as Map)['message']}',
                  style: const TextStyle(color: AppColor.danger),
                ),
              ),
            if (valid) ...[
              const SizedBox(height: AppSpace.md),
              TextField(
                onChanged: onReasonChanged,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Причина публикации *',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<String?> _showCrmConfigurationImpactDialog(
  BuildContext context,
  Map<String, dynamic> impact,
) async {
  var reason = '';
  final valid = impact['valid'] == true;
  final changes = impact['changes'] as Map? ?? const {};
  final screens = (impact['affectedScreens'] as List? ?? const []).join(', ');
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        valid ? 'Предпросмотр публикации' : 'Публикация заблокирована',
      ),
      content: _CrmConfigurationImpactContent(
        impact: impact,
        valid: valid,
        changes: changes,
        screens: screens,
        onReasonChanged: (value) => reason = value,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
        if (valid)
          FilledButton(
            onPressed: () {
              final value = reason.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Опубликовать'),
          ),
      ],
    ),
  );
}

Future<String?> _askCrmConfigurationReason(
  BuildContext context,
  String title,
) async {
  var reason = '';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        onChanged: (value) => reason = value,
        decoration: const InputDecoration(labelText: 'Причина *'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (reason.trim().isNotEmpty) {
              Navigator.pop(context, reason.trim());
            }
          },
          child: const Text('Продолжить'),
        ),
      ],
    ),
  );
}
