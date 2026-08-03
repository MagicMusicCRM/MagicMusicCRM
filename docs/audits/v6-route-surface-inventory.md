# MagicMusicCRM v6 — Production Route & Surface Inventory

**Task:** V6-001  
**Generation:** pwsh -File scripts/v6_ux_inventory.ps1  
**Validation:** machine-readable companion JSON, stale check supported.

## Coverage

| Slice | Count |
|---|---:|
| Dart files | 263 |
| Files reachable from main.dart | 256 |
| GoRouter routes | 21 |
| Screen/Page classes | 21 |
| Production-reachable screens | 21 |
| Isolated/unreachable screens | 0 |
| Modal/sheet/drawer callsites | 102 |
| Reachable surface callsites | 102 |
| Screens missing loading/error/retry evidence | 12 |
| Unowned items | 0 |

production_reachable means the file is reachable through static Dart imports from lib/main.dart; it is stronger than “file exists”, but runtime role/scope acceptance remains a later device gate. Every gap remains explicit in the JSON and is not treated as implemented.
