part of 'leads_widget.dart';

// Create/edit lead dialog.

class _LeadDialog extends StatefulWidget {
  // Pre-filled values let a failed create reopen the dialog without losing
  // what the manager already typed.
  const _LeadDialog({this.initial});

  final Map<String, String>? initial;

  @override
  State<_LeadDialog> createState() => _LeadDialogState();
}

class _LeadDialogState extends State<_LeadDialog> {
  late final _nameCtrl = TextEditingController(
    text: widget.initial?['name'] ?? '',
  );
  late String _canonicalPhone = widget.initial?['phone'] ?? '';
  late final _sourceCtrl = TextEditingController(
    text: widget.initial?['source'] ?? '',
  );

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('Новый лид'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          const SizedBox(height: 10),
          RuPhoneField(
            initialCanonical: _canonicalPhone.isEmpty ? null : _canonicalPhone,
            onCanonicalChanged: (c) => _canonicalPhone = c,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _sourceCtrl,
            decoration: const InputDecoration(
              labelText: 'Источник (ВКонтакте, сайт...)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (_nameCtrl.text.trim().isNotEmpty) {
              Navigator.pop(context, {
                'name': _nameCtrl.text.trim(),
                'phone': _canonicalPhone,
                'source': _sourceCtrl.text.trim(),
              });
            }
          },
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}
