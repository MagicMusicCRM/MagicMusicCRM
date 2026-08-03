# MagicMusicCRM v6 — Navigation Inventory

**Task:** V6-002

| Slice | Count |
|---|---:|
| Navigation callsites | 266 |
| Production-reachable callsites | 263 |
| Typed entity usages | 6 |
| Production workspace usages outside definitions | 0 |
| EntityLink types | 19 |
| Direct sites requiring classification/migration | 256 |
| Display-name route candidates | 1 |
| Unowned | 0 |

The key production gap is explicit: workspace foundations do not count as mounted until production_workspace_usages > 0. Direct Navigator calls include legitimate overlay exits and therefore remain review items rather than automatic defects.
