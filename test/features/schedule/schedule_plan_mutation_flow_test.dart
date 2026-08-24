import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/crm/presentation/client_card/schedule_plan_mutation_flow.dart';

void main() {
  test('mutation flow exposes typed outcome and deterministic slot times', () {
    expect(
      SchedulePlanMutationFlow.slotTime(
        beginTime: '09:15',
        durationMinutes: 45,
        slot: 2,
      ),
      '10:45',
    );
    expect(
      SchedulePlanMutationResult.values,
      containsAll([
        SchedulePlanMutationResult.committed,
        SchedulePlanMutationResult.cancelled,
      ]),
    );
  });
}
