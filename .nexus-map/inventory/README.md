> generated_by: nexus-mapper v2 + project exhaustive inventories
> verified_at: 2026-08-10T14:11:29.427591+00:00
> source_revision: 13a9734356eca27f3d7b60dec00c639f1d85264b
> source_digest_sha256: cc6c200f55daa66889d4cd3a5de0176abe3d95eaf450576addb0db652f42a15f
> provenance: untruncated AST, Dart analyzer, route/DTO/policy/schema inventories and Git forensics

# Exhaustive inventory router

| Файл | Что содержит |
|---|---|
| `flutter_code.json` | Все Dart declarations, именованные widgets/screens, providers, imports, API и constructor callsites под `lib/` |
| `ui_surfaces.json` | Все production GoRouter routes, screens, modal/sheet/drawer, navigation/scroll/Back surfaces |
| `server_code.json` | Все server classes/functions/modules, 321 endpoints, guards, policies, DTO, integrity schema и mutations |
| `wire_matrix.json` | Каждый Flutter API call: `matched`, `ambiguous`, `unreferenced_client_method` или `external_or_dynamic` |
| `feature_ownership.json` | Системный владелец экранов, routes, surfaces, providers и endpoint-групп |

JSON является исчерпывающим источником. Markdown содержит только навигацию и
сводки, чтобы не забивать контекст будущего агента.

## Regeneration

Использовать `nexus-mapper` с Python 3.10+ и staging внутри `.nexus-map/.tmp/`.
Перед EMIT обновить три базовых inventory-генератора:

```text
pwsh scripts/v4_inventory.ps1
pwsh scripts/v6_ux_inventory.ps1
pwsh scripts/v7_commerce_schedule_inventory.ps1
dart run tool/generate_dart_code_map.dart lib <staging>/inventory/flutter_code.json
python tool/generate_nexus_bundle.py . <staging>
```

Generic AST/Git raw-файлы создаются штатными скриптами
`.agents/skills/nexus-mapper/scripts/`. Публиковать staging только после
`truncated=false`, parse errors=0, inventory `-Check` и проверки всех code paths.
