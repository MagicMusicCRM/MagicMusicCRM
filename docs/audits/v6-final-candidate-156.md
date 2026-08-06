# MagicMusicCRM v6 — final engineering candidate 1.2.3+156

**Date:** 2026-08-07  
**Status:** ENGINEERING PASS; OWNER UAT PENDING

## Candidate scope

- Desktop Client Card is one scrollable workspace with compact paired sections.
- Additional fields live in a collapsed Overview section on desktop and mobile.
- The canonical lesson tray follows Preferred Schedule and remains available when no preference exists; duplicate actual/upcoming/past blocks are removed.
- Payment movements and installments are collapsed by default.
- Routed client workspaces keep the role navigation rail and canonical `Clients > Lead/Student > name` location state.
- Students and Leads share one search/filter/FAB board contract.
- Advertising source is one required canonical `lead_sources.id` for Lead and Student and is preserved on conversion; important client attributes are primary fields.

## Verification

```text
flutter analyze: PASS (0 issues)
flutter test: PASS (full suite)
backend typecheck/build: PASS
backend tests: 152/152 suites, 1159/1159 tests PASS
migration 0102 down -> up on local PostgreSQL: PASS
v6 inventory: routes=22, reachable=253, workspaceProduction=2, unowned=0
git diff --check: PASS
Windows x64 release build: PASS
Android release APK build: PASS
APK Signature Scheme v2: PASS (1 signer)
```

## Release artifacts

| Artifact | SHA-256 |
|---|---|
| `build/app/outputs/flutter-apk/app-release.apk` | `25705BD2E8F90877D65C0ABBAE647241A0CE0FB86F51DDC57ADC45330547608A` |
| `build/windows/x64/runner/Release/magic_music_crm.exe` | `0762CEBF26A950770DED57A743136FEBE37A4F8BBE7FB1B10E573505103A68C6` |
| `build/windows/x64/runner/Release/data/app.so` | `02C54D40E98B77BCEA3521A66AB5D0896F7BF53988E31E4E4F6B2314AF75103C` |

## Remaining acceptance boundary

Owner UAT `V6-701` remains open: execute the 26-point pack with real accounts 1..5 on Windows and Android, including logout/relogin, client navigation from Schedule, Lead-to-Student conversion, source persistence, and responsive visual acceptance.
