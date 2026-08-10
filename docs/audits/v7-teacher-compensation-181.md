# MagicMusicCRM 1.5.1+181 — Teacher compensation refinement

- Дата: `2026-08-11`
- Commit: `17ce254f11f353ffe0f6c7914f8f80a942fcf8e4`
- Production: без изменений, `1.5.1+180`
- Решение по локальному кандидату: `TECHNICAL PASS`
- Итоговая owner-приёмка: `NOT YET APPROVED`

## Что реализовано

- Один общий create/edit-компонент Teacher настраивает филиалы, дисциплины,
  уровни обучения, категории, даты, совместительство, blacklist, оклад и ставку.
- Ставка поддерживает `600/700/750/900 ₽/ч`, произвольное значение и
  `Входит в оклад`, действует с выбранной даты и сохраняется append-only
  историей `app.teacher_rates`.
- Создание Teacher атомарно записывает user/profile/teacher/link/branches/
  disciplines/rate; редактирование атомарно сохраняет профиль, назначения и
  новую строку ставки. Ошибка reference guard не оставляет частичных данных.
- Оплата преподавателю не связана со способом оплаты ученика, личным счётом или
  абонементом. Completed lesson использует effective immutable compensation
  fact; зарплатный отчёт не выдаёт aggregate payout за оплату конкретного урока.
- Payroll за произвольный период показывает завершённые, оплачиваемые и
  zero-accrual занятия, астрономические часы, начисления, доплаты, вычеты,
  выплаты и сальдо периода. Карточка Teacher сохраняет отдельный all-time debt.

## Regression и transaction evidence

| Контур | Результат |
|---|---|
| Backend full Jest | `158/158` suites, `1258/1258` tests, PASS |
| Backend build/typecheck | PASS |
| PostgreSQL Teacher transaction | create/edit/rate history PASS; invalid discipline rollback PASS |
| Flutter full test | `667/667`, PASS |
| Flutter analyze | `No issues found`, PASS |
| Финальная adaptive-form выборка | `10/10`, PASS |
| Diff/format integrity | PASS |
| Candidate Gitleaks | new commits, `0` findings |
| Backend production dependency audit | `0` vulnerabilities (offline cache) |

Полный Flutter gate был выполнен после основной реализации; после последней
адаптивной правки текстовых tab-labels повторно выполнены все затронутые widget
tests (`10/10`) и Release-сборки Windows/APK/AAB.

## Release/runtime evidence

- Windows Release: `FileVersion/ProductVersion=1.5.1+181`; ZIP распакован,
  внутренний EXE совпал по SHA-256 с build output и оставался жив через 10 секунд.
- Реальная Release-форма «Новый преподаватель» открыта в production-сессии в
  read-only smoke: новые поля, scroll и компактные tabs отображаются; сохранение
  не выполнялось. Временные кадры с production UI удалены и не коммитились.
- APK: `versionName=1.5.1`, `versionCode=181`, `minSdk=24`, `targetSdk=36`,
  Signature Scheme v2 PASS, signer SHA-256
  `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
- AAB: JAR signature PASS; сертификат действителен до `2053-10-15`, timestamp
  отсутствует в соответствии с текущим upload-key workflow.
- Inno Setup `6.7.3`: compile PASS, Authenticode `NotSigned` в рамках принятого
  owner risk. Новый silent install не завершён в неинтерактивной сессии из-за
  невидимого UAC; процесс остановлен, установка не произошла. Проверены ZIP
  launch и ранее пройденный install/launch/uninstall smoke неизменного packaging
  path для `+180`.
- Android 15/API 35 emulator: подписанный APK установлен поверх emulator data,
  package manager подтвердил `versionCode=181`; MainActivity стала foreground,
  процесс оставался жив, `FATAL EXCEPTION`, app-specific ANR и `E/flutter` не
  обнаружены. После smoke приложение остановлено, эмулятор штатно выключен.

Exact server image: `magicmusiccrm-server:1.5.1-181-17ce254`, image ID
`sha256:5fbd5a299bb43bb32f5269e446102c6014aac94f803d950b4cfafe217f7ba09f`,
non-root user `magiccrm`. Изолированный image-gate подтвердил containerized
migration `0118`, fail-closed production flags, live/ready, встроенный
healthcheck и HTTP 503 при нарушенном migration ledger; временные контейнеры и
БД удалены. Trivy image scan: `0` High/Critical, `0` secrets. Image ZIP повторно
загружен через `docker load`; SBOM сохранён в CycloneDX JSON.

После всех локальных операций production API проверен только на чтение:
`/health/live=ok`, `/health/ready=ok`, migration `0118`, database/migrations/
worker/outbox/v4Rollout checks — `ok`. Deployment `+180` не менялся.

## Артефакты

Каталог: `dist/1.5.1+181/`. Точные размеры и SHA-256 находятся в
`RELEASE-MANIFEST.json` и `SHA256SUMS.txt` этого каталога.

## Открытые условия

1. Повторить install/launch/uninstall smoke нового Setup `+181` в интерактивной
   elevated Windows-сессии; compile и portable ZIP launch уже подтверждены.
2. Повторить затронутые owner-UAT строки с уникальными UI/API/DB evidence;
   технический smoke не переводит их автоматически в `PASS`.
3. Production rollout `+181` требует отдельного решения владельца, нового
   backup/rollback gate и не следует из разрешения на уже развёрнутый `+180`.
