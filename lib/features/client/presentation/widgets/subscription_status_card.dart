import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/theme/design_tokens.dart';
import 'package:magic_music_crm/core/utils/money_format.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/core/widgets/magic_page_state.dart';

final subscriptionProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  // magicCurrentStudentIdProvider derives from the portal switcher selection
  // (KVA-156), so switching children re-evaluates and re-renders this card.
  final studentIdAsync = ref.watch(magicCurrentStudentIdProvider);
  final studentId = studentIdAsync.asData?.value;

  if (studentId == null) return null;

  final projection = await ref.watch(myCommerceProjectionProvider.future);
  final subscriptions =
      projection.studentById(studentId)?.legacySubscriptions ??
      const <Map<String, dynamic>>[];

  return subscriptions.firstOrNull;
});

class SubscriptionStatusCard extends ConsumerWidget {
  const SubscriptionStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(subscriptionProvider);

    return subAsync.when(
      data: (subscription) {
        if (subscription == null) {
          return Card(
            margin: const EdgeInsets.all(16.0),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_rounded,
                      size: 32,
                      color: AppTheme.warning,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Нет активного абонемента',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Пожалуйста, свяжитесь с администратором для приобретения или продления абонемента.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final courseName =
            (subscription['package_name']?.toString() ??
                    subscription['type']?.toString() ??
                    'Абонемент')
                .toUpperCase();
        // Subscriptions are tracked in HOURS (may be fractional).
        final hoursTotal = (subscription['lessons_total'] as num?) ?? 0;
        final hoursUsed = (subscription['lessons_used'] as num?) ?? 0;
        final remainingNum = hoursTotal - hoursUsed;
        final remainingClasses = remainingNum % 1 == 0
            ? remainingNum.toInt()
            : remainingNum;
        final endDateStr = subscription['valid_until'] as String?;
        final endDate = endDateStr == null
            ? null
            : DateTime.parse(endDateStr).toLocal();
        final daysLeft = endDate?.difference(DateTime.now()).inDays;
        final validityText = endDate == null
            ? 'Действует: бессрочно'
            : 'Действует до: ${DateFormat('d MMMM yyyy', 'ru').format(endDate)}';
        final nextPaymentRaw = subscription['next_payment_at']?.toString();
        final nextPaymentAt = nextPaymentRaw == null || nextPaymentRaw.isEmpty
            ? null
            : DateTime.tryParse(nextPaymentRaw)?.toLocal();
        final hasFinance = subscription.containsKey('actual_paid_minor');

        bool isExpiringSoon =
            (daysLeft != null && daysLeft <= 7) || remainingClasses <= 2;

        return Card(
          margin: const EdgeInsets.all(16.0),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        courseName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isExpiringSoon
                            ? AppTheme.danger.withAlpha(25)
                            : AppTheme.success.withAlpha(25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Осталось: $remainingClasses ч',
                        style: TextStyle(
                          color: isExpiringSoon
                              ? AppTheme.danger
                              : AppTheme.success,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      validityText,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (hasFinance) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _SubscriptionMetric(
                        key: const Key('subscription-hours'),
                        label: 'Часы',
                        value:
                            '${_formatHours(hoursUsed)} из ${_formatHours(hoursTotal)}',
                      ),
                      _SubscriptionMetric(
                        key: const Key('subscription-paid'),
                        label: 'Оплачено',
                        value: _formatMinor(
                          subscription['actual_paid_minor'],
                          currencyCode:
                              subscription['currency_code']?.toString() ??
                              'RUB',
                        ),
                        color: AppTheme.success,
                      ),
                      _SubscriptionMetric(
                        key: const Key('subscription-debt'),
                        label: 'Долг',
                        value: _formatMinor(
                          subscription['debt_minor'],
                          currencyCode:
                              subscription['currency_code']?.toString() ??
                              'RUB',
                        ),
                        color: _minorPositive(subscription['debt_minor'])
                            ? AppTheme.danger
                            : null,
                      ),
                      _SubscriptionMetric(
                        key: const Key('subscription-pending'),
                        label: 'Ожидает подтверждения',
                        value: _formatMinor(
                          subscription['pending_minor'],
                          currencyCode:
                              subscription['currency_code']?.toString() ??
                              'RUB',
                        ),
                        color: _minorPositive(subscription['pending_minor'])
                            ? AppTheme.warning
                            : null,
                      ),
                      _SubscriptionMetric(
                        key: const Key('subscription-overpayment'),
                        label: 'Переплата',
                        value: _formatMinor(
                          subscription['overpayment_minor'],
                          currencyCode:
                              subscription['currency_code']?.toString() ??
                              'RUB',
                        ),
                        color: _minorPositive(subscription['overpayment_minor'])
                            ? AppTheme.success
                            : null,
                      ),
                      _SubscriptionMetric(
                        key: const Key('subscription-next-payment'),
                        label: 'Следующий платёж',
                        value: nextPaymentAt == null
                            ? 'Не запланирован'
                            : DateFormat(
                                'd MMMM yyyy',
                                'ru',
                              ).format(nextPaymentAt),
                      ),
                    ],
                  ),
                ],
                if (isExpiringSoon) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.danger.withAlpha(50)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppTheme.danger,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            remainingClasses <= 0
                                ? 'Абонемент закончился. Пожалуйста, продлите его.'
                                : 'Абонемент скоро закончится! Не забудьте продлить.',
                            style: const TextStyle(
                              color: AppTheme.danger,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const _SubscriptionSkeleton(),
      error: (_, _) => MagicPageState(
        kind: MagicPageStateKind.error,
        title: 'Не удалось загрузить абонемент',
        message: 'Проверьте подключение и повторите загрузку.',
        actionLabel: 'Повторить',
        onAction: () {
          ref.invalidate(myCommerceProjectionProvider);
          ref.invalidate(subscriptionProvider);
        },
      ),
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
    );
  }
}

class _SubscriptionMetric extends StatelessWidget {
  const _SubscriptionMetric({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 154,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color ?? cs.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatHours(num value) => value == value.truncate()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

bool _minorPositive(Object? raw) =>
    (BigInt.tryParse(raw?.toString() ?? '') ?? BigInt.zero) > BigInt.zero;

String _formatMinor(Object? raw, {String currencyCode = 'RUB'}) {
  final minor = BigInt.tryParse(raw?.toString() ?? '') ?? BigInt.zero;
  return formatPaymentMinor(minor, currencyCode: currencyCode);
}

class _SubscriptionSkeleton extends StatelessWidget {
  const _SubscriptionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Skeleton(width: 150, height: 24),
                Skeleton(width: 80, height: 24),
              ],
            ),
            const SizedBox(height: 16),
            const Skeleton(width: 200, height: 18),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: AppColor.surfaceSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Skeleton(width: 24, height: 24),
                  SizedBox(width: 12),
                  Skeleton(width: 180, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
