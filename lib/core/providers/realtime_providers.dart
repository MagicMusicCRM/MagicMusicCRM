import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseProvider = Provider((ref) => Supabase.instance.client);

/// Provides the current student ID for the logged-in user.
final currentStudentIdProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.watch(supabaseProvider);
  final user = supabase.auth.currentUser;
  if (user == null) return null;

  final res = await supabase
      .from('students')
      .select('id')
      .eq('profile_id', user.id)
      .maybeSingle();
  
  return res?['id'] as String?;
});

/// Provides a real-time stream of lessons for a specific date range.
final lessonsStreamProvider = StreamProvider.family<List<Map<String, dynamic>>, DateTime>((ref, date) {
  final supabase = ref.watch(supabaseProvider);
  final startOfDay = DateTime(date.year, date.month, date.day).toIso8601String();
  final endOfDay = DateTime(date.year, date.month, date.day).add(const Duration(days: 1)).toIso8601String();

  return supabase
      .from('lessons')
      .stream(primaryKey: ['id'])
      .order('scheduled_at')
      .map((data) {
        // Note: Supabase .stream() doesn't support complex joins (select('*', students(...))).
        // We might need a separate mechanism or use a combined approach for related data
        // if real-time joins are critical. 
        // For now, we'll return the base data and let widgets handle additional lookups if necessary,
        // or trigger a refresh of related providers.
        return data.where((l) {
          final scheduledAt = l['scheduled_at'] as String?;
          if (scheduledAt == null) return false;
          return scheduledAt.compareTo(startOfDay) >= 0 && scheduledAt.compareTo(endOfDay) < 0;
        }).toList();
      });
});

/// Provides a real-time stream of students.
final studentsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final supabase = ref.watch(supabaseProvider);
  return supabase.from('students').stream(primaryKey: ['id']).order('id');
});

/// Provides a real-time stream of teachers.
final teachersStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final supabase = ref.watch(supabaseProvider);
  return supabase.from('teachers').stream(primaryKey: ['id']).order('id');
});

/// Provides a real-time stream of groups.
final groupsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final supabase = ref.watch(supabaseProvider);
  return supabase.from('groups').stream(primaryKey: ['id']).order('name');
});

/// Provides a real-time stream of rooms.
final roomsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final supabase = ref.watch(supabaseProvider);
  return supabase.from('rooms').stream(primaryKey: ['id']).order('name');
});

/// Provides a real-time stream of upcoming lessons for a specific student.
final studentLessonsStreamProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, studentId) {
  final supabase = ref.watch(supabaseProvider);
  final now = DateTime.now().toIso8601String();

  return supabase
      .from('lessons')
      .stream(primaryKey: ['id'])
      .eq('student_id', studentId)
      .order('scheduled_at')
      .map((data) {
        return data.where((l) {
          final scheduledAt = l['scheduled_at'] as String?;
          if (scheduledAt == null) return false;
          return scheduledAt.compareTo(now) >= 0;
        }).toList();
      });
});

/// Provides a real-time stream of tasks for a specific student.
final studentTasksStreamProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, studentId) {
  final supabase = ref.watch(supabaseProvider);
  return supabase
      .from('tasks')
      .stream(primaryKey: ['id'])
      .eq('student_id', studentId)
      .order('created_at', ascending: false);
});

/// Provides a real-time stream of subscriptions for a specific student.
final studentSubscriptionsStreamProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, studentId) {
  final supabase = ref.watch(supabaseProvider);
  return supabase
      .from('subscriptions')
      .stream(primaryKey: ['id'])
      .eq('student_id', studentId)
      .order('valid_until', ascending: false);
});
