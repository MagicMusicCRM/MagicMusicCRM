# Разделы настроек — локальная проверка 01.10.2026

Основа: `codex/ui-release-232`, HEAD `8653d650b76e28531d7df261edbb7c52fea76397`,
`1.5.52+232` и локальные правки персонала/организации из этой задачи.
Публикация не выполнялась; backend и миграции не менялись.

Настройки: Организация, Пользователи, Уведомления, CRM и воронки, Абонементы,
Интеграции и система. Прежние ссылки `access`/`sales` ведут в новые разделы.
Пользователи и доступы открываются встроенными экранами; канонические ссылки
заменяют переход на старую отдельную страницу профиля. Связанные кадровые
карточки не перехватываются экраном профиля. CRM использует вкладки над
списком и редактором, компактный экран имеет возврат к списку; каталог
абонементов имеет поиск. Сервисы, API, проверки прав и команды сохранены.

Проверки:

1. `flutter analyze --no-pub`: PASS; `dist/settings-restructure-analyze.log`.
2. `flutter test test/features/settings/system_settings_workspace_test.dart test/features/settings/crm_configuration_workspace_test.dart test/features/admin/profile_detail_screen_test.dart test/features/search/stable_server_search_test.dart test/features/workspace/personnel_deep_link_test.dart --no-pub --reporter expanded`:
   42 PASS; `dist/settings-restructure-tests.log`.
3. `node scripts/http-journey-check.cjs --audit-notification-preferences`:
   23 PASS, 0 FAIL, 43 HTTP, 0 серверных ошибок; по 9 UI шагов PASS для
   директора и управляющего. Матрица получателей и каналов, повторное
   открытие, 390×844, поиск аккаунта, встроенный профиль и доступы,
   сохранение поиска при возврате, связанный клиент в рабочей области.
   `dist/http-journeys/b2533e0f5ee940c9914fdf7d976e5897/result.json`,
   `notification-preferences-director.json`, `notification-preferences-manager.json`
   и `notification-preferences-windows.log`.
4. `node scripts/http-journey-check.cjs --audit-package-catalog`:
   23 PASS, 0 FAIL, 43 HTTP, 0 серверных ошибок; 15 UI шагов директора и
   4 управляющего. Создание, валидация, отмена, изменение/очистка параметров,
   HTTP 409, архивирование/восстановление, ограничение изменения по роли,
   поиск и 390×844.
   `dist/http-journeys/6e0aec6571d94803990d9e62f92bede4/result.json`,
   `catalog-director.json`, `catalog-manager.json` и `catalog-windows.log`.
5. `node scripts/http-journey-check.cjs --audit-configuration`:
   23 PASS, 0 FAIL, 43 HTTP, 0 серверных ошибок; 15 UI шагов PASS.
   Переход через новый раздел, создание поля, черновик/повторное открытие,
   отмена публикации, обязательная причина, публикация, редактирование,
   архивирование, история и откат как новая версия, 390×844 с возвратом
   от редактора к списку.
   `dist/http-journeys/d5bdfc4333a64a0a8ec603e42b9dc7bd/result.json`,
   `configuration-director.json` и `configuration-windows.log`.

E2E выполняется на Windows с изолированным локальным API/PostgreSQL и
синтетическими аккаунтами. Production API/БД не изменяются.
Хеш product sources (`lib`, `pubspec.yaml`, `pubspec.lock`):
`b4187201cb61a56033a5b22954f43cc3cf0891d9672891dba22c31fd794f9c5d`.
После прогона уведомлений добавлены проверки поиска/узкого экрана в
существующие E2E абонементов и CRM; product sources не менялись.
После этих прогонов обновлены только старые названия и селекторы разделов
в E2E навигации и персон. Их полный прогон не заявляется как выполненный.

`flutter build windows --release --target=lib/main.dart --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api`:
PASS, 77,9 с; `dist/settings-restructure-release.log`.
Локальная Release-сборка запущена из
`build/windows/x64/runner/Release/magic_music_crm.exe`:
PID 7832, FileVersion/ProductVersion `1.5.52+232`, окно `magic_music_crm`,
Responding=true. Проверка запуска и SHA256 бинарного файла:
`dist/settings-restructure-launch.json`. `git diff --check`: PASS.

Всего 52 UI шага в трёх локальных E2E-прогонах. Полный release gate
не выполнялся; публикация не выполнялась.
