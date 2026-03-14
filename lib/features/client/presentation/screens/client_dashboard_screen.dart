import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/widgets/updater_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';
import '../widgets/upcoming_lessons_list.dart';
import '../widgets/subscription_status_card.dart';
import '../widgets/chat_widget.dart';
import '../widgets/homework_widget.dart';
import '../widgets/progress_notes_widget.dart';
import '../widgets/next_lesson_countdown.dart';
import 'package:intl/intl.dart';

class ClientDashboardScreen extends ConsumerStatefulWidget {
  const ClientDashboardScreen({super.key});

  @override
  ConsumerState<ClientDashboardScreen> createState() => _ClientDashboardScreenState();
}

class _ClientDashboardScreenState extends ConsumerState<ClientDashboardScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdaterDialog.checkAndShow(context, ref).catchError((e) {
        debugPrint('ClientDashboard Updater error: $e');
      });
    });
  }

  final List<Widget> _tabs = const [
    _ScheduleTab(),
    _HomeworkTab(),
    _SubscriptionTab(),
    _ChatTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryPurple.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.music_note_rounded, color: AppTheme.primaryPurple, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('MagicMusic'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Выйти',
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_rounded), label: 'Занятия'),
          BottomNavigationBarItem(icon: Icon(Icons.school_rounded), label: 'Академия'),
          BottomNavigationBarItem(icon: Icon(Icons.card_membership_rounded), label: 'Абонемент'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_rounded), label: 'Чат'),
        ],
      ),
    );
  }
}

class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NextLessonCountdown(),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Расписание занятий',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(child: UpcomingLessonsList()),
      ],
    );
  }
}

class _HomeworkTab extends StatelessWidget {
  const _HomeworkTab();

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppTheme.primaryPurple,
      onRefresh: () async {
        // Invalidation handled by child widgets
      },
      child: ListView(
        children: const [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Домашние задания',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            height: 300, // Limit height or use shrinkWrap in child
            child: HomeworkWidget(),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'Мои успехи',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          ProgressNotesWidget(),
        ],
      ),
    );
  }
}

class _SubscriptionTab extends StatelessWidget {
  const _SubscriptionTab();

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    return RefreshIndicator(
      onRefresh: () async {
        // FutureProvider invalidation happens inside widgets if needed, 
        // but for simplicity we just reload UI state via key or similar if we used it.
      },
      child: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Мой абонемент',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SubscriptionStatusCard(),
          if (userId != null) _BalanceSection(userId: userId),
        ],
      ),
    );
  }
}

class _BalanceSection extends StatelessWidget {
  final String userId;
  const _BalanceSection({required this.userId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: Supabase.instance.client
          .from('students')
          .select('id')
          .eq('profile_id', userId)
          .maybeSingle(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) return const SizedBox.shrink();
        final studentId = snapshot.data!['id'];

        return FutureBuilder<Map<String, dynamic>?>(
          future: Supabase.instance.client
              .from('student_balances')
              .select('*')
              .eq('student_id', studentId)
              .maybeSingle(),
          builder: (context, balanceSnapshot) {
            if (!balanceSnapshot.hasData || balanceSnapshot.data == null) return const SizedBox.shrink();
            final balance = balanceSnapshot.data!['balance'] as num? ?? 0;
            final fmt = NumberFormat('#,##0', 'ru');

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (balance < 0 ? AppTheme.danger : AppTheme.success).withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        balance < 0 ? Icons.warning_amber_rounded : Icons.account_balance_wallet_rounded, 
                        color: balance < 0 ? AppTheme.danger : AppTheme.success
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Текущий баланс', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                          Text('${fmt.format(balance)} ₽', style: TextStyle(
                            fontSize: 20, 
                            fontWeight: FontWeight.bold,
                            color: balance < 0 ? AppTheme.danger : AppTheme.success,
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ChatTab extends StatelessWidget {
  const _ChatTab();

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      return const Center(child: Text('Пользователь не найден.'));
    }

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Сообщения',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(child: ChatWidget(currentUserId: userId)),
      ],
    );
  }
}
