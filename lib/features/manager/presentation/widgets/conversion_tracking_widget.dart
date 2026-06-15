import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class ConversionTrackingWidget extends ConsumerStatefulWidget {
  const ConversionTrackingWidget({super.key});

  @override
  ConsumerState<ConversionTrackingWidget> createState() =>
      _ConversionTrackingWidgetState();
}

class _ConversionTrackingWidgetState
    extends ConsumerState<ConversionTrackingWidget> {
  bool _loading = true;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final crm = ref.read(magicCrmServiceProvider);

      final [leads, students, trials] = await Future.wait([
        crm.listLeads(limit: 100),
        crm.listStudents(limit: 100),
        crm.listLessons(isTrial: true, limit: 200),
      ]);

      final totalLeads = leads.length;
      final convertedLeads = students.where((s) => s['lead_id'] != null).length;
      final conversionRate = totalLeads > 0
          ? (convertedLeads / totalLeads * 100)
          : 0.0;

      final completedTrials = trials
          .where((t) => t['status'] == 'completed')
          .length;
      final trialSuccessRate = trials.isNotEmpty
          ? (completedTrials / trials.length * 100)
          : 0.0;

      setState(() {
        _stats = {
          'total_leads': totalLeads,
          'converted': convertedLeads,
          'conversion_rate': conversionRate,
          'total_trials': trials.length,
          'completed_trials': completedTrials,
          'trial_success_rate': trialSuccessRate,
        };
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryPurple),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Воронка продаж',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          _buildStatCard(
            'Конверсия',
            '${_stats['conversion_rate'].toStringAsFixed(1)}%',
            'Из лидов в платящих учеников',
            Icons.analytics_rounded,
            AppTheme.primaryPurple,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSmallStat(
                  'Всего лидов',
                  '${_stats['total_leads']}',
                  Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: _buildSmallStat(
                  'Стали учениками',
                  '${_stats['converted']}',
                  AppTheme.success,
                ),
              ),
            ],
          ),
          const Divider(height: 48),
          const Text(
            'Пробные занятия',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          _buildStatCard(
            'Успешность пробных',
            '${_stats['trial_success_rate'].toStringAsFixed(1)}%',
            'Посещаемость пробных уроков',
            Icons.event_available_rounded,
            AppTheme.secondaryGold,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSmallStat(
                  'Назначено',
                  '${_stats['total_trials']}',
                  Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: _buildSmallStat(
                  'Проведено',
                  '${_stats['completed_trials']}',
                  AppTheme.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    String sub,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  Text(
                    sub,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
