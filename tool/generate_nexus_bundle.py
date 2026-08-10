#!/usr/bin/env python3
"""Build the tracked, current-code Nexus bundle from exhaustive inventories."""

from __future__ import annotations

import json
import hashlib
import re
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


OWNER_MAP = {
    "SYS-APP": "SYS-APP-EXPERIENCE",
    "SYS-ACCESS": "SYS-ACCESS-SCOPE",
    "SYS-CRM": "SYS-CRM-WORKSPACE",
    "SYS-SCHEDULE": "SYS-SCHEDULE",
    "SYS-COMMERCE": "SYS-COMMERCE-INTEGRITY",
    "SYS-WORKFLOW": "SYS-OPERATIONS",
    "SYS-REPORTING": "SYS-OPERATIONS",
    "SYS-PLATFORM": "SYS-PLATFORM-QUALITY",
}


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(value, str):
        path.write_text(value.rstrip() + "\n", encoding="utf-8")
    else:
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def owner(value: str | None) -> str:
    return OWNER_MAP.get(value or "", value or "SYS-PLATFORM-QUALITY")


def clean_rows(rows: list[dict]) -> list[dict]:
    return [{k: v for k, v in row.items() if k != "status"} for row in rows]


def normalize_client_path(expression: str | None) -> str | None:
    if not expression:
        return None
    text = expression.strip()
    prefixes = ("r'", 'r"', "'", '"')
    prefix = next((candidate for candidate in prefixes if text.startswith(candidate)), None)
    if prefix is not None and text.endswith(prefix[-1]):
        text = text[len(prefix) : -1]
    else:
        wrapped = re.search(r"r?(['\"])(/.*?)\1", text)
        if wrapped is None:
            return None
        text = wrapped.group(2)
    text = re.sub(r"\$\{[^}]+\}|\$[A-Za-z_]\w*", ":param", text)
    text = text.split("?", 1)[0]
    return "/" + "/".join(segment for segment in text.split("/") if segment)


def route_matches(client_path: str, server_path: str) -> bool:
    client = client_path.strip("/").split("/")
    server = server_path.strip("/").split("/")
    return len(client) == len(server) and all(
        left == right or left.startswith(":") or right.startswith(":")
        for left, right in zip(client, server)
    )


