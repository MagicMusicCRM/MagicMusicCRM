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
    test(
      'admin, manager, director and system_admin have operational access',
      () {
        expect(crmHasManagerAccess('manager'), isTrue);
        expect(crmHasManagerAccess('director'), isTrue);
        expect(crmHasManagerAccess('system_admin'), isTrue);
        expect(crmHasManagerAccess('admin'), isTrue);
        expect(crmHasManagerAccess('teacher'), isFalse);
        expect(crmHasManagerAccess('client'), isFalse);
      },
    );
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

  group('subscription package catalog RBAC (v4 T5.2.1)', () {
    test('active read is available only to issuing staff', () {
      for (final role in ['admin', 'manager', 'director', 'system_admin']) {
        expect(crmCanReadSubscriptionPackages(role), isTrue, reason: role);
      }
      for (final role in ['client', 'teacher']) {
        expect(crmCanReadSubscriptionPackages(role), isFalse, reason: role);
      }
    });

    test('catalog mutation is Director/system_admin only', () {
      for (final role in ['director', 'system_admin']) {
        expect(crmCanManageSubscriptionPackages(role), isTrue, reason: role);
      }
      for (final role in ['client', 'teacher', 'admin', 'manager']) {
        expect(crmCanManageSubscriptionPackages(role), isFalse, reason: role);
      }
    });
  });

  group('crmHasTeacherRatesAccess — поразрезные финансы (решение 16.07)', () {
    test('ставки педагогов видят и админ, и управляющий', () {
      // Ставка за занятие — не обще-суммарная сводка, поэтому граница шире,
      // чем у crmHasSchoolFinanceAccess.
      expect(crmHasTeacherRatesAccess('director'), isTrue);
      expect(crmHasTeacherRatesAccess('system_admin'), isTrue);
      expect(crmHasTeacherRatesAccess('manager'), isTrue);
      expect(crmHasTeacherRatesAccess('admin'), isTrue);
    });

    test('но не педагог и не клиент', () {
      expect(crmHasTeacherRatesAccess('teacher'), isFalse);
      expect(crmHasTeacherRatesAccess('client'), isFalse);
    });

    test('шире общешкольных финансов, но у́же операционного доступа', () {
      // Именно эта разница и есть суть решения: раньше ставки приравнивались
      // к общешкольным финансам, и управляющий мог массово менять ставки, но
      // не мог открыть отчёт, из которого это делается.
      for (final role in ['admin', 'manager']) {
        expect(crmHasSchoolFinanceAccess(role), isFalse);
        expect(crmHasTeacherRatesAccess(role), isTrue);
      }
      expect(crmHasManagerAccess('teacher'), isFalse);
      expect(crmHasTeacherRatesAccess('teacher'), isFalse);
    });
  });

  group('crmVisibleTabs — per-role destination matrix', () {
    test('Администратор (#17): «Задачи» (6) вместо «Обзора» (1) сразу после '
        'Чата, без лишних разделов', () {
      expect(crmVisibleTabs('admin', isDesktop: true), [0, 6, 2, 3]);
      expect(crmVisibleTabs('admin', isDesktop: false), [0, 6, 2, 3]);
    });

    test('Управляющий: operational CRM без раздела «Финансы» (5)', () {
      expect(crmVisibleTabs('manager', isDesktop: true), [0, 1, 2, 3, 4, 6, 7]);
      expect(crmVisibleTabs('manager', isDesktop: false), [0, 1, 2, 3, 4, 6]);
    });

    test('Директор: полный набор, включая «Финансы» (5)', () {
      expect(crmVisibleTabs('director', isDesktop: true), [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      ]);
      expect(crmVisibleTabs('director', isDesktop: false), [0, 1, 2, 3, 4, 6]);
    });

    test('Администратор системы == Директор (superuser keeps full access)', () {
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
      'manager-tier operational tabs are visible to manager+ on desktop',
      () {
        for (final tab in kManagerOnlyCrmTabs) {
          expect(crmVisibleTabs('manager', isDesktop: true), contains(tab));
          expect(crmVisibleTabs('director', isDesktop: true), contains(tab));
          expect(
            crmVisibleTabs('system_admin', isDesktop: true),
            contains(tab),
          );
        }
      },
    );

    test('«Задачи» (6) доступны admin и manager+ на телефоне', () {
      for (final role in ['admin', 'manager', 'director', 'system_admin']) {
        expect(
          crmVisibleTabs(role, isDesktop: false),
          contains(6),
          reason: '$role must be able to operate tasks on mobile',
        );
      }
      expect(crmVisibleTabs('teacher', isDesktop: false), isNot(contains(6)));
    });

    test('«Обзор» (1) скрыт у admin на любой ширине, «Задачи» (6) видны', () {
      expect(crmVisibleTabs('admin', isDesktop: true), isNot(contains(1)));
      expect(crmVisibleTabs('admin', isDesktop: false), isNot(contains(1)));
      expect(crmVisibleTabs('admin', isDesktop: true), contains(6));
      expect(crmVisibleTabs('admin', isDesktop: false), contains(6));
    });

    test(
      '«Финансы» (5) скрыт у manager/admin, виден director/system_admin',
      () {
        expect(crmVisibleTabs('manager', isDesktop: true), isNot(contains(5)));
        expect(crmVisibleTabs('admin', isDesktop: true), isNot(contains(5)));
        expect(crmVisibleTabs('director', isDesktop: true), contains(5));
        expect(crmVisibleTabs('system_admin', isDesktop: true), contains(5));
      },
    );
  });

  group('crmResolveVisibleTab — canonical deep-link membership', () {
    test(
      'manager mobile opens Tasks and keeps Overview for hidden Finance',
      () {
        final visible = crmVisibleTabs('manager', isDesktop: false);
        expect(
          crmResolveVisibleTab(
            visibleTabs: visible,
            requestedTab: 6,
            currentTab: 1,
          ),
          6,
        );
        expect(
          crmResolveVisibleTab(
            visibleTabs: visible,
            requestedTab: 5,
            currentTab: 1,
          ),
          1,
        );
        expect(
          crmResolveVisibleTab(
            visibleTabs: visible,
            requestedTab: 7,
            currentTab: 1,
          ),
          1,
        );
      },
    );

    test('sparse admin tabs do not numerically clamp Tasks to Clients', () {
      final visible = crmVisibleTabs('admin', isDesktop: false);
      expect(
        crmResolveVisibleTab(
          visibleTabs: visible,
          requestedTab: 6,
          currentTab: 0,
        ),
        6,
      );
      expect(
        crmResolveVisibleTab(
          visibleTabs: visible,
          requestedTab: 4,
          currentTab: 6,
        ),
        6,
      );
    });
  });
}
