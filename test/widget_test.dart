import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readProjectFile(String path) => File(path).readAsStringSync();

void main() {
  group('release metadata', () {
    test('Android package, label, and release signing gate are configured', () {
      final gradle = readProjectFile('android/app/build.gradle.kts');
      final manifest = readProjectFile(
        'android/app/src/main/AndroidManifest.xml',
      );

      expect(gradle, contains('applicationId = "magic.crm"'));
      expect(gradle, contains('Release signing is not configured'));
      expect(
        gradle,
        isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
      );
      expect(manifest, contains('android:label="Magic Music CRM"'));
      expect(manifest, contains('android.permission.INTERNET'));
      expect(
        manifest,
        contains(
          'android.permission.READ_EXTERNAL_STORAGE" tools:node="remove"',
        ),
      );
      expect(
        manifest,
        contains('android.permission.READ_MEDIA_IMAGES" tools:node="remove"'),
      );
      expect(
        manifest,
        contains('android.permission.READ_MEDIA_VIDEO" tools:node="remove"'),
      );
      expect(
        manifest,
        contains('android.permission.READ_MEDIA_AUDIO" tools:node="remove"'),
      );
      expect(
        manifest,
        isNot(contains('android.permission.WRITE_EXTERNAL_STORAGE')),
      );
    });

    test('Firebase app identifiers match immutable mobile package ids', () {
      final googleServices =
          jsonDecode(readProjectFile('android/app/google-services.json'))
              as Map<String, dynamic>;
      final androidClient = (googleServices['client'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((client) {
            final clientInfo = client['client_info'] as Map<String, dynamic>;
            final androidInfo =
                clientInfo['android_client_info'] as Map<String, dynamic>;
            return androidInfo['package_name'] == 'magic.crm';
          });
      final androidInfo = androidClient['client_info'] as Map<String, dynamic>;
      final androidPackage =
          androidInfo['android_client_info'] as Map<String, dynamic>;
      final iosPlist = readProjectFile('ios/Runner/GoogleService-Info.plist');

      expect(androidPackage['package_name'], 'magic.crm');
      expect(
        androidClient['oauth_client'].toString(),
        contains('1038036512599-vg813c70pl4qjv7kmtse94mgkorfatg6'),
      );
      expect(iosPlist, contains('<key>BUNDLE_ID</key>'));
      expect(iosPlist, contains('<string>magic.crm</string>'));
    });

    test('v3 API uses the owned Selectel backend host', () {
      final env = readProjectFile('lib/core/constants/env.dart');

      expect(env, contains('https://api.phantom-net.ru/api'));
      expect(env, isNot(contains('workers.dev')));
    });

    test(
      'integration smoke covers launch and deletion gates without secrets',
      () {
        final pubspec = readProjectFile('pubspec.yaml');
        final smoke = readProjectFile(
          'integration_test/app_launch_smoke_test.dart',
        );
        final runbook = readProjectFile(
          'docs/runbooks/flutter-integration-smoke.md',
        );

        expect(pubspec, contains('integration_test:'));
        expect(
          smoke,
          contains('IntegrationTestWidgetsFlutterBinding.ensureInitialized'),
        );
        expect(smoke, contains('MemoryMagicTokenStore()'));
        expect(smoke, contains('_NoopNotificationService'));
        expect(smoke, contains('Войдите в систему'));
        expect(smoke, contains('Введите корректную почту'));
        expect(smoke, contains('_accountDeletionSmokeRouter'));
        expect(smoke, contains("initialLocation: '/delete-account'"));
        expect(smoke, contains('_FakeReleaseGateService'));
        expect(smoke, contains('Отправить запрос'));
        expect(smoke, contains('Запрос принят'));
        expect(
          runbook,
          contains(r'flutter test integration_test\app_launch_smoke_test.dart'),
        );
        expect(runbook, contains('account deletion form'));
        expect(runbook, contains('private file upload/download'));
        expect(smoke, isNot(contains('HOLLIHOP_AUTH_KEY')));
        expect(smoke, isNot(contains('MIGRATION_DATABASE_URL')));
      },
    );

    test('Android real-device smoke runbook covers remaining INT-S6 gates', () {
      final runbook = readProjectFile(
        'docs/runbooks/android-real-device-smoke.md',
      );
      final helper = readProjectFile('scripts/android_real_device_smoke.ps1');

      expect(runbook, contains('flutter devices'));
      expect(runbook, contains(r'.\scripts\android_real_device_smoke.ps1'));
      expect(
        runbook,
        contains('MAGIC_API_BASE_URL=https://api.phantom-net.ru/api'),
      );
      expect(runbook, contains('Private files'));
      expect(runbook, contains('Account deletion'));
      expect(runbook, contains('Запрос принят'));
      expect(runbook, contains('lead saved presets'));
      expect(runbook, contains('task timeline/add-history'));
      expect(
        runbook,
        contains('no `FATAL EXCEPTION`, `FlutterError` or `Dart Error`'),
      );
      expect(runbook, contains('Cleanup'));
      expect(runbook, isNot(contains('HOLLIHOP_AUTH_KEY=')));
      expect(runbook, isNot(contains('MIGRATION_DATABASE_URL=')));
      expect(helper, contains(r'[switch]$CheckOnly'));
      expect(helper, contains('No physical Android device is connected'));
      expect(helper, contains('flutter", "build", "apk"'));
      expect(helper, contains('flutter", "install"'));
      expect(helper, contains('app_launch_smoke_test.dart'));
      expect(helper, contains('logcat -d'));
      expect(helper, contains('FATAL EXCEPTION|FlutterError|Dart Error'));
      expect(helper, isNot(contains('HOLLIHOP_AUTH_KEY=')));
      expect(helper, isNot(contains('MIGRATION_DATABASE_URL=')));
    });

    test('HolliHop staging dry-run helper is backup-gated and non-apply', () {
      final runbook = readProjectFile(
        'docs/runbooks/hollihop-staging-dry-run.md',
      );
      final helper = readProjectFile('scripts/hollihop_staging_dry_run.ps1');
      final importerDoc = readProjectFile(
        'docs/import/hollihop_importer_v2.md',
      );

      expect(runbook, contains(r'.\scripts\hollihop_staging_dry_run.ps1'));
      expect(runbook, contains('BackupEvidencePath'));
      expect(runbook, contains('db:migrate'));
      expect(runbook, contains('HOLLIHOP_IMPORT_MODE'));
      expect(runbook, contains('dry_run'));
      expect(runbook, contains('reviewed dry-run report'));
      expect(helper, contains(r'[switch]$CheckOnly'));
      expect(helper, contains(r'[string[]]$EnvFiles'));
      expect(helper, contains(r'[switch]$NoEnvFiles'));
      expect(helper, contains('server/.env'));
      expect(helper, contains('infra/staging/.env'));
      expect(helper, contains('infra/staging/.backup.env'));
      expect(helper, contains('Env file loaded'));
      expect(helper, contains('BackupEvidencePath is required'));
      expect(helper, contains('HOLLIHOP_IMPORT_MODE'));
      expect(helper, contains('dry_run'));
      expect(helper, contains('hollihop:import'));
      expect(helper, contains('--dry-run'));
      expect(helper, contains('HOLLIHOP_IMPORT_REPORT_DIR'));
      expect(helper, contains('MIGRATION_DATABASE_URL or DATABASE_URL'));
      expect(runbook, contains('-NoEnvFiles'));
      expect(runbook, contains('process values as the higher priority source'));
      expect(
        helper,
        contains('Refusing to continue while HOLLIHOP_IMPORT_MODE=apply'),
      );
      expect(helper, contains('postgres(?:ql)?://'));
      expect(helper, isNot(contains('HOLLIHOP_AUTH_KEY=')));
      expect(helper, isNot(contains('MIGRATION_DATABASE_URL=')));
      expect(runbook, isNot(contains('HOLLIHOP_AUTH_KEY=')));
      expect(runbook, isNot(contains('MIGRATION_DATABASE_URL=')));
      expect(importerDoc, contains('hollihop_staging_dry_run.ps1'));
    });

    test('email OTP UI is locked to 6 numeric digits', () {
      final otpScreen = readProjectFile(
        'lib/features/auth/presentation/screens/email_otp_screen.dart',
      );
      final loginScreen = readProjectFile(
        'lib/features/auth/presentation/screens/login_screen.dart',
      );

      expect(otpScreen, contains('const int emailOtpCodeLength = 6'));
      expect(otpScreen, contains('FilteringTextInputFormatter.digitsOnly'));
      expect(otpScreen, contains("hintText: '000000'"));
      expect(otpScreen, isNot(contains("hintText: '00000000'")));
      expect(loginScreen, isNot(contains('Войти без пароля по email-коду')));
      expect(loginScreen, isNot(contains('EmailOtpPurpose.passwordlessLogin')));
    });

    test('Google auth is removed from Flutter runtime', () {
      final authService = readProjectFile(
        'lib/features/auth/data/services/magic_auth_service.dart',
      );
      final loginScreen = readProjectFile(
        'lib/features/auth/presentation/screens/login_screen.dart',
      );
      final registrationScreen = readProjectFile(
        'lib/features/auth/presentation/screens/registration_screen.dart',
      );
      final authMethodsScreen = readProjectFile(
        'lib/features/profile/presentation/screens/auth_methods_screen.dart',
      );
      final pubspec = readProjectFile('pubspec.yaml');

      expect(authService, isNot(contains('/auth/google')));
      expect(authService, isNot(contains('signInWithGoogle')));
      expect(authService, isNot(contains('linkGoogleIdentity')));
      expect(loginScreen, isNot(contains('Google')));
      expect(registrationScreen, isNot(contains('Google')));
      expect(authMethodsScreen, isNot(contains('Google')));
      expect(pubspec, isNot(contains('google_sign_in')));
      expect(pubspec, isNot(contains('app_links')));
    });

    test('v3 file API owns uploads and short-lived downloads', () {
      final attachmentService = readProjectFile(
        'lib/core/services/chat_attachment_service.dart',
      );
      final avatarWidget = readProjectFile(
        'lib/core/widgets/telegram/avatar_widget.dart',
      );
      final env = readProjectFile('lib/core/constants/env.dart');

      expect(attachmentService, contains("'/files'"));
      expect(attachmentService, contains(r"'/files/$value'"));
      expect(attachmentService, contains(r"'/files/$fileId/download-token'"));
      expect(attachmentService, contains(r"'files/download/$token'"));
      expect(attachmentService, contains('_inFlightResolveUrls'));
      expect(attachmentService, contains("purpose: 'chat_attachment'"));
      expect(attachmentService, contains("purpose: 'chat_voice'"));
      expect(attachmentService, contains("purpose: 'profile_avatar'"));
      expect(attachmentService, contains('storage://'));
      expect(
        attachmentService,
        contains('Legacy Supabase storage references are ignored'),
      );
      expect(env, isNot(contains("'LEGACY_SUPABASE_URL'")));
      expect(env, isNot(contains("'LEGACY_SUPABASE_ANON_KEY'")));
      expect(attachmentService, isNot(contains('xblpnywnlhfgofskbdxb')));
      expect(attachmentService, isNot(contains('normalizeSupabaseUrl')));
      expect(avatarWidget, contains('ChatAttachmentService.resolveUrl'));
    });

    test('store legal artifacts include privacy, terms, and deletion URLs', () {
      final privacy = readProjectFile('release-site/privacy/index.html');
      final terms = readProjectFile('release-site/terms/index.html');
      final deletion = readProjectFile(
        'release-site/account-deletion/index.html',
      );
      final playStatus = readProjectFile(
        'docs/release/google_play_console_status.md',
      );

      expect(privacy, contains('Политика конфиденциальности'));
      expect(terms, contains('Условия использования'));
      expect(deletion, contains('Удаление аккаунта'));
      expect(
        playStatus,
        contains('https://magicmusiccrm-legal.vercel.app/privacy/'),
      );
      expect(
        playStatus,
        contains('https://magicmusiccrm-legal.vercel.app/account-deletion/'),
      );
    });

    test('Flutter runtime does not depend on Supabase SDK', () {
      final pubspec = readProjectFile('pubspec.yaml');
      final main = readProjectFile('lib/main.dart');
      final securityGate = readProjectFile(
        'server/src/security/security-gate.ts',
      );

      expect(pubspec, isNot(contains('supabase_flutter:')));
      expect(main, isNot(contains('Supabase.initialize')));
      expect(main, isNot(contains('supabase_flutter')));
      expect(
        securityGate,
        contains('pubspec.yaml still depends on supabase_flutter runtime'),
      );
      expect(
        securityGate,
        contains('main.dart still initializes or imports Supabase runtime'),
      );
    });

    test('push token sync retries after v3 auth session appears', () {
      final main = readProjectFile('lib/main.dart');
      final notificationService = readProjectFile(
        'lib/core/services/notification_service.dart',
      );
      final notificationsApi = readProjectFile(
        'lib/core/services/magic_notifications_service.dart',
      );

      expect(main, contains('ref.listen(magicAuthStateProvider'));
      expect(main, contains('syncCurrentDeviceToken()'));
      expect(
        notificationService,
        contains('Future<void> syncCurrentDeviceToken()'),
      );
      expect(
        notificationService,
        contains('magicNotificationsServiceProvider'),
      );
      expect(notificationService, contains('registerDevice(token: token'));
      expect(notificationsApi, contains("'/notifications/devices'"));
    });

    test('router keeps branded loading visible while auth or gate loads', () {
      final router = readProjectFile('lib/core/router/app_router.dart');

      expect(router, contains('ref.watch(magicAuthStateProvider)'));
      expect(router, contains('ref.watch(releaseGateStatusProvider)'));
      expect(router, contains('ref.listen<AsyncValue<MagicAuthSession?>>'));
      expect(router, contains('ref.listen<_RouteGateState>'));
      expect(router, contains('ref.read(_routeGateStateProvider)'));
      expect(router, contains('refreshListenable: routerRefreshNotifier'));
      expect(router, contains('ref.invalidate(releaseGateStatusProvider)'));
      expect(router, contains('previousAccessToken != nextAccessToken'));
      expect(router, contains('case _RouteGatePhase.gateError'));
      expect(router, contains('Не удалось проверить доступ'));
      expect(router, contains('Повторить'));
      expect(router, contains("return loc == '/' ? null : '/'"));
      expect(router, contains('const _AppGateLoadingScreen()'));
      expect(router, contains('Проверяем сессию и доступ'));
      expect(router, isNot(contains('redirect: (context, state) async')));
      expect(router, isNot(contains('await _fetchGateStatus')));
      expect(router, isNot(contains('await _fetchRole')));
      expect(router, isNot(contains('refreshListenable: authNotifier')));
      expect(
        router,
        isNot(
          contains(
            'final authState = ref.watch(magicAuthStateProvider);\n'
            '  final AsyncValue<ReleaseGateStatus>? gateState',
          ),
        ),
      );
    });

    test('HolliHop access is backend-only from Flutter runtime', () {
      final env = readProjectFile('lib/core/constants/env.dart');
      final hollihopService = readProjectFile(
        'lib/core/services/hollihop_service.dart',
      );
      final securityGate = readProjectFile(
        'server/src/security/security-gate.ts',
      );

      expect(env, isNot(contains('HOLLIHOP_AUTH_KEY')));
      expect(hollihopService, contains("'/crm/hollihop/disciplines'"));
      expect(hollihopService, contains("'/crm/hollihop/levels'"));
      expect(hollihopService, contains("'/crm/hollihop/lead-statuses'"));
      expect(hollihopService, isNot(contains('https://sokol.t8s.ru')));
      expect(
        securityGate,
        contains('HolliHop secrets are not loaded by Flutter'),
      );
    });

    test('CRM overview cards are wired to dashboard navigation', () {
      final messengerScreen = readProjectFile(
        'lib/features/messenger/presentation/screens/messenger_screen.dart',
      );
      final adminOverview = readProjectFile(
        'lib/features/admin/presentation/widgets/admin_overview_widget.dart',
      );
      final managerOverview = readProjectFile(
        'lib/features/manager/presentation/widgets/manager_overview_widget.dart',
      );

      expect(messengerScreen, contains('_handleOverviewTabChange'));
      expect(messengerScreen, contains('_overviewTargetTab'));
      expect(messengerScreen, contains('AdminOverviewWidget('));
      expect(messengerScreen, contains('ManagerOverviewWidget('));
      expect(messengerScreen, contains('TasksWidget()'));
      expect(messengerScreen, contains('ReportsWidget(initialTab:'));
      expect(messengerScreen, contains('_selectedReportsTab'));
      expect(messengerScreen, contains('onTabChange: (index, subIndex)'));
      expect(messengerScreen, isNot(contains('const AdminOverviewWidget()')));
      expect(messengerScreen, isNot(contains('const ManagerOverviewWidget()')));
      expect(adminOverview, contains('onTabChange?.call'));
      expect(adminOverview, isNot(contains('Groups for now')));
      expect(managerOverview, contains('onTabChange?.call'));
      expect(managerOverview, contains('getManagerDashboard'));
      expect(managerOverview, isNot(contains('Supabase.instance')));
    });

    test('student admin board uses v3 search and card aggregates', () {
      final manageEntities = readProjectFile(
        'lib/features/admin/presentation/widgets/manage_entities_widget.dart',
      );
      final studentDetail = readProjectFile(
        'lib/features/admin/presentation/widgets/student_detail_dialog.dart',
      );

      expect(manageEntities, contains('studentSearchProvider'));
      expect(manageEntities, contains('searchStudents(q: query'));
      expect(manageEntities, contains("'groups_count'"));
      expect(manageEntities, contains("'open_tasks_count'"));
      expect(manageEntities, contains("'linked_user_email'"));
      expect(
        manageEntities,
        isNot(contains('return crm.listStudents(limit: 100);')),
      );
      expect(studentDetail, contains('getStudentCard(id)'));
      expect(studentDetail, contains("_cardList('groups')"));
      expect(studentDetail, contains("_cardList('expected_payments')"));
      expect(studentDetail, contains("_cardList('timeline')"));
      expect(studentDetail, contains('Clipboard.setData'));
      expect(studentDetail, contains('Контакт для связи'));
      expect(studentDetail, contains('Контакт скопирован для связи'));
      expect(studentDetail, contains('CrmNavigationRequest.userRolesSearch'));
      expect(studentDetail, contains('Найти в пользователях'));
      expect(studentDetail, contains('inviteStudent(id)'));
      expect(studentDetail, contains('Отправить приглашение'));
      expect(studentDetail, contains('Приглашение отправлено на \$email'));
      expect(studentDetail, contains('@local.magicmusiccrm.invalid'));
      expect(studentDetail, isNot(contains('getStudent(id)')));
    });

    test('lead card exposes safe attach-to-existing-student workflow', () {
      final leadDetail = readProjectFile(
        'lib/features/manager/presentation/widgets/lead_detail_dialog.dart',
      );
      final leadsWidget = readProjectFile(
        'lib/features/manager/presentation/widgets/leads_widget.dart',
      );
      final leadsProviders = readProjectFile(
        'lib/features/manager/presentation/providers/leads_providers.dart',
      );
      final crmService = readProjectFile(
        'lib/core/services/magic_crm_service.dart',
      );

      expect(leadsWidget, contains('_saveCurrentPreset'));
      expect(leadsWidget, contains('Сохранить пресет'));
      expect(leadsWidget, contains('Пресеты'));
      expect(leadsWidget, contains('_handlePresetMenu'));
      expect(leadsWidget, contains('_loadMoreLeads'));
      expect(leadsWidget, contains('Загрузить ещё'));
      expect(leadsWidget, contains("board['next_cursor']"));
      expect(leadsWidget, contains('onLoadMore'));
      expect(leadsProviders, contains('LeadFilterPresetStore'));
      expect(leadsProviders, contains('crm.lead_filter_presets.v1'));
      expect(leadsProviders, contains('LeadBoardFilters.fromJson'));
      expect(leadsProviders, contains('fetchBoard('));
      expect(leadsProviders, contains('toJson()'));
      expect(leadDetail, contains('listDuplicateCandidates(leadId: leadId'));
      expect(leadDetail, contains('_duplicateCandidatesSection'));
      expect(leadDetail, contains('Кандидаты на связь с учеником'));
      expect(leadDetail, contains('decideDuplicateCandidate('));
      expect(leadDetail, contains("status: 'attached'"));
      expect(leadDetail, contains('Лид связан с существующим учеником'));
      expect(leadDetail, contains('_dirty ? true : null'));
      expect(crmService, contains("queryParameters['leadId']"));
      expect(crmService, contains(r"'/crm/duplicates/$id'"));
    });

    test('teacher and staff admin boards use v3 aggregate contracts', () {
      final manageEntities = readProjectFile(
        'lib/features/admin/presentation/widgets/manage_entities_widget.dart',
      );
      final teacherDetail = readProjectFile(
        'lib/features/admin/presentation/widgets/teacher_detail_dialog.dart',
      );
      final staffDetail = readProjectFile(
        'lib/features/admin/presentation/widgets/staff_detail_dialog.dart',
      );

      expect(manageEntities, contains('teacherSearchProvider'));
      expect(manageEntities, contains('staffSearchProvider'));
      expect(manageEntities, contains('listTeachers('));
      expect(manageEntities, contains('listStaff('));
      expect(manageEntities, contains('StaffDetailDialog.show'));
      expect(manageEntities, contains("'students_count'"));
      expect(manageEntities, contains("'lessons_count'"));
      expect(manageEntities, contains("'is_app_account'"));
      expect(
        manageEntities,
        isNot(contains('Редактирование сотрудника будет доступно')),
      );
      expect(
        manageEntities,
        isNot(contains('magicProfileAdminServiceProvider')),
      );
      expect(teacherDetail, contains('_buildSummary(context)'));
      expect(teacherDetail, contains("'students_count'"));
      expect(teacherDetail, contains("'lessons_count'"));
      expect(teacherDetail, contains("'branches'"));
      expect(teacherDetail, contains("'is_app_account'"));
      expect(staffDetail, contains('updateStaff('));
      expect(staffDetail, contains('CrmNavigationRequest.userRolesSearch'));
      expect(staffDetail, contains('Найти в пользователях'));
      expect(staffDetail, contains('Данные сотрудника сохранены'));
    });

    test('schedule screen uses v3 matrix and room availability contracts', () {
      final schedule = readProjectFile(
        'lib/features/admin/presentation/widgets/schedule_widget.dart',
      );

      expect(schedule, contains('getScheduleMatrix('));
      expect(schedule, contains('listRoomAvailability('));
      expect(schedule, contains('_buildAvailabilitySummary()'));
      expect(schedule, contains('_availabilityForRoom'));
      expect(schedule, contains("_conflictTypes(lesson['conflict_types'])"));
      expect(schedule, contains("'room_overlap' => 'пересечение аудитории'"));
      expect(schedule, contains("'teacher_overlap' => 'пересечение педагога'"));
      expect(schedule, contains('Доступность аудиторий'));
      expect(schedule, contains('Error fetching schedule matrix'));
    });

    test('task board exposes v3 timeline quick action', () {
      final tasks = readProjectFile(
        'lib/features/manager/presentation/widgets/tasks_widget.dart',
      );

      expect(tasks, contains('onTimelineTap: _showTaskTimeline'));
      expect(tasks, contains('listTimeline('));
      expect(tasks, contains('includeAudit: true'));
      expect(tasks, contains('limit: 40'));
      expect(tasks, contains('_TaskTimelineSheet'));
      expect(tasks, contains('История объекта'));
      expect(tasks, contains('История по объекту пока пустая'));
      expect(tasks, contains('_timelineTypeLabel'));
      expect(tasks, contains('Добавить запись'));
      expect(tasks, contains('Комментарий к истории'));
      expect(tasks, contains('createComment('));
      expect(tasks, contains('_TaskAssigneeDialog'));
      expect(tasks, contains('Назначить ответственного'));
      expect(tasks, contains('onReassignTap: _reassignTask'));
      expect(tasks, contains('assignedTo: assignedTo'));
    });

    test('debtor screen exposes v3 account drilldown', () {
      final debtors = readProjectFile(
        'lib/features/manager/presentation/widgets/debtors_widget.dart',
      );

      expect(debtors, contains('listStudentBalances(debtOnly: true'));
      expect(debtors, contains('listPayments(studentId: studentId'));
      expect(debtors, contains('listExpectedPayments(studentId: studentId'));
      expect(debtors, contains('listTimeline('));
      expect(debtors, contains("entityType: 'student'"));
      expect(debtors, contains('_DebtorDetailSheet'));
      expect(debtors, contains('TopUpDialog.show'));
      expect(debtors, contains('_topUpStudentPayload'));
      expect(debtors, contains('Добавить оплату'));
      expect(debtors, contains('Последние оплаты'));
      expect(debtors, contains('Ожидаемые платежи'));
      expect(debtors, contains('Карточка ученика'));
    });

    test('finance intake summary follows flat magic styling', () {
      final finance = readProjectFile(
        'lib/features/manager/presentation/widgets/finance_widget.dart',
      );

      expect(finance, contains('colors.surfaceContainerHighest'));
      expect(finance, contains('BorderRadius.circular(8)'));
      expect(finance, contains('AppTheme.success.withAlpha(30)'));
      expect(finance, isNot(contains('LinearGradient')));
      expect(finance, isNot(contains('Color(0xFF10B981)')));
      expect(finance, isNot(contains('BorderRadius.circular(18)')));
    });

    test('mass notification widget sends through v3 notifications API', () {
      final massNotificationWidget = readProjectFile(
        'lib/features/admin/presentation/widgets/mass_notification_widget.dart',
      );

      expect(
        massNotificationWidget,
        contains('magicNotificationsServiceProvider'),
      );
      expect(massNotificationWidget, contains('adminSend('));
      expect(massNotificationWidget, contains("'in_app'"));
      expect(massNotificationWidget, contains("'push'"));
      expect(massNotificationWidget, isNot(contains('Future.delayed')));
      expect(massNotificationWidget, isNot(contains('Simulate send delay')));
      expect(massNotificationWidget, isNot(contains('Только Сокол')));
      expect(massNotificationWidget, isNot(contains('Только Спортивная')));
    });

    test('messenger and notification diagnostics stay debug-only', () {
      final messengerScreen = readProjectFile(
        'lib/features/messenger/presentation/screens/messenger_screen.dart',
      );
      final notificationService = readProjectFile(
        'lib/core/services/notification_service.dart',
      );

      expect(messengerScreen, contains('void _logMessenger(String message)'));
      expect(
        notificationService,
        contains('void _logNotification(String message)'),
      );
      expect(RegExp(r'debugPrint\(').allMatches(messengerScreen).length, 1);
      expect(RegExp(r'debugPrint\(').allMatches(notificationService).length, 1);
      expect(messengerScreen, isNot(contains('🎯 MESSENGER')));
      expect(messengerScreen, isNot(contains('💬 MESSENGER')));
      expect(messengerScreen, isNot(contains('❌ MESSENGER ERROR')));
      expect(notificationService, isNot(contains('data.keys.join')));
      expect(
        notificationService,
        isNot(contains('message.notification?.title')),
      );
    });

    test('main messenger upserts sent REST responses without reload', () {
      final messengerScreen = readProjectFile(
        'lib/features/messenger/presentation/screens/messenger_screen.dart',
      );

      expect(
        messengerScreen,
        contains('void _upsertMessage(Map<String, dynamic> message)'),
      );
      expect(
        messengerScreen,
        contains('void _applySentMessage(Map<String, dynamic> message'),
      );
      expect(
        messengerScreen,
        contains('final message = await messenger.sendMessage('),
      );
      expect(messengerScreen, contains('_applySentMessage(message);'));
      expect(
        messengerScreen,
        contains('_applySentMessage(post, channel: true);'),
      );
      expect(
        messengerScreen,
        isNot(contains('_loadMessages(); // Refresh channel posts')),
      );
    });

    test('file pickers validate size before loading bytes', () {
      final messageInput = readProjectFile(
        'lib/core/widgets/telegram/message_input.dart',
      );
      final clientChat = readProjectFile(
        'lib/features/client/presentation/widgets/chat_widget.dart',
      );
      final adminChat = readProjectFile(
        'lib/features/admin/presentation/widgets/admin_chat_dashboard.dart',
      );
      final messengerScreen = readProjectFile(
        'lib/features/messenger/presentation/screens/messenger_screen.dart',
      );

      expect(messageInput, contains('withData: false'));
      expect(clientChat, contains('withData: false'));
      expect(adminChat, contains('withData: false'));
      expect(messageInput, isNot(contains('withData: true')));
      expect(clientChat, isNot(contains('withData: true')));
      expect(adminChat, isNot(contains('withData: true')));
      expect(messageInput, contains('_readPickedFileBytes'));
      expect(clientChat, contains('_readPickedFileBytes'));
      expect(adminChat, contains('_readPickedFileBytes'));
      expect(
        messengerScreen.indexOf('final size = await file.length();'),
        lessThan(
          messengerScreen.indexOf('final bytes = await file.readAsBytes();'),
        ),
      );
    });

    test('channel composer is text-only until channel attachments exist', () {
      final messengerScreen = readProjectFile(
        'lib/features/messenger/presentation/screens/messenger_screen.dart',
      );

      expect(messengerScreen, contains('bool _canPostToChannel()'));
      expect(messengerScreen, isNot(contains('FutureBuilder<bool>')));
      expect(
        messengerScreen,
        contains("else if (_canPostToChannel())\n              MessageInput("),
      );
      expect(messengerScreen, contains('Вложения в каналах пока недоступны'));
      expect(
        messengerScreen,
        isNot(
          contains('_sendFileMessage(bytes, name, size, caption: caption);'),
        ),
      );
    });

    test('typing auto-stop uses cancellable debounce timer', () {
      final messengerScreen = readProjectFile(
        'lib/features/messenger/presentation/screens/messenger_screen.dart',
      );

      expect(messengerScreen, contains('Timer? _typingStopTimer;'));
      expect(messengerScreen, contains('_typingStopTimer?.cancel();'));
      expect(
        messengerScreen,
        contains('Timer(const Duration(seconds: 3), () {'),
      );
      expect(
        messengerScreen,
        contains('if (!mounted || _selectedChatId != chatId) return;'),
      );
      expect(
        messengerScreen,
        isNot(contains('Future.delayed(const Duration(seconds: 3)')),
      );
    });

    test('messenger chat list starts independent loads in parallel', () {
      final messengerScreen = readProjectFile(
        'lib/features/messenger/presentation/screens/messenger_screen.dart',
      );

      expect(
        messengerScreen,
        contains('final rawItemsFuture = messenger.listChats'),
      );
      expect(
        messengerScreen,
        contains('final channelsFuture = messenger.listChannels'),
      );
      expect(
        messengerScreen,
        contains(
          'final adminAvatarFuture = MagicSettingsService.getAdminChatAvatar',
        ),
      );
      expect(
        messengerScreen,
        contains('final Future<Map<String, dynamic>?> adminChatFuture'),
      );
      expect(
        messengerScreen,
        contains(
          'final Future<List<Map<String, dynamic>>> adminProfilesFuture',
        ),
      );
      expect(
        messengerScreen.indexOf('final rawItemsFuture = messenger.listChats'),
        lessThan(
          messengerScreen.indexOf('final rawItems = await rawItemsFuture'),
        ),
      );
      expect(
        messengerScreen.indexOf(
          'final channelsFuture = messenger.listChannels',
        ),
        lessThan(
          messengerScreen.indexOf('final channels = await channelsFuture'),
        ),
      );
    });

    test('settings service reuses its default API client', () {
      final service = readProjectFile(
        'lib/core/services/magic_settings_service.dart',
      );

      expect(
        service,
        contains('static final MagicApiClient _defaultApiClient'),
      );
      expect(
        service,
        contains(
          'static MagicApiClient get _api => debugApiClientOverride ?? _defaultApiClient;',
        ),
      );
      expect(
        service,
        isNot(
          contains(
            'static MagicApiClient get _api =>\n      debugApiClientOverride ??\n      MagicApiClient(',
          ),
        ),
      );
    });

    test('secure token store reads token values in parallel batches', () {
      final store = readProjectFile('lib/core/api/magic_token_store.dart');

      expect(store, contains('final coreTokens = await Future.wait'));
      expect(store, contains('final metadata = await Future.wait'));
      expect(store, contains('final accessToken = coreTokens[0];'));
      expect(store, contains('tokenType: metadata[1] ?? \'Bearer\','));
      expect(
        store,
        isNot(
          contains(
            'final accessToken = await _storage.read(key: _accessTokenKey);',
          ),
        ),
      );
    });

    test('Android launch theme avoids black pre-frame background', () {
      final colors = readProjectFile(
        'android/app/src/main/res/values/colors.xml',
      );
      final styles = readProjectFile(
        'android/app/src/main/res/values/styles.xml',
      );
      final nightStyles = readProjectFile(
        'android/app/src/main/res/values-night/styles.xml',
      );
      final stylesV31 = readProjectFile(
        'android/app/src/main/res/values-v31/styles.xml',
      );
      final nightStylesV31 = readProjectFile(
        'android/app/src/main/res/values-night-v31/styles.xml',
      );
      final launchBackground = readProjectFile(
        'android/app/src/main/res/drawable/launch_background.xml',
      );
      final launchBackgroundV21 = readProjectFile(
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      );

      expect(
        colors,
        contains('<color name="launch_background">#F7F3EA</color>'),
      );
      expect(colors, contains('<color name="launch_gold">#C5A059</color>'));
      expect(styles, contains('@color/launch_background'));
      expect(nightStyles, contains('@android:style/Theme.Light.NoTitleBar'));
      expect(stylesV31, contains('windowSplashScreenBackground'));
      expect(stylesV31, contains('windowSplashScreenAnimatedIcon'));
      expect(stylesV31, contains('windowSplashScreenIconBackgroundColor'));
      expect(stylesV31, contains('@color/launch_background'));
      expect(stylesV31, contains('@color/launch_gold'));
      expect(stylesV31, contains('android:forceDarkAllowed'));
      expect(nightStylesV31, contains('windowSplashScreenBackground'));
      expect(nightStylesV31, contains('@color/launch_background'));
      expect(nightStylesV31, contains('android:forceDarkAllowed'));
      expect(nightStyles, isNot(contains('Theme.Black.NoTitleBar')));
      expect(nightStylesV31, isNot(contains('Theme.Black.NoTitleBar')));
      expect(launchBackground, contains('@color/launch_background'));
      expect(launchBackgroundV21, contains('@color/launch_background'));
      expect(launchBackgroundV21, isNot(contains('?android:colorBackground')));
    });

    test('messenger read marker is resolved by backend latest message', () {
      final messengerScreen = readProjectFile(
        'lib/features/messenger/presentation/screens/messenger_screen.dart',
      );

      expect(messengerScreen, contains('.markRead(_selectedChatId!)'));
      expect(
        messengerScreen,
        isNot(contains("final lastReadMessageId = _messages.isEmpty")),
      );
      expect(
        messengerScreen,
        isNot(contains("_messages.last['id']?.toString()")),
      );
    });

    test(
      'messenger realtime chat updates avoid full reload for read state',
      () {
        final messengerScreen = readProjectFile(
          'lib/features/messenger/presentation/screens/messenger_screen.dart',
        );

        expect(
          messengerScreen,
          contains('connection.onChatUpdated(_handleRealtimeChatUpdated);'),
        );
        expect(
          messengerScreen,
          contains(
            'void _handleRealtimeChatUpdated(Map<String, dynamic> payload)',
          ),
        );
        expect(
          messengerScreen,
          contains("final readerId = payload['readerId']?.toString();"),
        );
        expect(
          messengerScreen,
          contains('setState(() => _unreadCounts[chatId] = 0);'),
        );
        expect(
          messengerScreen,
          isNot(contains('connection.onChatUpdated((_) => _loadChatList());')),
        );
      },
    );

    test('messenger display normalizes messages to chronological order', () {
      final messengerScreen = readProjectFile(
        'lib/features/messenger/presentation/screens/messenger_screen.dart',
      );

      expect(messengerScreen, contains('void _sortMessagesChronologically()'));
      expect(messengerScreen, contains('aCreated.compareTo(bCreated)'));
      expect(
        messengerScreen,
        contains('_messages = List<Map<String, dynamic>>.from(msgs);'),
      );
      expect(messengerScreen, contains('_sortMessagesChronologically();'));
      expect(
        messengerScreen.indexOf(
          '_messages = List<Map<String, dynamic>>.from(msgs);',
        ),
        lessThan(
          messengerScreen.indexOf('_fetchReactionsForCurrentMessages();'),
        ),
      );
    });

    test('chat info editing affordance is limited to v3 channel contract', () {
      final chatInfoDialog = readProjectFile(
        'lib/core/widgets/telegram/chat_info_dialog.dart',
      );

      expect(
        chatInfoDialog,
        contains("if (widget.chatType != 'channel') return false;"),
      );
      expect(
        chatInfoDialog,
        contains(
          "_canEdit\n                            ? () => _editField('name'",
        ),
      );
      expect(
        chatInfoDialog,
        contains(
          "_canEdit\n                                  ? () => _editField(",
        ),
      );
      expect(
        chatInfoDialog,
        isNot(contains("if (widget.chatType != 'channel') return;\n")),
      );
    });

    test(
      'chat presence uses v3 realtime instead of empty placeholder stream',
      () {
        final chatProviders = readProjectFile(
          'lib/core/providers/chat_providers.dart',
        );
        final messengerScreen = readProjectFile(
          'lib/features/messenger/presentation/screens/messenger_screen.dart',
        );

        expect(chatProviders, contains('magicRealtimeServiceProvider'));
        expect(chatProviders, contains('onPresenceUpdated'));
        expect(chatProviders, contains('connection?.joinChat(chatId)'));
        expect(chatProviders, isNot(contains('yield const <String>[];')));
        expect(messengerScreen, contains('onlineUserIds: _onlineUsers'));
        expect(
          messengerScreen,
          isNot(contains('ref.watch(chatPresenceProvider')),
        );
      },
    );

    test('password reset flow is exposed through v3 auth API', () {
      final router = readProjectFile('lib/core/router/app_router.dart');
      final login = readProjectFile(
        'lib/features/auth/presentation/screens/login_screen.dart',
      );
      final resetScreen = readProjectFile(
        'lib/features/auth/presentation/screens/password_reset_screen.dart',
      );
      final authService = readProjectFile(
        'lib/features/auth/data/services/magic_auth_service.dart',
      );

      expect(router, contains("path: '/password-reset'"));
      expect(login, contains('Забыли пароль?'));
      expect(login, contains("context.push('/password-reset')"));
      expect(resetScreen, contains('Восстановление пароля'));
      expect(resetScreen, contains('requestPasswordReset(email: email)'));
      expect(
        resetScreen,
        contains('resetPassword(token: token, password: password)'),
      );
      expect(authService, contains("'/auth/password-reset/request'"));
      expect(authService, contains("'/auth/password-reset/confirm'"));
    });

    test('visible technical auth and CRM labels are localized', () {
      final login = readProjectFile(
        'lib/features/auth/presentation/screens/login_screen.dart',
      );
      final registration = readProjectFile(
        'lib/features/auth/presentation/screens/registration_screen.dart',
      );
      final teacherDetail = readProjectFile(
        'lib/features/admin/presentation/widgets/teacher_detail_dialog.dart',
      );
      final studentDetail = readProjectFile(
        'lib/features/admin/presentation/screens/student_detail_screen.dart',
      );
      final customFields = readProjectFile(
        'lib/features/admin/presentation/widgets/custom_field_config_widget.dart',
      );
      final attachments = readProjectFile(
        'lib/core/services/chat_attachment_service.dart',
      );
      final authService = readProjectFile(
        'lib/features/auth/data/services/magic_auth_service.dart',
      );

      expect(login, contains("labelText: 'Электронная почта'"));
      expect(login, contains('_isEmailUnverifiedError'));
      expect(login, contains('resendSignupOtp(email: email)'));
      expect(login, contains('purpose: EmailOtpPurpose.signup'));
      expect(login, contains('_errorMessage'));
      expect(registration, contains("labelText: 'Электронная почта'"));
      expect(teacherDetail, contains("labelText: 'Электронная почта'"));
      expect(studentDetail, contains("labelText: 'Ссылка на документ'"));
      expect(customFields, isNot(contains("hintText: 'parentName'")));
      expect(attachments, isNot(contains('Backend не')));
      expect(attachments, isNot(contains('v3 chatId')));
      expect(authService, isNot(contains('Google OAuth callback неполный')));
    });

    test('legacy SMS OTP screen and notification click delay are removed', () {
      final smsOtpScreen = File(
        'lib/features/auth/presentation/screens/otp_screen.dart',
      );
      final notificationService = readProjectFile(
        'lib/core/services/notification_service.dart',
      );

      expect(smsOtpScreen.existsSync(), isFalse);
      expect(notificationService, contains('scheduleMicrotask(()'));
      expect(
        notificationService,
        isNot(contains('Duration(milliseconds: 800)')),
      );
      expect(notificationService, isNot(contains('Введите код из SMS')));
    });

    test('mobile Android back returns from CRM depth before app exit', () {
      final messengerScreen = readProjectFile(
        'lib/features/messenger/presentation/screens/messenger_screen.dart',
      );

      expect(
        messengerScreen,
        contains('bool _hasInternalBackState({required bool includeCrmTabs})'),
      );
      expect(
        messengerScreen,
        contains('void _consumeBackNavigation({required bool includeCrmTabs})'),
      );
      expect(
        messengerScreen,
        contains('canPop: !_hasInternalBackState(includeCrmTabs: true)'),
      );
      expect(
        messengerScreen,
        contains('canPop: !_hasInternalBackState(includeCrmTabs: false)'),
      );
      expect(
        messengerScreen,
        contains('if (includeCrmTabs && _selectedCrmTab != 0)'),
      );
      expect(
        messengerScreen,
        isNot(
          contains('canPop: _selectedCrmTab != 0 || _selectedChatId == null'),
        ),
      );
      expect(
        messengerScreen,
        isNot(contains('Navigator.pop(context); // Close dialog')),
      );
    });

    test('visible auth and CRM copy avoids English technical labels', () {
      final login = readProjectFile(
        'lib/features/auth/presentation/screens/login_screen.dart',
      );
      final emailOtp = readProjectFile(
        'lib/features/auth/presentation/screens/email_otp_screen.dart',
      );
      final reset = readProjectFile(
        'lib/features/auth/presentation/screens/password_reset_screen.dart',
      );
      final registration = readProjectFile(
        'lib/features/auth/presentation/screens/registration_screen.dart',
      );
      final authMethods = readProjectFile(
        'lib/features/profile/presentation/screens/auth_methods_screen.dart',
      );
      final financeDashboard = readProjectFile(
        'lib/features/manager/presentation/widgets/financial_dashboard_widget.dart',
      );
      final createEmployee = readProjectFile(
        'lib/features/admin/presentation/widgets/create_employee_dialog.dart',
      );
      final studentDetailScreen = readProjectFile(
        'lib/features/admin/presentation/screens/student_detail_screen.dart',
      );
      final studentDetailDialog = readProjectFile(
        'lib/features/admin/presentation/widgets/student_detail_dialog.dart',
      );
      final leadDetail = readProjectFile(
        'lib/features/manager/presentation/widgets/lead_detail_dialog.dart',
      );
      final userRoles = readProjectFile(
        'lib/features/manager/presentation/widgets/user_roles_widget.dart',
      );
      final messengerScreen = readProjectFile(
        'lib/features/messenger/presentation/screens/messenger_screen.dart',
      );
      final crmNavigation = readProjectFile(
        'lib/core/providers/crm_navigation_provider.dart',
      );
      final tasks = readProjectFile(
        'lib/features/manager/presentation/widgets/tasks_widget.dart',
      );
      final massNotification = readProjectFile(
        'lib/features/admin/presentation/widgets/mass_notification_widget.dart',
      );
      final statuses = readProjectFile(
        'lib/features/manager/presentation/widgets/manage_statuses_dialog.dart',
      );
      final customFields = readProjectFile(
        'lib/features/admin/presentation/widgets/custom_field_config_widget.dart',
      );

      expect(login, isNot(contains('Неверный email или пароль')));
      expect(login, isNot(contains('Подтвердите email перед входом')));
      expect(login, isNot(contains('Введите корректный email')));
      expect(emailOtp, isNot(contains('Новый код отправлен на email')));
      expect(emailOtp, isNot(contains('Подтвердите email')));
      expect(emailOtp, isNot(contains('Введите код 2FA')));
      expect(reset, isNot(contains('Введите корректный email')));
      expect(reset, isNot(contains('на ваш email')));
      expect(registration, isNot(contains('email и пароль')));
      expect(registration, isNot(contains('Некорректный email')));
      expect(authMethods, isNot(contains('Email-код')));
      expect(authMethods, isNot(contains('email-вход')));
      expect(authMethods, isNot(contains('настройку 2FA')));
      expect(authMethods, isNot(contains('Email и пароль')));
      expect(authMethods, isNot(contains('по email и паролю')));
      expect(financeDashboard, isNot(contains('Lessons count')));
      expect(createEmployee, isNot(contains('по email или телефону')));
      expect(createEmployee, isNot(contains("label: 'Email'")));
      expect(createEmployee, isNot(contains('Некорректный email')));
      expect(studentDetailScreen, isNot(contains("label: 'Email'")));
      expect(studentDetailDialog, isNot(contains("'Email',")));
      expect(leadDetail, isNot(contains("'Email',")));
      expect(userRoles, isNot(contains('Поиск по имени, email')));
      expect(userRoles, contains('final String? initialSearch;'));
      expect(userRoles, contains('_applyInitialSearch(widget.initialSearch)'));
      expect(messengerScreen, contains('crmNavigationRequestProvider'));
      expect(messengerScreen, contains('_userRolesInitialSearch'));
      expect(crmNavigation, contains('CrmNavigationRequest.userRolesSearch'));
      expect(tasks, contains('String _roleLabel(String role)'));
      expect(tasks, isNot(contains(r"'$name ($role)'")));
      expect(massNotification, isNot(contains('push-уведомлений')));
      expect(statuses, isNot(contains('negotiation, на англ.')));
      expect(customFields, isNot(contains("hintText: 'pole1'")));
    });
  });
}
