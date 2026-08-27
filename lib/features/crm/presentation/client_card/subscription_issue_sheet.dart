import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/forms/dirty_form_exit.dart';
import 'package:magic_music_crm/core/widgets/magic_sheet.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

import 'subscription_issue_components.dart';
import 'subscription_issue_controller.dart';
import 'subscription_issue_form_feedback.dart';
import 'subscription_issue_form_sections.dart';
import 'subscription_issue_models.dart';

export 'subscription_issue_controller.dart' show SubscriptionIssueController;
export 'subscription_issue_models.dart'
    show
        SubscriptionIdentityFactory,
        SubscriptionIssueDiscountMode,
        SubscriptionIssueDraft,
        SubscriptionIssuePreview,
        SubscriptionIssueSubmission,
        SubscriptionIssueSubmit,
        SubscriptionIssueSubmitResult;
export 'subscription_issue_pricing.dart' show SubscriptionIssuePricing;

Future<bool?> showSubscriptionIssueFormSheet(
  BuildContext context, {
  required Map<String, dynamic> package,
  required String recipientStudentId,
  required String recipientLabel,
  required Future<List<SearchableSelectItem>> Function(String query)
  searchPayers,
  required SubscriptionIssuePreview onPreview,
  required SubscriptionIssueSubmit onSubmit,
}) {
  return showMagicSheet<bool>(
    context,
    title: 'Условия абонемента',
    subtitle: package['name']?.toString() ?? 'Настройте выдачу',
    icon: Icons.receipt_long_rounded,
    builder: (_) => SubscriptionIssueForm(
      package: package,
      recipientStudentId: recipientStudentId,
      recipientLabel: recipientLabel,
      searchPayers: searchPayers,
      onPreview: onPreview,
      onSubmit: onSubmit,
    ),
  );
}

class SubscriptionIssueForm extends StatefulWidget {
  const SubscriptionIssueForm({
    super.key,
    required this.package,
    required this.recipientStudentId,
    required this.recipientLabel,
    required this.searchPayers,
    required this.onPreview,
    required this.onSubmit,
    this.commandTimestamp,
  });

  final Map<String, dynamic> package;
  final String recipientStudentId;
  final String recipientLabel;
  final Future<List<SearchableSelectItem>> Function(String query) searchPayers;
  final SubscriptionIssuePreview onPreview;
  final SubscriptionIssueSubmit onSubmit;

  /// Test seam; production commands use the instant at which the form opens.
  final DateTime? commandTimestamp;

  @override
  State<SubscriptionIssueForm> createState() => _SubscriptionIssueFormState();
}

class _SubscriptionIssueFormState extends State<SubscriptionIssueForm> {
  final _formKey = GlobalKey<FormState>();
  late final SubscriptionIssueController _controller;
  late final DirtyFormExitController _exitController;

  @override
  void initState() {
    super.initState();
    _controller = SubscriptionIssueController(
      package: widget.package,
      recipientStudentId: widget.recipientStudentId,
      recipientLabel: widget.recipientLabel,
      onPreview: widget.onPreview,
      onSubmit: widget.onSubmit,
      commandTimestamp: widget.commandTimestamp,
    )..addListener(_handleControllerChanged);
    _exitController = DirtyFormExitController(
      onSave: () => _submit(closeOnSuccess: false),
    );
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChanged)
      ..dispose();
    _exitController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _submit({bool closeOnSuccess = true}) async {
    if (_controller.busy) return false;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return false;
    _exitController.setBusy(true);
    try {
      final result = await _controller.submit();
      if (result != SubscriptionIssueSubmitResult.committed) return false;
      _exitController.markClean();
      if (closeOnSuccess && mounted) Navigator.pop(context, true);
      return true;
    } finally {
      _exitController.setBusy(false);
    }
  }

  void _requestClose() {
    _exitController.requestExit(
      context,
      reason: DirtyFormExitReason.appBack,
      savedResult: true,
      discardedResult: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _controller.draft;
    final pricing = _controller.pricing;
    return DirtyFormExitScope(
      controller: _exitController,
      savedResult: true,
      discardedResult: false,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        onChanged: _exitController.markDirty,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SubscriptionIssuePriceSummary(
              packageName: widget.package['name']?.toString() ?? 'Абонемент',
              basePriceMinor: pricing.basePriceMinor,
              discountMinor: pricing.discountMinor,
              surchargeMinor: pricing.surchargeMinor,
              finalPriceMinor: pricing.amountsValid
                  ? pricing.finalPriceMinor
                  : null,
              currencyCode: draft.currencyCode,
            ),
            SubscriptionIssueFormSections(
              controller: _controller,
              searchPayers: widget.searchPayers,
              onChanged: _exitController.markDirty,
            ),
            SubscriptionIssueFormFeedback(
              draft: draft,
              preview: _controller.preview,
              attempted: _controller.attempted,
              error: _controller.error,
              busy: _controller.busy,
              onClose: _requestClose,
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
