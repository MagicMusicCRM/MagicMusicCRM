import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:magic_music_crm/core/models/payment.dart';
import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/core/widgets/lazy_indexed_stack.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/subscription_status_card.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/upcoming_lessons_list.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';

final clientPaymentsProvider = FutureProvider<List<Payment>>((ref) async {
  final studentId = ref.watch(magicCurrentStudentIdProvider).asData?.value;
  if (studentId == null) return const [];
  return ref
      .watch(magicCrmServiceProvider)
      .listPayments(studentId: studentId, limit: 100);
});

class ClientDashboardScreen extends ConsumerStatefulWidget {
  const ClientDashboardScreen({super.key});

  @override
  ConsumerState<ClientDashboardScreen> createState() =>
      _ClientDashboardScreenState();
}

class _ClientDashboardScreenState extends ConsumerState<ClientDashboardScreen> {
  int _selectedIndex = 0;

  // Client bottom nav (mobile) / rail (desktop): Чат opens first by default,
  // Профиль is last. «Занятия» merges the old Занятия+Расписание; «Абонемент»
  // merges the old Абонемент+Оплаты behind an in-tab toggle.
  static const _destinations = <_ClientDestination>[
    _ClientDestination(
      label: 'Чат',
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
    ),
    _ClientDestination(
      label: 'Занятия',
      icon: Icons.school_outlined,
      selectedIcon: Icons.school_rounded,
    ),
    _ClientDestination(
      label: 'Абонемент',
      icon: Icons.confirmation_number_outlined,
      selectedIcon: Icons.confirmation_number_rounded,
    ),
    _ClientDestination(
      label: 'Профиль',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    ref.listen(crmRealtimeProvider, (previous, next) {
      final event = next.value;
      if (event == null) return;
      switch (event.entity) {
        case 'lesson':
          ref.invalidate(upcomingLessonsRichProvider);
          ref.invalidate(pastLessonsRichProvider);
          break;
        case 'payment':
          ref.invalidate(clientPaymentsProvider);
          break;
        case 'subscription':
          ref.invalidate(subscriptionProvider);
          break;
        case 'student':
          ref.invalidate(myStudentsProvider);
          ref.invalidate(magicCurrentStudentIdProvider);
          ref.invalidate(subscriptionProvider);
          ref.invalidate(clientPaymentsProvider);
          ref.invalidate(upcomingLessonsRichProvider);
          ref.invalidate(pastLessonsRichProvider);
          break;
      }
    });

    final isDesktop = MediaQuery.of(context).size.width >= 768;
    // Mount tabs on first visit, then keep them in-place. A plain IndexedStack
    // preserved MessengerScreen but eagerly mounted all four tabs at login,
    // triggering their API providers simultaneously.
    final body = LazyIndexedStack(
      index: _selectedIndex,
      children: const [
        MessengerScreen(role: 'client'),
        _ClientSectionFrame(child: UpcomingLessonsList()),
        _ClientSubscriptionView(),
        ProfileScreen(),
      ],
    );

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              labelType: NavigationRailLabelType.all,
              minWidth: 92,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _ClientDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _ClientDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class _ClientSectionFrame extends StatelessWidget {
  final Widget child;

  const _ClientSectionFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: child,
      ),
    );
  }
}

/// «Абонемент» tab: a single tab that toggles between the subscription status
/// (окно «Абонемент») and the payments history (окно «Оплаты»), replacing the
/// two former separate bottom-nav tabs.
class _ClientSubscriptionView extends StatefulWidget {
  const _ClientSubscriptionView();

  @override
  State<_ClientSubscriptionView> createState() =>
      _ClientSubscriptionViewState();
}

class _ClientSubscriptionViewState extends State<_ClientSubscriptionView> {
  int _segment = 0; // 0: Абонемент, 1: Оплаты

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.primaryGold.withAlpha(30)),
            ),
            child: Row(
              children: [
                _SegmentButton(
                  label: 'Абонемент',
                  isActive: _segment == 0,
                  onTap: () => setState(() => _segment = 0),
                ),
                _SegmentButton(
                  label: 'Оплаты',
                  isActive: _segment == 1,
                  onTap: () => setState(() => _segment = 1),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _segment == 0
              ? _ClientSectionFrame(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: const [SubscriptionStatusCard()],
                  ),
                )
              : const _ClientPaymentsView(),
        ),
      ],
    );
  }
}

/// Segmented toggle button matching the in-tab toggle used by the lessons list.
class _SegmentButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primaryGold : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientPaymentsView extends ConsumerWidget {
  const _ClientPaymentsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(clientPaymentsProvider);
    final currency = NumberFormat.currency(
      locale: 'ru_RU',
      symbol: '₽',
      decimalDigits: 0,
    );

    return _ClientSectionFrame(
      child: paymentsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: ListSkeleton(count: 6),
        ),
        error: (err, _) => Center(
          child: Text(
            'Ошибка: $err',
            style: const TextStyle(color: AppTheme.danger),
          ),
        ),
        data: (payments) {
          if (payments.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.payments_outlined,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withAlpha(80),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Оплат пока нет',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => ref.invalidate(clientPaymentsProvider),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Обновить'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: AppTheme.primaryGold,
            onRefresh: () async => ref.invalidate(clientPaymentsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: payments.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final payment = payments[index];
                final amount = payment.amount;
                final date = DateTime.tryParse(payment.paymentDate ?? '');
                final method = payment.method?.trim();
                final notes = payment.notes?.trim();

                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x3322C55E),
                      child: Icon(
                        Icons.payments_rounded,
                        color: AppTheme.success,
                      ),
                    ),
                    title: Text(currency.format(amount)),
                    subtitle: Text(
                      [
                        if (date != null)
                          DateFormat('d MMMM yyyy', 'ru_RU').format(date),
                        if (method != null && method.isNotEmpty) method,
                        if (notes != null && notes.isNotEmpty) notes,
                      ].join(' · '),
                    ),
                  ),
                );
              },
            ),
          );
        },
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
      ),
    );
  }
}
