import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:magic_music_crm/core/widgets/searchable_picker_field.dart';

import '../lesson_decision/lesson_decision_models.dart';
import '../lesson_form_rules.dart';

class LessonClientFundingFields extends StatefulWidget {
  const LessonClientFundingFields({
    super.key,
    required this.participants,
    required this.decisions,
    required this.enabled,
    required this.searchPayers,
    required this.loadSubscriptions,
    required this.onChanged,
    this.subscriptionsByPayer = const {},
    this.knownPayers = const [],
    this.allowsNoFunding = false,
  });

  final List<LessonDecisionParticipant> participants;
  final List<Map<String, dynamic>> decisions;
  final bool enabled;
  final Future<List<LessonDecisionParticipant>> Function(String) searchPayers;
  final Future<List<LessonDecisionSubscription>> Function(String)
  loadSubscriptions;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final Map<String, List<LessonDecisionSubscription>> subscriptionsByPayer;
  final List<LessonDecisionParticipant> knownPayers;
  final bool allowsNoFunding;

  @override
  State<LessonClientFundingFields> createState() =>
      _LessonClientFundingFieldsState();
}

class _LessonClientFundingFieldsState extends State<LessonClientFundingFields> {
  late List<Map<String, dynamic>> _decisions;

  @override
  void initState() {
    super.initState();
    _decisions = widget.decisions;
  }

  @override
  void didUpdateWidget(covariant LessonClientFundingFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameData(oldWidget.decisions, widget.decisions)) {
      _decisions = widget.decisions;
    }
  }

  Map<String, dynamic> _decisionFor(String clientId) {
    final row = _decisions
        .where((row) => row['clientId'] == clientId)
        .firstOrNull;
    final isStudent = widget.participants
        .where((participant) => participant.id == clientId)
        .first
        .isStudent;
    return {
      if (isStudent) 'payerStudentId': clientId,
      'chargeType': isStudent
          ? 'subscription'
          : widget.allowsNoFunding
          ? 'none'
          : 'personal_account',
      'discount': const {'type': 'none'},
      'surcharge': const {'type': 'none'},
      ...?row,
      'clientId': clientId,
    };
  }

  void _update(String clientId, Map<String, dynamic> decision) {
    if (!widget.enabled || _sameData(_decisionFor(clientId), decision)) return;
    final exists = _decisions.any((row) => row['clientId'] == clientId);
    final updated = List<Map<String, dynamic>>.unmodifiable([
      for (final row in _decisions)
        if (row['clientId'] == clientId)
          Map<String, dynamic>.unmodifiable(decision)
        else
          row,
      if (!exists) Map<String, dynamic>.unmodifiable(decision),
    ]);
    setState(() => _decisions = updated);
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final participant in widget.participants)
        _ParticipantFundingFields(
          key: ValueKey(participant.id),
          participant: participant,
          decision: _decisionFor(participant.id),
          enabled: widget.enabled,
          allowsNoFunding: widget.allowsNoFunding,
          knownPayers: [...widget.participants, ...widget.knownPayers],
          subscriptionsByPayer: widget.subscriptionsByPayer,
          searchPayers: widget.searchPayers,
          loadSubscriptions: widget.loadSubscriptions,
          onChanged: (decision) => _update(participant.id, decision),
        ),
    ],
  );
}

class _ParticipantFundingFields extends StatefulWidget {
  const _ParticipantFundingFields({
    super.key,
    required this.participant,
    required this.decision,
    required this.enabled,
    required this.allowsNoFunding,
    required this.knownPayers,
    required this.subscriptionsByPayer,
    required this.searchPayers,
    required this.loadSubscriptions,
    required this.onChanged,
  });

  final LessonDecisionParticipant participant;
  final Map<String, dynamic> decision;
  final bool enabled;
  final bool allowsNoFunding;
  final List<LessonDecisionParticipant> knownPayers;
  final Map<String, List<LessonDecisionSubscription>> subscriptionsByPayer;
  final Future<List<LessonDecisionParticipant>> Function(String) searchPayers;
  final Future<List<LessonDecisionSubscription>> Function(String)
  loadSubscriptions;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_ParticipantFundingFields> createState() =>
      _ParticipantFundingFieldsState();
}

class _ParticipantFundingFieldsState extends State<_ParticipantFundingFields> {
  late Map<String, dynamic> _decision;
  final _price = TextEditingController();
  final _discountValue = TextEditingController();
  final _discountReason = TextEditingController();
  final _surchargeValue = TextEditingController();
  final _surchargeReason = TextEditingController();
  final _payerNames = <String, String>{};
  List<LessonDecisionSubscription> _subscriptions = const [];
  String? _loadedPayerId;
  String? _requestedPayerId;
  String? _subscriptionError;
  bool _loading = false;
  int _loadRevision = 0;

