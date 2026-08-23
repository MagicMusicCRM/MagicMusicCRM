import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider lives in the legacy export under Riverpod 3.x; it backs the
// portal's per-child switcher selection (selectedStudentIdProvider, KVA-156).
import 'package:flutter_riverpod/legacy.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/models/commerce_projection.dart';
import 'package:magic_music_crm/core/models/client_internal_context.dart';
import 'package:magic_music_crm/core/models/payment.dart';
import 'package:magic_music_crm/core/models/schedule_plan.dart';
import 'package:magic_music_crm/core/models/student_funnel.dart';

part 'magic_crm_service_core.dart';
part 'magic_crm_service_org.dart';
part 'magic_crm_service_leads.dart';
part 'magic_crm_service_schedule.dart';
part 'magic_crm_service_finance.dart';
part 'magic_crm_service_legacy_map_adapter.dart';

final magicCrmServiceProvider = Provider<MagicCrmService>((ref) {
  return MagicCrmService(ref.watch(magicApiClientProvider));
});

/// All students linked to the signed-in account, sourced from `/crm/me`.
/// A parent with two or more children sees every linked student here so the
/// client portal can offer a per-child switcher (KVA-156).
final myStudentsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.watch(magicCrmServiceProvider).listMyStudents();
});

/// Single read-only source for the Client portal's subscription, payment and
/// balance surfaces. It is deliberately separate from `/crm/me` so the base
/// identity projection never acquires finance fields.
final myCommerceProjectionProvider = FutureProvider<ClientCommerceProjection>((
  ref,
) {
  return ref.watch(magicCrmServiceProvider).getMyCommerceProjection();
});

/// The student the parent has explicitly picked in the portal switcher.
/// `null` means "no manual selection" — consumers then fall back to the first
/// linked student, preserving the single-student behaviour (KVA-156).
final selectedStudentIdProvider = StateProvider<String?>((ref) => null);

/// The student currently in focus across the client portal. Derived so that
/// existing widgets keep working untouched: it honours an explicit selection
/// from [selectedStudentIdProvider] when that id still belongs to the linked
/// students, otherwise it falls back to the first linked student.
final magicCurrentStudentIdProvider = FutureProvider<String?>((ref) async {
  final students = await ref.watch(myStudentsProvider.future);
  if (students.isEmpty) return null;

  final selectedId = ref.watch(selectedStudentIdProvider);
  if (selectedId != null &&
      students.any((s) => s['id']?.toString() == selectedId)) {
    return selectedId;
  }
  return students.first['id']?.toString();
});

class MagicCrmService {
  final MagicApiClient _api;

  const MagicCrmService(this._api);
}
