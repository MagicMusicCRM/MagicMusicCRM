# MagicMusicCRM — безопасный rollout светлого визуала

Дата: 28 августа 2026 года.

Статус: стенд и волна 1 утверждены владельцем. Production deploy требует
отдельной прямой команды после release gate и owner-UAT.

## 1. Решение

Переносить светлый визуал в два независимых слоя:

1. Сначала применить к существующему Flutter UI единые светлые семантические
   токены и общие компоненты без изменения маршрутов, компоновки, бизнес-логики,
   providers, services, API и RBAC.
2. Затем переносить индивидуально свёрстанные решения стенда по одному семейству
   экранов, каждый раз доказывая функциональное равенство с текущим Release.

Для экранов без отдельного дизайна разрешён только token-first reskin текущей
production-композиции. Новые кнопки, поля, статусы и сценарии не добавляются.

## 2. Исходная точка стенда

Каталог стенда содержит `202/202` зарегистрированных surface и `487/487`
проверяемых связей. Отдельная композиция реализована для `14/202` surface. Это
доказывает механическое покрытие маршрутов стенда, но не доказывает functional parity
с production.

## 3. Целевой token contract

| Назначение | Значение |
|---|---:|
| Фон приложения | `#FCFBF8` |
| Рабочая поверхность | `#FFFFFF` |
| Мягкая поверхность | `#F7F4EE` |
| Основной текст | `#181915` |
| Вторичный текст | `#6D6D66` |
| Граница | `#DFDBD2` |
| Бренд / выбранное | `#A97D25` |
| Сплошное основное действие | `#765417` |
| Фокус | `#3B73D1` |

В runtime остаётся одна тема. Старые `dark*`/`light*` aliases разрешены только как
compile-compatible мост; новые widgets используют `AppColor`.

## 4. Волны

- Волна 1: семантическая `ThemeData`, общие primitives и аудит локальных цветов без
  изменения layout и бизнес-логики.
- Волна 2: shell/navigation, задачи, лиды/ученики, карточки клиентов, расписание и
  аналитика переносятся по одному семейству экранов.
- Волна 3: остальные surface остаются в foundation reskin до их отдельного проектирования.

## 5. Неподвижные ограничения

- `server/`, PostgreSQL, migrations, API contracts, providers, services и RBAC не меняются.
- Desktop workspace сохраняет tab state, Back/Forward и dirty-exit semantics.
- Mobile сохраняет канонические сценарии без нового горизонтального overflow.

## 6. Gate и rollout

PR готов только если diff не меняет backend/contracts, Flutter tests/analyze и platform smoke
проходят, а desktop/mobile QA подтверждает contrast, focus, text scale, overflow и
loading/empty/error/forbidden/content. Минимум: WCAG AA `4.5:1` для обычного текста, `3:1`
для крупного текста и значимых границ; touch target не меньше `44×44`.

Production deploy: сначала новый candidate, Windows/Android smoke, role-matrix smoke и
owner-UAT; затем отдельно одобренная публикация. Rollback возвращает предыдущий
подписанный client artifact без изменения production data.

## 7. Evidence кандидата Wave 1

Проверено на ветке `codex/light-visual-wave-1` 28 августа 2026 года:

- `flutter test --reporter compact`: `1363/1363` теста прошли.
- `flutter analyze`: `No issues found`.
- `flutter test integration_test/app_launch_smoke_test.dart`: `2/2` Windows smoke
  прошли на собранном desktop-приложении.
- `flutter build apk --debug`: Android debug APK собран успешно.
- Scope diff: нет изменений `server/`, migrations, API, services, providers и RBAC.

До production остаются role-matrix smoke, owner-UAT на целевых Windows/Android
устройствах, release-сборка и отдельное прямое разрешение владельца на deploy.
