import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/admin/presentation/widgets/top_up_dialog.dart';

class DebtorsWidget extends ConsumerStatefulWidget {
  const DebtorsWidget({super.key});

  @override
  ConsumerState<DebtorsWidget> createState() => _DebtorsWidgetState();
}

class _DebtorsWidgetState extends ConsumerState<DebtorsWidget> {
  List<Map<String, dynamic>> _debtors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDebtors();
  }

  Future<void> _loadDebtors() async {
    setState(() => _loading = true);
    try {
      final res = await ref
          .read(magicCrmServiceProvider)
          .listStudentBalances(debtOnly: true, limit: 100);

      if (!mounted) return;
      setState(() {
        _debtors = res;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showDebtorDetails(Map<String, dynamic> debtor) async {
    final studentId = debtor['student_id']?.toString();
    if (studentId == null || studentId.trim().isEmpty) return;

    final crm = ref.read(magicCrmServiceProvider);
    final detailFuture =
        Future.wait<List<Map<String, dynamic>>>([
          crm.listPayments(studentId: studentId, limit: 30),
          crm.listExpectedPayments(studentId: studentId, limit: 30),
          crm.listTimeline(
            entityType: 'student',
            entityId: studentId,
            includeAudit: true,
            limit: 40,
          ),
        ]).then(
          (items) => _DebtorDetailData(
            payments: items[0],
            expectedPayments: items[1],
            timeline: items[2],
          ),
        );

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => _DebtorDetailSheet(
        debtor: debtor,
        detailFuture: detailFuture,
        onOpenStudent: () => context.push('/admin/student/$studentId'),
        onAddPayment: () async {
          final result = await TopUpDialog.show(
            sheetContext,
            _topUpStudentPayload(debtor),
          );
          if (result == true && sheetContext.mounted) {
            Navigator.pop(sheetContext, true);
          }
        },
      ),
    );
    if (changed == true && mounted) {
      await _loadDebtors();
    }
  }

  Map<String, dynamic> _topUpStudentPayload(Map<String, dynamic> debtor) {
    return {
      'id': debtor['student_id'],
      'first_name': debtor['first_name'],
      'last_name': debtor['last_name'],
      'phone': debtor['phone'],
    };
  }

  @override
  Widget build(BuildContext context) {
    final totalDebt = _debtors.fold<num>(
      0,
      (sum, debtor) => sum + _debtAmount(debtor),
    );
    final totalPaid = _debtors.fold<num>(
      0,
      (sum, debtor) => sum + _asNum(debtor['total_paid']).abs(),
    );
    final totalCost = _debtors.fold<num>(
      0,
      (sum, debtor) => sum + _asNum(debtor['total_cost']).abs(),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DebtorsHeader(
            count: _debtors.length,
            totalDebt: totalDebt,
            totalPaid: totalPaid,
            totalCost: totalCost,
            loading: _loading,
            onRefresh: _loadDebtors,
          ),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: ListSkeleton(count: 7),
                  )
                : RefreshIndicator(
                    onRefresh: _loadDebtors,
                    color: AppTheme.danger,
                    child: _debtors.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.45,
                                child: Center(
                                  child: Text(
                                    'Должников не найдено',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _debtors.length,
                            itemBuilder: (ctx, i) {
                              final debtor = _debtors[i];
                              return _DebtorCard(
                                debtor: debtor,
                                onTap: () => _showDebtorDetails(debtor),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DebtorsHeader extends StatelessWidget {
  final int count;
  final num totalDebt;
  final num totalPaid;
  final num totalCost;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _DebtorsHeader({
    required this.count,
    required this.totalDebt,
    required this.totalPaid,
    required this.totalCost,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Должники',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Обновить',
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DebtMetric(
                icon: Icons.people_alt_rounded,
                label: 'Учеников',
                value: '$count',
                color: AppTheme.danger,
              ),
              _DebtMetric(
                icon: Icons.priority_high_rounded,
                label: 'Долг',
                value: '${_formatMoney(totalDebt)} ₽',
                color: AppTheme.danger,
              ),
              _DebtMetric(
                icon: Icons.payments_rounded,
                label: 'Оплачено',
                value: '${_formatMoney(totalPaid)} ₽',
                color: AppTheme.success,
              ),
              _DebtMetric(
                icon: Icons.receipt_long_rounded,
                label: 'Начислено',
                value: '${_formatMoney(totalCost)} ₽',
                color: AppTheme.secondaryGold,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DebtMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DebtMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DebtorCard extends StatelessWidget {
  final Map<String, dynamic> debtor;
  final VoidCallback onTap;

  const _DebtorCard({required this.debtor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final balance = _asNum(debtor['balance']);
    final debt = _debtAmount(debtor);
    final totalPaid = _asNum(debtor['total_paid']);
    final totalCost = _asNum(debtor['total_cost']);
    final profile = _profile(debtor);
    final name = _studentName(profile);
    final phone = profile['phone']?.toString().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: AppTheme.danger.withAlpha(30),
          child: const Icon(
            Icons.person_remove_rounded,
            color: AppTheme.danger,
            size: 20,
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _DebtTag(
                icon: Icons.phone_outlined,
                text: phone == null || phone.isEmpty ? 'Нет телефона' : phone,
              ),
              _DebtTag(
                icon: Icons.payments_rounded,
                text: 'Оплачено ${_formatMoney(totalPaid)} ₽',
              ),
              _DebtTag(
                icon: Icons.receipt_long_rounded,
                text: 'Начислено ${_formatMoney(totalCost)} ₽',
              ),
            ],
          ),
        ),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 96),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_formatSignedMoney(balance)} ₽',
                style: TextStyle(
                  color: debt > 0 ? AppTheme.danger : AppTheme.success,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              Text(
                'баланс',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebtTag extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DebtTag({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _DebtorDetailData {
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> expectedPayments;
  final List<Map<String, dynamic>> timeline;

  const _DebtorDetailData({
    required this.payments,
    required this.expectedPayments,
    required this.timeline,
  });
}

class _DebtorDetailSheet extends StatelessWidget {
  final Map<String, dynamic> debtor;
  final Future<_DebtorDetailData> detailFuture;
  final VoidCallback onOpenStudent;
  final Future<void> Function() onAddPayment;

  const _DebtorDetailSheet({
    required this.debtor,
    required this.detailFuture,
    required this.onOpenStudent,
    required this.onAddPayment,
  });

  @override
  Widget build(BuildContext context) {
    final profile = _profile(debtor);
    final name = _studentName(profile);
    final phone = profile['phone']?.toString().trim();
    final balance = _asNum(debtor['balance']);
    final totalPaid = _asNum(debtor['total_paid']);
    final totalCost = _asNum(debtor['total_cost']);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withAlpha(70),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          phone == null || phone.isEmpty
                              ? 'Контакт не указан'
                              : phone,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Карточка ученика',
                    onPressed: () {
                      Navigator.pop(context);
                      onOpenStudent();
                    },
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DebtMetric(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Баланс',
                    value: '${_formatSignedMoney(balance)} ₽',
                    color: balance < 0 ? AppTheme.danger : AppTheme.success,
                  ),
                  _DebtMetric(
                    icon: Icons.payments_rounded,
                    label: 'Оплачено',
                    value: '${_formatMoney(totalPaid)} ₽',
                    color: AppTheme.success,
                  ),
                  _DebtMetric(
                    icon: Icons.receipt_long_rounded,
                    label: 'Начислено',
                    value: '${_formatMoney(totalCost)} ₽',
                    color: AppTheme.secondaryGold,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: onAddPayment,
                  icon: const Icon(Icons.add_card_rounded, size: 18),
                  label: const Text('Добавить оплату'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.success,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<_DebtorDetailData>(
                  future: detailFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const ListSkeleton(count: 5);
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Детализация временно недоступна',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    final data =
                        snapshot.data ??
                        const _DebtorDetailData(
                          payments: [],
                          expectedPayments: [],
                          timeline: [],
                        );
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DetailSection(
                            title: 'Последние оплаты',
                            empty: 'Оплат по ученику нет',
                            items: data.payments,
                            itemBuilder: _paymentTile,
                          ),
                          _DetailSection(
                            title: 'Ожидаемые платежи',
                            empty: 'Ожидаемых платежей нет',
                            items: data.expectedPayments,
                            itemBuilder: _expectedPaymentTile,
                          ),
                          _DetailSection(
                            title: 'Лента',
                            empty: 'История по ученику пока пустая',
                            items: data.timeline,
                            itemBuilder: _timelineTile,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentTile(BuildContext context, Map<String, dynamic> item) {
    final amount = _asNum(item['amount']);
    final note = (item['notes'] ?? item['description'] ?? '').toString().trim();
    final method = item['method']?.toString().trim();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.payments_rounded, color: AppTheme.success),
      title: Text('${_formatMoney(amount)} ₽'),
      subtitle: Text(
        [
          _formatDate(item['payment_date'] ?? item['created_at']),
          if (method != null && method.isNotEmpty) _paymentMethodLabel(method),
          if (note.isNotEmpty) note,
        ].where((value) => value != null && value.isNotEmpty).join(' · '),
      ),
    );
  }

  Widget _expectedPaymentTile(BuildContext context, Map<String, dynamic> item) {
    final amount = _asNum(item['amount']);
    final status = item['status']?.toString();
    final description = item['description']?.toString().trim();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(
        Icons.schedule_send_rounded,
        color: AppTheme.secondaryGold,
      ),
      title: Text('${_formatMoney(amount)} ₽'),
      subtitle: Text(
        [
          _formatDate(item['due_date']),
          if (status != null && status.isNotEmpty) _paymentStatusLabel(status),
          if (description != null && description.isNotEmpty) description,
        ].where((value) => value != null && value.isNotEmpty).join(' · '),
      ),
    );
  }

  Widget _timelineTile(BuildContext context, Map<String, dynamic> item) {
    final title = item['title']?.toString() ?? _timelineTypeLabel(item['type']);
    final body = item['body']?.toString().trim();
    final actor = item['actor_name']?.toString().trim();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        _timelineIcon(item['type']?.toString()),
        color: AppTheme.primaryPurple,
      ),
      title: Text(title),
      subtitle: Text(
        [
          if (body != null && body.isNotEmpty) body,
          _formatDate(item['occurred_at']),
          if (actor != null && actor.isNotEmpty) actor,
        ].where((value) => value != null && value.isNotEmpty).join(' · '),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final String empty;
  final List<Map<String, dynamic>> items;
  final Widget Function(BuildContext, Map<String, dynamic>) itemBuilder;

  const _DetailSection({
    required this.title,
    required this.empty,
    required this.items,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final visible = items.take(6).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          if (visible.isEmpty)
            Text(
              empty,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            )
          else
            ...visible.map((item) => itemBuilder(context, item)),
        ],
      ),
    );
  }
}

Map<String, dynamic> _profile(Map<String, dynamic> debtor) {
  final students = debtor['students'];
  if (students is! Map<String, dynamic>) return const {};
  final profile = students['profiles'];
  if (profile is! Map<String, dynamic>) return const {};
  return profile;
}

String _studentName(Map<String, dynamic> profile) {
  final firstName = profile['first_name']?.toString().trim() ?? '';
  final lastName = profile['last_name']?.toString().trim() ?? '';
  final name = '$firstName $lastName'.trim();
  return name.isEmpty ? 'Без имени' : name;
}

num _asNum(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

num _debtAmount(Map<String, dynamic> debtor) {
  final balance = _asNum(debtor['balance']);
  return balance < 0 ? balance.abs() : 0;
}

String _formatMoney(num value) {
  return NumberFormat.decimalPattern('ru').format(value.abs());
}

String _formatSignedMoney(num value) {
  final sign = value < 0 ? '-' : '';
  return '$sign${_formatMoney(value)}';
}

String? _formatDate(Object? raw) {
  final value = raw?.toString();
  if (value == null || value.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return DateFormat('d MMM yyyy', 'ru').format(parsed.toLocal());
}

String _paymentMethodLabel(String value) {
  return switch (value) {
    'cash' => 'наличные',
    'card' => 'карта',
    'transfer' => 'перевод',
    'subscription' => 'абонемент',
    'extra_lesson' => 'доп. занятие',
    _ => value,
  };
}

String _paymentStatusLabel(String value) {
  return switch (value) {
    'paid' => 'оплачен',
    'pending' => 'ожидается',
    'overdue' => 'просрочен',
    'cancelled' => 'отменен',
    _ => value,
  };
}

IconData _timelineIcon(String? type) {
  return switch (type) {
    'payment' => Icons.payments_rounded,
    'task' => Icons.task_alt_rounded,
    'comment' => Icons.chat_bubble_outline_rounded,
    'lesson' => Icons.event_available_rounded,
    'audit' => Icons.verified_user_rounded,
    _ => Icons.history_rounded,
  };
}

String _timelineTypeLabel(Object? type) {
  return switch (type?.toString()) {
    'payment' => 'Оплата',
    'task' => 'Задача',
    'comment' => 'Комментарий',
    'lesson' => 'Занятие',
    'audit' => 'Аудит',
    _ => 'Событие',
  };
}
