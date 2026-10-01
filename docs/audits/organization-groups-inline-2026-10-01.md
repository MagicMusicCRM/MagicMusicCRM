# Организация и группы — локальная проверка 01.10.2026

Основа: `codex/ui-release-232`, HEAD `8653d650b76e28531d7df261edbb7c52fea76397`,
версия `1.5.52+232`. Локальные изменения; публикация не выполнялась.

- Филиал создаётся и редактируется страницей внутри «Организации».
- Его рабочие часы и исключения видны в карточке и сохраняются существующим
  versioned API. Общая кнопка карточки также сохраняет изменённый график.
- «Группы» — отдельный раздел существующей рабочей области; создание,
  состав, расписание и завершение используют прежние формы и сервисы.
- «Обучение» убрано из настроек. Прежние номера разделов не изменены;
  «Группы» получили номер 9. Панель действий переносится на узком экране.

Условия E2E: Windows Flutter, действующий локальный PostgreSQL на loopback,
одноразовая БД и синтетические аккаунты от `http-journey-check.cjs`.
Production API/БД не изменялись.

Проверки:

1. `flutter analyze --no-pub`: PASS; `dist/organization-groups-analyze.log`.
2. `flutter test test/features/rbac_nav_matrix_test.dart test/features/navigation/entity_link_registry_test.dart test/features/workspace/typed_entity_navigation_policy_test.dart test/features/settings/system_settings_workspace_test.dart --no-pub --reporter expanded`:
   53 PASS; `dist/organization-groups-tests.log`.
3. `node scripts/http-journey-check.cjs --audit-branch-hours`: 23 PASS, 0 FAIL,
   43 HTTP, 0 серверных ошибок; 14 UI шагов PASS.
   `dist/http-journeys/e9d8cd20567f4860a3e380782e379bbe/result.json`,
   `branch-hours-director.json`, `branch-hours-windows.log` и PNG.
   Проверены 390×844 и 1440×1400, исключения, общая кнопка сохранения,
   отмена выхода и HTTP 409 без перезаписи новой версии.
4. `node scripts/http-journey-check.cjs --audit-branch-rooms`: 23 PASS, 0 FAIL,
   43 HTTP, 0 серверных ошибок; 15 UI шагов PASS.
   `dist/http-journeys/0d559a457a35452b9e0a7ba898a304a0/result.json`,
   `branch-rooms-director.json` и `branch-rooms-windows.log`.
   Проверены создание филиала с рабочими часами, редактирование, аудитории
   и отмена несохранённых изменений в карточке внутри раздела.
5. `node scripts/http-journey-check.cjs --audit-groups`: 23 PASS, 0 FAIL,
   43 HTTP, 0 серверных ошибок; по 9 UI шагов PASS для директора и управляющего.
   `dist/http-journeys/fbebdea4f0e741e2a91c68c03caa5a02/result.json`,
   `groups-director.json`, `groups-manager.json` и `groups-windows.log`.
   Проверены отдельный раздел, создание и поиск группы, состав учеников,
   повторное открытие и доступность тарифа по роли.

Хеш Flutter product sources (`lib`, `pubspec.yaml`, `pubspec.lock`):
`891e21cba2b3c7b2ca80d1f0762d2f85c717ad6c6607f1767092a9351a04bb29`.
После прогона часов корректировались только селекторы существующих E2E
в `branch_rooms_live_test.dart` и `group_membership_live_test.dart` под
актуальный `AppDropdownButtonFormField`; product sources не менялись.

`flutter build windows --release --target=lib/main.dart --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api`:
PASS, 172,4 с; `dist/organization-groups-release.log`.
Приложение запущено из `build/windows/x64/runner/Release/magic_music_crm.exe`;
FileVersion и ProductVersion `1.5.52+232`, PID 19580, окно `magic_music_crm`,
Responding=true. Проверка запуска и SHA256 бинарного файла сохранены в
`dist/organization-groups-launch.json`. Финальный `git diff --check`: PASS.

Публикация не выполнялась. Полный release gate не выполнялся;
проверены перечисленные локальные сценарии.
