# CRM: рабочая область — локальная проверка 01.10.2026

Основа: `codex/ui-release-232`, HEAD `8653d650b76e28531d7df261edbb7c52fea76397`,
`1.5.52+232` и предыдущие локальные изменения этой задачи.
Backend, миграции и production-данные не менялись; публикация не выполнялась.

Список полей расширен до 360–460 логических пикселей в зависимости от ширины
рабочей области. Длинные пояснения убраны; категории вынесены в отдельную
вкладку. Поиск по названию/ключу и фильтры категории/карточки показывают число
подходящих полей. На широком экране первый результат сразу выбран и виден в
панели свойств; на 390×844 сохраняются список и возврат из редактора.
Выбранное поле выделяется фоном. Категории, размещения и ширина в свойствах
показаны понятными русскими названиями.

Чёрный круг создавался штатной отметкой выбора `ChoiceChip` поверх его avatar.
В общей точке построения вкладок CRM выставлено `showCheckmark: false`;
выбор, наведение и клавиатурный фокус сохранены. Сервисы, проверки прав,
черновики, предпросмотр, причины публикации и неизменяемые версии сохранены.

Проверки и условия:

1. `flutter analyze --no-pub`: PASS, 16,6 с;
   `dist/crm-workspace-analyze.log`.
2. `flutter test test/features/settings/crm_configuration_workspace_test.dart test/features/settings/system_settings_workspace_test.dart --no-pub --reporter expanded`:
   37 PASS; `dist/crm-workspace-tests.log`. Адаптированы существующие селекторы
   новых вкладок и полей; новые unit-тесты не добавлялись.
3. `node scripts/http-journey-check.cjs --audit-configuration`: Windows,
   изолированные localhost API/PostgreSQL и синтетический директор. Реальные
   переходы через настройки, наведение на вкладки, категории, поиск по ключу,
   сочетание фильтров, пустой результат и очистка, черновик/повторное открытие,
   публикация/отмена/причина, изменение/архивирование, история/откат, 390×844.
   Контрольный снимок `configuration-filter-lead.png` фиксирует исключение
   поля ученика при фильтре «Лид». Итог прогона и путь указаны ниже.
4. Release: `flutter build windows --release --target=lib/main.dart --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api`.
   Журнал `dist/crm-workspace-release.log`, запуск и хеш бинарного файла —
   `dist/crm-workspace-launch.json`.
5. `git diff --check`; полный release gate не выполнялся.

Предыдущие E2E-прогоны не являются PASS итогового кандидата. В первом прогоне
селектор выбранного поля также захватывал пункт настроек. В проверке поиска
после выпадающего списка автоматический ввод попадал в предыдущий контрол;
снимок и значение FormField подтвердили исправную фильтрацию. Селектор сужен
до CRM, а перед вводом поиск получает реальный фокус через пользовательский
tap. Проверка текста контроллера исключает ложное подтверждение ввода.

Итоговый E2E: **23 PASS, 0 FAIL**, 43 HTTP, 0 серверных ошибок;
**18 UI шагов PASS**, `completed: true`.
Артефакты: `dist/http-journeys/cec41111242f4e89b59da26c7f32e579/result.json`,
`configuration-director.json`, `configuration-windows.log`,
`configuration-director-TABS-HOVER.png`, `configuration-director-CATEGORIES.png`,
`configuration-filter-lead.png`, `configuration-director-NARROW.png`.
Product sources (`lib`, `pubspec.yaml`, `pubspec.lock`, Git-tracked paths,
сортировка пути, разделитель NUL перед содержимым и после него):
`da5d7da68f1131ba7a9d4215023d5be1b141f3040d7751727543d7e2e5681116`,
также `dist/crm-workspace-product.sha256`.

Release: PASS, 77,3 с. Запущено окно `magic_music_crm`, PID **10008**,
FileVersion/ProductVersion **1.5.52+232**, Responding=true.
SHA256 бинарного файла:
`1BD0A125EF53C3735574C7F4181D13C49D4D33E22146C046BD93ECF120E30F0F`.
Сборка и запуск подтверждены журналом и `dist/crm-workspace-launch.json`.
Семь генерируемых Flutter registrant-файлов восстановлены к исходному HEAD;
`git diff --check`: PASS. Изменения локальны, без публикации.
