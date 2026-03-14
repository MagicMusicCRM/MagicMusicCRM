import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

class ConversionTrackingWidget extends StatefulWidget {
  const ConversionTrackingWidget({super.key});

  @override
  State<ConversionTrackingWidget> createState() => _ConversionTrackingWidgetState();
}

class _ConversionTrackingWidgetState extends State<ConversionTrackingWidget> {
  final _supabase = Supabase.instance.client;
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
      // final now = DateTime.now();

      final [leadsRes, studentsRes, trialsRes] = await Future.wait([
        _supabase.from('leads').select('id, created_at, status'),
        _supabase.from('students').select('id, created_at, lead_id'),
        _supabase.from('lessons').select('id, status, is_trial').eq('is_trial', true),
      ]);

      final leads = List<Map<String, dynamic>>.from(leadsRes);
      final students = List<Map<String, dynamic>>.from(studentsRes);
      final trials = List<Map<String, dynamic>>.from(trialsRes);

      // Calculations
      final totalLeads = leads.length;
      final convertedLeads = students.where((s) => s['lead_id'] != null).length;
      final conversionRate = totalLeads > 0 ? (convertedLeads / totalLeads * 100) : 0.0;

      final completedTrials = trials.where((t) => t['status'] == 'completed').length;
      final trialSuccessRate = trials.isNotEmpty ? (completedTrials / trials.length * 100) : 0.0;

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
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple));

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Воронка продаж', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
              Expanded(child: _buildSmallStat('Всего лидов', '${_stats['total_leads']}', AppTheme.textSecondary)),
              Expanded(child: _buildSmallStat('Стали учениками', '${_stats['converted']}', AppTheme.success)),
            ],
          ),
          const Divider(height: 48),
          const Text('Пробные занятия', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
              Expanded(child: _buildSmallStat('Назначено', '${_stats['total_trials']}', AppTheme.textSecondary)),
              Expanded(child: _buildSmallStat('Проведено', '${_stats['completed_trials']}', AppTheme.success)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, String sub, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
                  Text(sub, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
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
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      ],
    );
  }
}
