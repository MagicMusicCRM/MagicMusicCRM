import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/models/subscription_purchase.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';

import 'client_card_ui.dart';
import 'subscription_issue_components.dart';
import 'subscription_issue_models.dart';

class SubscriptionIssueFormFeedback extends StatelessWidget {
  const SubscriptionIssueFormFeedback({
    super.key,
    required this.draft,
    required this.preview,
    required this.attempted,
    required this.error,
    required this.busy,
    required this.packageUnits,
    required this.onClose,
    required this.onSubmit,
  });

  final SubscriptionIssueDraft draft;
  final SubscriptionPurchasePreview? preview;
  final bool attempted;
  final String? error;
  final bool busy;
  final SubscriptionUnitAmount packageUnits;
  final VoidCallback onClose;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview != null) ...[
          const SizedBox(height: AppSpace.md),
          SubscriptionIssuePurchasePreviewCard(
            preview: preview!,
            recipientLabel: draft.recipientLabel,
            payerLabel: draft.payerLabel,
            packageUnits: packageUnits,
          ),
        ],
        if (attempted) ...[
          const SizedBox(height: AppSpace.md),
          const SubscriptionIssueRetryNotice(),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpace.md),
          SubscriptionIssueInlineError(error: error!),
        ],
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xl),
          child: Row(
            children: [
              Expanded(
                child: clientCardGhostButton('Отмена', busy ? null : onClose),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: FilledButton(
                  key: const Key('subscription-issue-submit'),
                  onPressed: busy ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColor.gold,
                    foregroundColor: AppColor.onGold,
                    disabledBackgroundColor: AppColor.goldSoft,
                    disabledForegroundColor: AppColor.text2,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColor.onGold,
                          ),
                        )
                      : Text(_submitLabel()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _submitLabel() {
    if (attempted) return 'Повторить';
    return 'Оплатить';
  }
}
