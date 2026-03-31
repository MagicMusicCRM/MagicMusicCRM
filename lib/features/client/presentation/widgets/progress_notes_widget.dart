import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

final progressNotesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  final studentRes = await supabase
      .from('students')
      .select('id')
      .eq('profile_id', user.id)
      .maybeSingle();
  if (studentRes == null) return [];

  final notes = await supabase
      .from('entity_comments')
      .select('*, profiles(first_name, last_name)')
      .eq('entity_id', studentRes['id'])
      .eq('entity_type', 'student')
      .like('content', '[PROGRESS]%')
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(notes);
});

class ProgressNotesWidget extends ConsumerWidget {
  const ProgressNotesWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(progressNotesProvider);

    return notesAsync.when(
      loading: () => Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple)),
      error: (err, _) => Center(child: Text('Ошибка загрузки: $err', style: const TextStyle(color: AppTheme.danger))),
      data: (notes) {
        if (notes.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'Заметок об успехах пока нет. Продолжайте заниматься!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: notes.length,
          itemBuilder: (context, index) {
            final note = notes[index];
            final content = (note['content'] as String).replaceFirst('[PROGRESS] ', '');
            final dt = DateTime.tryParse(note['created_at'] ?? '');
            final dateStr = dt != null ? DateFormat('d MMMM yyyy', 'ru').format(dt.toLocal()) : '';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.success.withAlpha(15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.success.withAlpha(40)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.stars_rounded, color: AppTheme.success, size: 20),
                      SizedBox(width: 8),
                      Text(dateStr, style: TextStyle(color: Theme.of(context!).colorScheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    content,
                    style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
