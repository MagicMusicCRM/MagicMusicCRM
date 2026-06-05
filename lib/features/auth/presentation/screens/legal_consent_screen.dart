import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/features/auth/data/services/supa_release_gate_service.dart';
import 'package:magic_music_crm/features/auth/providers/release_gate_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class LegalConsentScreen extends ConsumerStatefulWidget {
  final bool requireAcceptance;

  const LegalConsentScreen({super.key, this.requireAcceptance = true});

  @override
  ConsumerState<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends ConsumerState<LegalConsentScreen> {
  final Set<String> _acceptedIds = {};
  bool _isSaving = false;

  Future<void> _accept(List<LegalDocument> documents) async {
    if (_acceptedIds.length != documents.length) return;

    setState(() => _isSaving = true);
    try {
      await ref
          .read(supaReleaseGateServiceProvider)
          .acceptCurrentLegalDocuments();
      ref.invalidate(releaseGateStatusProvider);
      ref.invalidate(currentLegalDocumentsProvider);

      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось сохранить согласие: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openDocument(LegalDocument document) async {
    final publicUrl = document.publicUrl;
    if (publicUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Для документа не задана публичная ссылка'),
        ),
      );
      return;
    }

    try {
      final opened = await launchUrl(
        Uri.parse(publicUrl),
        mode: LaunchMode.inAppBrowserView,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть документ')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть документ: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(currentLegalDocumentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Юридические документы')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: docsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Не удалось загрузить документы: $error'),
            ),
            data: (documents) {
              final canAccept =
                  documents.isNotEmpty &&
                  _acceptedIds.length == documents.length;

              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    widget.requireAcceptance
                        ? 'Перед использованием приложения необходимо принять актуальные документы.'
                        : 'Актуальные документы MagicMusicCRM.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  for (final doc in documents) ...[
                    _LegalDocumentTile(
                      document: doc,
                      accepted:
                          !widget.requireAcceptance ||
                          _acceptedIds.contains(doc.id),
                      showCheckbox: widget.requireAcceptance,
                      onOpen: () => _openDocument(doc),
                      onChanged: (value) {
                        setState(() {
                          if (value) {
                            _acceptedIds.add(doc.id);
                          } else {
                            _acceptedIds.remove(doc.id);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 16),
                  if (widget.requireAcceptance)
                    FilledButton.icon(
                      onPressed: canAccept && !_isSaving
                          ? () => _accept(documents)
                          : null,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_user_outlined),
                      label: const Text('Принять и продолжить'),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LegalDocumentTile extends StatelessWidget {
  final LegalDocument document;
  final bool accepted;
  final bool showCheckbox;
  final VoidCallback onOpen;
  final ValueChanged<bool> onChanged;

  const _LegalDocumentTile({
    required this.document,
    required this.accepted,
    this.showCheckbox = true,
    required this.onOpen,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          ExpansionTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(document.title),
            subtitle: Text('Версия ${document.version}'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(document.content),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_browser_outlined),
                  label: const Text('Открыть опубликованную версию'),
                ),
              ),
            ],
          ),
          if (showCheckbox)
            CheckboxListTile(
              value: accepted,
              onChanged: (value) => onChanged(value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Я принимаю документ'),
            ),
        ],
      ),
    );
  }
}
