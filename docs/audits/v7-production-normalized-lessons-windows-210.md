# Production release 1.5.30+210 — 2026-09-03

Владелец разрешил выпуск командой «Выпускаем». Сервер и четыре клиентских
пакета опубликованы; production rollout и проверки после установки PASS.

## Идентичность

| Назначение | Revision | Image ID |
| --- | --- | --- |
| Previous 209 | `229b8a6fd725e486f92947004987cebe6021350c` | `sha256:aee7deaf574eed311c26356fdb712fff07320249346ae5f9c5df5c68e77f9e1f` |
| Compatible bridge | `bf25d357e257b5215461ee856d12ecf507018300` | `sha256:a595e1e79ed37510bda803d2676371a1bac9d4c92ab15a1d679b0de61e66622f` |
| Final 210 | `b5994969c2e94c79d3e139bafe44209f281db442` | `sha256:c507e60e067e7582c9275a3c4c4680170891f1622c59f261a1aa95d7c1f4af89` |

Final image: `magicmusiccrm-server:1.5.30-210-b5994969c2e9`.
Migration: `0146_lesson_funding_payer`. Backend bridge/final byte-identical;
`git diff bf25d357 b5994969 -- server` пуст. Клиентский продукт идентичен
`60bfb250`; последний commit меняет только integration harness и исключение
сгенерированных `dist/` artifacts из анализатора.

## Поведение

- Общие action windows: центральный округлённый dialog на native desktop;
  нижний sheet на Android/iOS с крестиком, handler, свайпом, прокруткой и
  учётом клавиатуры. Web использует breakpoint 840. Удалены отдельный drawer,
  боковая информация чата и fullscreen-вариант редактора занятия.
- Единый редактор занятия выбирает актуального ученика и плательщика,
  абонемент либо личный счёт, цену, скидку/надбавку и правило преподавателя.
  По умолчанию используется стандартная ставка. Финансовые изменения
  проходят существующие versioned preview/commit и сохраняют историю.
- Цвет занятия обозначает lifecycle; отдельный зелёный значок показывает
  реальный резерв абонемента в ленте клиента и общем расписании. Matrix query
  теперь возвращает состояние последнего резерва.
- «Расчёты преподавателей» — третья вкладка Аналитики. Карточки используют
  каноническую student identity после конверсии лида; направление, лента
  занятий и денежные подписи приведены к общим правилам.

## Проверки кандидата

| Gate | Результат |
| --- | --- |
| Flutter full | 1553/1553 PASS, 7:49 |
| Release metadata | 7/7 PASS |
| Workspace Dart analyze | No issues found |
| Backend full | 279/279 suites, 3690/3690 tests, 693.45 s, fresh local DB |
| Backend typecheck/build | PASS; источник не изменился после тестов |
| Production-like | Fail-closed flags, live/ready, migration 0146, reconciliation PASS |
| Bridge/final exact images | Identity, non-root, healthcheck, invalid flags, degraded HTTP 503 PASS |
| Security | Strict gate 11 PASS/0 WARN/0 FAIL; npm audit 0 vulnerabilities |
| SAST/secrets/images | Semgrep 799 TS files/77 rules: 0 findings; Gitleaks release range: 0; Trivy bridge/final HIGH/CRITICAL and secret findings: 0 |
| Deployment contracts | Behavior/static/DB contracts PASS; legacy funding guard tested against six real PostgreSQL cases |
| Backup contracts | Static contracts and 15 injected failure phases, timeouts, HUP/INT/TERM PASS |
| Windows | x64, versions 1.5.30+210 / Setup 1.5.30.210; 31 ZIP entries SHA-match; process responding after 8 s |
| Android | APK/AAB versionCode 210, matching release certificate; APK v2 and AAB JAR verification PASS |

Ограничения: Android-устройство не подключено, device smoke не выполнялся;
Windows smoke проверял запуск, а не интерактивный бизнес-сценарий. Ранее
собранный local preview не считается новой production-проверкой. Trivy
сообщил, что Alpine 3.24 отсутствует в его EOL-списке; vulnerability scan
завершён. RepoWise live-git risk percentile 99.5/Elevated, coverage map нет;
поэтому выполнены полные наборы тестов.

