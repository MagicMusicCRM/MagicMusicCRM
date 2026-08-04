# MagicMusicCRM v6 — Task Audience & Branch UX

**Task:** V6-502 / REQ-TASK-002  
**Status:** PASS  
**Date:** 2026-08-04

## Result

The task editor now shows the effective recipients before submit and the reconciled count after create/update. It distinguishes fixed people from dynamic branch/school membership and does not guess from the directory loaded by Flutter.

## Contract

- `POST /crm/shared-tasks/audience-preview` resolves current PostgreSQL membership using the same user/branch/school rules as task delivery.
- Multiple selectors are de-duplicated by user; each selector still reports its own current count and label.
- Explicit recipients are restricted to operational task roles. Client accounts are rejected at the backend boundary and omitted from the picker.
- One or more people are fixed recipients. One branch and the whole school are clearly labelled dynamic; their future membership is recalculated when the task is used.
- Selecting the whole school replaces narrower selectors in the editor, avoiding a redundant mixed audience.
- Preview failure blocks submit and exposes `Повторить расчёт`; no task can be sent with an unknown audience.
- Create/update responses include `recipientSummary`; success feedback reports the resulting current count.
- Task actions use one vocabulary: `Новая задача`, `Изменить задачу`, `Задача сохранена`, `Закрыть задачу`, `Задача закрыта`, `Открыта/Закрыта`, `Один филиал`, `Вся школа`.
- Mobile create/edit uses the existing expandable full-width sheet; desktop uses the existing drawer. Icon actions retain semantic tooltips.

## Evidence

| Gate | Result |
|---|---:|
| Audience UI, retry, create/update/result and responsive widget tests | 11/11 |
| Affected client/task/navigation Flutter batch | 33/33 |
| Windows native device audience workflow | 1/1 |
| Android 15 API 35 audience + full-screen expansion workflow | 1/1 |
| SharedTask PostgreSQL/API/reminder reconciliation | 6/6 |
| Capability route-policy batch | 37/37 |
| Flutter analyze | clean |
| Full Flutter regression | 593/593 |
| Backend typecheck/build | clean |
| Full backend regression | 151/151 suites, 1170/1170 tests |
| V6 inventory | routes 21, reachable files 261, wire calls 262/262, unowned 0 |

The device test is reproducible at `integration_test/v6_task_audience_device_test.dart`; the PostgreSQL test proves fixed, branch and school counts against live membership rows and verifies unique recipient reconciliation.
