import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:magic_music_crm/features/manager/data/services/supa_lead_service.dart';

/// Provider for the SupaLeadService
final supaLeadServiceProvider = Provider<SupaLeadService>((ref) {
  final client = Supabase.instance.client;
  return SupaLeadService(client);
});

/// StreamProvider for leads
final leadsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final service = ref.watch(supaLeadServiceProvider);
  return service.getLeadsStream();
});

/// FutureProvider for lead statuses
final leadStatusesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final service = ref.watch(supaLeadServiceProvider);
  return service.getStatuses();
});