Устранённые проблемы gate: старый Android plugin registrant ссылался на
`integration_test`, а `--no-pub` пропускал регенерацию. Обычный release build
успешно регенерировал его без изменения product source и lockfile. Analyzer
нашёл копии прошлого релиза в `dist/` и устаревший `onSettle` в device harness:
artifacts исключены, harness обновлён, полный анализ затем PASS. Изолированный
backup harness повторён с явно исполняемым tmpfs `/tmp` после отказа `noexec`.

## Установка и состояние

Двухэтапный guarded cutover: 209 → bridge (0145 → 0146) → final (0146).
Оба `DEPLOY_API_RELEASE|PASS`. Образы перенесены с проверкой архива, слоёв и
OCI labels. Final container healthy, restart count 0; `DEPLOYED_REVISION`
совпадает с `b5994969`. Public readiness: все checks `ok`.

После установки reconciliation дважды `issues=[]`. Poison/due lessons,
unpublished/dead-letter events, due/exhausted fresh emails — все 0.
Readonly projection probe показывает 12 reserved lessons, все 12 — scheduled
с данными для зелёного значка. Probe не нашёл действующую series с точными
датами 01.09–01.12, поэтому не используется как повторный production PASS
для старого сценария 13 пятниц. Production monitor PASS, уведомления при
ручной проверке отключены через `ALERT_DRY_RUN=1`.

## Backup и rollback

Обе encrypted копии сохранены на сервере и off-host в
`C:/Users/Alinka/Documents/MagicMusicCRM Backups/2026-09-03/` с SHA-256 check.

| Копия | Байты | SHA-256 |
| --- | ---: | --- |
| `magicmusiccrm-staging-20260903T094352Z.tgz.enc` | 243600 | `6980aa1d89624109fa4f9db525719e430a0c200151eb38132fc3dfae12473888` |
| `magicmusiccrm-staging-20260903T100506Z.tgz.enc` | 244032 | `8a9839fd3339e08adaa907daf03fa87756bbc07ea2e7423fc67df61f10a5d2e9` |

Pre-copy прошла isolated restore bridge/209 и final/bridge; post-copy —
final/bridge. Drills используют отдельные network/volume и не изменяют live DB.

**Допустимый rollback после новых финансовых записей — только bridge**
`magicmusiccrm-server:1.5.30-210-bridge-bf25d357e257`. Старый 209 не понимает
payer/pricing и новые funding decisions. Guard после остановки writers
проверяет все charge facts и планы/переходы/коррекции; при несовместимости
или ошибке проверки старый runtime не запускается. Restore/reconciliation
сами по себе не доказывают финансовую совместимость. Bridge и final имеют
одинаковый backend: общий дефект требует forward fix, без удаления истории
и down migration.

Guarded scripts/overrides находятся в
`/opt/magicmusiccrm/releases/1.5.30-210-b5994969c2e9/` и bridge directory.
Для восстановления bridge используется существующий guarded deploy с
candidate/rollback, поменянными местами, и migration 0146 в обоих аргументах.
Предыдущие client manifests/history сохранены в final `client-rollback/`.

## Публикация

Оба `latest.json`/`latest-v2.json` и history показывают `1.5.30+210`.
Все четыре public downloads проверены полным скачиванием и SHA-256;
GitHub Release [v1.5.30](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.30)
опубликован, tag указывает на final revision, asset sizes/digests совпадают.

| Artifact | Байты | SHA-256 |
| --- | ---: | --- |
| `MagicMusicCRM-1.5.30-210-Setup.exe` | 15459406 | `a8c37a2fbe0abbd71cab970fd85d69d82eea33591a1f96f80941b3c7b44fc7ad` |
| `MagicMusicCRM-1.5.30-210-windows-x64.zip` | 19607119 | `0ad91180703126fe18c47d610d5845cd27f70857e94c836adac0425093014ee8` |
| `MagicMusicCRM-1.5.30-210.apk` | 87674342 | `e26a964eef50e04a69efb2ca2c471b007ed92422b0d84f0b58d0c3020cb88af8` |
| `MagicMusicCRM-1.5.30-210.aab` | 61131428 | `ec6f9ebf1dd949582e295eb09c7fd73ead307fad6c7329fd5cc0554962dfe893` |

Локальные raw logs, commands и JSON evidence: `dist/release210/`.
Секреты, dumps, backups и raw runtime logs в git не добавлены.
