# v7 History Rewrite Rehearsal

**Дата:** 2026-08-07  
**Исходный HEAD:** `a8fa8e30ccf8791a0f72b620bd29740d25c8a5ab`  
**Переписанный rehearsal HEAD:** `6b6339b974203ffd1f767a3301260da293cf2e3d`  
**Статус:** PASS в изолированном local clone; `origin` не изменён.

## Проверенный фильтр

Fresh `--no-local` clone был обработан `git-filter-repo 2.47.0`:

1. Из всех revisions удалены два имени одного Android bugreport:
   - `bugreport/bugreport-sdk_gphone64_x86_64-BE4B.251210.005-2026-03-11-13-05-03.txt`;
   - `_archive/bugreport/bugreport-sdk_gphone64_x86_64-BE4B.251210.005-2026-03-11-13-05-03.txt`.
2. Три уникальных credential/token значения из unredacted transient Gitleaks report заменены во всех blobs на marker. Значения передавались filter callback только через process environment; в команду, tracked-файл или stdout они не попали.
3. Firebase client identifiers не переписывались и покрываются узким repository allowlist: точный `AIza…` match **AND** точный client-config path.

## Доказательства

| Проверка | Результат |
|---|---|
| Reachable commits | source=761, rewritten=761 |
| Local heads | source=4, rewritten=4 |
| Tags | source=22, rewritten=22 |
| HEAD tree | `7e9fa73b1e7598228d0e4e5867a258571c748710` с обеих сторон |
| Commit map | source HEAD однозначно отображён в rehearsal HEAD |
| Оба bugreport path | 0 commits после rewrite |
| History-aware Gitleaks | 738 scanned commits, 0 findings |
| Rehearsal worktree | clean |
| Rehearsal remotes | 0; `git-filter-repo` удалил local-origin |
| Рабочий repository | HEAD/status не изменены |

Разница 761 reachable commits против 738 scanned Gitleaks commits объясняется способом обхода merge/history самим scanner; Git ref/commit preservation проверено отдельно через `rev-list --all`.

## Production runbook после ротации ключа

1. В HolliHop открыть `Настройки → Интеграция → API`, выпустить новый key и
   подтвердить отзыв старого. Это официальный путь получения API key; если экран
   не предлагает регенерацию/отзыв, операцию выполняет поддержка HolliHop.
   Простое повторное копирование прежнего значения ротацией не считается.
   Источник: <https://hollipedia.t8s.ru/books/api/page/hollihop-api-20>.
   Новый key устанавливается только вне Git.
2. Объявить короткий freeze на push; сохранить `git ls-remote --heads --tags origin` как expected ref map.
3. Создать новый `--no-local` clone из актуального локального repository, который
   содержит ещё не опубликованную `codex/client-card-desktop-canvas`; сверить все
   существующие remote refs с expected map и отдельно доказать отсутствие этой
   новой release-ветки на `origin`.
4. Повторить ровно проверенный filter для двух bugreport paths и трёх уникальных значений из нового unredacted transient scan.
5. Проверить commit/head/tag counts, commit-map, byte-identical current HEAD tree и history-aware Gitleaks=0.
6. Только после явного разрешения владельца добавить `origin` обратно и обновить
   каждую существующую ветку с explicit expected-old-SHA lease. Санитизированная
   `codex/client-card-desktop-canvas` создаётся как новый ref только если она всё
   ещё отсутствует на remote. Теги обновлять только после повторного remote ref
   comparison.
7. Удалить transient unredacted reports и несанифицированные rehearsal clones; уведомить участников о mandatory fresh clone/rebase.
8. На переписанном HEAD повторить полный T6.1.1 gate, затем Windows/Android release build, signature/install/launch, hashes и final smoke.

Runbook намеренно не содержит команды безусловного `git push --force --all`: она не защищает от конкурентного push между freeze и rewrite.
