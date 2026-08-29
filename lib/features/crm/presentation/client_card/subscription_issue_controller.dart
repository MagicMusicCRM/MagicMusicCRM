import 'package:flutter/foundation.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

import 'subscription_issue_models.dart';
import 'subscription_issue_pricing.dart';

class SubscriptionIssueController extends ChangeNotifier {
  SubscriptionIssueController({
    required Map<String, dynamic> package,
    required String recipientStudentId,
    required String recipientLabel,
    required SubscriptionIssuePreview onPreview,
    required SubscriptionIssueSubmit onSubmit,
    DateTime? commandTimestamp,
    SubscriptionIdentityFactory? identityFactory,
  }) : _onPreview = onPreview,
       _onSubmit = onSubmit,
       _identityFactory = identityFactory ?? _createIdentity {
    _package = package;
    _basePriceMinor = subscriptionPackageBasePriceMinor(package);
    _commandTimestamp = commandTimestamp ?? DateTime.now();
    _draft = SubscriptionIssueDraft.fromPackage(
      package: package,
      recipientStudentId: recipientStudentId,
      recipientLabel: recipientLabel,
      commandTimestamp: _commandTimestamp,
    );
    _identity = _identityFactory();
  }

  static MagicMutationIdentity _createIdentity() =>
      MagicMutationIdentity.create('subscription-purchase');

  late Map<String, dynamic> _package;
  late BigInt _basePriceMinor;
  late DateTime _commandTimestamp;
  final SubscriptionIssuePreview _onPreview;
  final SubscriptionIssueSubmit _onSubmit;
  final SubscriptionIdentityFactory _identityFactory;

  late SubscriptionIssueDraft _draft;
  late MagicMutationIdentity _identity;
  SubscriptionPurchasePreview? _preview;
  PurchaseSubscriptionInput? _frozenPurchase;
  bool _busy = false;
  bool _attempted = false;
  bool _disposed = false;
  int _draftGeneration = 0;
  int _previewRequestSequence = 0;
  int? _activePreviewRequest;
  String? _error;

  SubscriptionIssueDraft get draft => _draft;
  SubscriptionIssuePricing get pricing => SubscriptionIssuePricing.calculate(
    draft: _draft,
    basePriceMinor: _basePriceMinor,
    commandTimestamp: _draft.paymentOccurredAt,
  );
  SubscriptionPurchasePreview? get preview => _preview;
  MagicMutationIdentity get identity => _identity;
  bool get busy => _busy;
  bool get attempted => _attempted;
  bool get fieldsEnabled => !_attempted;
  String? get error => _error;

  void selectPayer(SearchableSelectItem item) {
    _updateDraft(
      _draft.copyWith(payerStudentId: item.id, payerLabel: item.label),
    );
  }

  void selectFundingMode(SubscriptionFundingMode mode) {
    _updateDraft(
      _draft.copyWith(
        fundingMode: mode,
        paymentAmount:
            mode == SubscriptionFundingMode.installment &&
                _draft.paymentAmount.isEmpty
            ? '0'
            : _draft.paymentAmount,
      ),
    );
  }

  void selectPaymentMethod(SubscriptionPaymentMethod method) {
    _updateDraft(_draft.copyWith(paymentMethod: method));
  }

  void selectDiscountMode(SubscriptionIssueDiscountMode mode) {
    if (!fieldsEnabled || _draft.discountMode == mode) return;
    _updateDraft(_draft.copyWith(discountMode: mode, discountValue: ''));
  }

  void setDiscountValue(String value) {
    _updateDraft(_draft.copyWith(discountValue: value));
  }

  void setDiscountReason(String value) {
    _updateDraft(_draft.copyWith(discountReason: value));
  }

  void setSurchargeEnabled(bool value) {
    _updateDraft(_draft.copyWith(surchargeEnabled: value));
  }

  void setSurchargeAmount(String value) {
    _updateDraft(_draft.copyWith(surchargeAmount: value));
  }

  void setSurchargeReason(String value) {
    _updateDraft(_draft.copyWith(surchargeReason: value));
  }

