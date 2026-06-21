import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/crm_nav_rbac.dart';

/// 5-role RBAC matrix for CRM navigation (KVA-194 / P1-2, plan §5d).
/// Locks the A1 hierarchy: Управляющий (`manager`) > Администратор (`admin`),
/// with the superuser `system_admin` retaining full access.
void main() {
  group('crmHasManagerAccess — A1 manager tier', () {
    test('manager and system_admin have manager access; admin does NOT', () {
      expect(crmHasManagerAccess('manager'), isTrue);
      expect(crmHasManagerAccess('system_admin'), isTrue);
      expect(crmHasManagerAccess('admin'), isFalse, reason: 'A1: admin < manager');
      expect(crmHasManagerAccess('teacher'), isFalse);
      expect(crmHasManagerAccess('client'), isFalse);
    });
  });

  group('crmVisibleTabs — per-role destination matrix', () {
    test('Администратор sees ONLY Чат/Расписание/Клиенты (0,2,3)', () {
      const expected = [0, 2, 3];
      expect(crmVisibleTabs('admin', isDesktop: true), expected);
      expect(crmVisibleTabs('admin', isDesktop: false), expected);
      // Never any manager-only destination.
      for (final tab in kManagerOnlyCrmTabs) {
        expect(
          crmVisibleTabs('admin', isDesktop: true),
          isNot(contains(tab)),
          reason: 'admin must not reach manager-only tab $tab',
        );
      }
    });

    test('Управляющий sees the full set (desktop 0..7, mobile 0..4)', () {
      expect(crmVisibleTabs('manager', isDesktop: true), [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(crmVisibleTabs('manager', isDesktop: false), [0, 1, 2, 3, 4]);
    });

    test('Администратор системы == Управляющий (superuser keeps full access)', () {
      expect(
        crmVisibleTabs('system_admin', isDesktop: true),
        crmVisibleTabs('manager', isDesktop: true),
      );
      expect(
        crmVisibleTabs('system_admin', isDesktop: false),
        crmVisibleTabs('manager', isDesktop: false),
      );
    });

    test('teacher sees 3 destinations (Чат/Расписание/Ученики)', () {
      expect(crmVisibleTabs('teacher', isDesktop: true), [0, 1, 2]);
      expect(crmVisibleTabs('teacher', isDesktop: false), [0, 1, 2]);
    });

    test('every manager-only tab is visible to manager/system_admin but not admin', () {
      for (final tab in kManagerOnlyCrmTabs) {
        expect(crmVisibleTabs('manager', isDesktop: true), contains(tab));
        expect(crmVisibleTabs('system_admin', isDesktop: true), contains(tab));
        expect(crmVisibleTabs('admin', isDesktop: true), isNot(contains(tab)));
      }
    });
  });
}
