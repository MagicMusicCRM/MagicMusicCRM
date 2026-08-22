import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/widgets/app_logo.dart';
import 'package:magic_music_crm/core/widgets/magic_shimmer.dart';
import 'package:magic_music_crm/features/auth/data/models/release_gate_models.dart';
import 'package:magic_music_crm/features/auth/presentation/widgets/auth_form_controls.dart';
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
  bool _showIncompleteError = false;

  Future<void> _accept(List<LegalDocument> documents) async {
    if (_acceptedIds.length != documents.length) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(releaseGateServiceProvider).acceptCurrentLegalDocuments();
      ref.invalidate(releaseGateStatusProvider);
      ref.invalidate(currentLegalDocumentsProvider);

      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось сохранить согласие. Повторите попытку.'),
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть документ')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(currentLegalDocumentsProvider);

    return Scaffold(
      backgroundColor: AppColor.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -1.0),
            radius: 1.1,
            colors: [Color(0x1AC5A059), AppColor.bg],
            stops: [0.0, 0.6],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.xxl,
                  vertical: 30,
                ),
                child: docsAsync.when(
                  loading: _buildLoading,
                  error: (_, _) => _buildError(),
                  data: _buildContent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrand() {
    return Column(
      children: [
        const AppLogo(size: 84),
        const SizedBox(height: AppSpace.xs),
        const Text(
          'Согласие с документами',
          style: TextStyle(color: AppColor.text2, fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBrand(),
        const SizedBox(height: AppSpace.xxl),
        for (var i = 0; i < 3; i++) ...[
          SkeletonBox(height: 56, radius: AppRadius.control),
          if (i < 2) const SizedBox(height: AppSpace.sm),
        ],
      ],
    );
  }

  Widget _buildError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBrand(),
        const SizedBox(height: AppSpace.xxl),
        const Text(
          'Не удалось загрузить документы. Проверьте подключение и повторите попытку.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColor.text2, fontSize: 12.5, height: 1.5),
        ),
        const SizedBox(height: AppSpace.lg),
        FilledButton.icon(
          onPressed: () => ref.invalidate(currentLegalDocumentsProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Повторить'),
        ),
        const SizedBox(height: AppSpace.sm),
        TextButton(
          onPressed: () => context.go('/login'),
          style: TextButton.styleFrom(
            foregroundColor: AppColor.gold,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            padding: const EdgeInsets.all(AppSpace.sm),
            minimumSize: const Size(0, 0),
          ),
          child: const Text('Назад ко входу'),
        ),
      ],
    );
  }

  Widget _buildContent(List<LegalDocument> documents) {
    final canAccept =
        documents.isNotEmpty && _acceptedIds.length == documents.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBrand(),
        const SizedBox(height: AppSpace.xxl),
        Text(
          widget.requireAcceptance
              ? 'Чтобы продолжить, подтвердите согласие с документами.'
              : 'Актуальные документы Magic Music.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColor.text2,
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        for (final doc in documents) ...[
          _ConsentRow(
            title: doc.title,
            accepted:
                !widget.requireAcceptance || _acceptedIds.contains(doc.id),
            showCheckbox: widget.requireAcceptance,
            onOpen: () => _openDocument(doc),
            onToggle: () {
              setState(() {
                if (_acceptedIds.contains(doc.id)) {
                  _acceptedIds.remove(doc.id);
                } else {
                  _acceptedIds.add(doc.id);
                }
                if (_acceptedIds.length == documents.length) {
                  _showIncompleteError = false;
                }
              });
            },
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (widget.requireAcceptance) ...[
          if (_showIncompleteError) ...[
            const SizedBox(height: AppSpace.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: AppSpace.sm,
              ),
              decoration: BoxDecoration(
                color: AppColor.dangerSoft,
                border: Border.all(color: const Color(0x52E53935)),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: const Text(
                'Отметьте все три документа, чтобы войти',
                style: TextStyle(color: Color(0xFFF4A3A1), fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          AuthPrimaryButton(
            label: 'Принять и войти',
            loading: _isSaving,
            onPressed: _isSaving
                ? null
                : () {
                    if (!canAccept) {
                      setState(() => _showIncompleteError = true);
                      return;
                    }
                    _accept(documents);
                  },
          ),
        ],
        const SizedBox(height: AppSpace.sm),
        TextButton(
          onPressed: () => context.go('/login'),
          style: TextButton.styleFrom(
            foregroundColor: AppColor.gold,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            padding: const EdgeInsets.all(AppSpace.sm),
            minimumSize: const Size(0, 0),
          ),
          child: const Text('Назад ко входу'),
        ),
      ],
    );
  }
}

/// v7 consent row (`.consent-row`): tappable row with a 22×22 check box, the
/// document label, and a trailing external-link affordance.
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.title,
    required this.accepted,
    required this.showCheckbox,
    required this.onOpen,
    required this.onToggle,
  });

  final String title;
  final bool accepted;
  final bool showCheckbox;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accepted ? const Color(0x0FC5A059) : AppColor.input,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: showCheckbox ? onToggle : null,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: accepted ? AppColor.goldLine : AppColor.divider,
            ),
          ),
          child: Row(
            children: [
              if (showCheckbox) ...[
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: accepted ? AppColor.gold : AppColor.surface,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: accepted ? Colors.transparent : AppColor.divider,
                      width: 1.5,
                    ),
                  ),
                  child: accepted
                      ? const Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: AppColor.onGold,
                        )
                      : null,
                ),
                const SizedBox(width: 11),
              ],
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColor.menuItemText,
                    ),
                    children: [
                      const TextSpan(text: 'Я принимаю '),
                      TextSpan(
                        text: title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColor.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              IconButton(
                tooltip: 'Открыть документ',
                onPressed: onOpen,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: AppColor.gold2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
