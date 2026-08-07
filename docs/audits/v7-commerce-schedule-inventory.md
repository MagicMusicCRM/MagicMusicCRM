# MagicMusicCRM v7 — Commerce & Schedule Mutation Inventory

**Task:** T1.1.1  
**Generation:** `pwsh -File scripts/v7_commerce_schedule_inventory.ps1`  
**Stale check:** `pwsh -File scripts/v7_commerce_schedule_inventory.ps1 -Check`

| Slice | Count |
|---|---:|
| Matched production source files | 50 |
| Finance SQL/wire callsites | 241 |
| Ordinary finance reads | 96 |
| Reporting-safe finance reads | 51 |
| Protected lesson temporal mutations | 13 |
| Unowned | 0 |

The JSON companion is the authoritative deterministic baseline. A new matching
callsite changes the artifact; an unknown owner fails generation immediately.
