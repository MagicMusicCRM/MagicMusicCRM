import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/crm_nav_rbac.dart';

/// 6-role RBAC matrix for CRM navigation (KVA-239):
/// client < teacher < admin < manager < director < system_admin.
/// Operational CRM work is shared by admin/manager/director/system_admin;
/// Общешкольные финансовые операции доступны только director/system_admin,
/// но v7 показывает их внутри единой «Аналитики» (tab 7), а не отдельным
/// пунктом навигации.
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
    test('client has no CRM shell destinations', () {
      expect(crmVisibleTabs('client', isDesktop: true), isEmpty);
      expect(crmVisibleTabs('client', isDesktop: false), isEmpty);
    });

    test('Администратор: Чат, Расписание, Клиенты и Задачи', () {
      expect(crmVisibleTabs('admin', isDesktop: true), [0, 2, 3, 6]);
      expect(crmVisibleTabs('admin', isDesktop: false), [0, 2, 3, 6]);
    });

    test('Управляющий: operational CRM без раздела «Финансы» (5)', () {
      expect(crmVisibleTabs('manager', isDesktop: true), [0, 1, 2, 3, 6, 7, 8]);
      expect(crmVisibleTabs('manager', isDesktop: false), [
        0,
        1,
        2,
        3,
        6,
        7,
        8,
      ]);
    });

    test('Директор: единая «Аналитика» без дублирующей вкладки 5', () {
      expect(crmVisibleTabs('director', isDesktop: true), [
        0,
        1,
        2,
        3,
        6,
        7,
        8,
      ]);
      expect(crmVisibleTabs('director', isDesktop: false), [
        0,
        1,
        2,
        3,
        6,
        7,
        8,
      ]);
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

    test('«Задачи» (6) доступны admin+ на телефоне', () {
      for (final role in ['admin', 'manager', 'director', 'system_admin']) {
        expect(
          crmVisibleTabs(role, isDesktop: false),
          contains(6),
          reason: '$role must be able to operate tasks on mobile',
        );
      }
      expect(crmVisibleTabs('teacher', isDesktop: false), isNot(contains(6)));
    });

    test('управленческие вкладки скрыты у admin на любой ширине', () {
      expect(crmVisibleTabs('admin', isDesktop: true), isNot(contains(1)));
      expect(crmVisibleTabs('admin', isDesktop: false), isNot(contains(1)));
      expect(crmVisibleTabs('admin', isDesktop: true), contains(6));
      expect(crmVisibleTabs('admin', isDesktop: false), contains(6));
    });

    test('legacy «Финансы» (5) не дублирует «Аналитику» в навигации', () {
      for (final role in ['admin', 'manager', 'director', 'system_admin']) {
        expect(crmVisibleTabs(role, isDesktop: true), isNot(contains(5)));
      }
    });

    test('Пользователи (4) собраны в единственные Настройки (8)', () {
      final visible = crmVisibleTabs('director', isDesktop: true);
      expect(visible, isNot(contains(4)));
      expect(visible, contains(8));
      expect(
        crmResolveVisibleTab(
          visibleTabs: visible,
          requestedTab: 4,
          currentTab: 0,
        ),
        8,
      );
    });
  });

  group('crmResolveVisibleTab — canonical deep-link membership', () {
    test('старый desktop deep link «Финансы» открывает «Аналитику»', () {
      final visible = crmVisibleTabs('director', isDesktop: true);
      expect(
        crmResolveVisibleTab(
          visibleTabs: visible,
          requestedTab: 5,
          currentTab: 0,
        ),
        7,
      );
    });
    test('manager mobile opens Tasks and Analytics without school finance', () {
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
        7,
      );
      expect(
        crmResolveVisibleTab(
          visibleTabs: visible,
          requestedTab: 7,
          currentTab: 1,
        ),
        7,
      );
    });

    test('sparse admin tabs accept tasks and reject hidden settings', () {
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
          currentTab: 2,
        ),
        2,
      );
    });
  });
}