  String get _payerId =>
      _decision['payerStudentId']?.toString() ??
      (widget.participant.isStudent ? widget.participant.id : '');
  String get _chargeType =>
      _decision['chargeType']?.toString() ?? 'subscription';
  Map<String, dynamic> get _discount => _map(_decision['discount']);
  Map<String, dynamic> get _surcharge => _map(_decision['surcharge']);
  String get _discountType => _discount['type']?.toString() ?? 'none';
  String get _surchargeType => _surcharge['type']?.toString() ?? 'none';
  String? get _subscriptionId => _decision['subscriptionId']?.toString();
  Key _key(String field) =>
      ValueKey('lesson-client-$field-${widget.participant.id}');

  @override
  void initState() {
    super.initState();
    _decision = widget.decision;
    _rememberPayers();
    _syncText();
    _subscriptions = widget.subscriptionsByPayer[_payerId] ?? const [];
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(covariant _ParticipantFundingFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPayer = _payerId;
    final oldSource = _chargeType;
    _rememberPayers();
    if (!_sameData(_decision, widget.decision)) {
      _decision = widget.decision;
      final decision = _decision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_decision, decision)) _syncText();
      });
    }
    if (!widget.enabled) {
      _invalidateLoad();
    } else if (!oldWidget.enabled ||
        oldPayer != _payerId ||
        oldSource != _chargeType) {
      _invalidateLoad();
      _scheduleLoad();
    } else if (!_sameData(
      oldWidget.subscriptionsByPayer,
      widget.subscriptionsByPayer,
    )) {
      _loadedPayerId = null;
      _scheduleLoad();
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _price,
      _discountValue,
      _discountReason,
      _surchargeValue,
      _surchargeReason,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _rememberPayers() {
    for (final payer in widget.knownPayers) {
      if (payer.isStudent) _payerNames[payer.id] = payer.name;
    }
  }

  void _syncText() {
    _price.text = _formatInput(_decision['basePriceMinor']);
    _discountValue.text = _formatInput(
      _discount[_discountType == 'percent'
          ? 'percentBasisPoints'
          : 'fixedMinor'],
    );
    _discountReason.text = _discount['reason']?.toString() ?? '';
    _surchargeValue.text = _formatInput(_surcharge['amountMinor']);
    _surchargeReason.text = _surcharge['reason']?.toString() ?? '';
  }

  void _scheduleLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureSubscriptions();
    });
  }

  void _invalidateLoad() {
    _loadRevision++;
    _loading = false;
    _requestedPayerId = null;
    _loadedPayerId = null;
    _subscriptionError = null;
  }

  Future<void> _ensureSubscriptions() async {
    if (!widget.enabled || _chargeType != 'subscription') return;
    final payerId = _payerId;
    if (payerId.isEmpty) return;
    if (_loading && _requestedPayerId == payerId) return;
    if (_loadedPayerId == payerId) {
      _chooseDefaultSubscription();
      return;
    }
    final revision = ++_loadRevision;
    setState(() {
      _requestedPayerId = payerId;
      _loading = true;
      _subscriptionError = null;
    });
    try {
      final rows =
          widget.subscriptionsByPayer[payerId] ??
          await widget.loadSubscriptions(payerId);
      if (!_ownsLoad(revision, payerId)) return;
      setState(() {
        _subscriptions = rows;
        _loadedPayerId = payerId;
        _loading = false;
      });
      _chooseDefaultSubscription();
    } catch (_) {
      if (!_ownsLoad(revision, payerId)) return;
      setState(() {
        _loading = false;
        _subscriptionError = 'Не удалось загрузить абонементы';
      });
    }
  }

  bool _ownsLoad(int revision, String payerId) =>
      mounted &&
      widget.enabled &&
      _chargeType == 'subscription' &&
      revision == _loadRevision &&
      payerId == _payerId;

  void _chooseDefaultSubscription() {
    if ((_subscriptionId == null || _subscriptionId!.isEmpty) &&
        _subscriptions.isNotEmpty) {
      _change({..._decision, 'subscriptionId': _subscriptions.first.id});
    }
  }

  void _change(Map<String, dynamic> next) {
    if (!widget.enabled || _sameData(_decision, next)) return;
    setState(() => _decision = next);
    widget.onChanged(next);
  }

  void _choosePayer(SearchableSelectItem? payer) {
    if (!widget.enabled || payer == null || payer.id == _payerId) return;
    _payerNames[payer.id] = payer.label;
    _invalidateLoad();
    _subscriptions = const [];
    _change(
      {..._decision, 'payerStudentId': payer.id}..remove('subscriptionId'),
    );
    _ensureSubscriptions();
  }

  void _chooseSource(String? source) {
    if (source == null || !widget.enabled || source == _chargeType) return;
    _invalidateLoad();
    final next = {..._decision, 'chargeType': source};
    if (source != 'subscription') next.remove('subscriptionId');
    _change(next);
    _ensureSubscriptions();
  }

  void _chooseDiscount(String? type) {
    if (!widget.enabled || type == null || type == _discountType) return;
    final discount = <String, dynamic>{..._discount, 'type': type}
      ..remove('fixedMinor')
      ..remove('percentBasisPoints');
    if (type == 'none') discount.remove('reason');
    _discountValue.clear();
    if (type == 'none') _discountReason.clear();
    _change({..._decision, 'discount': discount});
  }

  void _chooseSurcharge(String? type) {
    if (!widget.enabled || type == null || type == _surchargeType) return;
    final surcharge = <String, dynamic>{..._surcharge, 'type': type}
      ..remove('amountMinor');
    if (type == 'none') surcharge.remove('reason');
    _surchargeValue.clear();
    if (type == 'none') _surchargeReason.clear();
    _change({..._decision, 'surcharge': surcharge});
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Оплата: ${widget.participant.name}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        SearchablePickerField(
          key: _key('payer'),
          label: 'Плательщик *',
          hintText: 'Найдите ученика по имени',
          enabled: widget.enabled && _chargeType != 'none',
          isNullable: false,
          selectedId: _payerId.isEmpty ? null : _payerId,
          selectedLabel: _payerId.isEmpty
              ? null
              : _payerNames[_payerId] ?? 'Другой плательщик',
          placeholder: 'Выберите плательщика',
          errorText: _chargeType == 'personal_account' && _payerId.isEmpty
              ? 'Выберите ученика-плательщика'
              : null,
          items: [
            for (final entry in _payerNames.entries)
              SearchableSelectItem(id: entry.key, label: entry.value),
          ],
          onSearch: (query) async => [
            for (final payer in await widget.searchPayers(query))
              if (payer.isStudent)
                SearchableSelectItem(id: payer.id, label: payer.name),
          ],
          onSelected: _choosePayer,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          menuMaxHeight: 256,
          key: _key('charge-type'),
          initialValue: _chargeType,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Источник средств *'),
          items: [
            if (widget.participant.isStudent)
              const DropdownMenuItem(
                value: 'subscription',
                child: Text('С абонемента'),
              ),
            const DropdownMenuItem(
              value: 'personal_account',
              child: Text('С личного счёта'),
            ),
            if (widget.allowsNoFunding || _chargeType == 'none')
              const DropdownMenuItem(
                value: 'none',
                child: Text('Без списания'),
              ),
          ],
          onChanged: widget.enabled ? _chooseSource : null,
        ),
        if (_chargeType == 'subscription') ...[
          const SizedBox(height: 12),
          _subscriptionField(),
        ],
        if (_chargeType == 'personal_account') ...[
          const SizedBox(height: 12),
          _moneyField(
            name: 'price',
            label:
                'Цена занятия, ₽${_chargeType == 'personal_account' ? ' *' : ''}',
            controller: _price,
            optional: _chargeType != 'personal_account',
            helper: _chargeType == 'personal_account'
                ? 'До скидки и доплаты'
                : 'Оставьте пустым для цены по правилам',
            onChanged: (raw) {
              final next = <String, dynamic>{..._decision};
              if (raw.trim().isEmpty && _chargeType != 'personal_account') {
                next.remove('basePriceMinor');
              } else {
                next['basePriceMinor'] = _parseInput(raw) ?? '';
              }
              _change(next);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            menuMaxHeight: 256,
            key: _key('discount-type'),
            initialValue: _discountType,
            decoration: const InputDecoration(labelText: 'Скидка'),
            items: const [
              DropdownMenuItem(value: 'none', child: Text('Без скидки')),
              DropdownMenuItem(value: 'percent', child: Text('Процент')),
              DropdownMenuItem(value: 'fixed', child: Text('Сумма')),
            ],
            onChanged: widget.enabled ? _chooseDiscount : null,
          ),
          if (_discountType != 'none') ...[
            const SizedBox(height: 12),
            _moneyField(
              name: 'discount-value',
              label: _discountType == 'percent' ? 'Скидка, % *' : 'Скидка, ₽ *',
              controller: _discountValue,
              percent: _discountType == 'percent',
              onChanged: (raw) => _change({
                ..._decision,
                'discount': {
                  ..._discount,
                  if (_discountType == 'percent')
                    'percentBasisPoints': int.tryParse(_parseInput(raw) ?? '')
                  else
                    'fixedMinor': _parseInput(raw) ?? '',
                },
              }),
            ),
            const SizedBox(height: 12),
            _reasonField(
              'discount',
              _discountReason,
              'скидки',
              (reason) => _change({
                ..._decision,
                'discount': {..._discount, 'reason': reason},
              }),
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            menuMaxHeight: 256,
            key: _key('surcharge-type'),
            initialValue: _surchargeType,
            decoration: const InputDecoration(labelText: 'Доплата'),
            items: const [
              DropdownMenuItem(value: 'none', child: Text('Без доплаты')),
              DropdownMenuItem(
                value: 'fixed',
                child: Text('Фиксированная сумма'),
              ),
            ],
            onChanged: widget.enabled ? _chooseSurcharge : null,
          ),
          if (_surchargeType != 'none') ...[
            const SizedBox(height: 12),
            _moneyField(
              name: 'surcharge-value',
              label: 'Доплата, ₽ *',
              controller: _surchargeValue,
              onChanged: (raw) => _change({
                ..._decision,
                'surcharge': {
                  ..._surcharge,
                  'amountMinor': _parseInput(raw) ?? '',
                },
              }),
            ),
            const SizedBox(height: 12),
            _reasonField(
              'surcharge',
              _surchargeReason,
              'доплаты',
              (reason) => _change({
                ..._decision,
                'surcharge': {..._surcharge, 'reason': reason},
              }),
            ),
          ],
        ],
      ],
    ),
  );

  Widget _subscriptionField() {
    final selected = _subscriptions
        .where((row) => row.id == _subscriptionId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchablePickerField(
          key: _key('subscription'),
          label: 'Абонемент *',
          hintText: _loading
              ? 'Загружаем абонементы плательщика…'
              : 'Абонемент выбранного плательщика',
          placeholder: _subscriptions.isEmpty
              ? 'Нет доступных абонементов'
              : 'Выберите абонемент',
          selectedId: _subscriptionId,
          selectedLabel: selected?.label,
          enabled: widget.enabled && !_loading && _subscriptions.isNotEmpty,
          isNullable: false,
          items: [
            for (final row in _subscriptions)
              SearchableSelectItem(id: row.id, label: row.label),
          ],
          errorText:
              _subscriptionError ??
              (!_loading && _loadedPayerId != null && selected == null
                  ? _subscriptions.isEmpty
                        ? 'У плательщика нет доступных абонементов'
                        : 'Выберите доступный абонемент'
                  : null),
          onSelected: (item) {
            if (item != null) {
              _change({..._decision, 'subscriptionId': item.id});
            }
          },
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_subscriptionError != null && widget.enabled)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _ensureSubscriptions,
              child: const Text('Повторить загрузку'),
            ),
          ),
      ],
    );
  }

  Widget _moneyField({
    required String name,
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? helper,
    bool optional = false,
    bool percent = false,
  }) => TextFormField(
    key: _key(name),
    controller: controller,
    enabled: widget.enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,. ]'))],
    decoration: InputDecoration(labelText: label, helperText: helper),
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: (raw) {
      if (optional && (raw?.trim().isEmpty ?? true)) return null;
      final minor = BigInt.tryParse(_parseInput(raw ?? '') ?? '');
      if (minor == null) return 'Введите сумму от 0 с точностью до копейки';
      if (percent && minor > BigInt.from(10000)) {
        return 'Скидка должна быть от 0 до 100%';
      }
      return null;
    },
    onChanged: onChanged,
  );

  Widget _reasonField(
    String name,
    TextEditingController controller,
    String kind,
    ValueChanged<String> onChanged,
  ) => TextFormField(
    key: _key('$name-reason'),
    controller: controller,
    enabled: widget.enabled,
    maxLength: 500,
    decoration: InputDecoration(labelText: 'Причина $kind *'),
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: (value) =>
        value == null || value.trim().isEmpty ? 'Укажите причину $kind' : null,
    onChanged: onChanged,
  );
}

String? _parseInput(String raw) =>
    parseCompensationValueMinor(mode: 'fixed', rawValue: raw);
String _formatInput(Object? value) => value == null || value.toString().isEmpty
    ? ''
    : formatCompensationMinorInput(value.toString());

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

bool _sameData(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) => right.containsKey(key) && _sameData(left[key], right[key]),
        );
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        List.generate(
          left.length,
          (index) => _sameData(left[index], right[index]),
        ).every((value) => value);
  }
  return left == right;
}
