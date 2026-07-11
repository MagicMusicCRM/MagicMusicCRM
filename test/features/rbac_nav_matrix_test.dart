import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/messenger/presentation/screens/crm_nav_rbac.dart';

/// 6-role RBAC matrix for CRM navigation (KVA-239):
/// client < teacher < admin < manager < director < system_admin.
/// Operational CRM work is shared by admin/manager/director/system_admin;
/// раздел «Финансы» (tab 5) — только director/system_admin (общешкольные
/// финансы отключены у manager/admin); role editing is still enforced
/// separately by backend policy.
void main() {
  group('crmHasManagerAccess — operational CRM access', () {
    test('admin, manager, director and system_admin have operational access',
        () {
      expect(crmHasManagerAccess('manager'), isTrue);
      expect(crmHasManagerAccess('director'), isTrue);
      expect(crmHasManagerAccess('system_admin'), isTrue);
      expect(crmHasManagerAccess('admin'), isTrue);
      expect(crmHasManagerAccess('teacher'), isFalse);
      expect(crmHasManagerAccess('client'), isFalse);
    });
  });

  group('crmHasSchoolFinanceAccess — общешкольные финансы (KVA-239)', () {
    test('только director и system_admin', () {
      expect(crmHasSchoolFinanceAccess('director'), isTrue);
      expect(crmHasSchoolFinanceAccess('system_admin'), isTrue);
      expect(crmHasSchoolFinanceAccess('manager'), isFalse);
      expect(crmHasSchoolFinanceAccess('admin'), isFalse);
      expect(crmHasSchoolFinanceAccess('teacher'), isFalse);
      expect(crmHasSchoolFinanceAccess('client'), isFalse);
    });
  });

  group('crmVisibleTabs — per-role destination matrix', () {
    test('Администратор: operational CRM без раздела «Финансы» (5)', () {
      expect(crmVisibleTabs('admin', isDesktop: true), [0, 1, 2, 3, 4, 6, 7]);
      expect(crmVisibleTabs('admin', isDesktop: false), [0, 1, 2, 3, 4]);
    });

    test('Управляющий: operational CRM без раздела «Финансы» (5)', () {
      expect(crmVisibleTabs('manager', isDesktop: true), [0, 1, 2, 3, 4, 6, 7]);
      expect(crmVisibleTabs('manager', isDesktop: false), [0, 1, 2, 3, 4]);
    });

    test('Директор: полный набор, включая «Финансы» (5)', () {
      expect(
        crmVisibleTabs('director', isDesktop: true),
        [0, 1, 2, 3, 4, 5, 6, 7],
      );
      expect(crmVisibleTabs('director', isDesktop: false), [0, 1, 2, 3, 4]);
    });

    test('Администратор системы == Директор (superuser keeps full access)',
        () {
      expect(
        crmVisibleTabs('system_admin', isDesktop: true),
        crmVisibleTabs('director', isDesktop: true),
      );
      expect(
        crmVisibleTabs('system_admin', isDesktop: false),
        crmVisibleTabs('director', isDesktop: false),
      );
    });

    test('teacher sees 3 destinations (Чат/Расписание/Ученики)', () {
      expect(crmVisibleTabs('teacher', isDesktop: true), [0, 1, 2]);
      expect(crmVisibleTabs('teacher', isDesktop: false), [0, 1, 2]);
    });

    test(
        'operational tabs are visible to admin/manager/director/system_admin '
        'on desktop', () {
      for (final tab in kManagerOnlyCrmTabs) {
        expect(crmVisibleTabs('admin', isDesktop: true), contains(tab));
        expect(crmVisibleTabs('manager', isDesktop: true), contains(tab));
        expect(crmVisibleTabs('director', isDesktop: true), contains(tab));
        expect(crmVisibleTabs('system_admin', isDesktop: true), contains(tab));
      }
    });

    test('«Финансы» (5) скрыт у manager/admin, виден director/system_admin',
        () {
      expect(crmVisibleTabs('manager', isDesktop: true), isNot(contains(5)));
      expect(crmVisibleTabs('admin', isDesktop: true), isNot(contains(5)));
      expect(crmVisibleTabs('director', isDesktop: true), contains(5));
      expect(crmVisibleTabs('system_admin', isDesktop: true), contains(5));
    });
  });
}
