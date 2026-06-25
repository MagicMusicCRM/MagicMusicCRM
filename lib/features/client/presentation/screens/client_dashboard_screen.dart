import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:magic_music_crm/core/services/crm_realtime_provider.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import 'package:magic_music_crm/core/widgets/skeletons.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/subscription_status_card.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/upcoming_lessons_list.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/messenger_screen.dart';
import 'package:magic_music_crm/features/profile/presentation/screens/profile_screen.dart';

final clientPaymentsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final studentId = ref.watch(magicCurrentStudentIdProvider).asData?.value;
  if (studentId == null) return const [];
  return ref.watch(magicCrmServiceProvider).listPayments(
        studentId: studentId,
        limit: 100,
      );
});

class ClientDashboardScreen extends ConsumerStatefulWidget {
  const ClientDashboardScreen({super.key});

  @override
  ConsumerState<ClientDashboardScreen> createState() =>
      _ClientDashboardScreenState();
}

class _ClientDashboardScreenState extends ConsumerState<ClientDashboardScreen> {
  int _selectedIndex = 0;

  static const _destinations = <_ClientDestination>[
    _ClientDestination(
      label: 'Занятия',
      icon: Icons.school_outlined,
      selectedIcon: Icons.school_rounded,
    ),
    _ClientDestination(
      label: 'Расписание',
      icon: Icons.calendar_today_outlined,
      selectedIcon: Icons.calendar_today_rounded,
    ),
    _ClientDestination(
      label: 'Оплаты',
      icon: Icons.payments_outlined,
      selectedIcon: Icons.payments_rounded,
    ),
    _ClientDestination(
      label: 'Абонемент',
      icon: Icons.confirmation_number_outlined,
      selectedIcon: Icons.confirmation_number_rounded,
    ),
    _ClientDestination(
      label: 'Чат',
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
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
    final body = _buildBody(_selectedIndex);

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
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
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

  Widget _buildBody(int index) {
    return switch (index) {
      0 => const _ClientSectionFrame(child: UpcomingLessonsList()),
      1 => const _ClientSectionFrame(child: UpcomingLessonsList()),
      2 => const _ClientPaymentsView(),
      3 => const _ClientSectionFrame(child: SubscriptionStatusCard()),
      4 => const MessengerScreen(role: 'client'),
      5 => const ProfileScreen(),
      _ => const _ClientSectionFrame(child: UpcomingLessonsList()),
    };
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
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withAlpha(80),
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
                final amount = payment['amount'] is num
                    ? payment['amount'] as num
                    : num.tryParse(payment['amount']?.toString() ?? '') ?? 0;
                final date = DateTime.tryParse(
                  payment['payment_date']?.toString() ?? '',
                );
                final method = payment['method']?.toString().trim();
                final notes = payment['notes']?.toString().trim();

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
