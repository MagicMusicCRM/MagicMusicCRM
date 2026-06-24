import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/manager/presentation/transfer/lead_transfer_controller.dart';

void main() {
  group('LeadTransferController', () {
    late LeadTransferController c;
    final lead = {'id': 'lead-1', 'name': 'Тест', 'phone': '+79990000000'};

    setUp(() {
      c = LeadTransferController();
      addTearDown(c.dispose);
    });

    test('starts idle', () {
      expect(c.phase, LeadTransferPhase.idle);
      expect(c.isActive, isFalse);
      expect(c.leadId, isNull);
    });

    test('startFromLead enters onLeads phase with the lead in hand', () {
      c.startFromLead(lead);
      expect(c.phase, LeadTransferPhase.onLeads);
      expect(c.isActive, isTrue);
      expect(c.leadId, 'lead-1');
    });

    test('setBranches adopts the first branch as the default selection', () {
      c.setBranches([
        {'id': 'b1', 'name': 'Сокол'},
        {'id': 'b2', 'name': 'Спортивная'},
      ]);
      expect(c.selectedBranchId, 'b1');
      expect(c.selectedBranchName, 'Сокол');
    });

    test('enterStudents transitions phase and fires the host hook', () {
      var entered = 0;
      c.configure(onEnterStudents: () => entered++);
      c.setBranches([
        {'id': 'b1', 'name': 'Сокол'},
      ]);
      c.startFromLead(lead);
      c.enterStudents();
      expect(c.phase, LeadTransferPhase.students);
      expect(entered, 1);
      expect(c.selectedBranchId, 'b1');
    });

    test('selectBranch updates selection; «Без филиала» is carried verbatim',
        () {
      c.selectBranch('b2', 'Спортивная');
      expect(c.selectedBranchId, 'b2');
      expect(c.selectedBranchName, 'Спортивная');

      // The sentinel is kept in selectedBranchId so the board can load the
      // no-branch view; it is mapped to a null branch only at commit.
      c.selectBranch(kNoBranchValue, null);
      expect(c.selectedBranchId, kNoBranchValue);
      expect(c.selectedBranchName, 'Без филиала');
    });

    test('a «Без филиала» drop commits with a null branchId', () {
      c.startFromLead(lead);
      c.enterStudents();
      c.selectBranch(kNoBranchValue, null);
      c.debugSetHoverColumn('trial');
      final result = c.resolveDrop();
      expect(result.committed, isTrue);
      expect(result.branchId, isNull);
      expect(result.branchName, 'Без филиала');
      expect(result.columnStatus, 'trial');
    });

    test('resolveDrop cancels unless a column is hovered in the students phase',
        () {
      // No card in hand → cancel.
      expect(c.resolveDrop().committed, isFalse);

      c.startFromLead(lead);
      // Still on leads, even over (a hypothetically) hovered column → cancel.
      c.debugSetHoverColumn('active');
      expect(c.resolveDrop().committed, isFalse);

      // Students phase but no column hovered → cancel.
      c.debugSetPhase(LeadTransferPhase.students);
      c.debugSetHoverColumn(null);
      expect(c.resolveDrop().committed, isFalse);
    });

    test('resolveDrop commits with branch + column when dropped on a column',
        () {
      c.setBranches([
        {'id': 'b2', 'name': 'Спортивная'},
      ]);
      c.startFromLead(lead);
      c.enterStudents();
      c.selectBranch('b2', 'Спортивная');
      c.debugSetHoverColumn('active');

      final result = c.resolveDrop();
      expect(result.committed, isTrue);
      expect(result.branchId, 'b2');
      expect(result.branchName, 'Спортивная');
      expect(result.columnStatus, 'active');
      expect(result.lead?['id'], 'lead-1');
    });

    test('endDrag is idempotent and fires onCommit exactly once', () {
      var commits = 0;
      c.configure(onCommit: (_) => commits++);
      c.setBranches([
        {'id': 'b2', 'name': 'Спортивная'},
      ]);
      c.startFromLead(lead);
      c.enterStudents();
      c.debugSetHoverColumn('active');

      final first = c.endDrag();
      expect(first.committed, isTrue);
      expect(c.phase, LeadTransferPhase.idle);

      // A second end (Draggable fires onDragEnd AND onDraggableCanceled) is a
      // no-op: no extra commit, no phase change.
      final second = c.endDrag();
      expect(second.committed, isFalse);
      expect(commits, 1);
    });

    test('a drop that is not over a column leaves data unchanged (cancel)', () {
      var commits = 0;
      c.configure(onCommit: (_) => commits++);
      c.startFromLead(lead);
      c.enterStudents();
      // pointer released over no column
      final result = c.endDrag();
      expect(result.committed, isFalse);
      expect(commits, 0);
      expect(c.phase, LeadTransferPhase.idle);
    });

    test('hidden lead ids are tracked for optimistic removal + undo', () {
      c.addHiddenLead('lead-1');
      expect(c.hiddenLeadIds.contains('lead-1'), isTrue);
      c.removeHiddenLead('lead-1');
      expect(c.hiddenLeadIds.contains('lead-1'), isFalse);
    });

    test('cancel resets the flow to idle without a commit', () {
      var commits = 0;
      c.configure(onCommit: (_) => commits++);
      c.startFromLead(lead);
      c.enterStudents();
      c.debugSetHoverColumn('active');
      c.cancel();
      expect(c.phase, LeadTransferPhase.idle);
      expect(c.leadId, isNull);
      expect(commits, 0);
    });
  });
}
