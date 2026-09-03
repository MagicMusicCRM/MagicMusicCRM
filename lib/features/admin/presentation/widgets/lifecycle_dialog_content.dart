import 'package:flutter/material.dart';

class LifecycleDialogContent extends StatelessWidget {
  const LifecycleDialogContent({
    super.key,
    required this.title,
    required this.loading,
    required this.saving,
    required this.archived,
    required this.canCommit,
    required this.commitLabel,
    required this.reasonLabel,
    required this.reasonController,
    required this.effectiveDate,
    required this.onPickEffectiveDate,
    required this.history,
    required this.archivedHistoryLabel,
    required this.restoredHistoryLabel,
    required this.preservedFacts,
    required this.error,
    required this.onCommit,
    required this.details,
    this.width = 620,
  });

  final String title;
  final bool loading;
  final bool saving;
  final bool archived;
  final bool canCommit;
  final String commitLabel;
  final String reasonLabel;
  final TextEditingController reasonController;
  final String effectiveDate;
  final VoidCallback onPickEffectiveDate;
  final List<Map<String, dynamic>> history;
  final String archivedHistoryLabel;
  final String restoredHistoryLabel;
  final List<MapEntry<String, dynamic>> preservedFacts;
  final String? error;
  final VoidCallback onCommit;
  final List<Widget> details;
  final double width;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: width,
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...details,
                  if (preservedFacts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'История останется без изменений',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final fact in preservedFacts)
                          Chip(label: Text('${fact.key}: ${fact.value}')),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: saving ? null : onPickEffectiveDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text('Дата действия: $effectiveDate'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: reasonController,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: reasonLabel,
                      hintText: 'Причина останется в журнале изменений',
                    ),
                  ),
                  if (history.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('История (${history.length})'),
                      children: [
                        for (final item in history.take(10))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              item['toState'] == 'archived'
                                  ? Icons.archive_outlined
                                  : Icons.restore_rounded,
                            ),
                            title: Text(
                              item['toState'] == 'archived'
                                  ? archivedHistoryLabel
                                  : restoredHistoryLabel,
                            ),
                            subtitle: Text(
                              '${item['reasonText']?.toString() ?? 'Не указано'}'
                              '${item['effectiveDate'] == null ? '' : ' • ${item['effectiveDate']}'}',
                            ),
                          ),
                      ],
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton.icon(
        onPressed: saving || loading || !canCommit ? null : onCommit,
        icon: saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(archived ? Icons.restore_rounded : Icons.archive_outlined),
        label: Text(commitLabel),
      ),
    ],
  );
}