def route_score(client_path: str, server_path: str) -> int:
    score = 0
    for left, right in zip(client_path.strip("/").split("/"), server_path.strip("/").split("/")):
        if left == right:
            score += 3
        elif left.startswith(":") and right.startswith(":"):
            score += 2
    return score


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: generate_nexus_bundle.py <repo> <tmp-output>")
    repo = Path(sys.argv[1]).resolve()
    out = Path(sys.argv[2]).resolve()
    ast = load(out / "raw/ast_nodes.json")
    git_stats = load(out / "raw/git_stats.json")
    flutter = load(out / "inventory/flutter_code.json")
    route_surface = load(repo / "docs/audits/v6-route-surface-inventory.json")
    navigation = load(repo / "docs/audits/v6-navigation-inventory.json")
    input_back = load(repo / "docs/audits/v6-input-back-inventory.json")
    wire = load(repo / "docs/audits/v6-wire-service-baseline.json")
    backend = load(repo / "docs/audits/v4-current-state-inventory.json")
    commerce = load(repo / "docs/audits/v7-commerce-schedule-inventory.json")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    generated_at = datetime.now(timezone.utc).isoformat()
    source_digest = hashlib.sha256(
        (
            flutter["source_digest_sha256"]
            + backend["source_digest_sha256"]
            + commerce["source_digest"]
        ).encode()
    ).hexdigest()

    server_nodes = [
        node
        for node in ast["nodes"]
        if node.get("path", "").startswith(("server/src/", "server/db/"))
    ]
    server_module_ids = {node["id"] for node in server_nodes if node["type"] == "Module"}
    server_edges = [edge for edge in ast["edges"] if edge["source"] in server_module_ids]
    server = {
        "schema_version": 1,
        "source_revision": commit,
        "source_digest_sha256": source_digest,
        "scope": "server/src and server/db",
        "summary": {
            "modules": sum(node["type"] == "Module" for node in server_nodes),
            "classes": sum(node["type"] == "Class" for node in server_nodes),
            "functions_and_methods": sum(node["type"] == "Function" for node in server_nodes),
            "routes": len(backend["backend_routes"]),
            "dto_fields": len(backend["dto_fields"]),
            "policy_calls": len(backend["policy_calls"]),
            "migration_files": sum(
                node["type"] == "Module" and node.get("path", "").startswith("server/db/migrations/")
                for node in server_nodes
            ),
            "dependency_edges": len(server_edges),
        },
        "declarations": server_nodes,
        "dependency_edges": server_edges,
        "routes": [dict(row, owner=owner(row.get("owner"))) for row in clean_rows(backend["backend_routes"])],
        "role_guards": [dict(row, owner=owner(row.get("owner"))) for row in clean_rows(backend["role_guards"])],
        "policy_calls": [dict(row, owner=owner(row.get("owner"))) for row in clean_rows(backend["policy_calls"])],
        "dto_fields": [dict(row, owner=owner(row.get("owner"))) for row in clean_rows(backend["dto_fields"])],
        "integrity_schema": [dict(row, owner=owner(row.get("owner"))) for row in clean_rows(backend["database_schema"])],
        "finance_callsites": commerce["finance_callsites"],
        "lesson_temporal_mutations": commerce["lesson_temporal_mutations"],
    }
    write(out / "inventory/server_code.json", server)

    ui = {
        "schema_version": 1,
        "source_revision": commit,
        "source_digest_sha256": source_digest,
        "scope": "production-reachable Flutter UI under lib/",
        "summary": {
            **route_surface["summary"],
            "named_widgets": flutter["summary"]["widgets"],
            "dart_declarations": len(flutter["declarations"]),
            "providers": flutter["summary"]["providers"],
        },
        "routes": route_surface["routes"],
        "screens": route_surface["screens"],
        "surfaces": route_surface["surfaces"],
        "navigation_sites": navigation["navigation_sites"],
        "scroll_sites": input_back.get("scroll_sites", []),
        "back_sites": input_back.get("back_sites", []),
    }
    write(out / "inventory/ui_surfaces.json", ui)

    server_routes = server["routes"]
    matches = []
    matched_ids: set[str] = set()
    for call in flutter["api_calls"]:
        verb_expression = call.get("http_method_expression")
        request_verb = verb_expression.strip("'\"").upper() if verb_expression else "REQUEST"
        verb = {"postIdempotent": "POST", "request": request_verb}.get(call["verb"], call["verb"].upper())
        path = normalize_client_path(call.get("path_expression"))
        candidates = [
            route
            for route in server_routes
            if path and verb == route["verb"] and route_matches(path, route["route"])
        ]
        if candidates:
            best_score = max(route_score(path, route["route"]) for route in candidates)
            candidates = [route for route in candidates if route_score(path, route["route"]) == best_score]
        if len(candidates) == 1:
            status = "matched"
        elif candidates:
            status = "ambiguous"
        elif call.get("callable") and call.get("callable_invocations") == 0:
            status = "unreferenced_client_method"
        else:
            status = "external_or_dynamic"
        matched_ids.update(route["id"] for route in candidates)
        matches.append(
            {
                **call,
                "normalized_path": path,
                "normalized_verb": verb,
                "status": status,
                "server_routes": [route["id"] for route in candidates],
            }
        )
    wire_matrix = {
        "schema_version": 1,
        "source_revision": commit,
        "source_digest_sha256": source_digest,
        "summary": {
            "client_calls": len(matches),
            "matched": sum(row["status"] == "matched" for row in matches),
            "ambiguous": sum(row["status"] == "ambiguous" for row in matches),
            "unreferenced_client_method": sum(row["status"] == "unreferenced_client_method" for row in matches),
            "external_or_dynamic": sum(row["status"] == "external_or_dynamic" for row in matches),
            "server_routes": len(server_routes),
            "server_routes_without_direct_literal_flutter_call": len(server_routes) - len(matched_ids),
        },
        "client_to_server": matches,
        "server_routes_without_direct_literal_flutter_call": [
            route for route in server_routes if route["id"] not in matched_ids
        ],
        "note": "Unresolved does not imply broken: variables, public webhooks, downloads, realtime and server-only routes may not have a direct literal Flutter call.",
    }
    write(out / "inventory/wire_matrix.json", wire_matrix)

    ownership: dict[str, Counter] = defaultdict(Counter)

    def guess_path_owner(path: str) -> str:
        path = path.lower()
        if any(key in path for key in ("schedule", "lesson", "teacher")):
            return "SYS-SCHEDULE"
        if any(key in path for key in ("payment", "subscription", "commerce")):
            return "SYS-COMMERCE-INTEGRITY"
        if any(key in path for key in ("client", "student", "lead", "crm")):
            return "SYS-CRM-WORKSPACE"
        if any(key in path for key in ("task", "report", "analytic", "setting")):
            return "SYS-OPERATIONS"
        return "SYS-APP-EXPERIENCE"

    for row in server_routes:
        ownership[row["owner"]]["server_routes"] += 1
    for row in ui["screens"]:
        ownership[owner(row.get("owner"))]["screens"] += 1
    for row in ui["surfaces"]:
        ownership[owner(row.get("owner"))]["surfaces"] += 1
    for row in flutter["providers"]:
        guessed = guess_path_owner(row["file"])
        ownership[guessed]["providers"] += 1
    widgets = []
    for row in flutter["declarations"]:
        if row.get("is_widget") is not True:
            continue
        guessed = guess_path_owner(row["file"])
        ownership[guessed]["widgets"] += 1
        widgets.append({**row, "owner": guessed})
    feature_rows = [
        {"system": system, **dict(counts)} for system, counts in sorted(ownership.items())
    ]
    feature_map = {
        "schema_version": 1,
        "source_revision": commit,
        "source_digest_sha256": source_digest,
        "systems": feature_rows,
        "widgets": widgets,
        "screens": ui["screens"],
        "routes": ui["routes"],
        "server_route_groups": {
            system: [route["id"] for route in server_routes if route["owner"] == system]
            for system in sorted({route["owner"] for route in server_routes})
        },
    }
    write(out / "inventory/feature_ownership.json", feature_map)

    metadata = (
        "> generated_by: nexus-mapper v2 + project exhaustive inventories\n"
        f"> verified_at: {generated_at}\n"
        f"> source_revision: {commit}\n"
        f"> source_digest_sha256: {source_digest}\n"
        "> provenance: untruncated AST, Dart analyzer, route/DTO/policy/schema inventories and Git forensics\n\n"
    )
    ast_summary = ast["stats"]
    index = metadata + f"""# MagicMusicCRM current code map

Один Flutter Windows/Android клиент работает с одним NestJS/PostgreSQL backend.
Карта построена только из текущего дерева `main`; исторические планы не являются
источником реализации.

## Покрытие

- Flutter: {flutter['summary']['files']} файлов, {flutter['summary']['widgets']} именованных виджетов, {flutter['summary']['methods']} методов, {flutter['summary']['functions']} функций, {flutter['summary']['providers']} providers.
- UI: {ui['summary']['go_routes']} routes, {ui['summary']['production_screens']} production screens, {ui['summary']['production_surface_calls']} modal/sheet/drawer surfaces.
- Server: {server['summary']['routes']} endpoints, {server['summary']['classes']} classes, {server['summary']['functions_and_methods']} functions/methods, {server['summary']['dto_fields']} DTO fields, {server['summary']['policy_calls']} policy calls.
- AST: {ast_summary['total_files']} файлов, {len(ast['nodes'])} nodes, `truncated=false`, parse errors={ast_summary['parse_errors']}.
- Wire: {wire_matrix['summary']['client_calls']} client calls; {wire_matrix['summary']['matched']} literal route matches; remaining rows explicitly classified.

## Read next

- `inventory/README.md` — маршрутизация по исчерпывающим JSON.
- `arch/systems.md` — границы систем и владельцы.
- `arch/dependencies.md` — runtime/wire topology.
- `arch/test_coverage.md` — доказанное покрытие и белые пятна.
- `hotspots/git_forensics.md` — change-risk hotspots.

## Инструкция по эксплуатации

Перед изменением кода найти сущность в `inventory/feature_ownership.json`, затем
проверить точную декларацию в `flutter_code.json` или `server_code.json` и связь
в `wire_matrix.json`. Не загружать целые JSON в контекст: выбирать строки через
`rg`, `jq` или PowerShell. Если source digest не совпадает с рабочим деревом,
сначала регенерировать карту. `source_revision` может предшествовать map-only
коммиту и не является stale-признаком сам по себе.
"""
    write(out / "INDEX.md", index)

    inventory_readme = metadata + f"""# Exhaustive inventory router

| Файл | Что содержит |
|---|---|
| `flutter_code.json` | Все Dart declarations, именованные widgets/screens, providers, imports, API и constructor callsites под `lib/` |
| `ui_surfaces.json` | Все production GoRouter routes, screens, modal/sheet/drawer, navigation/scroll/Back surfaces |
| `server_code.json` | Все server classes/functions/modules, {server['summary']['routes']} endpoints, guards, policies, DTO, integrity schema и mutations |
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
"""
    write(out / "inventory/README.md", inventory_readme)

    systems_lines = [metadata + "# Systems and code ownership\n"]
    for row in feature_rows:
        counts = ", ".join(f"{key}={value}" for key, value in row.items() if key != "system") or "mapped"
        systems_lines.append(f"- **{row['system']}** — {counts}.")
    systems_lines.append("\nТочные элементы находятся в `inventory/feature_ownership.json`; все implemented code paths проверены при генерации.")
    write(out / "arch/systems.md", "\n".join(systems_lines))

    dependencies = metadata + """# Runtime and dependency topology

```mermaid
flowchart LR
  UI[Flutter widgets/screens] --> RP[Riverpod providers/controllers]
  RP --> API[Magic API services]
  API -->|HTTPS JSON /api| N[NestJS controllers + DTO validation]
  API -->|Socket.IO /realtime| RT[Realtime gateway]
  N --> P[Capability/resource policies]
  P --> D[Domain services]
  D --> DB[(PostgreSQL)]
  D --> O[Audit/outbox/workers]
```

Process roots and spawn sites remain recorded in the generated wire baseline.
REST DTO/policy validation is strong on the server; map-shaped Flutter decoding
is a weaker boundary and requires Release UI smoke.
"""
    write(out / "arch/dependencies.md", dependencies)

    test_files = [path for path in ast.get("nodes", []) if path["type"] == "Module" and (path.get("path", "").startswith("test/") or ".spec." in path.get("path", "") or path.get("path", "").startswith("integration_test/"))]
    coverage = metadata + f"""# Test and evidence coverage

- Test/spec modules mapped: {len(test_files)}.
- Inventory validation: routes/screens/wire/backend/commerce generators must pass `-Check`.
- Structural AST: parse errors={ast_summary['parse_errors']}, truncated={str(ast_summary['truncated']).lower()}.
- Production owner UAT remains governed by `docs/audits/v7-owner-production-mega-uat-result.md`; static coverage is not owner acceptance.

## Explicit gaps

- Dart analyzer records declarations and callsites, not the runtime widget tree produced by conditional builders.
- `unresolved` wire rows can be computed paths, download URLs, public/server-only or realtime contracts; inspect before treating as a defect.
- Five tables in `integrity_schema` are the guarded finance/schedule/access core, not a claim that PostgreSQL has only five tables.
"""
    write(out / "arch/test_coverage.md", coverage)

    domains = metadata + """# Active domains

- **App Experience** — session, routes, workspace tabs, Back and adaptive shell.
- **Access Scope** — roles, capabilities, actor/resource projection and safe 404.
- **CRM Workspace** — Lead/Student, cards, pipelines, fields, comments and notes.
- **Schedule** — lessons, conflicts, recurring plans, reservations and lifecycle.
- **Commerce Integrity** — wallet, subscriptions, payments, reversals, settlement and teacher accrual.
- **Operations** — tasks, analytics, exports, settings and technical history.
- **Platform Quality** — migrations, audit/outbox, realtime, files, workers and release gates.
"""
    write(out / "concepts/domains.md", domains)

    concept_paths = {
        "app-experience": "lib/core/router/",
        "access-scope": "server/src/access-control/",
        "crm-workspace": "server/src/crm/",
        "schedule": "server/src/crm/schedule/",
        "commerce-integrity": "server/src/crm/commerce/",
        "operations": "server/src/crm/tasks/",
        "platform-quality": "server/src/platform/",
    }
    nodes = []
    for concept_id, code_path in concept_paths.items():
        if not (repo / code_path).exists():
            raise RuntimeError(f"Missing implemented code_path: {code_path}")
        nodes.append({
            "id": concept_id,
            "type": "System",
            "label": concept_id.replace("-", " ").title(),
            "responsibility": "See concepts/domains.md",
            "implementation_status": "implemented",
            "code_path": code_path,
            "tech_stack": ["Flutter", "NestJS", "PostgreSQL"],
            "complexity": "high",
        })
    write(out / "concepts/concept_model.json", {
        "$schema": "nexus-mapper/concept-model/v1",
        "generated_at": generated_at,
        "repo_path": ".",
        "nodes": nodes,
    })

    hotspots = git_stats.get("hotspots", [])[:25]
    hotspot_lines = [metadata + "# Git forensics\n", f"Window: {git_stats.get('analysis_period_days', 90)} days.\n", "| File | Changes | Risk |", "|---|---:|---|"]
    hotspot_lines.extend(f"| `{row['path']}` | {row['changes']} | {row['risk']} |" for row in hotspots)
    write(out / "hotspots/git_forensics.md", "\n".join(hotspot_lines))


if __name__ == "__main__":
    main()
