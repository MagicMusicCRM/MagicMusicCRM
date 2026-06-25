import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/crm_nav_rbac.dart';

/// 5-role RBAC matrix for CRM navigation.
/// Operational CRM work is shared by admin/manager/system_admin; role editing is
/// still enforced separately by backend policy.
void main() {
  group('crmHasManagerAccess — operational CRM access', () {
    test('admin, manager and system_admin have operational access', () {
      expect(crmHasManagerAccess('manager'), isTrue);
      expect(crmHasManagerAccess('system_admin'), isTrue);
      expect(crmHasManagerAccess('admin'), isTrue);
      expect(crmHasManagerAccess('teacher'), isFalse);
      expect(crmHasManagerAccess('client'), isFalse);
    });
  });

  group('crmVisibleTabs — per-role destination matrix', () {
    test('Администратор sees operational CRM sections', () {
      expect(crmVisibleTabs('admin', isDesktop: true), [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(crmVisibleTabs('admin', isDesktop: false), [0, 1, 2, 3, 4]);
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

    test('operational tabs are visible to admin/manager/system_admin on desktop', () {
      for (final tab in kManagerOnlyCrmTabs) {
        expect(crmVisibleTabs('admin', isDesktop: true), contains(tab));
        expect(crmVisibleTabs('manager', isDesktop: true), contains(tab));
        expect(crmVisibleTabs('system_admin', isDesktop: true), contains(tab));
      }
    });
  });
}
