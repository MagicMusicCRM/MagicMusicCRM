# MagicMusicCRM v6 — Navigation Inventory

**Task:** V6-002

| Slice | Count |
|---|---:|
| Navigation callsites | 289 |
| Production-reachable callsites | 270 |
| Typed entity usages | 19 |
| Production workspace usages outside definitions | 2 |
| EntityLink types | 19 |
| Direct sites requiring classification/migration | 246 |
| Display-name route candidates | 1 |
| Unowned | 0 |

The key production gap is explicit: workspace foundations do not count as mounted until production_workspace_usages > 0. Direct Navigator calls include legitimate overlay exits and therefore remain review items rather than automatic defects.