  void setPurchaseReason(String value) {
    _updateDraft(_draft.copyWith(purchaseReason: value));
  }

  void setInstallmentCount(int value) {
    _updateDraft(_draft.copyWith(installmentCount: value));
  }

  String? validateDiscountValue(String? _) =>
      SubscriptionIssuePricing.validateDiscountValue(_draft, _basePriceMinor);
  String? validateDiscountReason(String? _) =>
      SubscriptionIssuePricing.validateDiscountReason(_draft);
  String? validateSurchargeAmount(String? _) =>
      SubscriptionIssuePricing.validateSurchargeAmount(_draft);
  String? validateSurchargeReason(String? _) =>
      SubscriptionIssuePricing.validateSurchargeReason(_draft);
  String? validatePurchaseReason(String? _) =>
      SubscriptionIssuePricing.validatePurchaseReason(_draft);
  PurchaseSubscriptionInput buildPurchase() {
    if (_frozenPurchase != null) return _frozenPurchase!;
    final currentPricing = pricing;
    if (!currentPricing.isValid) {
      throw StateError(currentPricing.error!);
    }
    SubscriptionDiscountInput? discount;
    switch (_draft.discountMode) {
      case SubscriptionIssueDiscountMode.none:
        break;
      case SubscriptionIssueDiscountMode.percent:
        discount = SubscriptionDiscountInput.percent(
          basisPoints: currentPricing.discountBasisPoints!,
          reason: _draft.discountReason,
        );
        break;
      case SubscriptionIssueDiscountMode.fixed:
        discount = SubscriptionDiscountInput.fixed(
          fixedMinor: currentPricing.discountMinor,
          reason: _draft.discountReason,
        );
        break;
    }
    final paymentAmountMinor = _draft.paymentAmount.trim().isEmpty
        ? currentPricing.finalPriceMinor
        : parseSubscriptionMoneyMinor(_draft.paymentAmount)!;
    return PurchaseSubscriptionInput(
      payerStudentId: _draft.payerStudentId,
      fundingMode: _draft.fundingMode,
      startsAt: _draft.startsAt,
      expiresAt: _draft.expiresAt,
      paymentAmountMinor: paymentAmountMinor,
      paymentOccurredAt: paymentAmountMinor == BigInt.zero
          ? null
          : _draft.paymentOccurredAt,
      paymentComment: _draft.paymentComment,
      purchaseReason: _draft.purchaseReason,
      issue: IssueSubscriptionInput(
        packageId: _draft.packageId,
        paymentMethod: paymentAmountMinor == BigInt.zero
            ? null
            : _draft.paymentMethod,
        discount: discount,
        installments: currentPricing.installments,
        surcharge: _draft.surchargeEnabled
            ? SubscriptionSurchargeInput(
                amountMinor: currentPricing.surchargeMinor,
                reason: _draft.surchargeReason,
              )
            : null,
      ),
    );
  }

  Future<SubscriptionIssueSubmitResult> submit() async {
    if (_disposed || _busy) return SubscriptionIssueSubmitResult.blocked;
    final currentPricing = pricing;
    if (!currentPricing.isValid) {
      _error = currentPricing.error;
      _notifyListeners();
      return SubscriptionIssueSubmitResult.blocked;
    }
    final purchase = buildPurchase();
    _busy = true;
    _error = null;
    _notifyListeners();
    final currentPreview = _preview;
    if (currentPreview == null) return _loadPreview(purchase);
    try {
      if (!currentPreview.canCommit) {
        _busy = false;
        _error = 'На личном счёте недостаточно средств.';
        _notifyListeners();
        return SubscriptionIssueSubmitResult.blocked;
      }
      _attempted = true;
      _frozenPurchase = purchase;
      _notifyListeners();
      await _onSubmit(
        SubscriptionIssueSubmission(
          purchase: purchase,
          preview: currentPreview,
          identity: _identity,
        ),
      );
      _busy = false;
      _notifyListeners();
      return SubscriptionIssueSubmitResult.committed;
    } catch (caught) {
      _busy = false;
      _error = userErrorMessage(
        caught,
        fallback: 'Не удалось оформить абонемент.',
      );
      _notifyListeners();
      return SubscriptionIssueSubmitResult.failed;
    }
  }

