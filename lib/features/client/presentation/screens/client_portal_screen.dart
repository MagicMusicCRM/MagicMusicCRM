import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:magic_music_crm/features/client/presentation/widgets/subscription_status_card.dart';
import 'package:magic_music_crm/features/client/presentation/widgets/upcoming_lessons_list.dart';

/// Client-facing portal: shows the student's balance/subscription, upcoming
/// lessons and attendance history in one place. Reachable from the client chat
/// shell. Composes the existing (data-wired) client widgets.
class ClientPortalScreen extends ConsumerWidget {
  const ClientPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Моя школа'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
            onPressed: () {
              ref.invalidate(subscriptionProvider);
              ref.invalidate(upcomingLessonsRichProvider);
              ref.invalidate(pastLessonsRichProvider);
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          // Keep the portal readable on wide desktop windows.
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              // Balance / subscription status.
              SubscriptionStatusCard(),
              // Upcoming lessons + attendance history (own tab switcher).
              Expanded(child: UpcomingLessonsList()),
            ],
          ),
        ),
      ),
    );
  }
}
