# MagicMusicCRM v6 — Wire-to-Service Baseline

**Task:** V6-005  
**Evidence level:** static call inventory + seeded actor/payload and Flutter service-contract baseline recorded in 6-s0-baseline.md.

| Slice | Count |
|---|---:|
| Service/API files | 34 |
| HTTP-like callsites | 277 |
| Production-reachable callsites | 277 |
| Process roots | 2 |
| Spawn sites | 2 |
| Unowned | 0 |

## Runtime boundaries

- Flutter process: HTTPS/JSON and Socket.IO to the NestJS API.
- NestJS process: HTTP/JSON + Socket.IO, DTO/policy contracts, PostgreSQL persistence.
- Local child-process sites are lifecycle-reviewed separately in the JSON; they are not part of CRM request routing.

The checked companion baseline records the seeded actor/payload matrix and representative Schedule, Client, Payment, Tasks, Dashboard and configuration contract tests. Real-account acceptance remains an S7 gate.
