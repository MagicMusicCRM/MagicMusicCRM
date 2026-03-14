import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AutoInvoicingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Generates expected payments for all students in a group for a specific month/year.
  Future<void> generateInvoicesForGroup(String groupId, int month, int year) async {
    // 1. Fetch group details (price per lesson)
    final groupRes = await _supabase.from('groups').select('name, price_per_lesson').eq('id', groupId).single();
    final double pricePerLesson = (groupRes['price_per_lesson'] as num).toDouble();
    final String groupName = groupRes['name'];

    // 2. Fetch all students in the group
    final studentsRes = await _supabase.from('group_students').select('student_id').eq('group_id', groupId);
    final studentIds = List<String>.from(studentsRes.map((s) => s['student_id']));

    // 3. Fetch all scheduled lessons for this group in the target month
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 1).subtract(const Duration(seconds: 1));

    final lessonsRes = await _supabase
        .from('lessons')
        .select('id, student_id')
        .eq('group_id', groupId)
        .gte('scheduled_at', startOfMonth.toIso8601String())
        .lte('scheduled_at', endOfMonth.toIso8601String());

    final lessons = List<Map<String, dynamic>>.from(lessonsRes);

    // 4. Create invoices (one per student for the whole month)
    for (final studentId in studentIds) {
      // Calculate amount based on lesson count for this student in this group
      // If it's a group lesson, usually scheduled for the group, but we check if student is assigned
      final studentLessonCount = lessons.length; // Simplified: assumes all group members attend all group lessons
      
      if (studentLessonCount == 0) continue;

      final double totalAmount = studentLessonCount * pricePerLesson;

      await _supabase.from('expected_payments').insert({
        'student_id': studentId,
        'group_id': groupId,
        'amount': totalAmount,
        'due_date': startOfMonth.toIso8601String(), // Due at start of month
        'status': 'pending',
        'description': 'Оплата за $groupName (${DateFormat('MMMM yyyy', 'ru').format(startOfMonth)})',
      });
    }
  }
}

// Note: DateFormat requires intl package and initialization.