  Future<SubscriptionIssueSubmitResult> _loadPreview(
    PurchaseSubscriptionInput purchase,
  ) async {
    final requestId = ++_previewRequestSequence;
    final generation = _draftGeneration;
    final identity = _identity;
    _activePreviewRequest = requestId;
    try {
      final preview = await _onPreview(purchase);
      if (!_isCurrentPreviewRequest(requestId, generation, identity)) {
        return SubscriptionIssueSubmitResult.blocked;
      }
      _activePreviewRequest = null;
      _preview = preview;
      _busy = false;
      _notifyListeners();
      return SubscriptionIssueSubmitResult.previewLoaded;
    } catch (caught) {
      if (!_isCurrentPreviewRequest(requestId, generation, identity)) {
        return SubscriptionIssueSubmitResult.blocked;
      }
      _activePreviewRequest = null;
      _busy = false;
      _error = userErrorMessage(
        caught,
        fallback: 'Не удалось оформить абонемент.',
      );
      _notifyListeners();
      return SubscriptionIssueSubmitResult.failed;
    }
  }

  bool _isCurrentPreviewRequest(
    int requestId,
    int generation,
    MagicMutationIdentity identity,
  ) =>
      !_disposed &&
      _activePreviewRequest == requestId &&
      _draftGeneration == generation &&
      identical(_identity, identity);

  void _updateDraft(SubscriptionIssueDraft next) {
    if (_disposed || !fieldsEnabled) return;
    _draftGeneration++;
    _activePreviewRequest = null;
    _draft = next;
    _preview = null;
    _busy = false;
    _error = null;
    _identity = _identityFactory();
    _notifyListeners();
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _draftGeneration++;
    _activePreviewRequest = null;
    super.dispose();
  }
}

extension SubscriptionIssuePaymentActions on SubscriptionIssueController {
  Map<String, dynamic> get selectedPackage => _package;

  void selectPackage(Map<String, dynamic> package) {
    if (!fieldsEnabled || package['id']?.toString() == _draft.packageId) return;
    _package = package;
    _basePriceMinor = subscriptionPackageBasePriceMinor(package);
    _updateDraft(
      SubscriptionIssueDraft.fromPackage(
        package: package,
        recipientStudentId: _draft.recipientStudentId,
        recipientLabel: _draft.recipientLabel,
        commandTimestamp: _commandTimestamp,
      ),
    );
  }

  void setStartsAt(DateTime value) {
    final start = DateTime.utc(value.year, value.month, value.day);
    _updateDraft(
      _draft.copyWith(
        startsAt: start,
        expiresAt: _draft.expiresAt.isBefore(start)
            ? subscriptionAddCalendarMonth(start)
            : _draft.expiresAt,
      ),
    );
  }

  void setExpiresAt(DateTime value) {
    _updateDraft(
      _draft.copyWith(
        expiresAt: DateTime.utc(value.year, value.month, value.day),
      ),
    );
  }

  void setPaymentAmount(String value) {
    _updateDraft(_draft.copyWith(paymentAmount: value));
  }

  void setPaymentOccurredAt(DateTime value) {
    _updateDraft(_draft.copyWith(paymentOccurredAt: value.toUtc()));
  }

  void setPaymentComment(String value) {
    _updateDraft(_draft.copyWith(paymentComment: value));
  }

  String? validatePaymentAmount(String? _) {
    final raw = _draft.paymentAmount.trim();
    if (raw.isEmpty) return null;
    return parseSubscriptionMoneyMinor(raw) == null
        ? 'Введите сумму, например 8 000 или 8 000,50'
        : null;
  }

  String? validateExpiresAt() => _draft.expiresAt.isBefore(_draft.startsAt)
      ? 'Дата окончания не может быть раньше даты начала'
      : null;
}
